# EA_GradienteLinear2 (v2)

Robô de grid (Gradiente Linear) — versão 2, nativo em MQL5 para MetaTrader 5 em conta **NETTING** (WINFUT / B3).

---

## 1. Visão Geral e Principais Mudanças em Relação à v1

1. **Stop Financeiro Global**: Substitui o stop técnico por indicadores por um limite financeiro fixo em R$ (`StopFinanceiro`, padrão R$ 5.000,00).
2. **Entrada baseada no TPV Subindo/Caindo**: O TPV entra na dimensão de inclinação rápida (`TPVSubindo`/`TPVCaindo`) em vez de apenas cruzamento com a média (`TPV_comprado`/`TPV_vendido`).
3. **Mecanismo Mola com "Balde Persistente" e Lote 2x**:
   - Não altera o espaçamento do grid (`DistanciaGrid` permanece constante).
   - Dobra a quantidade das ordens pendentes para 2x (`QuantidadePorOrdem * 2`).
   - A cada execução de nível dobrado: metade (1x) vira uma OCO individual normal (`DistanciaGridSaida`), e a outra metade é acumulada no **Balde** (uma ordem consolidada mantida no $\text{Preço Médio} \pm \text{MolaPontos}$).
   - O balde **persiste durante todo o ciclo**, mesmo que a Mola desligue.
4. **Teto Universal de Saída**: Nenhuma OCO individual pode ter alvo além de $\text{Preço Médio} \pm \text{MolaPontos}$. Alvos que ultrapassariam o teto são incorporados ao balde.
5. **Magic Number**: `198199` (permite execução paralela com a v1 no mesmo ativo).

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `NiveisGradiente` | `50` | Quantidade máxima de níveis de grid. |
| `DistanciaGrid` | `75.0` | Espaçamento entre ordens de entrada (pontos). |
| `DistanciaGridSaida` | `100.0` | Alvo de lucro da saída OCO individual (pontos). |
| `DistanciaGridMola` | `150.0` | *(Não utilizado na v2)* Mantido por compatibilidade. |
| `MolaPontos` | `50.0` | Distância do Balde a partir do preço médio da posição. |
| `ToleranciaDescarga`| `25.0` | Margem de segurança antes de disparar a descarga do balde. |
| `QuantidadePorOrdem`| `1` | Quantidade base de contratos por ordem. |
| `PeriodoPuckAgressao`| `21` | Período do indicador `Puck_Agressao`. |
| `ReconstruirHistorico`| `true` | Reconstrói histórico de agressão via ticks. |
| `DiasHistoricoTicks`| `2` | Dias de histórico de ticks para reconstrução. |
| `PeriodoTPV` | `50` | Período do indicador `TPV_SMA`. |
| `StopFinanceiro` | `5000.0` | Perda flutuante máxima em R$ para fechar tudo. |
| `MagicNumber` | `198199` | Identificador único das ordens. |

---

## 3. Regras de Entrada
Executadas apenas quando **não há posição aberta** (`!PositionSelect`):

- **Sinal de Compra**:
  $$\text{compra\_subindo} \land \neg\text{venda\_subindo} \land \text{TPV\_subindo}$$
  - Abre ordem a mercado `Buy` de `QuantidadePorOrdem`.
  - Posiciona ordens limites `BuyLimit` a cada `DistanciaGrid` (75 pts) abaixo da entrada.

- **Sinal de Venda**:
  $$\text{venda\_subindo} \land \neg\text{compra\_subindo} \land \text{TPV\_caindo}$$
  - Abre ordem a mercado `Sell` de `QuantidadePorOrdem`.
  - Posiciona ordens limites `SellLimit` a cada `DistanciaGrid` (75 pts) acima da entrada.

---

## 4. Regras de Saída e Gerenciamento

### 4.1. Saída OCO Individual
- Cada nível executado (1x) gera um take-profit individual a `DistanciaGridSaida` (100 pts) do preço executado.
- Se o take-profit individual preencher:
  - Se ainda houver posição aberta, o nível é recarregado (com 1x ou 2x dependendo do estado atual da Mola).
  - Se zerar a posição, encerra o ciclo e cancela ordens pendentes.

### 4.2. Mecanismo Mola e o "Balde"
- **Ativação**:
  - Posição Comprada: `TPV_caindo`
  - Posição Vendida: `TPV_subindo`
- **Ao Ativar**:
  - As ordens de entrada pendentes restantes têm sua quantidade dobrada (`QuantidadePorOrdem * 2`).
  - OCOs individuais existentes fora do balde são canceladas e somadas ao volume do balde.
  - O balde é recalculado: $\text{Volume Balde} = \text{Volume Posição} - \text{Volume OCOs Individuais}$.
  - Ordem do balde é colocada no $\text{Preço Médio} \pm \text{MolaPontos}$.
- **Ao Desativar** (`TPV_subindo` para comprado / `TPV_caindo` para vendido):
  - As entradas pendentes voltam a ter quantidade normal (1x).
  - O balde **permanece ativo** no preço médio, aguardando execução ou nova ativação.

### 4.3. Teto Universal
- Alvos de OCO individuais não podem ficar além do preço médio $\pm$ `MolaPontos`.
- A função `MigrarOrdensAlemDoTeto` varre ordens e converte qualquer alvo além do teto diretamente para o volume do balde.

### 4.4. Stop Financeiro
- Prioridade máxima absoluta sobre qualquer outra regra.
- Se o resultado flutuante ($\text{Profit} + \text{Swap}$) atingir $\le -\text{StopFinanceiro}$ (ex: $\le -\text{R\$\ } 5.000,00$):
  - Envia `PositionClose` para zerar a mercado.
  - Cancela todas as ordens pendentes (grid, OCOs e balde).
  - Reseta todo o estado interno.

---

## 5. Dependências
- Indicadores compilados em `MQL5/Indicators/dsalazar/`:
  - `Puck_Agressao.mq5`
  - `TPV_SMA.mq5`
