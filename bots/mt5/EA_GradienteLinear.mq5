//+------------------------------------------------------------------+
//|                                      EA_GradienteLinear.mq5      |
//| Robô de grid (Gradiente Linear), nativo MQL5.                    |
//|                                                                    |
//| Entrada: automática, combinando os indicadores Puck_Agressao e    |
//| TPV (a trava extra contra entrada+stop simultâneo já incluída):   |
//|   Sinal Compra = compra_subindo E NÃO venda_subindo E TPV_comprado|
//|   Sinal Venda  = venda_subindo  E NÃO compra_subindo E TPV_vendido|
//|                                                                    |
//| Mecanismo MOLA: estado defensivo intermediário, entre "sinal      |
//| ainda ok" e o stop de verdade — cobre o caso de estar posicionado |
//| e o TPV começar a desfavorecer a posição, sem que o stop tenha    |
//| disparado ainda. Depende só da dimensão TPV_subindo/TPV_caindo    |
//| (independente do Puck_Agressao):                                  |
//|   Ativa (comprado): TPV_caindo  | Desativa B: TPV_subindo         |
//|   Ativa (vendido):  TPV_subindo | Desativa B: TPV_caindo          |
//| Como as duas são opostas exatas, é um estado que reflete o valor  |
//| atual a cada tick, não um evento de borda único.                  |
//| Enquanto ativa: as pendentes de entrada que faltam passam a usar  |
//| DistanciaGridMola (espaçamento dobrado) a partir do preço de      |
//| entrada original; todas as saídas viram UMA ordem consolidada no  |
//| preço médio da posição ± MolaPontos, cobrindo 100% do volume.     |
//| Desativa de duas formas: (A) a saída consolidada preenche ->      |
//| fecha tudo, ciclo encerrado, reentrada exige sinal normal do      |
//| zero; (B) TPV_subindo (comprado) ou TPV_caindo (vendido) volta a  |
//| ser verdadeiro, ainda posicionado -> reconstrói as OCOs           |
//| individuais de cada nível já preenchido (usando a lista interna   |
//| guardada) e as pendentes que faltam voltam pro espaçamento padrão |
//| (DistanciaGrid).                                                   |
//|                                                                    |
//| Saída híbrida (fora da Mola):                                     |
//|  1) OCO por nível: cada unidade preenchida (entrada a mercado ou  |
//|     nível de grid) ganha sua própria ordem de saída (limit),      |
//|     DistanciaGridSaida pontos de lucro a partir do preço real     |
//|     daquele preenchimento — igual ao OCO do NTSL original.        |
//|  2) Stop por sinal — tem prioridade sobre a Mola, fecha tudo       |
//|     independente do estado. Dois blocos por OU, cada um cobrindo  |
//|     um jeito diferente da posição ter "nascido" (a entrada não    |
//|     fixa qual média domina, então a posição pode começar em       |
//|     qualquer um dos dois regimes):                                |
//|     Stop Comprado =                                                |
//|       (media_pos[0]<media_neg[0] E venda_subindo E compra_caindo  |
//|        E TPV_vendido)                          <- regime já ruim, |
//|                                                     3 confirmações|
//|       OU (media_pos[1]>media_neg[1] E media_pos[0]<media_neg[0])  |
//|                                          <- virada agora mesmo    |
//|     Stop Vendido (espelhado):                                     |
//|       (media_neg[0]<media_pos[0] E compra_subindo E venda_caindo  |
//|        E TPV_comprado)                                            |
//|       OU (media_neg[1]>media_pos[1] E media_neg[0]<media_pos[0])  |
//|     Fecha a posição inteira de uma vez (PositionClose) e cancela  |
//|     TODAS as ordens pendentes restantes (níveis de grid não       |
//|     preenchidos + saídas OCO/consolidada ainda não preenchidas).  |
//|                                                                    |
//| Grid: réplica da config atual (NiveisGradiente=50, sem stop de    |
//|       preço) — se o sinal não reverter e o preço não recuperar    |
//|       nenhum nível, a posição fica exposta até o limite do grid.  |
//|                                                                    |
//| Requer Puck_Agressao.mq5 e TPV_SMA.mq5 já compilados em           |
//| MQL5/Indicators/dsalazar. Assume conta em modo NETTING (padrão    |
//| para B3) — uma única posição agregada por ativo, não hedging.     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Normaliza um preço calculado (soma/subtração/multiplicação) pra a |
//| grade de tick real do símbolo. Necessário porque médias e contas  |
//| aritméticas podem gerar valores que não existem na grade de       |
//| preços do ativo (ex: preço médio de posição no WDO) — sem isso, o |
//| MT5 rejeita a ordem com "invalid price". NÃO usar NormalizeDouble |
//| sozinho pra isso — ele só arredonda casas decimais, não alinha ao |
//| tick size real, que pode ser diferente (0.5, 5.0, etc).           |
//+------------------------------------------------------------------+
double NormalizarPreco(double preco)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0)
      return(NormalizeDouble(preco, _Digits));

   return(NormalizeDouble(MathRound(preco / tickSize) * tickSize, _Digits));
}

