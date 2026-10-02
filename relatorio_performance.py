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
    qtd_ordens: int = 0
    qtd_contratos: float = 0.0
    custos_b3: float = 0.0
    corretagem_total: float = 0.0
    custo_operacional_total: float = 0.0
    irpf: float = 0.0
    resultado_liquido: float = 0.0


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
        self,
        data_ini: date,
        data_fim: date,
        ativo_filtro: str = "Todos",
        corretagem_por_ordem: float = 0.11,
        taxa_b3_por_contrato: float = 0.25,
        aliquota_irpf: float = 20.0,
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
        total_ordens: int = 0
        total_contratos: float = 0.0

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
            total_ordens += len(sorted_deals)
            total_contratos += sum(float(d.volume) for d in sorted_deals)

        # Calcular métricas
        metrics = PerformanceMetrics()
        metrics.qtd_operacoes = len(operacoes_resultados)
        metrics.qtd_ordens = total_ordens
        metrics.qtd_contratos = total_contratos

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

        # Taxas, Emolumentos e IRPF
        metrics.custos_b3 = total_contratos * taxa_b3_por_contrato
        metrics.corretagem_total = total_ordens * corretagem_por_ordem
        metrics.custo_operacional_total = metrics.custos_b3 + metrics.corretagem_total

        # IRPF incide sobre o lucro líquido após custos operacionais
        lucro_tributavel = max(0.0, metrics.resultado_total - metrics.custo_operacional_total)
        metrics.irpf = lucro_tributavel * (aliquota_irpf / 100.0)
        metrics.resultado_liquido = (
            metrics.resultado_total - metrics.custo_operacional_total - metrics.irpf
        )

        return True, metrics, ""


# Habilita suporte a códigos de escape ANSI no console do Windows
if os.name == "nt":
    os.system("")


class Colors:
    """Códigos de escape ANSI para coloração no terminal."""
    RESET = "\033[0m"
    BOLD = "\033[1m"
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    GRAY = "\033[90m"


