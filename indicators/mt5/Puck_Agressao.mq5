//+------------------------------------------------------------------+
//|                                            Puck_Agressao.mq5     |
//| Equivalente ao indicador "Puck Agressao" do NTSL (Profit).       |
//|                                                                    |
//| MODO PARAMETRIZÁVEL — controlado pelo input ReconstruirHistorico: |
//|  true  (opção 2): na primeira execução, reconstrói             |
//|        AgressionVolBuy/Sell das barras recentes buscando os     |
//|        ticks armazenados no MT5 (CopyTicksRange, DiasHistoricoTicks|
//|        dias pra trás), evitando o aquecimento zerado.           |
//|  false (opção 1): não busca nada pra trás — só tempo real, a    |
//|        partir do momento em que o indicador é carregado.        |
//| Nos dois casos, a atualização depois disso é sempre em tempo    |
//| real, a partir dos ticks novos.                                 |
//|                                                                    |
//| Classifica cada negócio pelos flags TICK_FLAG_BUY/SELL. Ticks com|
//| os dois flags ligados ("negócio direto") têm o volume dividido   |
//| meio a meio entre compra e venda.                                |
//|                                                                    |
//| REGRA DE ONDAS E COLORAÇÃO:                                      |
//|  - Início de nova onda: quando MediaPos e MediaNeg se cruzam.    |
//|  - Compra (MediaPos):                                            |
//|     * Verde Escuro (clrForestGreen): 1º impulso de subida.       |
//|     * Branco (clrWhite): Compra caindo / sem inclinação positiva.|
//|     * Verde Fraco (clrPaleGreen): Subindo após já ter caído.     |
//|  - Venda (MediaNeg):                                             |
//|     * Vermelho (clrRed): 1º impulso de subida.                   |
//|     * Branco (clrWhite): Venda caindo / sem inclinação positiva. |
//|     * Rosa Fraco (clrLightPink): Subindo após já ter caído.      |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   2

#property indicator_label1  "Media Agressao Compradora"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrForestGreen,clrWhite,clrPaleGreen
#property indicator_width1  1

#property indicator_label2  "Media Agressao Vendedora"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrRed,clrWhite,clrLightPink
#property indicator_width2  1

input int  PeriodoPuckAgressao   = 21;    // Período da soma móvel e da média exponencial
input bool ReconstruirHistorico  = true;  // true = opção 2 (reconstrói histórico via ticks) | false = opção 1 (só tempo real)
input int  DiasHistoricoTicks    = 1;     // Usado só se ReconstruirHistorico=true (só precisa cobrir ~PeriodoPuckAgressao barras)

double MediaPosBuffer[];   // media_agress_pos
double CorPosBuffer[];     // índice de cor compradora: 0=Verde Escuro, 1=Branco, 2=Verde Fraco
double MediaNegBuffer[];   // media_agress_neg
double CorNegBuffer[];     // índice de cor vendedora: 0=Vermelho, 1=Branco, 2=Rosa Fraco
double SinalC[];           // SinalPuckAgressaoC: 1.0 (verde escuro), 2.0 (verde fraco), 0.0 (branco)
double SinalV[];           // SinalPuckAgressaoV: 1.0 (vermelho), 2.0 (rosa fraco), 0.0 (branco)

double AgressionVolBuy[];  // arrays de trabalho (não são buffers de indicador)
double AgressionVolSell[];
bool   CompraJaSubiu[];    // rastreamento de estado por barra dentro da onda
bool   CompraTeveQueda[];
bool   VendaJaSubiu[];
bool   VendaTeveQueda[];

bool     g_historicoCarregado   = false;
datetime g_barraTentativaHistorico = 0; // barra em que a última tentativa de reconstruir o histórico falhou (retenta 1x por barra)

