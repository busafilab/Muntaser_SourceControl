# Polymarket Signal-Driven Bot

A live, signal-driven trader for Polymarket's CLOB on Polygon.
Built around `py-clob-client`. Single-market, single-signal, with hard
risk caps and a daily-loss kill switch.

> WARNING: This bot is configured to place real orders against
> mainnet when `LIVE=1`. Start with `LIVE=0` (paper mode) and small caps.

## Setup

```bash
cd polymarket-bot
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env: PRIVATE_KEY, YES_TOKEN_ID, NO_TOKEN_ID, caps
```

Find token IDs from a market via Polymarket's Gamma API, e.g.
`https://gamma-api.polymarket.com/markets?slug=<market-slug>`.
The two `clobTokenIds` are YES and NO.

## Run

```bash
python run.py
```

The bot polls every `POLL_INTERVAL_SECONDS`, asks the signal for a fair
YES probability, compares it to the live book top, and trades when the
edge exceeds `SIGNAL_THRESHOLD`. Every order goes through `RiskGate`
(`bot/risk.py`), which enforces:

- `MAX_ORDER_USDC` per order
- `MAX_OPEN_NOTIONAL_USDC` total
- `MAX_DAILY_LOSS_USDC` kill switch (UTC daily reset)
- `MIN_PRICE` / `MAX_PRICE` guards

State is persisted to `state.json` so daily PnL and the kill switch
survive restarts.

## Plug in your signal

`bot/signals.py` defines a `SignalSource` protocol. The default in
`run.py` is a constant 0.50. Replace `build_signal()` to pull from
your real source:

```python
def build_signal(cfg):
    def fn():
        fair = my_news_api.probability_of_yes()
        return Signal(fair=fair, confidence=0.8)
    return CallableSignal(fn)
```

Return `None` from your callable to skip a tick.

## Going live

1. `LIVE=0` first; verify the logged "PAPER" lines look sane.
2. Drop caps low (`MAX_ORDER_USDC=5`).
3. Flip `LIVE=1` and watch the first few ticks live.
4. Ctrl-C cancels all open orders before exiting.

## File map

```
polymarket-bot/
  run.py              entry point
  bot/config.py       env loader + Config dataclass
  bot/client.py       py-clob-client wrapper
  bot/signals.py      SignalSource protocol + helpers
  bot/risk.py         caps, kill switch, daily PnL state
  bot/trader.py       main loop
  bot/logger.py       stdout logger
```
