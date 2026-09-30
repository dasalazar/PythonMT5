//+------------------------------------------------------------------+
//|                                     EA_GradienteLinear3.mq5      |
//| Robô de grid (Gradiente Linear) — v3, ponto de partida idêntico  |
//| ao EA_GradienteLinear2.mq5 (v2), que continua intocado e rodando |
//| como está. Este arquivo é onde as próximas evoluções entram.     |
//|                                                                    |
//| Entrada: automática, combinando os indicadores Puck_Agressao e    |
//| TPV (a trava extra contra entrada+stop simultâneo já incluída).   |
//| "Não posicionado" é garantido estruturalmente (só entra dentro do |
//| bloco !PositionSelect), não precisa ser uma condição explícita.   |
//| O TPV entra pela dimensão Subindo/Caindo, não Comprado/Vendido:   |
//|   Sinal Compra = compra_subindo E NÃO venda_subindo E TPV_subindo |
//|   Sinal Venda  = venda_subindo  E NÃO compra_subindo E TPV_caindo |
//|                                                                    |
//| Mecanismo MOLA: estado defensivo intermediário, entre "sinal      |
//| ainda ok" e o stop de verdade — cobre o caso de estar posicionado |
//| e o TPV começar a desfavorecer a posição, sem que o stop tenha    |
//| disparado ainda. Depende só da dimensão TPV_subindo/TPV_caindo    |
//| (independente do Puck_Agressao):                                  |
//|   Ativa (comprado): TPV_caindo  | Desativa: TPV_subindo           |
//|   Ativa (vendido):  TPV_subindo | Desativa: TPV_caindo            |
//| Como as duas são opostas exatas, é um estado que reflete o valor  |
//| atual a cada tick, não um evento de borda único.                  |
//|                                                                    |
//| Ligada: pendentes de entrada que faltam mantêm o MESMO espaçamento|
//| (DistanciaGrid), só a QUANTIDADE dobra (2x QuantidadePorOrdem).   |
//| Cada preenchimento de um nível dobrado divide ao meio: metade vai |
//| pra uma OCO individual normal (DistanciaGridSaida); a outra       |
//| metade entra no "balde" — uma saída consolidada, sempre reposta   |
//| no preço médio ATUAL da posição ± MolaPontos, com o volume         |
//| acumulado. Se a metade individual de um nível dobrado bate o      |
//| alvo dela, recarrega aquele nível — de novo em 2x, se a Mola      |
//| ainda estiver ligada nesse momento.                                |
//|                                                                    |
//| O BALDE PERSISTE o ciclo inteiro — nunca é cancelado só por a      |
//| Mola desligar. Ao desligar, só a quantidade das pendentes volta   |
//| pra 1x; o balde fica parado, exatamente como está, esperando ser  |
//| preenchido ou ser retomado numa próxima ativação (ligar de novo   |
//| não cria um balde novo — soma ao que já existe).                  |
//| Preenchimentos feitos com a Mola desligada usam OCO individual     |
//| normal; ao religar, essas OCOs são varridas e somadas ao balde.   |
//| Se o balde preencher (total ou parcial), reduz o volume dele; se   |
//| a posição zerar por causa dele, encerra o ciclo inteiro.           |
//|                                                                    |
//| TETO UNIVERSAL: nenhuma OCO individual pode ter alvo além de       |
//| preço_médio ± MolaPontos, não importa se a Mola está ligada ou    |
//| desligada no momento — se ultrapassaria, o volume vai direto pro  |
//| balde. Checado na criação (ColocarSaidaOCO) e continuamente        |
//| (MigrarOrdensAlemDoTeto, rodando toda vez que o balde recalcula), |
//| pra pegar também ordens que ficaram obsoletas com o tempo.         |
//|                                                                    |
//| DESCARGA DO BALDE: DESATIVADA nesta versão. A tentativa de        |
//| descarregar unidades no limiar contra colocava ordens de saída     |
//| abaixo do preço médio (no prejuízo), causando perdas reais no grid.|
//| No Gradiente Linear, o fechamento só ocorre no lucro (alvo do      |
//| balde / OCO) ou no Stop Financeiro global da posição.              |
//|                                                                    |
//| Saída híbrida (fora da Mola):                                     |
//|  1) OCO por nível: cada unidade preenchida (entrada a mercado ou  |
//|     nível de grid) ganha sua própria ordem de saída (limit),      |
//|     DistanciaGridSaida pontos de lucro a partir do preço real     |
//|     daquele preenchimento — igual ao OCO do NTSL original.        |
//|  2) Stop FINANCEIRO — não depende mais de indicador nenhum. Fecha |
//|     a posição inteira quando a perda flutuante (lucro + swap)     |
//|     atinge -StopFinanceiro (padrão R$ 5.000,00). Tem prioridade   |
//|     sobre a Mola, fecha tudo independente do estado. Cancela      |
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
//|                                                                    |
//| MagicNumber padrão diferente do v1 (198198) e do v2 (198199) —    |
//| pra rodar as três versões ao mesmo tempo, no mesmo símbolo, sem   |
//| uma interferir nas ordens da outra, caso você queira comparar.    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