int OnInit()
{
   SetIndexBuffer(0, MediaPosBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, CorPosBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, MediaNegBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, CorNegBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, SinalC,         INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SinalV,         INDICATOR_CALCULATIONS);

   ArraySetAsSeries(MediaPosBuffer, false);
   ArraySetAsSeries(CorPosBuffer,   false);
   ArraySetAsSeries(MediaNegBuffer, false);
   ArraySetAsSeries(CorNegBuffer,   false);
   ArraySetAsSeries(SinalC,         false);
   ArraySetAsSeries(SinalV,         false);

   // Força explicitamente a tabela de cores no terminal para evitar que o MT5 use cache anterior
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 3);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrForestGreen); // 0 = Verde Escuro
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrWhite);       // 1 = Branco
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, clrPaleGreen);   // 2 = Verde Fraco

   PlotIndexSetInteger(1, PLOT_COLOR_INDEXES, 3);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, clrRed);         // 0 = Vermelho
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, clrWhite);       // 1 = Branco
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 2, clrLightPink);   // 2 = Rosa Fraco

   IndicatorSetString(INDICATOR_SHORTNAME, "PuckAgressao(" + IntegerToString(PeriodoPuckAgressao) + ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Classifica um bloco de ticks nas barras correspondentes           |
//+------------------------------------------------------------------+
void ClassificarTicks(MqlTick &ticks[], int total, const datetime &time[], int rates_total, int barraInicial)
{
   int barIdx = barraInicial;
   for(int t = 0; t < total; t++)
   {
      datetime tt = ticks[t].time;

      while(barIdx < rates_total - 1 && tt >= time[barIdx + 1])
         barIdx++;

      bool isBuy  = (ticks[t].flags & TICK_FLAG_BUY)  != 0;
      bool isSell = (ticks[t].flags & TICK_FLAG_SELL) != 0;

      if(!isBuy && !isSell)
         continue; // tick sem classificação de agressão (provável atualização de cotação, não negócio)

      double vol = (ticks[t].volume_real > 0) ? ticks[t].volume_real : (double)ticks[t].volume;

      if(isBuy && isSell)
      {
         // negócio "direto": metade pra cada lado, para não duplicar o volume total
         AgressionVolBuy[barIdx]  += vol / 2.0;
         AgressionVolSell[barIdx] += vol / 2.0;
      }
      else if(isBuy)
         AgressionVolBuy[barIdx] += vol;
      else
         AgressionVolSell[barIdx] += vol;
   }
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
   if(rates_total < PeriodoPuckAgressao + 2)
      return(0);

   // Força a direção dos arrays, para não depender do comportamento padrão
   ArraySetAsSeries(time, false);

   int prevCalc = prev_calculated;

   // --- Redimensiona arrays auxiliares zerando as posições novas (ArrayResize não inicializa) ---
   int tamAnterior = ArraySize(AgressionVolBuy);
   if(tamAnterior != rates_total)
   {
      ArrayResize(AgressionVolBuy, rates_total);
      ArrayResize(AgressionVolSell, rates_total);
      ArrayResize(CompraJaSubiu, rates_total);
      ArrayResize(CompraTeveQueda, rates_total);
      ArrayResize(VendaJaSubiu, rates_total);
      ArrayResize(VendaTeveQueda, rates_total);

      for(int k = tamAnterior; k < rates_total; k++)
      {
         AgressionVolBuy[k]  = 0.0;
         AgressionVolSell[k] = 0.0;
         CompraJaSubiu[k]    = false;
         CompraTeveQueda[k]  = false;
         VendaJaSubiu[k]     = false;
         VendaTeveQueda[k]   = false;
      }
   }

   // Recálculo total pedido pelo terminal (troca de período, histórico atualizado...): refaz o histórico também.
   if(prev_calculated == 0)
      g_historicoCarregado = false;

   // --- Histórico: reconstrói (ou não) conforme o parâmetro. Se a reconstrução falhar, retenta 1x por barra. ---
   bool reconstruiu = false;
   datetime barraAtual = time[rates_total - 1];

   if(!g_historicoCarregado)
   {
      if(ReconstruirHistorico)
      {
         if(g_barraTentativaHistorico != barraAtual)
         {
            g_barraTentativaHistorico = barraAtual;

            datetime inicio = TimeCurrent() - DiasHistoricoTicks * 86400;
            MqlTick ticks[];
            int copiados = 0;

            // Na primeira chamada, o terminal pode ainda não ter sincronizado o
            // histórico de tick localmente (comportamento documentado do MQL5) —
            // por isso tenta até 3 vezes, com uma pequena pausa entre elas.
            for(int tentativa = 1; tentativa <= 3; tentativa++)
            {
               copiados = CopyTicksRange(_Symbol, ticks, COPY_TICKS_TRADE, (ulong)inicio * 1000, 0);

               if(copiados > 0)
                  break;

               Print("PuckAgressao: tentativa ", tentativa, "/3 de reconstruir histórico não retornou ticks (terminal pode ainda estar sincronizando). Tentando novamente...");
               Sleep(300);
            }

            if(copiados > 0)
            {
               ArrayInitialize(AgressionVolBuy, 0.0);
               ArrayInitialize(AgressionVolSell, 0.0);
               ArrayInitialize(CompraJaSubiu, false);
               ArrayInitialize(CompraTeveQueda, false);
               ArrayInitialize(VendaJaSubiu, false);
               ArrayInitialize(VendaTeveQueda, false);

               ClassificarTicks(ticks, copiados, time, rates_total, 0);
               g_historicoCarregado = true;
               reconstruiu          = true;
               prevCalc             = 0;
            }
            else
               Print("PuckAgressao: nenhum tick histórico retornado após 3 tentativas. Seguindo só com os ticks das últimas barras; nova tentativa na próxima barra.");
         }
      }
      else
      {
         Print("PuckAgressao: iniciado em modo tempo real (ReconstruirHistorico=false). Barras anteriores a agora ficam sem valor de agressão.");
         g_historicoCarregado = true;
      }
   }

   // --- Atualização das barras recentes: ZERA e RECONTA a partir dos ticks (idempotente).
   //     Não acumula por chamada: o resultado não depende de quantas vezes o OnCalculate rodou,
   //     então o gráfico e o EA (instâncias separadas) chegam exatamente aos mesmos valores. ---
   if(!reconstruiu)
   {
      int recalcDe = rates_total - 2;
      if(prevCalc > 0)
         recalcDe = MathMin(prevCalc - 1, rates_total - 2);

      for(int k = recalcDe; k < rates_total; k++)
      {
         AgressionVolBuy[k]  = 0.0;
         AgressionVolSell[k] = 0.0;
      }

      MqlTick ticksNovos[];
      int copiados = CopyTicksRange(_Symbol, ticksNovos, COPY_TICKS_TRADE, (ulong)time[recalcDe] * 1000, 0);

      if(copiados > 0)
         ClassificarTicks(ticksNovos, copiados, time, rates_total, recalcDe);
   }

   // --- Delta, soma móvel, cmfReal, agress_pos/neg e médias exponenciais ---
   // Sempre recalcula também a barra 1 (a que o EA lê), pois o volume dela foi recontado acima.
   int start = (prevCalc == 0) ? PeriodoPuckAgressao - 1 : MathMax(MathMin(prevCalc - 1, rates_total - 2), PeriodoPuckAgressao - 1);
   double alpha = 2.0 / (PeriodoPuckAgressao + 1.0);

   if(prevCalc == 0)
   {
      for(int k = 0; k < PeriodoPuckAgressao - 1; k++)
      {
         MediaPosBuffer[k] = 0.0;
         MediaNegBuffer[k] = 0.0;
         CorPosBuffer[k]   = 1; // branco
         CorNegBuffer[k]   = 1; // branco
         SinalC[k]         = 0.0;
         SinalV[k]         = 0.0;
         CompraJaSubiu[k]   = false;
         CompraTeveQueda[k] = false;
         VendaJaSubiu[k]    = false;
         VendaTeveQueda[k]  = false;
      }
   }

   for(int i = start; i < rates_total; i++)
   {
      double somaDelta = 0.0, somaVolume = 0.0;

      for(int j = 0; j < PeriodoPuckAgressao; j++)
      {
         double delta    = AgressionVolBuy[i - j] - AgressionVolSell[i - j];
         double volTotal = AgressionVolBuy[i - j] + AgressionVolSell[i - j];
         somaDelta  += delta;
         somaVolume += volTotal;
      }

      double cmfReal = (somaVolume > 0) ? (somaDelta / somaVolume) * 1000.0 : 0.0;

      double agress_pos = (cmfReal > 0) ? MathAbs(cmfReal) : 0.0;
      double agress_neg = (cmfReal < 0) ? MathAbs(cmfReal) : 0.0;

      if(i == 0 || (i == PeriodoPuckAgressao - 1 && prevCalc == 0))
      {
         // semente da média exponencial: primeiro valor calculado da janela
         MediaPosBuffer[i] = agress_pos;
         MediaNegBuffer[i] = agress_neg;
      }
      else
      {
         MediaPosBuffer[i] = MediaPosBuffer[i - 1] + alpha * (agress_pos - MediaPosBuffer[i - 1]);
         MediaNegBuffer[i] = MediaNegBuffer[i - 1] + alpha * (agress_neg - MediaNegBuffer[i - 1]);
      }

      // --- Início de nova onda: cruzamento das médias MediaPos e MediaNeg ---
      bool cruzamento = false;
      if(i > PeriodoPuckAgressao - 1)
      {
         bool posAcimaAtual = (MediaPosBuffer[i] >= MediaNegBuffer[i]);
         bool posAcimaAnt   = (MediaPosBuffer[i - 1] >= MediaNegBuffer[i - 1]);
         cruzamento = (posAcimaAtual != posAcimaAnt);
      }

      bool compra_ja_subiu   = false;
      bool compra_teve_queda = false;
      bool venda_ja_subiu    = false;
      bool venda_teve_queda  = false;

      if(i > 0 && !cruzamento)
      {
         // Herda estado da barra anterior dentro da mesma onda
         compra_ja_subiu   = CompraJaSubiu[i - 1];
         compra_teve_queda = CompraTeveQueda[i - 1];
         venda_ja_subiu    = VendaJaSubiu[i - 1];
         venda_teve_queda  = VendaTeveQueda[i - 1];
      }
      // Se cruzamento == true, as flags iniciam zeradas (false) para a nova onda

      // --- Inclinação das médias ---
      bool compra_subindo = false;
      bool venda_subindo  = false;

      if(i >= 2)
      {
         compra_subindo = (MediaPosBuffer[i] >= MathMin(MediaPosBuffer[i - 1], MediaPosBuffer[i - 2]));
         venda_subindo  = (MediaNegBuffer[i] >= MathMin(MediaNegBuffer[i - 1], MediaNegBuffer[i - 2]));
      }
      else if(i == 1)
      {
         compra_subindo = (MediaPosBuffer[i] >= MediaPosBuffer[i - 1]);
         venda_subindo  = (MediaNegBuffer[i] >= MediaNegBuffer[i - 1]);
      }

      // --- Classificação de Sinal e Cor para Compra (MediaPos) ---
      if(compra_subindo)
      {
         if(!compra_teve_queda)
         {
            // 1º impulso de subida da onda -> Verde Escuro
            SinalC[i]       = 1.0;
            CorPosBuffer[i] = 0; // 0 = clrForestGreen
            compra_ja_subiu = true;
         }
         else
         {
            // Repique: subindo após já ter caído nesta mesma onda -> Verde Fraco
            SinalC[i]       = 2.0;
            CorPosBuffer[i] = 2; // 2 = clrPaleGreen
         }
      }
      else
      {
         // Compra caindo / sem inclinação positiva -> Branco
         SinalC[i]       = 0.0;
         CorPosBuffer[i] = 1; // 1 = clrWhite
         if(compra_ja_subiu)
            compra_teve_queda = true;
      }

      // --- Classificação de Sinal e Cor para Venda (MediaNeg) ---
      if(venda_subindo)
      {
         if(!venda_teve_queda)
         {
            // 1º impulso de subida da onda -> Vermelho
            SinalV[i]       = 1.0;
            CorNegBuffer[i] = 0; // 0 = clrRed
            venda_ja_subiu  = true;
         }
         else
         {
            // Repique: subindo após já ter caído nesta mesma onda -> Rosa Fraco
            SinalV[i]       = 2.0;
            CorNegBuffer[i] = 2; // 2 = clrLightPink
         }
      }
      else
      {
         // Venda caindo / sem inclinação positiva -> Branco
         SinalV[i]       = 0.0;
         CorNegBuffer[i] = 1; // 1 = clrWhite
         if(venda_ja_subiu)
            venda_teve_queda = true;
      }

      // Salva os estados da barra para persistência incremental
      CompraJaSubiu[i]   = compra_ja_subiu;
      CompraTeveQueda[i] = compra_teve_queda;
      VendaJaSubiu[i]    = venda_ja_subiu;
      VendaTeveQueda[i]  = venda_teve_queda;
   }

   return(rates_total);
}
