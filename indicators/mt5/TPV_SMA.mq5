//+------------------------------------------------------------------+
//|                                                      TPV_SMA.mq5 |
//| Equivalente ao indicador TPV do NTSL (Profit):                   |
//|   TPV[i] := TPV[i-1] + v * ((Close[i]-Close[i-1]) / Close[i-1])  |
//|   mm := Media(PeriodoTPV, TPV)                                   |
//| v = aproximação de volume financeiro (real_volume * close),      |
//| pois o MT5 não fornece volume financeiro nativo por tick.        |
//|                                                                    |
//| Duas dimensões independentes, combinadas na cor da linha:         |
//|  1) Comprado/Vendido (SinalC/SinalV): TPV vs a própria Média.     |
//|  2) Subindo/Caindo (TPVSubindo): TPVBuffer[i] vs TPVBuffer[i-3],  |
//|     calculado sobre o valor BRUTO do TPV, não sobre a SMA — sem   |
//|     usar o MIN de 2 barras do Puck_Agressao (enviesado pro lado   |
//|     "subindo"), pra não piorar o ruído de um valor já sem         |
//|     suavização.                                                   |
//|                                                                    |
//| Comprado+Subindo = Verde | Vendido+Caindo = Vermelho | resto=Branco|
//+------------------------------------------------------------------+
#property copyright "Douglas"
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   2

#property indicator_label1  "TPV"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed,clrWhite
#property indicator_width1  1

#property indicator_label2  "Media TPV"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrWhite
#property indicator_width2  1

input int PeriodoTPV = 50;   // Período da SMA sobre o TPV

double TPVBuffer[];    // linha do TPV (acumulado)
double CorTPVBuffer[]; // índice de cor da linha do TPV (0=verde, 1=vermelho, 2=branco)
double MMBuffer[];     // SMA do TPV (linha branca, cor fixa)
double SinalC[];       // 1 quando TPV > média = Comprado (equivalente SinalTPVC), buffer de dados apenas
double SinalV[];       // 1 quando TPV < média = Vendido (equivalente SinalTPVV), buffer de dados apenas
double TPVSubindo[];   // 1 quando TPVBuffer[i] > TPVBuffer[i-3] = Subindo, 0 = Caindo — segunda dimensão, independente de Comprado/Vendido

int OnInit()
{
   SetIndexBuffer(0, TPVBuffer,   INDICATOR_DATA);
   SetIndexBuffer(1, CorTPVBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, MMBuffer,    INDICATOR_DATA);
   SetIndexBuffer(3, SinalC,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, SinalV,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, TPVSubindo,  INDICATOR_CALCULATIONS);

   ArraySetAsSeries(TPVBuffer,    false);
   ArraySetAsSeries(CorTPVBuffer, false);
   ArraySetAsSeries(MMBuffer,     false);
   ArraySetAsSeries(SinalC,       false);
   ArraySetAsSeries(SinalV,       false);
   ArraySetAsSeries(TPVSubindo,   false);

   IndicatorSetString(INDICATOR_SHORTNAME, "TPV(" + IntegerToString(PeriodoTPV) + ")");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                 const int prev_calculated,
                 const datetime &time[],
                 const double &open[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const long &tick_volume[],
                 const long &volume[],       // real_volume (volume em contratos)
                 const int &spread[])
{
   if(rates_total < PeriodoTPV + 2)
      return(0);

   int start;

   if(prev_calculated == 0)
   {
      TPVBuffer[0] = 0.0;
      start = 1;
   }
   else
      start = prev_calculated - 1;

   // --- Cálculo acumulado do TPV ---
   for(int i = start; i < rates_total; i++)
   {
      double v = (double)volume[i] * close[i];   // aproximação de volume financeiro
      double retorno = (close[i-1] != 0.0) ? (close[i] - close[i-1]) / close[i-1] : 0.0;

      TPVBuffer[i] = TPVBuffer[i-1] + v * retorno;
   }

   // --- SMA do TPV (equivalente a Media(PeriodoTPV, TPV)) ---
   int mmStart = MathMax(start, PeriodoTPV - 1);
   for(int i = mmStart; i < rates_total; i++)
   {
      double soma = 0.0;
      for(int j = 0; j < PeriodoTPV; j++)
         soma += TPVBuffer[i - j];

      MMBuffer[i] = soma / PeriodoTPV;

      SinalC[i] = (TPVBuffer[i] > MMBuffer[i]) ? 1.0 : 0.0;
      SinalV[i] = (TPVBuffer[i] < MMBuffer[i]) ? 1.0 : 0.0;

      // Segunda dimensão: Subindo/Caindo, sobre o TPV bruto (não a SMA)
      TPVSubindo[i] = (i >= 3 && TPVBuffer[i] > TPVBuffer[i - 3]) ? 1.0 : 0.0;

      // Combinação: Comprado+Subindo=verde, Vendido+Caindo=vermelho, resto=branco
      bool comprado = (SinalC[i] > 0.5);
      bool subindo  = (TPVSubindo[i] > 0.5);

      if(comprado && subindo)
         CorTPVBuffer[i] = 0; // verde
      else if(!comprado && !subindo)
         CorTPVBuffer[i] = 1; // vermelho
      else
         CorTPVBuffer[i] = 2; // branco (casos mistos)
   }

   return(rates_total);
}