input int    NiveisGradiente     = 50;      // Níveis máximos do grid
input double DistanciaGrid       = 75.0;    // Distância entre níveis de ENTRADA (pontos de preço)
input double DistanciaGridSaida  = 100.0;   // Distância da saída OCO individual, a partir do preço de preenchimento (fora da Mola)
input double DistanciaGridMola   = 150.0;   // Espaçamento das pendentes de entrada ENQUANTO a Mola estiver ativa
input double MolaPontos          = 50.0;    // Distância da saída consolidada a partir do preço médio, durante a Mola
input double QuantidadePorOrdem  = 1;       // Contratos por ordem/nível
input int    PeriodoPuckAgressao = 21;      // Deve bater com o período configurado no indicador
input bool   ReconstruirHistorico = true;   // Deve bater com o parâmetro do indicador
input int    DiasHistoricoTicks   = 2;      // Deve bater com o parâmetro do indicador
input int    PeriodoTPV          = 50;      // Deve bater com o período configurado no indicador TPV
input int    MagicNumber         = 198198;  // Identificador das ordens deste EA

int    handlePuck       = INVALID_HANDLE;
int    handleTPV        = INVALID_HANDLE;
double preco_entrada     = 0;
int    niveis_colocados  = 0;
int    direcao_atual     = 0;  // 0 = sem posição, 1 = comprado, -1 = vendido
bool   g_fechandoPorStop = false; // true durante o FecharTudo(), pra OnTradeTransaction não recarregar níveis nesse caso
bool   g_molaAtiva       = false;

double g_nivelPreco[];   // lista de preços de cada unidade preenchida no ciclo atual (inclui a entrada a mercado)
double g_nivelVolume[];  // volume correspondente de cada entrada em g_nivelPreco
int    g_totalNiveis     = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   handlePuck = iCustom(_Symbol, PERIOD_CURRENT, "dsalazar\\Puck_Agressao", PeriodoPuckAgressao, ReconstruirHistorico, DiasHistoricoTicks);
   if(handlePuck == INVALID_HANDLE)
   {
      Print("Falha ao carregar o indicador Puck_Agressao. Confirme que o arquivo está compilado em MQL5/Indicators/dsalazar.");
      return(INIT_FAILED);
   }

   handleTPV = iCustom(_Symbol, PERIOD_CURRENT, "dsalazar\\TPV_SMA", PeriodoTPV);
   if(handleTPV == INVALID_HANDLE)
   {
      Print("Falha ao carregar o indicador TPV_SMA. Confirme que o arquivo está compilado em MQL5/Indicators/dsalazar.");
      return(INIT_FAILED);
   }

   // Reconstrói o estado se o EA for reiniciado com posição já aberta
   if(PositionSelect(_Symbol))
   {
      direcao_atual    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      preco_entrada    = PositionGetDouble(POSITION_PRICE_OPEN);
      niveis_colocados = NiveisGradiente; // assume que os níveis já tinham sido colocados antes do restart
      Print("EA reiniciado com posição já aberta. Estado reconstruído a partir da posição existente.");
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(handlePuck != INVALID_HANDLE)
      IndicatorRelease(handlePuck);
   if(handleTPV != INVALID_HANDLE)
      IndicatorRelease(handleTPV);
}