def colorize_valor(valor: float, texto_formatado: str) -> str:
    """Aplica coloração verde para positivo e vermelho para negativo."""
    if valor > 1e-9:
        return f"{Colors.GREEN}{texto_formatado}{Colors.RESET}"
    elif valor < -1e-9:
        return f"{Colors.RED}{texto_formatado}{Colors.RESET}"
    return texto_formatado


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
    def render_menu(
        data_ini: date,
        data_fim: date,
        ativo: str,
        corretagem: float,
        taxa_b3: float,
        aliquota_irpf: float,
    ):
        CLIFormatter.clear_screen()
        CLIFormatter.render_header("RELATÓRIO DE PERFORMANCE MT5")
        
        hoje = date.today()
        is_hoje = (data_ini == hoje and data_fim == hoje)
        periodo_str = f"{data_ini.strftime('%d/%m/%Y')} a {data_fim.strftime('%d/%m/%Y')}"
        if is_hoje:
            periodo_str += " (Hoje)"

        print("Configuração Atual:")
        print(f"  • Período:        {periodo_str}")
        print(f"  • Ativo:          {ativo}")
        print(f"  • Corretagem:     {format_brl(corretagem)} / ordem")
        print(f"  • Taxa B3:        {format_brl(taxa_b3)} / contrato")
        print(f"  • Alíquota IRPF:  {aliquota_irpf:g}%")
        print("-" * 70)
        print("Opções:")
        print("  (1) Período")
        print("  (2) Ativo")
        print("  (3) Corretagem por ordem")
        print("  (4) Taxa B3 por contrato")
        print("  (5) Alíquota IRPF (%)")
        print("  (6) Iniciar relatório")
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
        corretagem_por_ordem: float,
        taxa_b3_por_contrato: float,
        aliquota_irpf: float,
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
            print(f"{Colors.RED}⚠️  ERRO DE CONEXÃO COM O METATRADER 5:{Colors.RESET}")
            print(f"  {error_msg}")
            print("\n  Tentando reconectar automaticamente a cada 15 segundos...")
            print("=" * 70)
            return

        if metrics is not None:
            # Formatação de Indicadores
            res_total_str = f"{format_brl(metrics.resultado_total):>15}"
            lucro_bruto_str = f"{format_brl(metrics.lucro_bruto):>15}"
            prejuizo_bruto_str = f"{format_brl(metrics.prejuizo_bruto):>15}"
            qtd_ops_str = f"{metrics.qtd_operacoes:>15}"
            venc_str = f"{metrics.qtd_vencedoras:>15}"
            perd_str = f"{metrics.qtd_perdedoras:>15}"

            if metrics.fator_lucro is not None:
                fator_val_str = f"{format_numero(metrics.fator_lucro):>15}"
                if metrics.fator_lucro >= 1.0:
                    fator_lucro_str = f"{Colors.GREEN}{fator_val_str}{Colors.RESET}"
                else:
                    fator_lucro_str = f"{Colors.RED}{fator_val_str}{Colors.RESET}"
            else:
                fator_lucro_str = f"{'—':>15}"

            res_total_colorido = colorize_valor(metrics.resultado_total, res_total_str)
            lucro_bruto_colorido = (
                f"{Colors.GREEN}{lucro_bruto_str}{Colors.RESET}"
                if metrics.lucro_bruto > 0
                else lucro_bruto_str
            )
            prejuizo_bruto_colorido = (
                f"{Colors.RED}{prejuizo_bruto_str}{Colors.RESET}"
                if metrics.prejuizo_bruto < 0
                else prejuizo_bruto_str
            )
            venc_colorido = (
                f"{Colors.GREEN}{venc_str}{Colors.RESET}"
                if metrics.qtd_vencedoras > 0
                else venc_str
            )
            perd_colorido = (
                f"{Colors.RED}{perd_str}{Colors.RESET}"
                if metrics.qtd_perdedoras > 0
                else perd_str
            )

            print("INDICADORES (OPERAÇÕES FECHADAS):")
            print(f"  Resultado Total:                  {res_total_colorido}")
            print(f"  Lucro Bruto:                      {lucro_bruto_colorido}")
            print(f"  Prejuízo Bruto:                  {prejuizo_bruto_colorido}")
            print(f"  Quantidade de Operações:          {qtd_ops_str}")
            print(f"  Operações Vencedoras:             {venc_colorido}")
            print(f"  Operações Perdedoras:             {perd_colorido}")
            print(f"  Fator de Lucro:                   {fator_lucro_str}")

            # Seção: Taxas e Emolumentos
            custos_b3_str = f"{format_brl(-metrics.custos_b3):>15}"
            corretagem_str = f"{format_brl(-metrics.corretagem_total):>15}"
            custo_op_str = f"{format_brl(-metrics.custo_operacional_total):>15}"
            irpf_str = f"{format_brl(-metrics.irpf):>15}"
            res_liq_str = f"{format_brl(metrics.resultado_liquido):>15}"
            res_liq_colorido = colorize_valor(metrics.resultado_liquido, res_liq_str)

            lbl_corretagem = f"Corretagem (a {format_brl(corretagem_por_ordem)}/ordem):"
            lbl_b3 = "Custos B3 (Emolumentos + Registro):"
            lbl_irpf = f"IRPF ({aliquota_irpf:g}%):"

            print("-" * 70)
            print("TAXAS E EMOLUMENTOS:")
            print(f"  {lbl_b3:<34} {custos_b3_str}")
            print(f"  {lbl_corretagem:<34} {corretagem_str}")
            print(f"  {'Custo Operacional Total:':<34} {custo_op_str}")
            print(f"  {lbl_irpf:<34} {irpf_str}")
            print(f"  {'Resultado Líquido:':<34} {res_liq_colorido}")
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
                pl_colorido = colorize_valor(pos.lucro_prejuizo, pl_str)

                # Coloração do tipo de posição (Compra = Verde, Venda = Vermelho)
                if pos.tipo == "Compra":
                    tipo_colorido = f"{Colors.GREEN}{pos.tipo:<6}{Colors.RESET}"
                else:
                    tipo_colorido = f"{Colors.RED}{pos.tipo:<6}{Colors.RESET}"

                print(
                    f"  Ativo: {pos.symbol:<8} | Tipo: {tipo_colorido} | "
                    f"Qtd: {qtd_str:>3} | Preço Médio: {preco_str} | "
                    f"Lucro/Prejuízo: {pl_colorido}"
                )
        print("=" * 70)


