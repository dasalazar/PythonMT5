# EA_GradienteLinear3 (v3)

Robô de grid (Gradiente Linear) — versão 3, nativo em MQL5 para MetaTrader 5 em conta **NETTING** (WINFUT / B3).

---

## 1. Visão Geral e Evoluções em Relação à v2

O **EA_GradienteLinear3** é a versão em evolução contínua da estratégia de Gradiente Linear:
1. **Progressão de Lotes na Mola (`MolaProgressaoLotes`)**: Permite parametrizar uma sequência customizada de lotes (ex: `"2,3,4,5,10"`) para os níveis pendentes após a ativação da Mola, em vez de fixar apenas em 2x.
2. **Descarga do Balde Desativada**: Removida a lógica de descarga parcial em limiares desfavoráveis que geravam saídas no prejuízo. No Gradiente Linear, saídas só ocorrem no lucro (alvo de OCO / Balde no preço médio favorável) ou no Stop Financeiro global.
3. **Persistência do Balde e Teto Universal**: Mantém a arquitetura do balde persistente ao longo de todo o ciclo e a migração automática de OCOs que ultrapassariam o teto do preço médio $\pm$ `MolaPontos`.
4. **Stop Financeiro Global**: Encerramento total por limite financeiro em R$ (`StopFinanceiro = 5000.0`).
5. **Magic Number**: `198200` (permite execução e testes simultâneos com v1 e v2).

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `NiveisGradiente` | `50` | Níveis máximos do grid de ordens. |
| `DistanciaGrid` | `75.0` | Distância entre níveis de entrada (pontos). |
| `DistanciaGridSaida` | `100.0` | Distância do alvo OCO individual (pontos). |
| `DistanciaGridMola` | `150.0` | *(Não utilizado nesta versão)*. |
| `MolaPontos` | `50.0` | Distância da saída do balde a partir do preço médio. |
| `MolaProgressaoLotes`| `"2,3,4,5,10"` | Sequência de lotes para os níveis pendentes na ativação da Mola. |
| `DistanciaDescargaBalde`| `50.0` | *(Desativado)*. |
| `ToleranciaDescarga`| `25.0` | *(Desativado)*. |
| `QuantidadePorOrdem`| `1` | Contratos padrão por nível do grid. |
| `PeriodoPuckAgressao`| `21` | Período do indicador `Puck_Agressao`. |
| `ReconstruirHistorico`| `true` | Reconstrói histórico de agressão via ticks. |
| `DiasHistoricoTicks`| `2` | Dias de histórico para reconstrução de ticks. |
| `PeriodoTPV` | `50` | Período do indicador `TPV_SMA`. |
| `StopFinanceiro` | `5000.0` | Perda máxima flutuante em R$ antes de zerar tudo. |
| `MagicNumber` | `198200` | Identificador das ordens da v3. |

---

## 3. Regras de Entrada
Executadas apenas quando o robô **não possui posição** (`!PositionSelect`):

- **Sinal de Compra**:
  $$\text{compra\_subindo} \land \neg\text{venda\_subindo} \land \text{TPV\_subindo}$$
  - Executa compra a mercado de `QuantidadePorOrdem`.
  - Posiciona ordens limites `BuyLimit` a cada `DistanciaGrid` abaixo da entrada até `NiveisGradiente`.

- **Sinal de Venda**:
  $$\text{venda\_subindo} \land \neg\text{compra\_subindo} \land \text{TPV\_caindo}$$
  - Executa venda a mercado de `QuantidadePorOrdem`.
  - Posiciona ordens limites `SellLimit` a cada `DistanciaGrid` acima da entrada até `NiveisGradiente`.

---

## 4. Regras de Gerenciamento e Saída

### 4.1. Saída OCO Individual e Recarregamento
- Ordens executadas geram saídas limites a `DistanciaGridSaida` pontos de distância.
- Preenchimento de OCO com posição remanescente recarrega o nível na mesma cotação de entrada.
- Se a posição zerar via OCO individual, o ciclo é encerrado e ordens pendentes são canceladas.

### 4.2. Mola e Balde Consolidado
- **Ativação da Mola**:
  - Compra: `TPV_caindo`
  - Venda: `TPV_subindo`
- **Comportamento na Ativação**:
  - Atualiza as pendentes de entrada restantes com a progressão definida em `MolaProgressaoLotes`.
  - Cancela OCOs individuais fora do balde e recalcula a ordem única consolidada no $\text{Preço Médio} \pm \text{MolaPontos}$.
  - Volume do Balde = $\text{Volume Total Posição} - \text{Volume Ordens OCO Ativas}$.
- **Persistência**: Ao desativar a Mola, as entradas pendentes voltam ao lote padrão (`QuantidadePorOrdem`), mas o balde existente é preservado até o encerramento do ciclo.

### 4.3. Teto Universal e Migração de Ordens
- Alvos individuais nunca podem ultrapassar o preço do balde ($\text{Preço Médio} \pm \text{MolaPontos}$).
- Ordens que violarem o teto são canceladas e transferidas diretamente para a ordem do balde (`MigrarOrdensAlemDoTeto`).

### 4.4. Stop Financeiro Global
- Se $(\text{Lucro Flutuante} + \text{Swap}) \le -\text{StopFinanceiro}$:
  - Fecha a posição imediatamente a mercado (`PositionClose`).
  - Cancela todas as ordens ativas e pendentes.
  - Zera o estado interno do ciclo.

---

## 5. Dependências
- Indicadores compilados em `MQL5/Indicators/dsalazar/`:
  - `Puck_Agressao.mq5`
  - `TPV_SMA.mq5`
