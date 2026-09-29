# EA_GradienteLinear (v1)

Robô de grid (Gradiente Linear) nativo em MQL5 para MetaTrader 5, operando em conta **NETTING** no mini-índice da B3 (WINFUT).

---

## 1. Visão Geral e Estratégia
O **EA_GradienteLinear** combina análise de fluxo/agressão (`Puck_Agressao`) e volume com tendência de preço (`TPV_SMA`) para realizar entradas automáticas a favor do movimento e gerenciar um grid linear com saídas OCO individuais e um mecanismo defensivo intermediário denominado **MOLA**.

- **Magic Number**: `198198`
- **Modo de Conta**: NETTING (posição agregada única).
- **Entrada**: 1 ordem a mercado na direção do sinal + pré-posicionamento de até `NiveisGradiente` ordens pendentes limitadas.

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `NiveisGradiente` | `50` | Quantidade máxima de níveis de grid pendentes. |
| `DistanciaGrid` | `75.0` | Espaçamento entre ordens de entrada do grid (pontos). |
| `DistanciaGridSaida` | `100.0` | Alvo da saída OCO individual em pontos a partir do preço de preenchimento. |
| `DistanciaGridMola` | `150.0` | Espaçamento das ordens de entrada pendentes enquanto a Mola estiver ativa. |
| `MolaPontos` | `50.0` | Distância da saída consolidada a partir do preço médio durante a Mola. |
| `QuantidadePorOrdem` | `1` | Quantidade de contratos por nível/ordem. |
| `PeriodoPuckAgressao` | `21` | Período do indicador `Puck_Agressao`. |
| `ReconstruirHistorico` | `true` | Reconstrói histórico de agressão via ticks no `Puck_Agressao`. |
| `DiasHistoricoTicks` | `2` | Dias de histórico de ticks para reconstrução do `Puck_Agressao`. |
| `PeriodoTPV` | `50` | Período da média móvel do indicador `TPV_SMA`. |
| `MagicNumber` | `198198` | Identificador das ordens do robô. |

---

## 3. Regras de Entrada
A entrada é disparada apenas quando o robô **não está posicionado** (`!PositionSelect`):

- **Sinal de Compra**:
  $$\text{compra\_subindo} \land \neg\text{venda\_subindo} \land \text{TPV\_comprado}$$
  - Abre posição compradora a mercado (`Buy`) com `QuantidadePorOrdem`.
  - Posiciona ordens `BuyLimit` a cada `DistanciaGrid` pontos abaixo do preço de entrada (até `NiveisGradiente`).

- **Sinal de Venda**:
  $$\text{venda\_subindo} \land \neg\text{compra\_subindo} \land \text{TPV\_vendido}$$
  - Abre posição vendedora a mercado (`Sell`) com `QuantidadePorOrdem`.
  - Posiciona ordens `SellLimit` a cada `DistanciaGrid` pontos acima do preço de entrada (até `NiveisGradiente`).

---

## 4. Regras de Saída (Fora da Mola)
1. **Take-Profit Individual (OCO por nível)**:
   - A cada preenchimento de entrada (mercado ou nível de grid), é enviada uma ordem limite de saída a `DistanciaGridSaida` (100 pontos) do preço real preenchido.
   - Quando a ordem de saída é executada:
     - Se ainda restar posição aberta, o nível é **recarregado** recolocando a ordem de entrada no mesmo preço.
     - Se a posição zerar (última unidade preenchida), o **ciclo é encerrado** e todas as ordens pendentes órfãs são canceladas.

2. **Stop por Sinal (Inversão de Indicadores)**:
   - Fecha a posição inteira a mercado (`PositionClose`) e cancela todas as ordens pendentes se qualquer uma das condições de stop ocorrer:
   - **Stop Comprado**:
     - `(media_pos < media_neg) E venda_subindo E compra_caindo E TPV_vendido` (Regime desfavorável com 3 confirmações)
     - **OU** `viradaParaVenda`: dominância das médias inverteu na barra atual (`media_pos[1] > media_neg[1] && media_pos[0] < media_neg[0]`).
   - **Stop Vendido**:
     - `(media_neg < media_pos) E compra_subindo E venda_caindo E TPV_comprado`
     - **OU** `viradaParaCompra`: dominância das médias inverteu na barra atual (`media_neg[1] > media_pos[1] && media_neg[0] < media_pos[0]`).

---

## 5. Mecanismo MOLA (Estado Defensivo Intermediário)
O estado MOLA é ativado quando o TPV passa a se mover contra a posição sem que o stop por sinal tenha sido acionado:

- **Ativação**:
  - Posição Comprada: `TPV_caindo`
  - Posição Vendida: `TPV_subindo`
- **Ações na Ativação**:
  1. Cancela ordens pendentes de entrada e saídas OCO individuais.
  2. Recoloca ordens pendentes restantes com espaçamento ampliado (`DistanciaGridMola` = 150 pontos) a partir da entrada original.
  3. Consolida todas as saídas em **uma única ordem de saída** no $\text{Preço Médio} \pm \text{MolaPontos}$ cobrindo 100% do volume da posição.
- **Desativação / Encerramento da Mola**:
  - **Via Take-Profit**: Se a saída consolidada for totalmente executada, a posição é zerada e o ciclo se encerra.
  - **Via Retomada do Sinal Normal**: Se `TPV_subindo` (comprado) ou `TPV_caindo` (vendido) voltar a ocorrer enquanto posicionado:
    - Cancela a saída consolidada e ordens com espaçamento ampliado.
    - Reconstrói as saídas OCO individuais de cada nível preenchido.
    - Recoloca as entradas pendentes no espaçamento padrão (`DistanciaGrid`).

---

## 6. Dependências
- Indicadores compilados em `MQL5/Indicators/dsalazar/`:
  - `Puck_Agressao.mq5`
  - `TPV_SMA.mq5`