//+------------------------------------------------------------------+
//| Dispara a cada negócio executado na conta. Usado para detectar    |
//| quando uma unidade é preenchida (entrada a mercado ou nível de    |
//| grid) e colocar a saída OCO correspondente, no preço real do      |
//| preenchimento — não no preço teórico do nível.                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;

   ENUM_DEAL_ENTRY entrada  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long   tipoDeal   = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   double precoDeal  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double volumeDeal = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   if(entrada == DEAL_ENTRY_IN)
   {
      // Toda entrada preenchida (mercado ou nível de grid) é registrada na
      // lista interna — precisamos disso pra reconstruir as OCOs individuais
      // se a Mola ativar e depois desativar sem fechar a posição.
      RegistrarNivel(precoDeal, volumeDeal);

      if(g_molaAtiva)
         AtualizarSaidaConsolidada();
      else if(tipoDeal == DEAL_TYPE_BUY)
         ColocarSaidaOCO(true, precoDeal, volumeDeal);
      else if(tipoDeal == DEAL_TYPE_SELL)
         ColocarSaidaOCO(false, precoDeal, volumeDeal);

      return;
   }

   if(entrada == DEAL_ENTRY_OUT && !g_fechandoPorStop)
   {
      if(g_molaAtiva)
      {
         // Durante a Mola, a saída é uma ordem única cobrindo 100% do volume.
         // Se a posição zerou, foi ela que preencheu (cheia) -> encerra o ciclo.
         // Se ainda sobra volume, foi um preenchimento parcial dela mesma —
         // o restante continua pendente no mesmo preço, nada a fazer aqui.
         if(!PositionSelect(_Symbol))
            FinalizarCicloMola();

         return;
      }

      // Fora da Mola: comportamento normal (recarrega o nível ou encerra o ciclo)
      TratarSaidaOCO(tipoDeal, precoDeal, volumeDeal);
   }
}

//+------------------------------------------------------------------+
//| Reage a uma saída OCO preenchida. Se ainda sobra posição aberta, |
//| recarrega o nível (recoloca a entrada no mesmo preço). Se essa   |
//| era a última unidade, encerra o ciclo e limpa ordens órfãs, para |
//| o próximo grid (se o TPV continuar alinhado) nascer limpo.       |
//+------------------------------------------------------------------+
void TratarSaidaOCO(long tipoDealSaida, double precoSaida, double volumeSaida)
{
   bool aindaTemPosicao = PositionSelect(_Symbol);

   if(aindaTemPosicao)
   {
      double precoEntradaReconstruido;
      bool   ok;

      if(tipoDealSaida == DEAL_TYPE_SELL)
      {
         // era saída de um grid comprado -> recoloca a entrada de compra
         precoEntradaReconstruido = NormalizarPreco(precoSaida - DistanciaGridSaida);
         ok = trade.BuyLimit(volumeSaida, precoEntradaReconstruido, _Symbol);
      }
      else
      {
         // era saída de um grid vendido -> recoloca a entrada de venda
         precoEntradaReconstruido = NormalizarPreco(precoSaida + DistanciaGridSaida);
         ok = trade.SellLimit(volumeSaida, precoEntradaReconstruido, _Symbol);
      }

      if(ok)
         Print("Nivel recarregado: saida preenchida em ", DoubleToString(precoSaida, _Digits),
               " -> nova entrada recolocada em ", DoubleToString(precoEntradaReconstruido, _Digits));
      else
         Print("Falha ao recarregar nivel em ", DoubleToString(precoEntradaReconstruido, _Digits), ": ", trade.ResultRetcodeDescription());
   }
   else
   {
      // Essa era a última unidade aberta: o ciclo inteiro fechou via OCO
      // (não pelo stop de reversão). Não recarrega esse nível — em vez disso,
      // limpa qualquer ordem remanescente do ciclo anterior (níveis de entrada
      // nunca preenchidos) para não misturar com o próximo grid. A reentrada em
      // si acontece sozinha no próximo tick, no OnTick, se o TPV continuar alinhado.
      CancelarOrdensPendentes();
      direcao_atual    = 0;
      niveis_colocados = 0;
      preco_entrada    = 0;

      Print("Ciclo encerrado: todas as unidades saíram via OCO. Ordens remanescentes canceladas. Reentrada depende do sinal do TPV no próximo tick.");
   }
}

