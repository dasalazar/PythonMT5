# Puck_Agressao

Indicador técnico customizado para MetaTrader 5 (MQL5), equivalente ao indicador **"Puck Agressão"** do Profit (NTSL).

---

## 1. Visão Geral
O **Puck_Agressao** calcula o saldo e a força da agressão compradora e vendedora através da leitura individual de cada negócio (ticks com flags de agressão). Ele aplica médias móveis exponenciais sobre a agressão normalizada para fornecer linhas independentes de pressão compradora e vendedora.

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `PeriodoPuckAgressao` | `21` | Período da soma móvel de volume e da média móvel exponencial. |
| `ReconstruirHistorico` | `true` | Se `true`, busca ticks passados via `CopyTicksRange` para inicializar barras anteriores sem aguardar formação em tempo real. |
| `DiasHistoricoTicks` | `1` | Quantidade de dias de histórico de ticks a buscar na inicialização. |

---

## 3. Lógica de Cálculo e Regras

### 3.1. Classificação dos Ticks
Para cada negócio executado no book:
- `TICK_FLAG_BUY`: Volume somado ao buffer compradora (`AgressionVolBuy`).
- `TICK_FLAG_SELL`: Volume somado ao buffer vendedor (`AgressionVolSell`).
- Ambos os flags ativos (Negócio Direto / Cross): Volume dividido igualmente ($50\%$ compra e $50\%$ venda).

### 3.2. Delta Acumulado e Normalização
Em uma janela deslizante de tamanho `PeriodoPuckAgressao`:
$$\text{somaDelta} = \sum_{j=0}^{\text{Periodo}-1} (\text{AgressionVolBuy}_{i-j} - \text{AgressionVolSell}_{i-j})$$
$$\text{somaVolume} = \sum_{j=0}^{\text{Periodo}-1} (\text{AgressionVolBuy}_{i-j} + \text{AgressionVolSell}_{i-j})$$
$$\text{cmfReal} = \frac{\text{somaDelta}}{\text{somaVolume}} \times 1000.0$$

Agressões separadas:
- $\text{agress\_pos} = \max(\text{cmfReal}, 0)$
- $\text{agress\_neg} = \max(-\text{cmfReal}, 0)$

### 3.3. Médias Móveis Exponenciais (EMA)
Com $\alpha = \frac{2}{\text{PeriodoPuckAgressao} + 1}$:
$$\text{MediaPos}[i] = \text{MediaPos}[i-1] + \alpha \times (\text{agress\_pos} - \text{MediaPos}[i-1])$$
$$\text{MediaNeg}[i] = \text{MediaNeg}[i-1] + \alpha \times (\text{agress\_neg} - \text{MediaNeg}[i-1])$$

### 3.4. Definição de Onda (Cruzamento de Médias)
- **Início de Nova Onda**: Ocorre no momento em que as médias `MediaPos` e `MediaNeg` se cruzam ($(\text{MediaPos}_i \ge \text{MediaNeg}_i) \neq (\text{MediaPos}_{i-1} \ge \text{MediaNeg}_{i-1})$).
- Ao iniciar uma nova onda, o histórico de impulsos (flags de subida/queda) é **reinicializado**.

### 3.5. Regras de Sinais e Coloração
As linhas possuem regras independentes de inclinação e histórico de impulsos dentro da onda:
- **Linha de Compra (`MediaPos`)**:
  - `compra_subindo`: $\text{MediaPos}[i] \ge \min(\text{MediaPos}[i-1], \text{MediaPos}[i-2])$
    - Se é o **1º impulso de subida da onda** (ainda não houve queda após subir nesta onda) $\rightarrow$ **Verde Escuro** (`clrForestGreen`, $\text{SinalC} = 1.0$).
    - Se está subindo **após já ter caído nesta mesma onda** (repique / 2º impulso) $\rightarrow$ **Verde Fraco** (`clrPaleGreen`, $\text{SinalC} = 2.0$).
  - `compra_caindo`: $\text{MediaPos}[i] < \min(\text{MediaPos}[i-1], \text{MediaPos}[i-2])$ $\rightarrow$ **Branco** (`clrWhite`, $\text{SinalC} = 0.0$).
- **Linha de Venda (`MediaNeg`)**:
  - `venda_subindo`: $\text{MediaNeg}[i] \ge \min(\text{MediaNeg}[i-1], \text{MediaNeg}[i-2])$
    - Se é o **1º impulso de subida da onda** $\rightarrow$ **Vermelho** (`clrRed`, $\text{SinalV} = 1.0$).
    - Se está subindo **após já ter caído nesta mesma onda** (repique / 2º impulso) $\rightarrow$ **Rosa Fraco** (`clrLightPink`, $\text{SinalV} = 2.0$).
  - `venda_caindo`: $\text{MediaNeg}[i] < \min(\text{MediaNeg}[i-1], \text{MediaNeg}[i-2])$ $\rightarrow$ **Branco** (`clrWhite`, $\text{SinalV} = 0.0$).

---

## 4. Mapeamento de Buffers (para uso via `iCustom`)

| Buffer Index | Nome Interno | Tipo | Descrição / Valores |
| :---: | :--- | :--- | :--- |
| `0` | `MediaPosBuffer` | `INDICATOR_DATA` | Valor numérico da EMA de Agressão Compradora. |
| `1` | `CorPosBuffer` | `INDICATOR_COLOR_INDEX` | Índice de cor da linha compradora (`0` = Verde Escuro, `1` = Branco, `2` = Verde Fraco). |
| `2` | `MediaNegBuffer` | `INDICATOR_DATA` | Valor numérico da EMA de Agressão Vendedora. |
| `3` | `CorNegBuffer` | `INDICATOR_COLOR_INDEX` | Índice de cor da linha vendedora (`0` = Vermelho, `1` = Branco, `2` = Rosa Fraco). |
| `4` | `SinalC` | `INDICATOR_CALCULATIONS` | `1.0` = Compra 1º Impulso (Verde Escuro), `2.0` = Compra Repique (Verde Fraco), `0.0` = Compra Caindo (Branco). |
| `5` | `SinalV` | `INDICATOR_CALCULATIONS` | `1.0` = Venda 1º Impulso (Vermelho), `2.0` = Venda Repique (Rosa Fraco), `0.0` = Venda Caindo (Branco). |
