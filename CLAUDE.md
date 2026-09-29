# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Repository for algorithmic trading development, backtesting, analysis, custom indicators, and automated strategies for the Brazilian market (B3 - WINFUT / Mini-índice), targeting **MetaTrader 5** and **Nelogica Profit**.

## Directory Structure

- **`bots/`**: Automated trading strategies and expert advisors.
  - **`bots/mt5/`**: MetaTrader 5 Expert Advisors (MQL5 / Python). Example: `EA_GradienteLinear3.mq5`.
  - **`bots/profit/`**: Nelogica Profit strategies, scripts, and automation.
- **`indicators/`**: Custom technical indicators and signals.
  - **`indicators/mt5/`**: Custom indicators for MetaTrader 5 (e.g. MQL5 `.mq5` or Python calculations).
  - **`indicators/profit/`**: Custom indicators, coloring rules, and signal scripts for Profit (Nelogica).

## Development Environment: Mac → Windows

Code is written on macOS but **runs in production on Windows**, with MetaTrader 5 and/or Profit terminals active.

This split exists because the official `MetaTrader5` pip package only ships a Windows build (`pip install MetaTrader5` fails on macOS/Linux with `No matching distribution found` — this is expected and not an environment problem to fix).

### Development Guidelines

- **Native APIs**: Write real production code against the official APIs (`import MetaTrader5 as mt5`, direct calls such as `initialize`, `login`, `copy_rates_from_pos`, `order_send`, per [MQL5 Python docs](https://www.mql5.com/en/docs/integration/python_metatrader5)). **No mocks, no abstraction layers, no execution stubs** — the code must be exactly what runs on Windows.
- **No Local MT5 Installs on Mac**: Never attempt `pip install MetaTrader5` on macOS.
- **Execution & Validation**: Modules importing `MetaTrader5` cannot be executed locally on macOS. Validation occurs on Windows:
  - *Workflow*: Write/adjust on macOS → sync via git → run/test on Windows → push fixes back.

## Market Context (B3)

- **Instrument**: B3 mini index futures (WINFUT).
- **Symbol Expiration**: Continuous symbol `WIN$` is not tradable — only the active contract of the current expiration is tradable (e.g. `WINV26`, `WINZ26`, etc.). Never hardcode `WIN$` as an order symbol.
