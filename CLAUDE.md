# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Python CLI application for the WINFUT (B3 mini index futures) market, integrated with
MetaTrader 5. Scope includes trading automation, backtesting/analysis, performance
reporting, custom indicators, and order execution. The repository is in initial setup;
no application code exists yet.

There is already a native MQL5 robot in the account, `EA_GradienteLinear.mq5` (magic
number 198198), implementing a grid/martingale strategy with two custom indicators:
`TPV_SMA` (volume-price with moving average) and `Puck_Agressao` (aggression balance
reconstructed from tick flags via `CopyTicksRange`). The exact relationship between this
Python project and that EA (complementary reporting vs. an alternative execution path) is
not yet defined — do not assume one without confirming.

## Development environment: Mac → Windows

Code is written on macOS but **runs in production on Windows**, with the MetaTrader 5
terminal open and logged into the broker account there.

This split exists because the official `MetaTrader5` pip package only ships a Windows
build. `pip install MetaTrader5` fails on macOS/Linux with `No matching distribution
found` — this is expected and not an environment problem to fix.

Rules that follow from this:

- Write real production code against the official API: `import MetaTrader5 as mt5`,
  direct calls such as `initialize`, `login`, `copy_rates_from_pos`, `order_send`, per
  https://www.mql5.com/en/docs/integration/python_metatrader5. **No mocks, no
  abstraction layer, no execution stubs** — the code must be exactly what runs on
  Windows.
- Never attempt `pip install MetaTrader5` on the Mac.
- Nothing that imports the `MetaTrader5` module can be run or tested locally on this
  machine. All execution validation (connection, order sending, real-time data) happens
  only on Windows.
- Expected flow: write/adjust on Mac → sync via git → run/validate on Windows → bring
  fixes back.

## Market context

- Instrument: B3 mini index futures (WINFUT). The continuous symbol `WIN$` is not
  tradable — only the specific contract of the current expiration is (e.g. `WINV26`).
  Never hardcode `WIN$` as an order symbol.