#define COMENTARIO_BALDE "BALDE"

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
input double DistanciaGridMola   = 150.0;   // [NÃO USADO no momento]
input double MolaPontos          = 50.0;    // Distância da saída consolidada a partir do preço médio, durante a Mola
input string MolaProgressaoLotes = "1,1,2,2,3,3,4,4,5,5,5,5,4,4,3,3,2,2,1,1"; // Lotes TOTAIS por nível (1 a 20) na Mola
input string MolaProgressaoOCO   = "1,1,1,1,2,2,3,3,4,4,4,4,3,3,2,2,1,1,1,1"; // Lotes OCO individuais por nível (1 a 20) na Mola
input double DistanciaDescargaBalde = 50.0; // [DESATIVADO] Evita vendas no prejuízo
input double ToleranciaDescarga  = 25.0;    // [DESATIVADO]
input double QuantidadePorOrdem  = 1;       // Contratos padrão por ordem/nível fora da Mola
input int    PeriodoPuckAgressao = 21;      // Deve bater com o período configurado no indicador
input bool   ReconstruirHistorico = true;   // Deve bater com o parâmetro do indicador
input int    DiasHistoricoTicks   = 2;      // Deve bater com o parâmetro do indicador
input int    PeriodoTPV          = 50;      // Deve bater com o período configurado no indicador TPV
input double StopFinanceiro      = 5000.0;  // Perda máxima em R$ (lucro flutuante + swap) antes de fechar tudo
input int    MagicNumber         = 198200;  // Identificador das ordens deste EA (v3: 198200)

int    handlePuck       = INVALID_HANDLE;
int    handleTPV        = INVALID_HANDLE;
double preco_entrada     = 0;
int    niveis_colocados  = 0;
int    direcao_atual     = 0;  // 0 = sem posição, 1 = comprado, -1 = vendido
bool   g_fechandoPorStop = false; // true durante o FecharTudo(), pra OnTradeTransaction não recarregar níveis nesse caso
bool   g_molaAtiva       = false;
int    g_totalNiveis     = 0;  // contagem de unidades preenchidas no ciclo atual (inclui a entrada a mercado)

bool   g_baldeExiste     = false; // o "balde" (saída consolidada em preço médio ± MolaPontos) persiste no ciclo inteiro
double g_baldeVolume     = 0.0;   // volume acumulado dentro do balde até agora
ulong  g_baldeTicket     = 0;     // ticket da ordem pendente que representa o balde, pra distinguir de OCOs individuais
int    g_niveisDescarregados = 0; // [DESATIVADO]
long   g_ultimaContaConhecida = 0; // detecta troca de conta/corretora sem reinício do EA (ver VerificarTrocaDeConta)

double g_molaTotalLotes[];
double g_molaOcoLotes[];
int    g_totalMolaNiveisTotal = 0;
int    g_totalMolaNiveisOCO   = 0;

void CarregarProgressaoMola()
{
   // Carrega sequência de Lotes Totais
   string itensTotal[];
   int total = StringSplit(MolaProgressaoLotes, ',', itensTotal);
   ArrayResize(g_molaTotalLotes, total);
   g_totalMolaNiveisTotal = 0;
   for(int i = 0; i < total; i++)
   {
      StringTrimLeft(itensTotal[i]);
      StringTrimRight(itensTotal[i]);
      double val = StringToDouble(itensTotal[i]);
      if(val > 0)
      {
         g_molaTotalLotes[g_totalMolaNiveisTotal] = val;
         g_totalMolaNiveisTotal++;
      }
   }

   // Carrega sequência de Lotes OCO
   string itensOCO[];
   int totalOCO = StringSplit(MolaProgressaoOCO, ',', itensOCO);
   ArrayResize(g_molaOcoLotes, totalOCO);
   g_totalMolaNiveisOCO = 0;
   for(int i = 0; i < totalOCO; i++)
   {
      StringTrimLeft(itensOCO[i]);
      StringTrimRight(itensOCO[i]);
      double val = StringToDouble(itensOCO[i]);
      if(val > 0)
      {
         g_molaOcoLotes[g_totalMolaNiveisOCO] = val;
         g_totalMolaNiveisOCO++;
      }
   }
}

void ObterLotesPorNivel(int nivel, double &totalLotes, double &ocoLotes, double &baldeLotes)
{
   if(nivel >= 1 && nivel <= g_totalMolaNiveisTotal)
      totalLotes = g_molaTotalLotes[nivel - 1];
   else
      totalLotes = QuantidadePorOrdem;

   if(nivel >= 1 && nivel <= g_totalMolaNiveisOCO)
      ocoLotes = g_molaOcoLotes[nivel - 1];
   else
      ocoLotes = totalLotes;

   if(ocoLotes > totalLotes)
      ocoLotes = totalLotes;

   baldeLotes = totalLotes - ocoLotes;
}

