# EA_GradienteLinear3 (v3)

Robô de grid (Gradiente Linear) — versão 3, nativo em MQL5 para MetaTrader 5 em conta **NETTING** (WINFUT / B3).

---

## 1. Visão Geral e Evoluções em Relação à v2

O **EA_GradienteLinear3** é a versão em evolução contínua da estratégia de Gradiente Linear:
1. **Tabela de Lotes e Distribuição OCO / Balde na Mola**: Permite configurar a sequência de lotes totais (`MolaProgressaoLotes`) e de saídas OCO individuais (`MolaProgressaoOCO`) para cada um dos 20 níveis do grid na ativação da Mola. O excedente de cada nível vai automaticamente para o Balde consolidado.
2. **Entrada Estrita no 1º Impulso da Onda**: Integração com a nova lógica de ondas do `Puck_Agressao`, exigindo **Verde Escuro** (`SinalC = 1.0`) para compras e **Vermelho** (`SinalV = 1.0`) para vendas. Repiques (Verde/Rosa fraco) não geram novas entradas a mercado sem posição.
3. **Recarregamento Contínuo de Níveis**: Enquanto houver posição aberta, todo alvo OCO preenchido recarrega imediatamente a ordem de entrada no mesmo nível (em lote padrão fora da Mola ou no lote da tabela durante a Mola).
4. **Descarga do Balde Desativada**: Saídas ocorrem no lucro (alvo OCO ou Balde no preço médio favorável) ou no Stop Financeiro global.
5. **Persistência do Balde e Teto Universal**: Balde persiste durante todo o ciclo e absorve OCOs que ultrapassariam o teto do preço médio $\pm$ `MolaPontos`.
6. **Stop Financeiro Global**: Encerramento total por limite financeiro em R$ (`StopFinanceiro = 5000.0`).
7. **Magic Number**: `198200` (permite execução e testes simultâneos com v1 e v2).

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `NiveisGradiente` | `50` | Níveis máximos do grid de ordens. |
| `DistanciaGrid` | `75.0` | Distância entre níveis de entrada (pontos). |
| `DistanciaGridSaida` | `100.0` | Distância do alvo OCO individual (pontos). |
| `MolaPontos` | `50.0` | Distância da saída do balde a partir do preço médio. |
| `MolaProgressaoLotes`| `"1,1,2,2,3,3,4,4,5,5,5,5,4,4,3,3,2,2,1,1"` | Sequência de lotes TOTAIS por nível (1 a 20) na Mola. |
| `MolaProgressaoOCO` | `"1,1,1,1,2,2,3,3,4,4,4,4,3,3,2,2,1,1,1,1"` | Sequência de lotes OCO individuais por nível (1 a 20) na Mola. |
| `QuantidadePorOrdem`| `1` | Contratos padrão por nível do grid fora da Mola. |
| `PeriodoPuckAgressao`| `21` | Período do indicador `Puck_Agressao`. |
| `ReconstruirHistorico`| `true` | Reconstrói histórico de agressão via ticks. |
| `DiasHistoricoTicks`| `2` | Dias de histórico para reconstrução de ticks. |
| `PeriodoTPV` | `50` | Período do indicador `TPV_SMA`. |
| `StopFinanceiro` | `5000.0` | Perda máxima flutuante em R$ antes de zerar tudo. |
| `MagicNumber` | `198200` | Identificador das ordens da v3. |

---

## 3. Tabela de Distribuição de Lotes na Mola (por Nível)

