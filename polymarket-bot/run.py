"""Entry point for the Polymarket signal-driven bot.

Usage:
    cp .env.example .env   # fill in PRIVATE_KEY, token IDs, caps
    pip install -r requirements.txt
    python run.py
"""

from bot import config
from bot.client import PolyClient
from bot.logger import get_logger
from bot.risk import RiskGate
from bot.signals import constant_signal
from bot.trader import Trader

log = get_logger("main")


def build_signal(cfg):
    # Replace this with your real signal: news API, oracle, model, etc.
    # As shipped, the bot uses a constant fair value of 0.50, so it will
    # only trade when the YES book is meaningfully off 50/50.
    return constant_signal(fair=0.50, confidence=1.0)


def main() -> None:
    cfg = config.load()
    log.info(
        "config loaded: host=%s live=%s yes=%s",
        cfg.clob_host, cfg.live, cfg.yes_token_id[:10] + "...",
    )
    client = PolyClient(cfg)
    risk = RiskGate(cfg)
    signal = build_signal(cfg)
    Trader(cfg, client, signal, risk).run_forever()


if __name__ == "__main__":
    main()