double ObterTotalLotePorNivel(int nivel)
{
   if(nivel >= 1 && nivel <= g_totalMolaNiveisTotal)
      return g_molaTotalLotes[nivel - 1];

   return QuantidadePorOrdem;
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   g_ultimaContaConhecida = AccountInfoInteger(ACCOUNT_LOGIN);
   CarregarProgressaoMola();

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

   // Reconstrói o estado se o EA for reiniciado com posição já aberta.
   // Limitação conhecida: g_totalNiveis, g_molaAtiva e o balde (g_baldeExiste/
   // g_baldeVolume/g_baldeTicket) NÃO são reconstruídos — o MT5 não guarda
   // "quantos níveis já preencheram" nem "havia um balde em aberto" em lugar
   // nenhum consultável. Reiniciar o EA no meio de um ciclo com Mola ativa (ou
   // com um balde parado) pode deixar esse estado interno incorreto até o
   // próximo ciclo começar do zero. Evite reiniciar o EA nessas condições.
   if(PositionSelect(_Symbol))
   {
      direcao_atual    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      preco_entrada    = PositionGetDouble(POSITION_PRICE_OPEN);
      niveis_colocados = NiveisGradiente; // assume que os níveis já tinham sido colocados antes do restart
      Print("EA reiniciado com posição já aberta. Estado reconstruído de forma aproximada — g_totalNiveis, Mola e balde ficam zerados.");
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
      // Toda entrada preenchida (mercado ou nível de grid) conta pro total do ciclo —
      // precisamos disso só pra saber quantos níveis de grid já foram preenchidos.
      g_totalNiveis++;

      bool ehCompra = (tipoDeal == DEAL_TYPE_BUY);

      if(g_molaAtiva)
      {
         // Mola ligada: a pendente foi colocada com a quantidade da tabela do nível,
         // então divide o preenchimento entre OCO individual e balde conforme a tabela.
         int nivel = (DistanciaGrid > 0 && preco_entrada > 0) ? (int)MathRound(MathAbs(preco_entrada - precoDeal) / DistanciaGrid) : 0;

         double totalL = volumeDeal, ocoL = volumeDeal, baldeL = 0;
         if(nivel >= 1)
            ObterLotesPorNivel(nivel, totalL, ocoL, baldeL);

         if(ocoL > volumeDeal)
            ocoL = volumeDeal; // nunca coloca OCO maior que o que realmente preencheu

         if(ocoL > 0)
            ColocarSaidaOCO(ehCompra, precoDeal, ocoL);

         AtualizarBalde();
      }
      else
      {
         // Mola desligada (com ou sem balde já existente): o preenchimento inteiro ganha
         // a sua OCO no preço original. O teto (checado dentro de ColocarSaidaOCO) é o
         // único motivo pra parte dela ir pro balde.
         ColocarSaidaOCO(ehCompra, precoDeal, volumeDeal);
      }

      return;
   }

   if(entrada == DEAL_ENTRY_OUT && !g_fechandoPorStop)
   {
      ulong ordemOrigem = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);

      // O ticket guardado pode já ter sido zerado pelo AtualizarBalde (ordem já FILLED no book
      // antes deste evento chegar) — por isso confere também o comentário gravado na ordem.
      bool foiBalde = (g_baldeTicket != 0 && ordemOrigem == g_baldeTicket);
      if(!foiBalde && HistoryOrderSelect(ordemOrigem))
         foiBalde = (HistoryOrderGetString(ordemOrigem, ORDER_COMMENT) == COMENTARIO_BALDE);

      if(foiBalde)
      {
         // Foi o balde que preencheu (total ou parcialmente).
         g_baldeVolume -= volumeDeal;
         if(g_baldeVolume < 0.00000001)
         {
            g_baldeVolume = 0;
            g_baldeExiste = false;
            g_baldeTicket = 0;
         }

         if(!PositionSelect(_Symbol))
         {
            // Posição zerou de vez — encerra o ciclo inteiro.
            CancelarOrdensPendentes(ordemOrigem);
            LimparEstadoCiclo();

            Print("Balde preencheu por completo e zerou a posição. Ciclo encerrado. Reentrada exige o sinal de entrada normal.");
         }
         // Se ainda sobra posição, foi um preenchimento parcial do balde —
         // o restante continua pendente no mesmo preço, nada a fazer.

         return;
      }

      // Não foi o balde: foi uma OCO individual preenchendo (saída de ordem
      // intermediária). Recarrega o nível e, se a Mola ou balde estiverem ativos,
      // recalcula o balde pra refletir isso agora.
      TratarSaidaOCO(tipoDeal, precoDeal, volumeDeal);

      if(g_molaAtiva || g_baldeExiste)
         AtualizarBalde();
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

   // PositionSelect pode retornar falso MOMENTANEAMENTE logo após um
   // preenchimento parcial, antes do registro da posição ser atualizado
   // pelo terminal — confirma de novo (com uma pequena pausa) antes de
   // declarar o ciclo encerrado e apagar todo o estado interno. Fazer
   // isso sem confirmar já causou um bug real: o código concluiu "posição
   // zerada" com a posição ainda viva, corrompendo direcao_atual/
   // preco_entrada/g_totalNiveis e gerando um stop financeiro fictício.
   if(!aindaTemPosicao)
   {
      Sleep(150);
      aindaTemPosicao = PositionSelect(_Symbol);
   }

   if(aindaTemPosicao)
   {
      double precoEntradaReconstruido;
      if(tipoDealSaida == DEAL_TYPE_SELL)
         precoEntradaReconstruido = NormalizarPreco(precoSaida - DistanciaGridSaida);
      else
         precoEntradaReconstruido = NormalizarPreco(precoSaida + DistanciaGridSaida);

      int nivel = (DistanciaGrid > 0 && preco_entrada > 0) ? (int)MathRound(MathAbs(preco_entrada - precoEntradaReconstruido) / DistanciaGrid) : 1;
      double volumeRecarga = g_molaAtiva ? ObterTotalLotePorNivel(nivel) : QuantidadePorOrdem;
      bool   ok;

      if(tipoDealSaida == DEAL_TYPE_SELL)
      {
         // era saída de um grid comprado -> recoloca a entrada de compra
         ok = trade.BuyLimit(volumeRecarga, precoEntradaReconstruido, _Symbol);
      }
      else
      {
         // era saída de um grid vendido -> recoloca a entrada de venda
         ok = trade.SellLimit(volumeRecarga, precoEntradaReconstruido, _Symbol);
      }

      if(ok)
         Print("Nivel ", nivel, " recarregado (", (g_molaAtiva ? (DoubleToString(volumeRecarga, 0) + " contratos, Mola ligada") : (DoubleToString(volumeRecarga, 0) + " contrato, padrão")), "): saida em ", DoubleToString(precoSaida, _Digits),
               " -> nova entrada em ", DoubleToString(precoEntradaReconstruido, _Digits));
      else
         Print("Falha ao recarregar nivel em ", DoubleToString(precoEntradaReconstruido, _Digits), ": ", trade.ResultRetcodeDescription());
   }
   else
   {
      // Essa era a última unidade aberta fora do balde: o ciclo inteiro fechou
      // via OCO individual (não pelo balde, não pelo stop). Não recarrega esse
      // nível — limpa qualquer ordem remanescente.
      CancelarOrdensPendentes();
      LimparEstadoCiclo();

      Print("Ciclo encerrado: todas as unidades saíram via OCO individual. Ordens remanescentes canceladas. Reentrada depende do sinal de entrada no próximo tick.");
   }
}

