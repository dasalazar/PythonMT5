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
//| NOTA: o bloco original em NTSL tinha uma condição "else if"      |
//| inalcançável (o cmfReal>0 dentro do else de cmfReal>0). O efeito |
//| líquido do código original é matematicamente idêntico a:         |
//|   agress_pos := max(cmfReal, 0)                                  |
//|   agress_neg := max(-cmfReal, 0)                                 |
//| que é o que está implementado abaixo. Se a intenção original era |
//| outra (reação diferente quando o preço reverte contra o sinal),  |
//| me avise para eu ajustar.                                        |
//+------------------------------------------------------------------+
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   2

#property indicator_label1  "Media Agressao Compradora"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrWhite
#property indicator_width1  1

#property indicator_label2  "Media Agressao Vendedora"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrRed,clrWhite
#property indicator_width2  1

input int  PeriodoPuckAgressao   = 21;    // Período da soma móvel e da média exponencial
input bool ReconstruirHistorico  = true;  // true = opção 2 (reconstrói histórico via ticks) | false = opção 1 (só tempo real)
input int  DiasHistoricoTicks    = 1;     // Usado só se ReconstruirHistorico=true (só precisa cobrir ~PeriodoPuckAgressao barras)

double MediaPosBuffer[];   // media_agress_pos
double CorPosBuffer[];     // índice de cor da linha compradora (0=verde, 1=branco) — independente da linha de venda
double MediaNegBuffer[];   // media_agress_neg
double CorNegBuffer[];     // índice de cor da linha vendedora (0=vermelho, 1=branco) — independente da linha de compra
double SinalC[];           // SinalPuckAgressaoC = compra_subindo (1.0/0.0), buffer de dados apenas — fonte da cor da linha compradora
double SinalV[];           // SinalPuckAgressaoV = venda_subindo (1.0/0.0), buffer de dados apenas — fonte da cor da linha vendedora

double AgressionVolBuy[];  // arrays de trabalho (não são buffers de indicador)
double AgressionVolSell[];

datetime g_ultimoTickProcessado = 0;
bool     g_historicoCarregado   = false;

int OnInit()
{
   SetIndexBuffer(0, MediaPosBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, CorPosBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, MediaNegBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, CorNegBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, SinalC, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SinalV, INDICATOR_CALCULATIONS);

   ArraySetAsSeries(MediaPosBuffer, false);
   ArraySetAsSeries(CorPosBuffer,   false);
   ArraySetAsSeries(MediaNegBuffer, false);
   ArraySetAsSeries(CorNegBuffer,   false);
   ArraySetAsSeries(SinalC, false);
   ArraySetAsSeries(SinalV, false);

   IndicatorSetString(INDICATOR_SHORTNAME, "PuckAgressao(" + IntegerToString(PeriodoPuckAgressao) + ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Classifica um bloco de ticks nas barras correspondentes           |
//+------------------------------------------------------------------+
void ClassificarTicks(MqlTick &ticks[], int total, const datetime &time[], int rates_total)
{
   int barIdx = 0;
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

   // --- Redimensiona arrays auxiliares preservando dados já calculados ---
   if(ArraySize(AgressionVolBuy) != rates_total)
   {
      ArrayResize(AgressionVolBuy, rates_total);
      ArrayResize(AgressionVolSell, rates_total);
   }

   // --- Inicialização (uma única vez): reconstrói histórico ou não, conforme o parâmetro ---
   if(!g_historicoCarregado)
   {
      ArrayInitialize(AgressionVolBuy, 0.0);
      ArrayInitialize(AgressionVolSell, 0.0);

      if(ReconstruirHistorico)
      {
         datetime inicio = TimeCurrent() - DiasHistoricoTicks * 86400;
         MqlTick ticks[];
         int copiados = 0;

         // Na primeira chamada, o terminal pode ainda não ter sincronizado o
         // histórico de tick localmente (comportamento documentado do MQL5) —
         // por isso tenta até 3 vezes, com uma pequena pausa entre elas, antes
         // de desistir e seguir só em tempo real.
         for(int tentativa = 1; tentativa <= 3; tentativa++)
         {
            copiados = CopyTicksRange(_Symbol, ticks, COPY_TICKS_TRADE, (ulong)inicio * 1000, (ulong)TimeCurrent() * 1000);

            if(copiados > 0)
               break;

            Print("PuckAgressao: tentativa ", tentativa, "/3 de reconstruir histórico não retornou ticks (terminal pode ainda estar sincronizando). Tentando novamente...");
            Sleep(300);
         }

         if(copiados > 0)
            ClassificarTicks(ticks, copiados, time, rates_total);
         else
            Print("PuckAgressao: nenhum tick histórico retornado após 3 tentativas. Seguindo só em tempo real a partir de agora (aquecimento de ~", PeriodoPuckAgressao, " barras).");
      }
      else
      {
         Print("PuckAgressao: iniciado em modo tempo real (ReconstruirHistorico=false). Barras anteriores a agora ficam sem valor de agressão.");
      }

      g_ultimoTickProcessado = TimeCurrent();
      g_historicoCarregado   = true;
   }
   else
   {
      // --- Atualização incremental: só os ticks novos desde a última chamada (igual nos dois modos) ---
      MqlTick ticksNovos[];
      int copiados = CopyTicksRange(_Symbol, ticksNovos, COPY_TICKS_TRADE, (ulong)g_ultimoTickProcessado * 1000, (ulong)TimeCurrent() * 1000 + 1000);

      if(copiados > 0)
         ClassificarTicks(ticksNovos, copiados, time, rates_total);

      g_ultimoTickProcessado = TimeCurrent();
   }

   // --- Delta, soma móvel, cmfReal, agress_pos/neg e médias exponenciais ---
   int start = (prev_calculated == 0) ? PeriodoPuckAgressao - 1 : MathMax(prev_calculated - 1, PeriodoPuckAgressao - 1);
   double alpha = 2.0 / (PeriodoPuckAgressao + 1.0);

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

      if(i == 0 || (i == start && prev_calculated == 0))
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

      // --- Cor das linhas: cada linha agora tem sua PRÓPRIA regra,
      //     independente da outra (compra e venda não se comparam entre si).
      //     SinalC/SinalV são a fonte única de verdade — calculados aqui,
      //     e a cor é derivada deles (não recalculada em separado). ---
      if(i >= 2)
      {
         bool compra_subindo = (MediaPosBuffer[i] >= MathMin(MediaPosBuffer[i-1], MediaPosBuffer[i-2]));
         bool venda_subindo  = (MediaNegBuffer[i] >= MathMin(MediaNegBuffer[i-1], MediaNegBuffer[i-2]));

         SinalC[i] = compra_subindo ? 1.0 : 0.0;
         SinalV[i] = venda_subindo  ? 1.0 : 0.0;
      }
      else
      {
         SinalC[i] = 0.0; // sem barras suficientes ainda: assume caindo por padrão
         SinalV[i] = 0.0;
      }

      int corPos = (SinalC[i] == 1.0) ? 0 : 1; // 0 = verde, 1 = branco
      int corNeg = (SinalV[i] == 1.0) ? 0 : 1; // 0 = vermelho, 1 = branco

      CorPosBuffer[i] = corPos;
      CorNegBuffer[i] = corNeg;
   }

   return(rates_total);
}