| Nível | Total Lotes | Saída OCO | Balde Consolidado |
| :---: | :---: | :---: | :---: |
| **1** | 1 | 1 | 0 |
| **2** | 1 | 1 | 0 |
| **3** | 2 | 1 | 1 |
| **4** | 2 | 1 | 1 |
| **5** | 3 | 2 | 1 |
| **6** | 3 | 2 | 1 |
| **7** | 4 | 3 | 1 |
| **8** | 4 | 3 | 1 |
| **9** | 5 | 4 | 1 |
| **10** | 5 | 4 | 1 |
| **11** | 5 | 4 | 1 |
| **12** | 5 | 4 | 1 |
| **13** | 4 | 3 | 1 |
| **14** | 4 | 3 | 1 |
| **15** | 3 | 2 | 1 |
| **16** | 3 | 2 | 1 |
| **17** | 2 | 1 | 1 |
| **18** | 2 | 1 | 1 |
| **19** | 1 | 1 | 0 |
| **20** | 1 | 1 | 0 |
| **>20** | 1 | 1 | 0 |

---

## 4. Regras Operacionais

### 4.1. Entrada Inicial (Sem Posição)
Executada apenas quando o robô **não possui posição** (`!PositionSelect`):
- **Sinal de Compra**:
  $$\text{compra\_verde\_escuro (1º impulso)} \land \text{venda\_caindo} \land \text{TPV\_subindo}$$
  - Executa compra a mercado de `QuantidadePorOrdem`.
  - Posiciona ordens limites `BuyLimit` a cada `DistanciaGrid` abaixo da entrada até `NiveisGradiente`.
- **Sinal de Venda**:
  $$\text{venda\_vermelho (1º impulso)} \land \text{compra\_caindo} \land \text{TPV\_caindo}$$
  - Executa venda a mercado de `QuantidadePorOrdem`.
  - Posiciona ordens limites `SellLimit` a cada `DistanciaGrid` acima da entrada até `NiveisGradiente`.

### 4.2. Saída OCO Individual e Recarregamento
- Níveis executados lançam ordens limites de saída a `DistanciaGridSaida` pontos.
- Ao preencher uma OCO individual, se a posição ainda existir, o robô **recarrega imediatamente** a entrada naquele mesmo nível:
  - Com a Mola ativa: recarrega com o lote total do nível (`ObterTotalLotePorNivel(nivel)`).
  - Fora da Mola: recarrega com `QuantidadePorOrdem` (1 lote).
- Se a posição zerar via OCO individual, o ciclo é encerrado.

### 4.3. Mecanismo MOLA & Balde Consolidado
- **Ativação da Mola**:
  - Compra: `TPV_caindo` ou (`compra_caindo && venda_subindo`).
  - Venda: `TPV_subindo` ou (`venda_caindo && compra_subindo`).
- **Comportamento na Ativação**:
  - As ordens OCO individuais existentes são **mantidas ativas em seus preços originais** (desde que respeitem o teto do preço médio $\pm \text{MolaPontos}$).
  - Apenas as ordens que ultrapassarem o preço teto são migradas para o balde.
  - A única alteração que a Mola faz nas ordens pendentes é **ajustar a quantidade de contratos das ordens de entrada do grid ainda não executadas**, aplicando a tabela de progressão.
  - O volume do Balde é sempre mantido na invariante:
    $$\text{Volume Balde} = \text{Volume Total Posição} - \text{Volume OCOs Individuais Válidas}$$
- **Desativação da Mola**: Ao desativar a Mola, apenas as ordens de entrada pendentes voltam para 1 contrato (`QuantidadePorOrdem`), mantendo todas as ordens OCO e o Balde intactos.

### 4.4. Teto Universal e Stop Financeiro Global
- OCOs individuais nunca podem ultrapassar o preço do balde ($\text{Preço Médio} \pm \text{MolaPontos}$). Violações são migradas para o balde (`MigrarOrdensAlemDoTeto`).
- Se $(\text{Lucro Flutuante} + \text{Swap}) \le -\text{StopFinanceiro}$ (R$ -5.000,00):
  - Executa `PositionClose` imediatamente e cancela todas as pendentes.

---

## 5. Dependências
- Indicadores compilados em `MQL5/Indicators/dsalazar/`:
  - `Puck_Agressao.mq5`
  - `TPV_SMA.mq5`
