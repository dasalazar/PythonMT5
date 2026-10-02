#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Relatório de Performance MT5 (CLI)
Conecta ao MetaTrader 5, extrai histórico de operações e posições abertas,
calcula indicadores de performance e atualiza o relatório a cada 15 segundos.

Regras de Negócio e Especificações:
- PRD 01: docs/prd/PRD-01-relatorio-performance-mt5-cli.md
- RAW: docs/raw/20261002-relatorio-performance-mt5-cli.md
"""

from dataclasses import dataclass
from datetime import date, datetime, time as dtime
import os
import sys
import time
from typing import Dict, List, Optional, Set, Tuple

import MetaTrader5 as mt5


@dataclass
class PerformanceMetrics:
    """Métricas de performance para operações fechadas."""
    resultado_total: float = 0.0
    lucro_bruto: float = 0.0
    prejuizo_bruto: float = 0.0
    qtd_operacoes: int = 0
    qtd_vencedoras: int = 0
    qtd_perdedoras: int = 0
    fator_lucro: Optional[float] = None  # None representa "—" (indefinido)


@dataclass
class PositionInfo:
    """Informações de uma posição atualmente aberta."""
    symbol: str
    tipo: str  # "Compra" ou "Venda"
    quantidade: float
    preco_medio: float
    lucro_prejuizo: float


def format_brl(valor: float) -> str:
    """Formata valor monetário em padrão brasileiro (R$ 1.250,50 ou -R$ 30,00)."""
    val_abs = abs(valor)
    formatted = f"{val_abs:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    if valor < 0:
        return f"-R$ {formatted}"
    return f"R$ {formatted}"


def format_numero(valor: float) -> str:
    """Formata número com separador de milhar e decimal brasileiro."""
    return f"{valor:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def format_quantidade(qtd: float) -> str:
    """Formata quantidade/volume (ex.: 1 se inteiro ou 1,5 se fracionado)."""
    if qtd.is_integer():
        return str(int(qtd))
    return f"{qtd:g}".replace(".", ",")


def format_preco(preco: float) -> str:
    """Formata preço de ativo respeitando casas decimais relevantes."""
    if preco.is_integer():
        return f"{int(preco):,}".replace(",", ".")
    formatted = f"{preco:,.5f}".rstrip("0").rstrip(".")
    return formatted.replace(",", "X").replace(".", ",").replace("X", ".")


class MT5PerformanceService:
    """Serviço responsável pela comunicação com o MT5 e cálculo dos indicadores."""

    def __init__(self):
        self._connected = False

    def ensure_connection(self) -> Tuple[bool, str]:
        """Garante que a conexão com o terminal MT5 está ativa."""
        if not self._connected:
            if not mt5.initialize():
                err = mt5.last_error()
                self._connected = False
                return False, f"Falha ao inicializar MT5: {err}"
            self._connected = True
        return True, "Conectado"

    def shutdown(self):
        """Encerra a conexão com o MT5."""
        if self._connected:
            try:
                mt5.shutdown()
            except Exception:
                pass
            self._connected = False

    def get_available_symbols(self, data_ini: date, data_fim: date) -> List[str]:
        """
        Retorna lista de ativos negociados no período ou com posições abertas.
        """
        symbols: Set[str] = set()
        ok, _ = self.ensure_connection()
        if not ok:
            return []

        start_dt = datetime.combine(data_ini, dtime.min)
        end_dt = datetime.combine(data_fim, dtime.max)

        # 1. Símbolos do histórico de deals
        deals = mt5.history_deals_get(start_dt, end_dt)
        if deals:
            for deal in deals:
                if deal.symbol and deal.symbol.strip():
                    symbols.add(deal.symbol.strip())

        # 2. Símbolos das posições abertas
        positions = mt5.positions_get()
        if positions:
            for pos in positions:
                if pos.symbol and pos.symbol.strip():
                    symbols.add(pos.symbol.strip())

        return sorted(list(symbols))

    def get_open_positions(self, ativo_filtro: str = "Todos") -> Tuple[bool, List[PositionInfo], str]:
        """
        Consulta posições abertas no MT5 filtradas pelo ativo.
        RN-09: Tipo (Compra ou Venda), Quantidade, Preço médio e Lucro/Prejuízo flutuante.
        """
        ok, err_msg = self.ensure_connection()
        if not ok:
            return False, [], err_msg

        positions = mt5.positions_get()
        if positions is None:
            err = mt5.last_error()
            return False, [], f"Erro ao consultar posições: {err}"

        result: List[PositionInfo] = []
        for pos in positions:
            symbol = pos.symbol.strip() if pos.symbol else ""
            if ativo_filtro != "Todos" and symbol != ativo_filtro:
                continue

            tipo = "Compra" if pos.type == mt5.POSITION_TYPE_BUY else "Venda"
            result.append(
                PositionInfo(
                    symbol=symbol,
                    tipo=tipo,
                    quantidade=float(pos.volume),
                    preco_medio=float(pos.price_open),
                    lucro_prejuizo=float(pos.profit),
                )
            )

        return True, result, ""

    def calculate_performance(
        self, data_ini: date, data_fim: date, ativo_filtro: str = "Todos"
    ) -> Tuple[bool, PerformanceMetrics, str]:
        """
        Calcula os indicadores de performance para operações fechadas no período.
        Regras aplicadas:
        RN-01: Operação de zero a zero com execuções parciais agrupadas por position_id.
        RN-02: Resultado sem taxas/comissões/swap.
        RN-03: Operação pertence ao período pela data de fechamento.
        RN-04: 00:00:00 da data_ini até 23:59:59 da data_fim.
        RN-05: >0 vencedora, <0 perdedora, =0 conta no total mas não em vencedora/perdedora.
        RN-06: Lucro bruto = soma das vencedoras; Prejuízo bruto = soma das perdedoras; Resultado total = lucro + prejuízo.
        RN-07: Fator de lucro = lucro bruto / |prejuízo bruto|, ou indefinido (None) se prejuízo == 0.
        RN-08: Não inclui flutuante de posições abertas.
        """
        ok, err_msg = self.ensure_connection()
        if not ok:
            return False, PerformanceMetrics(), err_msg

        start_dt = datetime.combine(data_ini, dtime.min)
        end_dt = datetime.combine(data_fim, dtime.max)

        # Obter IDs de posições atualmente abertas para não tratá-las como fechadas
        open_positions = mt5.positions_get()
        open_pos_ids: Set[int] = set()
        if open_positions:
            for p in open_positions:
                open_pos_ids.add(p.ticket)
                if hasattr(p, "identifier") and p.identifier:
                    open_pos_ids.add(p.identifier)

        # Buscar deals no período
        deals_in_period = mt5.history_deals_get(start_dt, end_dt)
        if deals_in_period is None:
            err = mt5.last_error()
            return False, PerformanceMetrics(), f"Erro ao consultar histórico de deals: {err}"

        # Coletar IDs de posições com negociação no período
        candidate_position_ids: Set[int] = set()
        for deal in deals_in_period:
            if deal.position_id and deal.position_id > 0:
                candidate_position_ids.add(deal.position_id)

        operacoes_resultados: List[float] = []

        for pos_id in candidate_position_ids:
            # Se ainda estiver aberta, não entra nos indicadores de fechadas (RN-08)
            if pos_id in open_pos_ids:
                continue

            # Buscar todas as execuções dessa posição ao longo do tempo
            pos_deals = mt5.history_deals_get(position=pos_id)
            if not pos_deals:
                continue

            # Ordenar execuções cronologicamente
            sorted_deals = sorted(pos_deals, key=lambda d: (d.time, getattr(d, "time_msc", 0)))
            last_deal = sorted_deals[-1]
            first_deal = sorted_deals[0]

            # Verificar filtro de ativo
            deal_symbol = (first_deal.symbol or last_deal.symbol or "").strip()
            if ativo_filtro != "Todos" and deal_symbol != ativo_filtro:
                continue

            # Verificar se o fechamento da operação ocorreu dentro do período (RN-03)
            close_time = datetime.fromtimestamp(last_deal.time)
            if not (start_dt <= close_time <= end_dt):
                continue

            # RN-02: Lucro/prejuízo apurado pelas execuções da operação, sem comissão, swap e taxas
            op_profit = sum(float(d.profit) for d in sorted_deals)
            operacoes_resultados.append(op_profit)

        # Calcular métricas
        metrics = PerformanceMetrics()
        metrics.qtd_operacoes = len(operacoes_resultados)

        for res in operacoes_resultados:
            if res > 0:
                metrics.qtd_vencedoras += 1
                metrics.lucro_bruto += res
            elif res < 0:
                metrics.qtd_perdedoras += 1
                metrics.prejuizo_bruto += res
            # res == 0 conta na qtd_operacoes, mas não é vencedora nem perdedora (RN-05)

        metrics.resultado_total = metrics.lucro_bruto + metrics.prejuizo_bruto

        # RN-07: Fator de lucro = lucro bruto ÷ |prejuízo bruto|. Se prejuízo == 0, indefinido ("—")
        if abs(metrics.prejuizo_bruto) > 1e-9:
            metrics.fator_lucro = metrics.lucro_bruto / abs(metrics.prejuizo_bruto)
        else:
            metrics.fator_lucro = None

        return True, metrics, ""


class CLIFormatter:
    """Formatador de telas para o terminal."""

    @staticmethod
    def clear_screen():
        """Limpa o terminal de forma compatível com Windows e Unix."""
        os.system("cls" if os.name == "nt" else "clear")

    @staticmethod
    def render_header(title: str = "RELATÓRIO DE PERFORMANCE MT5"):
        print("=" * 70)
        print(f"{title:^70}")
        print("=" * 70)

    @staticmethod
    def render_menu(data_ini: date, data_fim: date, ativo: str):
        CLIFormatter.clear_screen()
        CLIFormatter.render_header("RELATÓRIO DE PERFORMANCE MT5")
        
        hoje = date.today()
        is_hoje = (data_ini == hoje and data_fim == hoje)
        periodo_str = f"{data_ini.strftime('%d/%m/%Y')} a {data_fim.strftime('%d/%m/%Y')}"
        if is_hoje:
            periodo_str += " (Hoje)"

        print("Configuração Atual:")
        print(f"  • Período: {periodo_str}")
        print(f"  • Ativo:   {ativo}")
        print("-" * 70)
        print("Opções:")
        print("  (1) Período")
        print("  (2) Ativo")
        print("  (3) Iniciar relatório")
        print("  (0) Sair")
        print("=" * 70)

    @staticmethod
    def render_report(
        data_ini: date,
        data_fim: date,
        ativo: str,
        last_update: datetime,
        metrics: Optional[PerformanceMetrics],
        positions: List[PositionInfo],
        error_msg: Optional[str] = None,
    ):
        CLIFormatter.clear_screen()
        CLIFormatter.render_header("RELATÓRIO DE PERFORMANCE MT5")

        periodo_str = f"{data_ini.strftime('%d/%m/%Y')} a {data_fim.strftime('%d/%m/%Y')}"
        horario_str = last_update.strftime("%H:%M:%S")

        print(f"Período: {periodo_str} | Ativo: {ativo}")
        print(f"Última Atualização: {horario_str}")
        print("[Pressione Ctrl+C para voltar ao menu]")
        print("-" * 70)

        if error_msg:
            print("⚠️  ERRO DE CONEXÃO COM O METATRADER 5:")
            print(f"  {error_msg}")
            print("\n  Tentando reconectar automaticamente a cada 15 segundos...")
            print("=" * 70)
            return

        if metrics is not None:
            fator_lucro_str = (
                format_numero(metrics.fator_lucro) if metrics.fator_lucro is not None else "—"
            )
            print("INDICADORES (OPERAÇÕES FECHADAS):")
            print(f"  Resultado Total:                  {format_brl(metrics.resultado_total):>15}")
            print(f"  Lucro Bruto:                      {format_brl(metrics.lucro_bruto):>15}")
            print(f"  Prejuízo Bruto:                  {format_brl(metrics.prejuizo_bruto):>15}")
            print(f"  Quantidade de Operações:          {metrics.qtd_operacoes:>15}")
            print(f"  Operações Vencedoras:             {metrics.qtd_vencedoras:>15}")
            print(f"  Operações Perdedoras:             {metrics.qtd_perdedoras:>15}")
            print(f"  Fator de Lucro:                   {fator_lucro_str:>15}")
        else:
            print("INDICADORES: Dados indisponíveis.")

        print("-" * 70)
        print("POSIÇÃO ATUAL:")
        if not positions:
            print("  Sem posição")
        else:
            for pos in positions:
                qtd_str = format_quantidade(pos.quantidade)
                preco_str = format_preco(pos.preco_medio)
                pl_str = format_brl(pos.lucro_prejuizo)
                print(
                    f"  Ativo: {pos.symbol:<8} | Tipo: {pos.tipo:<6} | "
                    f"Qtd: {qtd_str:>3} | Preço Médio: {preco_str} | "
                    f"Lucro/Prejuízo: {pl_str}"
                )
        print("=" * 70)


class PerformanceReportCLI:
    """Controlador da aplicação de linha de comando."""

    def __init__(self):
        self.service = MT5PerformanceService()
        self.data_inicial: date = date.today()
        self.data_final: date = date.today()
        self.ativo: str = "Todos"

    def parse_data(self, data_str: str) -> Optional[date]:
        """Converte string no formato DD/MM/AAAA para objeto date."""
        try:
            return datetime.strptime(data_str.strip(), "%d/%m/%Y").date()
        except ValueError:
            return None

    def handle_selecionar_periodo(self):
        """Ação 1: Selecionar período com validações de negócio."""
        print("\n--- Seleção de Período ---")
        print("Informe as datas no formato DD/MM/AAAA (ou pressione Enter para cancelar/manter)")

        while True:
            ini_input = input(
                f"Data inicial [{self.data_inicial.strftime('%d/%m/%Y')}]: "
            ).strip()
            if not ini_input:
                nova_ini = self.data_inicial
            else:
                parsed_ini = self.parse_data(ini_input)
                if parsed_ini is None:
                    print("❌ Formato de data inicial inválido. Use DD/MM/AAAA.")
                    continue
                nova_ini = parsed_ini

            fim_input = input(
                f"Data final   [{self.data_final.strftime('%d/%m/%Y')}]: "
            ).strip()
            if not fim_input:
                nova_fim = self.data_final
            else:
                parsed_fim = self.parse_data(fim_input)
                if parsed_fim is None:
                    print("❌ Formato de data final inválido. Use DD/MM/AAAA.")
                    continue
                nova_fim = parsed_fim

            if nova_fim < nova_ini:
                print("❌ A data final não pode ser anterior à data inicial. Tente novamente.")
                continue

            self.data_inicial = nova_ini
            self.data_final = nova_fim
            print("✅ Período atualizado com sucesso!")
            time.sleep(1)
            break

    def handle_selecionar_ativo(self):
        """Ação 2: Selecionar ativo a partir de lista numerada."""
        print("\n--- Seleção de Ativo ---")
        print("Buscando ativos com negociação no período...")

        symbols = self.service.get_available_symbols(self.data_inicial, self.data_final)
        options = ["Todos"] + symbols

        while True:
            print("\nAtivos disponíveis:")
            for idx, sym in enumerate(options, 1):
                atual_tag = " (atual)" if sym == self.ativo else ""
                print(f"  ({idx}) {sym}{atual_tag}")

            escolha = input(f"\nEscolha o ativo [1-{len(options)}]: ").strip()
            if not escolha.isdigit():
                print("❌ Opção inválida. Digite o número correspondente ao ativo.")
                continue

            num = int(escolha)
            if 1 <= num <= len(options):
                self.ativo = options[num - 1]
                print(f"✅ Ativo definido como: {self.ativo}")
                time.sleep(1)
                break
            else:
                print(f"❌ Opção inválida. Escolha um número entre 1 e {len(options)}.")

    def handle_iniciar_relatorio(self):
        """Ação 3: Iniciar visualização do relatório com atualização a cada 15 segundos."""
        print("\nIniciando relatório de performance...")
        try:
            while True:
                now = datetime.now()
                ok_perf, metrics, err_perf = self.service.calculate_performance(
                    self.data_inicial, self.data_final, self.ativo
                )
                ok_pos, positions, err_pos = self.service.get_open_positions(self.ativo)

                error_msg = None
                if not ok_perf:
                    error_msg = err_perf
                elif not ok_pos:
                    error_msg = err_pos

                CLIFormatter.render_report(
                    data_ini=self.data_inicial,
                    data_fim=self.data_final,
                    ativo=self.ativo,
                    last_update=now,
                    metrics=metrics if ok_perf else None,
                    positions=positions if ok_pos else [],
                    error_msg=error_msg,
                )

                # RN-12: Intervalo de 15 segundos entre atualizações
                # Loop responsivo para capturar Ctrl+C sem lag
                for _ in range(30):
                    time.sleep(0.5)

        except KeyboardInterrupt:
            # Ação 4: Ctrl+C volta ao menu principal preservando período e ativo
            print("\n\nVoltando ao menu principal...")
            time.sleep(0.8)

    def run(self):
        """Loop principal da aplicação."""
        try:
            while True:
                CLIFormatter.render_menu(self.data_inicial, self.data_final, self.ativo)
                opcao = input("Escolha uma opção: ").strip()

                if opcao == "1":
                    self.handle_selecionar_periodo()
                elif opcao == "2":
                    self.handle_selecionar_ativo()
                elif opcao == "3":
                    self.handle_iniciar_relatorio()
                elif opcao == "0":
                    # Ação 5: Sair
                    print("\nEncerrando aplicação e desconectando do MetaTrader 5...")
                    self.service.shutdown()
                    print("Até logo!")
                    break
                else:
                    print("❌ Opção inválida. Escolha 1, 2, 3 ou 0.")
                    time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nEncerrando aplicação...")
            self.service.shutdown()
            sys.exit(0)


if __name__ == "__main__":
    app = PerformanceReportCLI()
    app.run()