class PerformanceReportCLI:
    """Controlador da aplicação de linha de comando."""

    def __init__(self):
        self.service = MT5PerformanceService()
        self.data_inicial: date = date.today()
        self.data_final: date = date.today()
        self.ativo: str = "Todos"
        self.corretagem_por_ordem: float = 0.11
        self.taxa_b3_por_contrato: float = 0.25
        self.aliquota_irpf: float = 20.0

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

    def handle_configurar_corretagem(self):
        """Ação 3: Configurar valor da taxa de corretagem por ordem."""
        print("\n--- Configuração de Corretagem por Ordem ---")
        atual_str = format_numero(self.corretagem_por_ordem)
        while True:
            entrada = input(
                f"Informe o valor da corretagem por ordem (ex: 0,11) [{atual_str}]: "
            ).strip()
            if not entrada:
                print(f"Mantido valor de: {format_brl(self.corretagem_por_ordem)} / ordem")
                time.sleep(1)
                break

            entrada_limpa = entrada.replace("R$", "").replace(" ", "").replace(",", ".")
            try:
                valor = float(entrada_limpa)
                if valor < 0:
                    print("❌ O valor da corretagem não pode ser negativo.")
                    continue
                self.corretagem_por_ordem = valor
                print(f"✅ Corretagem configurada para: {format_brl(self.corretagem_por_ordem)} / ordem")
                time.sleep(1)
                break
            except ValueError:
                print("❌ Valor inválido. Digite um número decimal válido (ex: 0,11).")

    def handle_configurar_taxa_b3(self):
        """Ação 4: Configurar valor de custos B3 (Emolumentos + Registro) por contrato."""
        print("\n--- Configuração de Taxas B3 por Contrato ---")
        atual_str = format_numero(self.taxa_b3_por_contrato)
        while True:
            entrada = input(
                f"Informe a taxa B3 por contrato (ex: 0,25) [{atual_str}]: "
            ).strip()
            if not entrada:
                print(f"Mantido valor de: {format_brl(self.taxa_b3_por_contrato)} / contrato")
                time.sleep(1)
                break

            entrada_limpa = entrada.replace("R$", "").replace(" ", "").replace(",", ".")
            try:
                valor = float(entrada_limpa)
                if valor < 0:
                    print("❌ A taxa B3 não pode ser negativa.")
                    continue
                self.taxa_b3_por_contrato = valor
                print(f"✅ Taxa B3 configurada para: {format_brl(self.taxa_b3_por_contrato)} / contrato")
                time.sleep(1)
                break
            except ValueError:
                print("❌ Valor inválido. Digite um número decimal válido (ex: 0,25).")

    def handle_configurar_irpf(self):
        """Ação 5: Configurar alíquota de IRPF sobre operações Day Trade."""
        print("\n--- Configuração de Alíquota IRPF (%) ---")
        while True:
            entrada = input(
                f"Informe a alíquota de IRPF em % (ex: 20) [{self.aliquota_irpf:g}%]: "
            ).strip()
            if not entrada:
                print(f"Mantida alíquota de: {self.aliquota_irpf:g}%")
                time.sleep(1)
                break

            entrada_limpa = entrada.replace("%", "").replace(" ", "").replace(",", ".")
            try:
                valor = float(entrada_limpa)
                if valor < 0 or valor > 100:
                    print("❌ A alíquota deve ser entre 0% e 100%.")
                    continue
                self.aliquota_irpf = valor
                print(f"✅ Alíquota IRPF configurada para: {self.aliquota_irpf:g}%")
                time.sleep(1)
                break
            except ValueError:
                print("❌ Valor inválido. Digite um número decimal válido (ex: 20).")

    def handle_iniciar_relatorio(self):
        """Ação 6: Iniciar visualização do relatório com atualização a cada 15 segundos."""
        print("\nIniciando relatório de performance...")
        try:
            while True:
                now = datetime.now()
                ok_perf, metrics, err_perf = self.service.calculate_performance(
                    self.data_inicial,
                    self.data_final,
                    self.ativo,
                    self.corretagem_por_ordem,
                    self.taxa_b3_por_contrato,
                    self.aliquota_irpf,
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
                    corretagem_por_ordem=self.corretagem_por_ordem,
                    taxa_b3_por_contrato=self.taxa_b3_por_contrato,
                    aliquota_irpf=self.aliquota_irpf,
                    error_msg=error_msg,
                )

                # RN-12: Intervalo de 15 segundos entre atualizações
                # Loop responsivo para capturar Ctrl+C sem lag
                for _ in range(30):
                    time.sleep(0.5)

        except KeyboardInterrupt:
            # Ctrl+C volta ao menu principal preservando filtros e configurações
            print("\n\nVoltando ao menu principal...")
            time.sleep(0.8)

    def run(self):
        """Loop principal da aplicação."""
        try:
            while True:
                CLIFormatter.render_menu(
                    self.data_inicial,
                    self.data_final,
                    self.ativo,
                    self.corretagem_por_ordem,
                    self.taxa_b3_por_contrato,
                    self.aliquota_irpf,
                )
                opcao = input("Escolha uma opção: ").strip()

                if opcao == "1":
                    self.handle_selecionar_periodo()
                elif opcao == "2":
                    self.handle_selecionar_ativo()
                elif opcao == "3":
                    self.handle_configurar_corretagem()
                elif opcao == "4":
                    self.handle_configurar_taxa_b3()
                elif opcao == "5":
                    self.handle_configurar_irpf()
                elif opcao == "6":
                    self.handle_iniciar_relatorio()
                elif opcao == "0":
                    # Sair
                    print("\nEncerrando aplicação e desconectando do MetaTrader 5...")
                    self.service.shutdown()
                    print("Até logo!")
                    break
                else:
                    print("❌ Opção inválida. Escolha 1, 2, 3, 4, 5, 6 ou 0.")
                    time.sleep(1)
        except (KeyboardInterrupt, EOFError):
            print("\nEncerrando aplicação...")
            self.service.shutdown()
            sys.exit(0)


if __name__ == "__main__":
    app = PerformanceReportCLI()
    app.run()