//+------------------------------------------------------------------+
//| Coloca a ordem de saída (take-profit) de uma unidade específica,  |
//| DistanciaGridSaida pontos a partir do preço real de preenchimento.|
//|                                                                    |
//| Só é chamada (a partir do OnTradeTransaction) quando NÃO existe   |
//| balde algum ainda (g_baldeVolume <= 0) — assim que um balde existe|
//| de qualquer ativação anterior da Mola, mesmo desligada agora,     |
//| novos preenchimentos não passam mais por aqui: ficam descobertos  |
//| e o AtualizarBalde() os conta automaticamente como parte do       |
//| balde. Por isso não precisa mais checar teto nenhum aqui dentro — |
//| se chegou até essa função, é porque não existe balde pra          |
//| ultrapassar.                                                       |
//+------------------------------------------------------------------+
void ColocarSaidaOCO(bool ehCompra, double precoEntradaNivel, double volume)
{
   if(volume <= 0) return;

   double precoSaida = NormalizarPreco(ehCompra ? (precoEntradaNivel + DistanciaGridSaida) : (precoEntradaNivel - DistanciaGridSaida));

   if(PositionSelect(_Symbol))
   {
      double precoMedio = PositionGetDouble(POSITION_PRICE_OPEN);
      double teto       = ehCompra ? (precoMedio + MolaPontos) : (precoMedio - MolaPontos);
      bool ultrapassa   = ehCompra ? (precoSaida > teto) : (precoSaida < teto);

      if(ultrapassa)
      {
         Print("Saida individual em ", DoubleToString(precoSaida, _Digits),
               " ultrapassa o teto (", DoubleToString(teto, _Digits), "). Volume ", volume, " vai direto para o balde.");
         AtualizarBalde();
         return;
      }
   }

   bool ok = ehCompra ? trade.SellLimit(volume, precoSaida, _Symbol) : trade.BuyLimit(volume, precoSaida, _Symbol);

   if(ok)
      Print("Saida OCO individual colocada: nivel ", DoubleToString(precoEntradaNivel, _Digits),
            " -> alvo em ", DoubleToString(precoSaida, _Digits), " | vol=", volume);
   else
      Print("Falha ao colocar saida OCO em ", DoubleToString(precoSaida, _Digits), ": ", trade.ResultRetcodeDescription());

   AtualizarBalde();
}

//+------------------------------------------------------------------+
//| Soma o volume de todas as ordens pendentes de um tipo específico  |
//| (as OCOs individuais), EXCLUINDO o ticket do balde. Usado pra     |
//| recalcular o volume do balde a partir da invariante: volume da    |
//| posição = volume no balde + volume ainda coberto por individuais. |
//+------------------------------------------------------------------+
double SomarVolumeIndividualPendente(ENUM_ORDER_TYPE tipo)
{
   double soma = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipo) continue;
      if(g_baldeTicket != 0 && ticket == g_baldeTicket) continue;

      soma += OrderGetDouble(ORDER_VOLUME_CURRENT);
   }

   return(soma);
}

//+------------------------------------------------------------------+
//| Cancela só as ordens pendentes de um tipo específico (ex: só as   |
//| BuyLimit, ou só as SellLimit) — usado pra mexer separadamente nas |
//| pendentes de entrada e na(s) ordem(ns) de saída durante a Mola.   |
//+------------------------------------------------------------------+
void CancelarOrdensPorTipo(ENUM_ORDER_TYPE tipo, ulong ticketExcluir = 0)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(ticketExcluir != 0 && ticket == ticketExcluir) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipo) continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(state != ORDER_STATE_PLACED) continue;

      trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Cancela SÓ o excedente de OCOs individuais (as mais distantes do   |
//| preço médio primeiro) até a soma voltar a caber no volume da       |
//| posição. As demais continuam intactas no preço em que foram criadas.|
//+------------------------------------------------------------------+
void CancelarExcessoIndividual(ENUM_ORDER_TYPE tipo, double volumePosicao, bool ehCompra)
{
   for(int rodada = 0; rodada < 100; rodada++)
   {
      if(SomarVolumeIndividualPendente(tipo) <= volumePosicao + 0.0000001)
         return;

      ulong  ticketAlvo = 0;
      double precoAlvo  = 0;

      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
         if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipo) continue;
         if(g_baldeTicket != 0 && ticket == g_baldeTicket) continue;
         if((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE) != ORDER_STATE_PLACED) continue;

         double preco = OrderGetDouble(ORDER_PRICE_OPEN);
         bool maisDistante = (ticketAlvo == 0) || (ehCompra ? (preco > precoAlvo) : (preco < precoAlvo));
         if(maisDistante)
         {
            ticketAlvo = ticket;
            precoAlvo  = preco;
         }
      }

      if(ticketAlvo == 0 || !trade.OrderDelete(ticketAlvo))
         return;
   }
}

