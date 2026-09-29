//+------------------------------------------------------------------+
//|                                              TPV_DeTrend.mq5     |
//| DeTrend do TPV: mede o "afastamento" do TPV em relação à própria |
//| média, e coloca bandas estatísticas (2 e 3 desvios-padrão) ao    |
//| redor da média móvel desse afastamento.                          |
//|                                                                    |
//| afastamento    = TPV - Media(TPV, PeriodoTPV)                     |
//| mm_afastamento = Media(afastamento, PeriodoTPV)     [rolling]     |
//| desvio         = DesvioPadrao(afastamento, PeriodoTPV) [rolling]  |
//|                                                                    |
//| banda_sup_2dp = mm_afastamento + 2 * desvio                       |
//| banda_inf_2dp = mm_afastamento - 2 * desvio                       |
//| banda_sup_3dp = mm_afastamento + 3 * desvio                       |
//| banda_inf_3dp = mm_afastamento - 3 * desvio                       |
//|                                                                    |
//| Não recalcula o TPV — lê o TPV_SMA já existente via iCustom       |
//| (buffer 0 = TPV, buffer 2 = Média), mesmo padrão usado no EA      |
//| GradienteLinear, pra não duplicar a fórmula em dois lugares.      |
//|                                                                    |
//| SinalC/SinalV = sinal do próprio afastamento (afastamento > 0 ou  |
//| < 0), mesma convenção usada no TPV_SMA — fonte única de verdade,  |
//| a cor da linha principal é derivada daqui. As bandas em si não    |
//| geram sinal — são só contexto visual de "esticado demais".        |
//|                                                                    |
//| Requer TPV_SMA.mq5 já compilado em MQL5/Indicators/dsalazar.      |
//| Aviso de aquecimento: as primeiras ~2×PeriodoTPV barras podem     |
//| ficar distorcidas, porque o TPV_SMA também está aquecendo ao      |
//| mesmo tempo que a janela estatística deste indicador.             |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   5

#property indicator_label1  "Afastamento TPV"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed
#property indicator_width1  2

#property indicator_label2  "Banda Superior 2DP"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "Banda Inferior 2DP"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

#property indicator_label4  "Banda Superior 3DP"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGray
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

#property indicator_label5  "Banda Inferior 3DP"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGray
#property indicator_style5  STYLE_DASH
#property indicator_width5  1

input int PeriodoTPV = 50;   // Deve bater com o período configurado no indicador TPV_SMA; também usado como janela da média/desvio do afastamento

double AfastamentoBuffer[];  // afastamento = TPV - Média(TPV)
double CorAfastamento[];     // índice de cor (0 = verde, 1 = vermelho), derivado de SinalC/SinalV
double BandaSup2[];
double BandaInf2[];
double BandaSup3[];
double BandaInf3[];
double SinalC[];             // afastamento > 0 (buffer de dados, fonte única de verdade da cor)
double SinalV[];             // afastamento < 0 (buffer de dados, fonte única de verdade da cor)

int handleTPV = INVALID_HANDLE;

int OnInit()
{
   SetIndexBuffer(0, AfastamentoBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, CorAfastamento,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BandaSup2,         INDICATOR_DATA);
   SetIndexBuffer(3, BandaInf2,         INDICATOR_DATA);
   SetIndexBuffer(4, BandaSup3,         INDICATOR_DATA);
   SetIndexBuffer(5, BandaInf3,         INDICATOR_DATA);
   SetIndexBuffer(6, SinalC,            INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, SinalV,            INDICATOR_CALCULATIONS);

   ArraySetAsSeries(AfastamentoBuffer, false);
   ArraySetAsSeries(CorAfastamento,    false);
   ArraySetAsSeries(BandaSup2,         false);
   ArraySetAsSeries(BandaInf2,         false);
   ArraySetAsSeries(BandaSup3,         false);
   ArraySetAsSeries(BandaInf3,         false);
   ArraySetAsSeries(SinalC,            false);
   ArraySetAsSeries(SinalV,            false);

   handleTPV = iCustom(_Symbol, PERIOD_CURRENT, "dsalazar\\TPV_SMA", PeriodoTPV);
   if(handleTPV == INVALID_HANDLE)
   {
      Print("TPV_DeTrend: falha ao carregar o indicador TPV_SMA. Confirme que está compilado em MQL5/Indicators/dsalazar.");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "TPV_DeTrend(" + IntegerToString(PeriodoTPV) + ")");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(handleTPV != INVALID_HANDLE)
      IndicatorRelease(handleTPV);
}

int OnCalculate(const int rates_total,
                 const int prev_calculated,
                 const datetime &time[],
                 const double &open[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const long &tick_volume[],
                 const long &volume[],
                 const int &spread[])
{
   // Precisa de barras suficientes pro TPV_SMA aquecer (PeriodoTPV) e ainda
   // ter PeriodoTPV afastamentos pra trás pra calcular média/desvio.
   if(rates_total < PeriodoTPV * 2)
      return(0);

   int start = (prev_calculated == 0) ? PeriodoTPV : MathMax(prev_calculated - 1, PeriodoTPV);

   // Só busca no TPV_SMA a faixa necessária: do início da janela estatística
   // mais recuada até o fim, não o histórico inteiro a cada tick.
   int copiarDe = MathMax(0, start - PeriodoTPV);
   int copiarQtd = rates_total - copiarDe;

   // start_pos do CopyBuffer conta SEMPRE a partir da barra atual (0 = mais
   // recente), independente do ArraySetAsSeries do array de destino — por
   // isso é sempre 0 aqui: queremos as 'copiarQtd' barras mais recentes,
   // que cobrem exatamente o intervalo [copiarDe, rates_total) em índice
   // absoluto. tpvArr[0] = barra copiarDe, tpvArr[copiarQtd-1] = barra atual.
   double tpvArr[], mmArr[];
   ArrayResize(tpvArr, copiarQtd);
   ArrayResize(mmArr, copiarQtd);
   ArraySetAsSeries(tpvArr, false);
   ArraySetAsSeries(mmArr, false);

   if(CopyBuffer(handleTPV, 0, 0, copiarQtd, tpvArr) <= 0) return(0); // TPV_SMA ainda não calculou essa faixa
   if(CopyBuffer(handleTPV, 2, 0, copiarQtd, mmArr)  <= 0) return(0);

   for(int i = copiarDe; i < rates_total; i++)
      AfastamentoBuffer[i] = tpvArr[i - copiarDe] - mmArr[i - copiarDe];

   for(int i = start; i < rates_total; i++)
   {
      double soma = 0.0;
      for(int j = 0; j < PeriodoTPV; j++)
         soma += AfastamentoBuffer[i - j];
      double media = soma / PeriodoTPV;

      double somaQuadrados = 0.0;
      for(int j = 0; j < PeriodoTPV; j++)
      {
         double diff = AfastamentoBuffer[i - j] - media;
         somaQuadrados += diff * diff;
      }
      double desvio = MathSqrt(somaQuadrados / PeriodoTPV);

      BandaSup2[i] = media + 2.0 * desvio;
      BandaInf2[i] = media - 2.0 * desvio;
      BandaSup3[i] = media + 3.0 * desvio;
      BandaInf3[i] = media - 3.0 * desvio;

      SinalC[i] = (AfastamentoBuffer[i] > 0) ? 1.0 : 0.0;
      SinalV[i] = (AfastamentoBuffer[i] < 0) ? 1.0 : 0.0;

      CorAfastamento[i] = (SinalC[i] == 1.0) ? 0 : 1; // 0 = verde, 1 = vermelho
   }

   return(rates_total);
}