//+------------------------------------------------------------------+
//| Coloca a ordem de saída (take-profit) de uma unidade específica,  |
//| DistanciaGridSaida pontos a partir do preço real de preenchimento.|
//+------------------------------------------------------------------+
void ColocarSaidaOCO(bool ehCompra, double precoEntradaNivel, double volume)
{
   double precoSaida;
   bool   ok;

   if(ehCompra)
   {
      precoSaida = NormalizarPreco(precoEntradaNivel + DistanciaGridSaida);
      ok = trade.SellLimit(volume, precoSaida, _Symbol);
   }
   else
   {
      precoSaida = NormalizarPreco(precoEntradaNivel - DistanciaGridSaida);
      ok = trade.BuyLimit(volume, precoSaida, _Symbol);
   }

   if(ok)
      Print("Saida OCO colocada: nivel preenchido em ", DoubleToString(precoEntradaNivel, _Digits),
            " -> alvo de saida em ", DoubleToString(precoSaida, _Digits));
   else
      Print("Falha ao colocar saida OCO em ", DoubleToString(precoSaida, _Digits), ": ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Registra um preenchimento (preço+volume) na lista interna do      |
//| ciclo atual. Necessário pra reconstruir as OCOs individuais caso  |
//| a Mola ative e depois desative sem fechar a posição.              |
//+------------------------------------------------------------------+
void RegistrarNivel(double preco, double volume)
{
   g_totalNiveis++;
   ArrayResize(g_nivelPreco, g_totalNiveis);
   ArrayResize(g_nivelVolume, g_totalNiveis);
   g_nivelPreco[g_totalNiveis - 1]  = preco;
   g_nivelVolume[g_totalNiveis - 1] = volume;
}

void LimparNiveis()
{
   ArrayResize(g_nivelPreco, 0);
   ArrayResize(g_nivelVolume, 0);
   g_totalNiveis = 0;
}

//+------------------------------------------------------------------+
//| Cancela só as ordens pendentes de um tipo específico (ex: só as   |
//| BuyLimit, ou só as SellLimit) — usado pra mexer separadamente nas |
//| pendentes de entrada e na(s) ordem(ns) de saída durante a Mola.   |
//+------------------------------------------------------------------+
void CancelarOrdensPorTipo(ENUM_ORDER_TYPE tipo)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipo) continue;

      trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Ativa a Mola: cancela as pendentes de entrada e a(s) saída(s)     |
//| atuais, recoloca as pendentes que faltam com espaçamento dobrado  |
//| (DistanciaGridMola) a partir do preço de entrada original, e      |
//| coloca a saída consolidada no preço médio ± MolaPontos.           |
//+------------------------------------------------------------------+
void AtivarMola()
{
   g_molaAtiva = true;

   bool ehCompra = (direcao_atual == 1);
   ENUM_ORDER_TYPE tipoEntradaPendente = ehCompra ? ORDER_TYPE_BUY_LIMIT  : ORDER_TYPE_SELL_LIMIT;
   ENUM_ORDER_TYPE tipoSaidaPendente   = ehCompra ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   CancelarOrdensPorTipo(tipoEntradaPendente);
   CancelarOrdensPorTipo(tipoSaidaPendente);

   int niveisPreenchidosGrid = g_totalNiveis - 1; // exclui a entrada a mercado (nível 0)
   for(int nivel = niveisPreenchidosGrid + 1; nivel <= NiveisGradiente; nivel++)
   {
      double nivelPreco = NormalizarPreco(ehCompra ? (preco_entrada - nivel * DistanciaGridMola) : (preco_entrada + nivel * DistanciaGridMola));
      bool ok = ehCompra ? trade.BuyLimit(QuantidadePorOrdem, nivelPreco, _Symbol) : trade.SellLimit(QuantidadePorOrdem, nivelPreco, _Symbol);

      if(!ok)
         Print("Mola: falha ao recolocar nivel ", nivel, " em ", DoubleToString(nivelPreco, _Digits), ": ", trade.ResultRetcodeDescription());
   }

   AtualizarSaidaConsolidada();

   Print("MOLA ATIVADA (", (ehCompra ? "compra" : "venda"), "). Espaçamento das pendentes: ", DistanciaGridMola,
         " | saida consolidada: preco medio +/- ", MolaPontos);
}

//+------------------------------------------------------------------+
//| Recoloca a saída consolidada no preço médio atual da posição      |
//| (o MT5 já recalcula isso automaticamente), cobrindo 100% do       |
//| volume. Chamada ao ativar a Mola e a cada novo preenchimento      |
//| enquanto ela estiver ativa (o preço médio muda a cada fill).      |
//+------------------------------------------------------------------+
void AtualizarSaidaConsolidada()
{
   bool ehCompra = (direcao_atual == 1);
   ENUM_ORDER_TYPE tipoSaidaPendente = ehCompra ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   CancelarOrdensPorTipo(tipoSaidaPendente);

   if(!PositionSelect(_Symbol))
      return;

   double precoMedio  = PositionGetDouble(POSITION_PRICE_OPEN);
   double volumeTotal = PositionGetDouble(POSITION_VOLUME);
   double precoSaida  = NormalizarPreco(ehCompra ? (precoMedio + MolaPontos) : (precoMedio - MolaPontos));

   bool ok = ehCompra ? trade.SellLimit(volumeTotal, precoSaida, _Symbol) : trade.BuyLimit(volumeTotal, precoSaida, _Symbol);

   if(ok)
      Print("Mola: saida consolidada recolocada em ", DoubleToString(precoSaida, _Digits), " | volume=", volumeTotal);
   else
      Print("Mola: falha ao colocar saida consolidada em ", DoubleToString(precoSaida, _Digits), ": ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| A saída consolidada da Mola preencheu por completo (posição       |
//| zerou) — encerra o ciclo inteiro, igual ao fim de ciclo normal.   |
//+------------------------------------------------------------------+
void FinalizarCicloMola()
{
   CancelarOrdensPendentes(); // limpa qualquer pendente a 150 que ainda restava

   g_molaAtiva      = false;
   direcao_atual    = 0;
   niveis_colocados = 0;
   preco_entrada    = 0;
   LimparNiveis();

   Print("Mola: saida consolidada preencheu por completo. Ciclo encerrado. Reentrada exige o sinal de entrada normal.");
}

//+------------------------------------------------------------------+
//| Desativa a Mola SEM fechar a posição — o sinal de entrada normal  |
//| voltou a ser verdadeiro. Reconstrói as OCOs individuais de cada   |
//| nível já preenchido (usando a lista interna) e recoloca as        |
//| pendentes que faltam no espaçamento padrão (DistanciaGrid).       |
//+------------------------------------------------------------------+
void DesativarMolaSemFechar()
{
   bool ehCompra = (direcao_atual == 1);
   ENUM_ORDER_TYPE tipoEntradaPendente = ehCompra ? ORDER_TYPE_BUY_LIMIT  : ORDER_TYPE_SELL_LIMIT;
   ENUM_ORDER_TYPE tipoSaidaPendente   = ehCompra ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   CancelarOrdensPorTipo(tipoEntradaPendente); // cancela as pendentes a 150
   CancelarOrdensPorTipo(tipoSaidaPendente);   // cancela a saida consolidada

   int niveisPreenchidosGrid = g_totalNiveis - 1;
   for(int nivel = niveisPreenchidosGrid + 1; nivel <= NiveisGradiente; nivel++)
   {
      double nivelPreco = NormalizarPreco(ehCompra ? (preco_entrada - nivel * DistanciaGrid) : (preco_entrada + nivel * DistanciaGrid));
      bool ok = ehCompra ? trade.BuyLimit(QuantidadePorOrdem, nivelPreco, _Symbol) : trade.SellLimit(QuantidadePorOrdem, nivelPreco, _Symbol);

      if(!ok)
         Print("Desativar Mola: falha ao recolocar nivel ", nivel, " em ", DoubleToString(nivelPreco, _Digits), ": ", trade.ResultRetcodeDescription());
   }

   for(int idx = 0; idx < g_totalNiveis; idx++)
   {
      double precoNivel = g_nivelPreco[idx];
      double volNivel   = g_nivelVolume[idx];
      double precoSaida = NormalizarPreco(ehCompra ? (precoNivel + DistanciaGridSaida) : (precoNivel - DistanciaGridSaida));

      bool ok = ehCompra ? trade.SellLimit(volNivel, precoSaida, _Symbol) : trade.BuyLimit(volNivel, precoSaida, _Symbol);

      if(!ok)
         Print("Desativar Mola: falha ao recriar OCO individual em ", DoubleToString(precoSaida, _Digits), ": ", trade.ResultRetcodeDescription());
   }

   g_molaAtiva = false;
   Print("MOLA DESATIVADA (sinal de entrada normal retornou). Espaçamento voltou ao padrão (", DistanciaGrid, "/", DistanciaGridSaida, ").");
}

void OnTick()
{
   // Puck_Agressao: buffer0=media_pos, buffer2=media_neg, buffer4=SinalC(compra_subindo), buffer5=SinalV(venda_subindo)
   // media_pos/media_neg: pega 2 barras (atual [0] e anterior [1]) — o novo stop precisa
   // detectar o momento exato da virada de dominância entre as duas médias.
   double mediaPosArr[], mediaNegArr[], puckSinalCArr[], puckSinalVArr[];

   if(CopyBuffer(handlePuck, 0, 0, 2, mediaPosArr)   <= 0) return;
   if(CopyBuffer(handlePuck, 2, 0, 2, mediaNegArr)   <= 0) return;
   if(CopyBuffer(handlePuck, 4, 0, 1, puckSinalCArr) <= 0) return;
   if(CopyBuffer(handlePuck, 5, 0, 1, puckSinalVArr) <= 0) return;

   // TPV_SMA: buffer3=SinalC(TPV_comprado), buffer4=SinalV(TPV_vendido), buffer5=TPVSubindo
   double tpvSinalCArr[], tpvSinalVArr[], tpvSubindoArr[];

   if(CopyBuffer(handleTPV, 3, 0, 1, tpvSinalCArr)  <= 0) return;
   if(CopyBuffer(handleTPV, 4, 0, 1, tpvSinalVArr)  <= 0) return;
   if(CopyBuffer(handleTPV, 5, 0, 1, tpvSubindoArr) <= 0) return;

   bool compra_subindo = (puckSinalCArr[0] == 1.0);
   bool venda_subindo  = (puckSinalVArr[0] == 1.0);
   bool compra_caindo  = !compra_subindo;
   bool venda_caindo   = !venda_subindo;
   bool TPV_comprado   = (tpvSinalCArr[0] == 1.0);
   bool TPV_vendido    = (tpvSinalVArr[0] == 1.0);
   bool TPV_subindo    = (tpvSubindoArr[0] == 1.0);
   bool TPV_caindo     = !TPV_subindo;

   bool sinalCompra = compra_subindo && !venda_subindo && TPV_comprado;
   bool sinalVenda  = venda_subindo  && !compra_subindo && TPV_vendido;

   // Novo stop: dois blocos por OU, cada um cobrindo um jeito diferente da
   // posição ter "nascido" (o sinal de entrada não fixa qual média domina).
   bool regimeAtualVendaDomina  = (mediaPosArr[0] < mediaNegArr[0]);
   bool regimeAtualCompraDomina = (mediaNegArr[0] < mediaPosArr[0]);

   bool viradaParaVenda  = (mediaPosArr[1] > mediaNegArr[1]) && (mediaPosArr[0] < mediaNegArr[0]);
   bool viradaParaCompra = (mediaNegArr[1] > mediaPosArr[1]) && (mediaNegArr[0] < mediaPosArr[0]);

   bool stopComprado = (regimeAtualVendaDomina && venda_subindo && compra_caindo && TPV_vendido) || viradaParaVenda;
   bool stopVendido  = (regimeAtualCompraDomina && compra_subindo && venda_caindo && TPV_comprado) || viradaParaCompra;

   // Mola: agora depende só da dimensão TPV_subindo/TPV_caindo (independente
   // do Puck_Agressao) — comprado desfavorece quando TPV cai, vendido
   // desfavorece quando TPV sobe. Ativação e desativação-B são espelhadas
   // (TPV_subindo/TPV_caindo são opostos exatos), então é um estado que
   // reflete o valor atual a cada tick, não um evento único.
   bool molaCompra = TPV_caindo;
   bool molaVenda  = TPV_subindo;

   if(!PositionSelect(_Symbol))
   {
      direcao_atual    = 0;
      niveis_colocados = 0;

      if(sinalCompra)
      {
         Print("Sinal de entrada COMPRA: compra_subindo=", compra_subindo,
               " venda_subindo=", venda_subindo, " TPV_comprado=", TPV_comprado);
         AbrirGrid(ORDER_TYPE_BUY);
      }
      else if(sinalVenda)
      {
         Print("Sinal de entrada VENDA: venda_subindo=", venda_subindo,
               " compra_subindo=", compra_subindo, " TPV_vendido=", TPV_vendido);
         AbrirGrid(ORDER_TYPE_SELL);
      }
      // se nenhum dos dois lados bater todas as condições, não entra

      return;
   }

   long tipoPos = PositionGetInteger(POSITION_TYPE);

   if(tipoPos == POSITION_TYPE_BUY && stopComprado)
   {
      Print("Sinal de STOP COMPRADO: regimeAtualVendaDomina=", regimeAtualVendaDomina,
            " venda_subindo=", venda_subindo, " compra_caindo=", compra_caindo, " TPV_vendido=", TPV_vendido,
            " | viradaParaVenda=", viradaParaVenda);
      FecharTudo();
      return;
   }

   if(tipoPos == POSITION_TYPE_SELL && stopVendido)
   {
      Print("Sinal de STOP VENDIDO: regimeAtualCompraDomina=", regimeAtualCompraDomina,
            " compra_subindo=", compra_subindo, " venda_caindo=", venda_caindo, " TPV_comprado=", TPV_comprado,
            " | viradaParaCompra=", viradaParaCompra);
      FecharTudo();
      return;
   }

   // Stop não disparou. Verifica transições da Mola.
   if(tipoPos == POSITION_TYPE_BUY)
   {
      if(!g_molaAtiva && molaCompra)
      {
         Print("Sinal de MOLA COMPRA (ativa): TPV_caindo=", TPV_caindo);
         AtivarMola();
      }
      else if(g_molaAtiva && TPV_subindo)
      {
         Print("Sinal de MOLA COMPRA (desativa B): TPV_subindo=", TPV_subindo);
         DesativarMolaSemFechar();
      }
   }
   else if(tipoPos == POSITION_TYPE_SELL)
   {
      if(!g_molaAtiva && molaVenda)
      {
         Print("Sinal de MOLA VENDA (ativa): TPV_subindo=", TPV_subindo);
         AtivarMola();
      }
      else if(g_molaAtiva && TPV_caindo)
      {
         Print("Sinal de MOLA VENDA (desativa B): TPV_caindo=", TPV_caindo);
         DesativarMolaSemFechar();
      }
   }

   // Nenhuma transição: nada a fazer.
}

//+------------------------------------------------------------------+
//| Abre a posição a mercado e pré-monta todos os níveis do grid     |
//| como ordens pendentes, de uma vez (evita reenviar/duplicar a     |
//| cada tick, que era um risco não confirmado no código NTSL).      |
//+------------------------------------------------------------------+
void AbrirGrid(ENUM_ORDER_TYPE tipo)
{
   bool enviado;

   LimparNiveis(); // garante que não sobra lista do ciclo anterior

   if(tipo == ORDER_TYPE_BUY)
      enviado = trade.Buy(QuantidadePorOrdem, _Symbol);
   else
      enviado = trade.Sell(QuantidadePorOrdem, _Symbol);

   if(!enviado)
   {
      Print("Falha ao enviar ordem a mercado: ", trade.ResultRetcodeDescription());
      return;
   }

   preco_entrada    = trade.ResultPrice();
   direcao_atual    = (tipo == ORDER_TYPE_BUY) ? 1 : -1;
   niveis_colocados = 0;

   for(int nivel = 1; nivel <= NiveisGradiente; nivel++)
   {
      double nivelPreco;
      bool ok;

      if(tipo == ORDER_TYPE_BUY)
      {
         nivelPreco = NormalizarPreco(preco_entrada - nivel * DistanciaGrid);
         ok = trade.BuyLimit(QuantidadePorOrdem, nivelPreco, _Symbol);
      }
      else
      {
         nivelPreco = NormalizarPreco(preco_entrada + nivel * DistanciaGrid);
         ok = trade.SellLimit(QuantidadePorOrdem, nivelPreco, _Symbol);
      }

      if(ok)
         niveis_colocados++;
      else
         Print("Falha ao colocar nível ", nivel, " do grid em ", DoubleToString(nivelPreco, _Digits), ": ", trade.ResultRetcodeDescription());
   }

   Print("Grid aberto: ", (tipo == ORDER_TYPE_BUY ? "COMPRA" : "VENDA"),
         " | entrada=", DoubleToString(preco_entrada, _Digits),
         " | niveis colocados=", niveis_colocados, "/", NiveisGradiente);
}

//+------------------------------------------------------------------+
//| Fecha a posição inteira de uma vez e cancela as ordens pendentes  |
//| restantes do grid (equivalente ao ClosePosition do NTSL).         |
//+------------------------------------------------------------------+
void FecharTudo()
{
   g_fechandoPorStop = true;
   trade.PositionClose(_Symbol);
   CancelarOrdensPendentes();
   g_fechandoPorStop = false;

   Print("Posição fechada por sinal de stop (Puck_Agressao + TPV).");

   g_molaAtiva      = false;
   direcao_atual    = 0;
   niveis_colocados = 0;
   preco_entrada    = 0;
   LimparNiveis();
}

void CancelarOrdensPendentes()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

      trade.OrderDelete(ticket);
   }
}