//+------------------------------------------------------------------+
//| A Mola só muda a QUANTIDADE das pendentes de entrada ainda não    |
//| executadas: cada uma é recolocada no MESMO preço, com a quantidade |
//| do nível (tabela se ligada, QuantidadePorOrdem se desligada). Não  |
//| depende de contagem de níveis — trabalha sobre as pendentes que    |
//| realmente existem no book (inclui níveis recarregados por OCO).    |
//| Saídas (OCO/balde) não são tocadas aqui.                           |
//+------------------------------------------------------------------+
void AjustarQuantidadeEntradasPendentes(bool molaLigada)
{
   bool ehCompra = (direcao_atual == 1);
   ENUM_ORDER_TYPE tipoEntrada = ehCompra ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

   ulong  tickets[];
   double precos[];
   double volumes[];
   int    n = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipoEntrada) continue;
      if((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE) != ORDER_STATE_PLACED) continue;

      ArrayResize(tickets, n + 1);
      ArrayResize(precos,  n + 1);
      ArrayResize(volumes, n + 1);
      tickets[n] = ticket;
      precos[n]  = OrderGetDouble(ORDER_PRICE_OPEN);
      volumes[n] = OrderGetDouble(ORDER_VOLUME_CURRENT);
      n++;
   }

   for(int k = 0; k < n; k++)
   {
      int nivel = (DistanciaGrid > 0 && preco_entrada > 0) ? (int)MathRound(MathAbs(preco_entrada - precos[k]) / DistanciaGrid) : 0;
      double alvo = molaLigada ? ObterTotalLotePorNivel(nivel) : QuantidadePorOrdem;

      if(MathAbs(alvo - volumes[k]) < 0.0000001)
         continue; // já está na quantidade certa

      if(!trade.OrderDelete(tickets[k]))
      {
         Print("Mola: falha ao cancelar entrada pendente #", tickets[k], " (nivel ", nivel, "): ", trade.ResultRetcodeDescription());
         continue;
      }

      bool ok = ehCompra ? trade.BuyLimit(alvo, precos[k], _Symbol) : trade.SellLimit(alvo, precos[k], _Symbol);
      if(!ok)
         Print("Mola: falha ao recolocar nivel ", nivel, " com ", alvo, " contratos em ", DoubleToString(precos[k], _Digits), ": ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Ativa a Mola: varre as OCOs individuais existentes (preenchimentos|
//| feitos com a Mola desligada) e soma o volume delas ao balde — sem |
//| recriar um balde novo, se um já existir de um ciclo anterior de   |
//| Mola ligada dentro da mesma posição. Dobra a QUANTIDADE das       |
//| pendentes de entrada que faltam (mesmo espaçamento).              |
//+------------------------------------------------------------------+
void AtivarMola()
{
   g_molaAtiva = true;

   CarregarProgressaoMola();

   // AtualizarBalde() só migra pro balde as OCOs que ultrapassam o teto; as demais ficam
   // no preço original. Também define direcao_atual a partir da posição real.
   AtualizarBalde();

   bool ehCompra = (direcao_atual == 1);

   // A Mola altera APENAS a quantidade das pendentes de entrada ainda não executadas.
   AjustarQuantidadeEntradasPendentes(true);

   Print("MOLA ATIVADA (", (ehCompra ? "compra" : "venda"), "). Pendentes de entrada ajustadas por nivel. Balde: volume=", g_baldeVolume);
}

//+------------------------------------------------------------------+
//| Cancela ordens individuais pendentes cujo preço já ultrapassa o   |
//| teto do balde (preço médio ± MolaPontos) — acontece quando o      |
//| preço médio se move DEPOIS que a ordem individual já tinha sido   |
//| criada. Sem isso, ficaria uma ordem inalcançável (o balde fecha   |
//| tudo antes dela).                                                  |
//+------------------------------------------------------------------+
void MigrarOrdensAlemDoTeto(ENUM_ORDER_TYPE tipo, double teto, bool ehCompra)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != tipo) continue;
      if(g_baldeTicket != 0 && ticket == g_baldeTicket) continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(state != ORDER_STATE_PLACED) continue;

      double precoOrdem = OrderGetDouble(ORDER_PRICE_OPEN);
      bool   ultrapassa = ehCompra ? (precoOrdem > teto) : (precoOrdem < teto);

      if(ultrapassa)
      {
         Print("Migrando ordem individual #", ticket, " em ", DoubleToString(precoOrdem, _Digits),
               " pro balde — ultrapassava o teto (", DoubleToString(teto, _Digits), ").");
         trade.OrderDelete(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Recria a ordem do balde no preço médio ATUAL da posição ±          |
//| MolaPontos, com o volume recalculado DO ZERO a cada chamada:      |
//| volume_balde = volume_da_posição - volume_ainda_coberto_por_OCOs_ |
//| individuais_pendentes. Isso garante que a soma de todas as ordens |
//| de saída seja SEMPRE IGUAL ao volume da posição, sem falta e      |
//| sem excesso (evitando inversão indesejada de posição no Netting). |
//+------------------------------------------------------------------+
void AtualizarBalde()
{
   if(!PositionSelect(_Symbol))
   {
      if(g_baldeTicket != 0)
      {
         if(OrderSelect(g_baldeTicket) && (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE) == ORDER_STATE_PLACED)
            trade.OrderDelete(g_baldeTicket);
      }

      g_baldeTicket = 0;
      g_baldeExiste = false;
      g_baldeVolume = 0;
      return;
   }

   // Garante direção correta baseada diretamente na posição real no terminal
   long tipoPosReal = PositionGetInteger(POSITION_TYPE);
   bool ehCompra    = (tipoPosReal == POSITION_TYPE_BUY);
   direcao_atual    = ehCompra ? 1 : -1;

   ENUM_ORDER_TYPE tipoSaida = ehCompra ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;

   double precoMedio = PositionGetDouble(POSITION_PRICE_OPEN);
   double teto       = ehCompra ? (precoMedio + MolaPontos) : (precoMedio - MolaPontos);

   // 1. Sempre migra OCOs individuais que ultrapassam o teto (independente de Mola estar ligada ou não)
   MigrarOrdensAlemDoTeto(tipoSaida, teto, ehCompra);

   double volumePosicao    = PositionGetDouble(POSITION_VOLUME);
   double volumeIndividual = SomarVolumeIndividualPendente(tipoSaida);

   // 2. Trava de segurança contra inversão: se volumeIndividual > volumePosicao, cancela excesso
   if(volumeIndividual > volumePosicao)
   {
      Print("!!! ALERTA DE SEGURANÇA: Volume de saidas individuais (", volumeIndividual,
            ") > volume da posicao (", volumePosicao, "). Cancelando só o excedente (as mais distantes).");
      CancelarExcessoIndividual(tipoSaida, volumePosicao, ehCompra);
      volumeIndividual = SomarVolumeIndividualPendente(tipoSaida);
   }

   double novoVolumeBalde = volumePosicao - volumeIndividual;

   if(novoVolumeBalde <= 0)
   {
      // Toda a posição já está coberta por OCOs individuais — sem necessidade de balde agora.
      if(g_baldeVolume != 0 || g_baldeTicket != 0)
      {
         g_baldeVolume = 0;
         g_niveisDescarregados = 0;
         if(g_baldeTicket != 0)
         {
            if(OrderSelect(g_baldeTicket) && (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE) == ORDER_STATE_PLACED)
               trade.OrderDelete(g_baldeTicket);
         }

         g_baldeTicket = 0;
         g_baldeExiste = false;
      }
      return;
   }

   double precoSaida = NormalizarPreco(teto);

   // Verifica se a ordem atual do balde ainda está ativa no book
   bool   ordemAtualValida = false;
   double volumeAtualOrdem = -1;
   double precoAtualOrdem  = -1;

   if(g_baldeTicket != 0 && OrderSelect(g_baldeTicket))
   {
      ENUM_ORDER_STATE st = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(st == ORDER_STATE_PLACED)
      {
         ordemAtualValida = true;
         volumeAtualOrdem = OrderGetDouble(ORDER_VOLUME_CURRENT);
         precoAtualOrdem  = OrderGetDouble(ORDER_PRICE_OPEN);
      }
      else
      {
         g_baldeTicket = 0;
      }
   }

   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   bool   volumeIgual = ordemAtualValida && (MathAbs(volumeAtualOrdem - novoVolumeBalde) < 0.0000001);
   bool   precoIgual  = ordemAtualValida && (MathAbs(precoAtualOrdem - precoSaida) <= (tickSize > 0 ? tickSize / 2.0 : 0.0000001));

   // Se volume e preço já estão corretos, não precisa alterar nada
   if(volumeIgual && precoIgual)
   {
      g_baldeVolume = novoVolumeBalde;
      g_baldeExiste = true;
      return;
   }

   // Se apenas o preço médio mudou e o volume é o mesmo, modifica in-place sem recriar
   if(volumeIgual && !precoIgual)
   {
      if(trade.OrderModify(g_baldeTicket, precoSaida, 0, 0, ORDER_TIME_GTC, 0))
      {
         g_baldeVolume = novoVolumeBalde;
         g_baldeExiste = true;
         Print("Balde modificado: preco medio+/-", MolaPontos, " = ", DoubleToString(precoSaida, _Digits),
               " | volume=", g_baldeVolume);
         return;
      }
   }

   // No modo Netting da B3, cancelamos a ordem anterior antes de enviar a nova para
   // JAMAIS ter duas ordens de saída ativas no book que somadas excedam a posição!
   if(ordemAtualValida && g_baldeTicket != 0)
   {
      trade.OrderDelete(g_baldeTicket);
      g_baldeTicket = 0;
   }

   bool ok = false;
   for(int tentativa = 1; tentativa <= 3 && !ok; tentativa++)
   {
      ok = ehCompra ? trade.SellLimit(novoVolumeBalde, precoSaida, _Symbol, 0, 0, ORDER_TIME_GTC, 0, COMENTARIO_BALDE)
                    : trade.BuyLimit(novoVolumeBalde, precoSaida, _Symbol, 0, 0, ORDER_TIME_GTC, 0, COMENTARIO_BALDE);

      if(!ok)
      {
         Print("Balde: tentativa ", tentativa, "/3 de criar a ordem nova falhou (", trade.ResultRetcodeDescription(), "). Tentando de novo...");
         Sleep(100);
      }
   }

   if(ok)
   {
      g_baldeTicket = trade.ResultOrder();
      g_baldeExiste = true;
      g_baldeVolume = novoVolumeBalde;

      Print("Balde recalculado: preco medio+/-", MolaPontos, " = ", DoubleToString(precoSaida, _Digits),
            " | volume=", g_baldeVolume, " (posicao=", volumePosicao, " - individual=", volumeIndividual, ")");
   }
   else
   {
      Print("!!! ALERTA: falha ao atualizar o balde em ", DoubleToString(precoSaida, _Digits),
            " após 3 tentativas (", trade.ResultRetcodeDescription(), ").");
   }
}

//+------------------------------------------------------------------+
//| Desativa a Mola SEM fechar a posição e SEM tocar no balde — ele   |
//| fica exatamente como está, parado, esperando ser preenchido ou    |
//| ser retomado numa próxima ativação. Só reverte a quantidade das   |
//| pendentes de entrada que faltam, de volta pro padrão (1x).        |
//+------------------------------------------------------------------+
void DesativarMolaSemFechar()
{
   // Volta a quantidade das pendentes de entrada ainda não executadas pro padrão (1x).
   AjustarQuantidadeEntradasPendentes(false);

   g_molaAtiva = false;
   Print("MOLA DESATIVADA. Pendentes voltaram pra ", QuantidadePorOrdem, " contrato(s). Balde MANTIDO (volume=", g_baldeVolume, "), sem cancelar.");
}

void OnTick()
{
   // Rede de segurança contra troca de conta/corretora sem reiniciar o EA:
   // se a conta logada mudou desde a última checagem, TODO o estado interno
   // (preco_entrada, direcao_atual, balde, etc.) pode estar se referindo à
   // conta ANTERIOR — não confiável pra decisão nenhuma. Zera tudo.
   long contaAtual = AccountInfoInteger(ACCOUNT_LOGIN);
   if(g_ultimaContaConhecida != 0 && contaAtual != g_ultimaContaConhecida)
   {
      Print("!!! ALERTA: a conta logada mudou de #", g_ultimaContaConhecida, " para #", contaAtual,
            " sem o EA reiniciar. Estado interno zerado por segurança — cancelando qualquer ordem pendente residual.");
      CancelarOrdensPendentes();
      LimparEstadoCiclo();
   }
   g_ultimaContaConhecida = contaAtual;

   // Rede de segurança contra corrupção de direcao_atual (a causa raiz do
   // bug real que já aconteceu: um "ciclo encerrado" prematuro zerou o
   // estado com a posição ainda viva, e direcao_atual=0 foi então tratado
   // como "venda" em toda a lógica da Mola/balde, mesmo com a posição real
   // sendo comprada). Confere a cada tick se existe posição de verdade e se
   // direcao_atual bate com ela — corrige na hora se não bater.
   if(PositionSelect(_Symbol))
   {
      long tipoPosReal = PositionGetInteger(POSITION_TYPE);
      int  direcaoReal = (tipoPosReal == POSITION_TYPE_BUY) ? 1 : -1;

      if(direcao_atual != direcaoReal)
      {
         Print("!!! ALERTA: direcao_atual interna (", direcao_atual, ") não batia com a posição real (",
               (direcaoReal == 1 ? "comprado" : "vendido"), "). Corrigido agora.");
         direcao_atual = direcaoReal;

         if(preco_entrada <= 0)
            preco_entrada = PositionGetDouble(POSITION_PRICE_OPEN); // aproximação melhor que 0
      }
   }

   // Puck_Agressao:
   // Leitura na Barra 1 (barra anterior já fechada/consolidada, eliminando ruído e repintura intra-tick):
   //  SinalC (buffer 4): 1.0 = Verde Escuro, 2.0 = Verde Claro, 0.0 = Branco
   //  SinalV (buffer 5): 1.0 = Vermelho, 2.0 = Rosa Fraco, 0.0 = Branco
   double puckSinalCArr[], puckSinalVArr[];

   if(CopyBuffer(handlePuck, 4, 1, 1, puckSinalCArr) <= 0) return;
   if(CopyBuffer(handlePuck, 5, 1, 1, puckSinalVArr) <= 0) return;

   // TPV_SMA: buffer 5 = TPVSubindo na barra fechada (1.0 = subindo, 0.0 = caindo)
   double tpvSubindoArr[];
   if(CopyBuffer(handleTPV, 5, 1, 1, tpvSubindoArr) <= 0) return;

   bool compra_verde_escuro = (puckSinalCArr[0] == 1.0); // Puck Comprador Verde Escuro (cor do Puck)
   bool venda_vermelho      = (puckSinalVArr[0] == 1.0); // Puck Vendedor Vermelho (cor do Puck)
   bool compra_subindo      = (puckSinalCArr[0] > 0.0);  // Puck Comprador colorido (Verde Escuro ou Claro)
   bool venda_subindo       = (puckSinalVArr[0] > 0.0);  // Puck Vendedor colorido (Vermelho ou Rosa)
   bool compra_caindo       = (puckSinalCArr[0] == 0.0); // Puck Comprador Branco
   bool venda_caindo        = (puckSinalVArr[0] == 0.0); // Puck Vendedor Branco
   bool TPV_subindo         = (tpvSubindoArr[0] == 1.0); // TPV subindo
   bool TPV_caindo          = !TPV_subindo;              // TPV caindo

   // Só confia na leitura da barra 1 quando os dois indicadores já terminaram de calcular todas as barras
   // (no primeiro tick de uma barra nova o EA pode rodar antes do OnCalculate dos indicadores terminar).
   int  barrasTotal         = Bars(_Symbol, PERIOD_CURRENT);
   bool indicadoresProntos  = (BarsCalculated(handlePuck) >= barrasTotal && BarsCalculated(handleTPV) >= barrasTotal);

   // Entrada / Reentrada:
   //  - Compra: Puck Verde Escuro + TPV Subindo
   //  - Venda:  Puck Vermelho + TPV Caindo
   bool sinalCompra = compra_verde_escuro && TPV_subindo;
   bool sinalVenda  = venda_vermelho && TPV_caindo;

   // Mola (v3): Ativação e Desativação mutuamente exclusivas para evitar oscilação rápida (flapping)
   bool molaAtivaCompra    = TPV_caindo  || (compra_caindo && venda_subindo);
   bool molaDesativaCompra = !molaAtivaCompra;
   bool molaAtivaVenda     = TPV_subindo || (venda_caindo && compra_subindo);
   bool molaDesativaVenda  = !molaAtivaVenda;

   if(!PositionSelect(_Symbol))
   {
      // Rede de segurança: sem posição aberta, não deveria existir NENHUMA
      // ordem pendente nossa (nem de entrada, nem OCO, nem balde). Se sobrou
      // alguma órfã de um fechamento anterior (ex: um OrderDelete que falhou
      // silenciosamente), limpa aqui antes de considerar qualquer entrada nova.
      if(ExistemOrdensOrfas())
      {
         Print("Limpeza: encontradas ordens pendentes sem posição aberta. Cancelando antes de avaliar entrada.");
         CancelarOrdensPendentes();
      }

      direcao_atual    = 0;
      niveis_colocados = 0;

      // Indicadores ainda recalculando a barra que acabou de fechar: a leitura da barra 1 pode estar
      // defasada (o gráfico já mostra o valor final, o EA ainda não). Não decide entrada nesse tick.
      if(!indicadoresProntos)
         return;

      // Diagnóstico: uma linha sempre que a leitura (barra 1) mudar enquanto zerado.
      static double diagC = -1, diagV = -1, diagT = -1;
      if(puckSinalCArr[0] != diagC || puckSinalVArr[0] != diagV || tpvSubindoArr[0] != diagT)
      {
         diagC = puckSinalCArr[0];
         diagV = puckSinalVArr[0];
         diagT = tpvSubindoArr[0];
         Print("Zerado - leitura barra 1: SinalC=", DoubleToString(diagC, 1),
               " SinalV=", DoubleToString(diagV, 1),
               " TPVSubindo=", DoubleToString(diagT, 1),
               " | sinalCompra=", sinalCompra, " sinalVenda=", sinalVenda);
      }

      if(sinalCompra)
      {
         Print("Sinal de entrada COMPRA (Puck Verde Escuro + TPV subindo): compra_verde_escuro=", compra_verde_escuro,
               " TPV_subindo=", TPV_subindo);
         AbrirGrid(ORDER_TYPE_BUY);
      }
      else if(sinalVenda)
      {
         Print("Sinal de entrada VENDA (Puck Vermelho + TPV caindo): venda_vermelho=", venda_vermelho,
               " TPV_caindo=", TPV_caindo);
         AbrirGrid(ORDER_TYPE_SELL);
      }
      // se nenhum dos dois lados bater todas as condições, não entra

      return;
   }

   long tipoPos = PositionGetInteger(POSITION_TYPE);

   // Stop financeiro: não depende de indicador nenhum, só do resultado em R$.
   double lucroFlutuante = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   if(lucroFlutuante <= -MathAbs(StopFinanceiro))
   {
      Print("Sinal de STOP FINANCEIRO: lucro flutuante = ", DoubleToString(lucroFlutuante, 2),
            " <= -", DoubleToString(MathAbs(StopFinanceiro), 2));
      FecharTudo();
      return;
   }

   // Stop não disparou. Verifica transições da Mola (só com indicadores prontos).
   if(!indicadoresProntos)
   {
      AtualizarBalde();
      return;
   }

   if(tipoPos == POSITION_TYPE_BUY)
   {
      if(!g_molaAtiva && molaAtivaCompra)
      {
         Print("Sinal de MOLA COMPRA (ativa): TPV_caindo=", TPV_caindo, " compra_caindo=", compra_caindo, " venda_subindo=", venda_subindo);
         AtivarMola();
      }
      else if(g_molaAtiva && molaDesativaCompra)
      {
         Print("Sinal de MOLA COMPRA (desativa): TPV_subindo=", TPV_subindo, " compra_subindo=", compra_subindo, " venda_caindo=", venda_caindo);
         DesativarMolaSemFechar();
      }
   }
   else if(tipoPos == POSITION_TYPE_SELL)
   {
      if(!g_molaAtiva && molaAtivaVenda)
      {
         Print("Sinal de MOLA VENDA (ativa): TPV_subindo=", TPV_subindo, " venda_caindo=", venda_caindo, " compra_subindo=", compra_subindo);
         AtivarMola();
      }
      else if(g_molaAtiva && molaDesativaVenda)
      {
         Print("Sinal de MOLA VENDA (desativa): TPV_caindo=", TPV_caindo, " venda_subindo=", venda_subindo, " compra_caindo=", compra_caindo);
         DesativarMolaSemFechar();
      }
   }

   // Mantém auditoria contínua de cobertura e migração de teto para 100% da posição aberta
   AtualizarBalde();
}

//+------------------------------------------------------------------+
//| Confere se um ticket de ordem pendente ainda existe no book.      |
//+------------------------------------------------------------------+
bool OrdemAindaExiste(ulong ticket)
{
   if(ticket == 0)
      return(false);

   return(OrderSelect(ticket));
}

//+------------------------------------------------------------------+
//| Abre a posição a mercado e pré-monta todos os níveis do grid     |
//| como ordens pendentes, de uma vez (evita reenviar/duplicar a     |
//| cada tick, que era um risco não confirmado no código NTSL).      |
//+------------------------------------------------------------------+
void AbrirGrid(ENUM_ORDER_TYPE tipo)
{
   bool enviado;

   LimparEstadoCiclo(); // garante que não sobra estado do ciclo anterior

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

   Print("Posição fechada por STOP FINANCEIRO.");

   LimparEstadoCiclo();
}

void CancelarOrdensPendentes(ulong ticketExcluir = 0)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(ticketExcluir != 0 && ticket == ticketExcluir) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(state != ORDER_STATE_PLACED) continue;

      if(!trade.OrderDelete(ticket))
      {
         uint retcode = trade.ResultRetcode();
         if(retcode != TRADE_RETCODE_INVALID && retcode != 10013)
            Print("Falha ao cancelar ordem pendente #", ticket, ": ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Confere se existe alguma ordem pendente nossa (entrada, OCO ou    |
//| balde) no book, sem checar posição — usado como rede de segurança |
//| pra garantir a invariante "sem posição = sem ordens pendentes".   |
//+------------------------------------------------------------------+
bool ExistemOrdensOrfas()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(state != ORDER_STATE_PLACED) continue;

      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Zera todo o estado interno do ciclo (posição, Mola, balde,        |
//| contagem de níveis) — usado sempre que um ciclo termina de vez    |
//| (fechamento total) ou está prestes a começar um novo (AbrirGrid). |
//+------------------------------------------------------------------+
void LimparEstadoCiclo()
{
   g_molaAtiva      = false;
   g_baldeExiste    = false;
   g_baldeVolume    = 0;
   g_baldeTicket    = 0;
   g_niveisDescarregados = 0;
   direcao_atual    = 0;
   niveis_colocados = 0;
   preco_entrada    = 0;
   g_totalNiveis    = 0;
}
