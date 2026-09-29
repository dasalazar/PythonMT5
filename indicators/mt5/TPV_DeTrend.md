# TPV_DeTrend

Indicador técnico estatístico customizado para MetaTrader 5 (MQL5), que calcula o **DeTrend (descolamento/afastamento)** do TPV em relação à sua média móvel com bandas de Bollinger/Desvio Padrão ($\pm 2\sigma$ e $\pm 3\sigma$).

---

## 1. Visão Geral
O **TPV_DeTrend** quantifica a magnitude da divergência entre a curva acumulada do TPV e sua média histórica (`TPV_SMA`). O indicador traça a linha de afastamento oscilando em torno de zero, juntamente com bandas estatísticas de $2$ e $3$ desvios-padrão para identificar regiões de exaustão e sobreextensão ("esticado demais").

---

## 2. Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
| :--- | :--- | :--- |
| `PeriodoTPV` | `50` | Período de cálculo do indicador `TPV_SMA` e tamanho da janela móvel para a média e desvio-padrão do afastamento. |

---

## 3. Lógica de Cálculo e Regras

### 3.1. Afastamento Bruto
Lê os buffers do indicador `TPV_SMA` via `iCustom`:
$$\text{Afastamento}_i = \text{TPV}_i - \text{SMA}(\text{TPV}_i, \text{PeriodoTPV})$$

### 3.2. Média Móvel e Desvio Padrão do Afastamento
Em uma janela móvel de tamanho `PeriodoTPV`:
$$\mu_i = \frac{1}{\text{PeriodoTPV}} \sum_{j=0}^{\text{PeriodoTPV}-1} \text{Afastamento}_{i-j}$$
$$\sigma_i = \sqrt{\frac{1}{\text{PeriodoTPV}} \sum_{j=0}^{\text{PeriodoTPV}-1} (\text{Afastamento}_{i-j} - \mu_i)^2}$$

### 3.3. Bandas Estatísticas
- **Bandas de $2$ Desvios-Padrão ($2\sigma$)**:
  $$\text{Banda Superior } 2\sigma = \mu_i + 2 \times \sigma_i$$
  $$\text{Banda Inferior } 2\sigma = \mu_i - 2 \times \sigma_i$$

- **Bandas de $3$ Desvios-Padrão ($3\sigma$)**:
  $$\text{Banda Superior } 3\sigma = \mu_i + 3 \times \sigma_i$$
  $$\text{Banda Inferior } 3\sigma = \mu_i - 3 \times \sigma_i$$

### 3.4. Regra de Sinais e Coloração
- $\text{Afastamento}_i > 0$ ($\text{SinalC} = 1.0$): Linha de afastamento **Verde**.
- $\text{Afastamento}_i < 0$ ($\text{SinalV} = 1.0$): Linha de afastamento **Vermelha**.
*(Nota: As bandas em si fornecem contexto de saturação estatística e não geram gatilho direto de inversão).*

---

## 4. Mapeamento de Buffers (para uso via `iCustom`)

| Buffer Index | Nome Interno | Tipo | Plot / Estilo | Descrição |
| :---: | :--- | :--- | :--- | :--- |
| `0` | `AfastamentoBuffer` | `INDICATOR_DATA` | Linha Colorida (largura 2) | Valor do afastamento ($\text{TPV} - \text{Média}$). |
| `1` | `CorAfastamento` | `INDICATOR_COLOR_INDEX` | - | 0 = Verde (Afastamento > 0), 1 = Vermelho (Afastamento < 0). |
| `2` | `BandaSup2` | `INDICATOR_DATA` | Linha Prata Pontilhada | $\mu + 2\sigma$. |
| `3` | `BandaInf2` | `INDICATOR_DATA` | Linha Prata Pontilhada | $\mu - 2\sigma$. |
| `4` | `BandaSup3` | `INDICATOR_DATA` | Linha Cinza Tracejada | $\mu + 3\sigma$. |
| `5` | `BandaInf3` | `INDICATOR_DATA` | Linha Cinza Tracejada | $\mu - 3\sigma$. |
| `6` | `SinalC` | `INDICATOR_CALCULATIONS` | - | `1.0` se Afastamento > 0, `0.0` caso contrário. |
| `7` | `SinalV` | `INDICATOR_CALCULATIONS` | - | `1.0` se Afastamento < 0, `0.0` caso contrário. |

---

## 5. Dependências
- Requer `TPV_SMA.mq5` compilado no diretório `MQL5/Indicators/dsalazar/`.
