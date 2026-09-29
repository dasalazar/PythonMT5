# TPV_SMA

Indicador técnico customizado para MetaTrader 5 (MQL5), equivalente ao indicador **TPV (Total Price Volume)** com Média Móvel Simples (SMA) do Profit (NTSL).

---

## 1. Visão Geral
O **TPV_SMA** calcula o volume financeiro ponderado pela variação percentual do preço de fechamento de forma acumulada. Ele compara a curva acumulada do TPV com sua própria média móvel simples (SMA) e monitora a inclinação recente do TPV bruto.

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `PeriodoTPV` | `50` | Período da Média Móvel Simples (SMA) aplicada sobre a curva acumulada do TPV. |

---

## 3. Lógica de Cálculo e Regras

### 3.1. Acumulação do TPV
Para cada barra $i$:
$$v_i = \text{volume}_i \times \text{close}_i \quad (\text{estimativa de volume financeiro})$$
$$\text{retorno}_i = \frac{\text{close}_i - \text{close}_{i-1}}{\text{close}_{i-1}}$$
$$\text{TPV}_i = \text{TPV}_{i-1} + v_i \times \text{retorno}_i$$

### 3.2. Média Móvel Simples (SMA)
$$\text{MM}_i = \frac{1}{\text{PeriodoTPV}} \sum_{j=0}^{\text{PeriodoTPV}-1} \text{TPV}_{i-j}$$

### 3.3. As Duas Dimensões Independentes
1. **Regime de Posição (TPV vs Média)**:
   - $\text{SinalC} = 1.0$ (**Comprado**): $\text{TPV}_i > \text{MM}_i$
   - $\text{SinalV} = 1.0$ (**Vendido**): $\text{TPV}_i < \text{MM}_i$

2. **Direção da Inclinação Bruta (Subindo vs Caindo)**:
   - $\text{TPVSubindo} = 1.0$ (**Subindo**): $\text{TPV}_i > \text{TPV}_{i-3}$
   - $\text{TPVSubindo} = 0.0$ (**Caindo**): $\text{TPV}_i \le \text{TPV}_{i-3}$

### 3.4. Regra de Coloração da Linha
A linha principal do TPV assume cores dinâmicas baseadas na combinação das duas dimensões:
- **Verde**: $\text{Comprado} \land \text{Subindo}$ ($\text{TPV} > \text{MM}$ e $\text{TPV}_i > \text{TPV}_{i-3}$)
- **Vermelho**: $\text{Vendido} \land \text{Caindo}$ ($\text{TPV} < \text{MM}$ e $\text{TPV}_i \le \text{TPV}_{i-3}$)
- **Branco**: Casos mistos / indefinição (ex: Comprado mas Caindo, ou Vendido mas Subindo).

---

## 4. Mapeamento de Buffers (para uso via `iCustom`)

| Buffer Index | Nome Interno | Tipo | Descrição |
| :---: | :--- | :--- | :--- |
| `0` | `TPVBuffer` | `INDICATOR_DATA` | Valor da curva acumulada do TPV. |
| `1` | `CorTPVBuffer` | `INDICATOR_COLOR_INDEX` | Índice de cor da linha (0=Verde, 1=Vermelho, 2=Branco). |
| `2` | `MMBuffer` | `INDICATOR_DATA` | Valor da Média Móvel Simples (SMA) do TPV. |
| `3` | `SinalC` | `INDICATOR_CALCULATIONS` | `1.0` se TPV > Média (Comprado), `0.0` caso contrário. |
| `4` | `SinalV` | `INDICATOR_CALCULATIONS` | `1.0` se TPV < Média (Vendido), `0.0` caso contrário. |
| `5` | `TPVSubindo` | `INDICATOR_CALCULATIONS` | `1.0` se TPV[i] > TPV[i-3] (Subindo), `0.0` se Caindo. |
