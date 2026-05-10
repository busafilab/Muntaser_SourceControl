import time

from py_clob_client.order_builder.constants import BUY, SELL

from .client import PolyClient
from .config import Config
from .logger import get_logger
from .risk import RiskGate
from .signals import SignalSource

log = get_logger("trader")


class Trader:
    """Signal-driven trader.

    On each tick:
      1. Ask the signal for a fair YES probability.
      2. Read the YES order book top.
      3. If fair - ask > threshold, buy YES at ask (model thinks it's cheap).
         If bid - fair > threshold, sell YES at bid (model thinks it's rich).
      4. Every order is gated by RiskGate; in non-LIVE mode we log and skip.
    """

    def __init__(self, cfg: Config, client: PolyClient, signal: SignalSource, risk: RiskGate):
        self.cfg = cfg
        self.client = client
        self.signal = signal
        self.risk = risk

    def _size_shares(self, price: float) -> float:
        budget = self.cfg.max_order_usdc
        shares = budget / max(price, 0.01)
        return round(shares, 2)

    def _maybe_trade(self, side: str, price: float) -> None:
        size = self._size_shares(price)
        ok, reason = self.risk.check(price, size)
        if not ok:
            log.info("skip %s @ %.3f size %.2f: %s", side, price, size, reason)
            return

        notional = price * size
        if not self.cfg.live:
            log.info("PAPER %s %.2f @ %.3f (notional $%.2f)", side, size, price, notional)
            return

        try:
            resp = self.client.place_limit(self.cfg.yes_token_id, side, price, size)
            log.info("LIVE %s %.2f @ %.3f -> %s", side, size, price, resp)
            self.risk.record_open(notional)
        except Exception as e:
            log.exception("order failed: %s", e)

    def tick(self) -> None:
        sig = self.signal.evaluate()
        if sig is None or sig.confidence <= 0:
            log.debug("no signal")
            return

        top = self.client.book_top(self.cfg.yes_token_id)
        if top is None:
            log.warning("no book for YES token")
            return

        edge_buy = sig.fair - top.ask
        edge_sell = top.bid - sig.fair
        log.info(
            "fair=%.3f bid=%.3f ask=%.3f mid=%.3f edge_buy=%.3f edge_sell=%.3f",
            sig.fair, top.bid, top.ask, top.mid, edge_buy, edge_sell,
        )

        if edge_buy > self.cfg.signal_threshold:
            self._maybe_trade(BUY, top.ask)
        elif edge_sell > self.cfg.signal_threshold:
            self._maybe_trade(SELL, top.bid)

    def run_forever(self) -> None:
        log.info(
            "starting loop: live=%s poll=%ss threshold=%.3f",
            self.cfg.live, self.cfg.poll_interval_seconds, self.cfg.signal_threshold,
        )
        while True:
            try:
                self.tick()
            except KeyboardInterrupt:
                log.info("interrupted; cancelling open orders")
                if self.cfg.live:
                    self.client.cancel_all()
                return
            except Exception as e:
                log.exception("tick error: %s", e)
            time.sleep(self.cfg.poll_interval_seconds)
