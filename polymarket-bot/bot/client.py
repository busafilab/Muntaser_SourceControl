from dataclasses import dataclass

from py_clob_client.client import ClobClient
from py_clob_client.clob_types import ApiCreds, OrderArgs, OrderType
from py_clob_client.order_builder.constants import BUY, SELL

from .config import Config
from .logger import get_logger

log = get_logger("client")


@dataclass
class BookTop:
    bid: float
    ask: float
    mid: float


class PolyClient:
    """Thin wrapper around py-clob-client with the calls the bot needs."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.client = ClobClient(
            host=cfg.clob_host,
            key=cfg.private_key,
            chain_id=cfg.chain_id,
            signature_type=cfg.signature_type,
            funder=cfg.funder_address,
        )
        creds = self._ensure_api_creds()
        self.client.set_api_creds(creds)
        log.info("CLOB client ready (signature_type=%s)", cfg.signature_type)

    def _ensure_api_creds(self) -> ApiCreds:
        try:
            return self.client.derive_api_key()
        except Exception:
            log.info("Deriving CLOB API key failed; creating new key")
            return self.client.create_api_key()

    def book_top(self, token_id: str) -> BookTop | None:
        book = self.client.get_order_book(token_id)
        if not book or not book.bids or not book.asks:
            return None
        bid = float(book.bids[-1].price)
        ask = float(book.asks[-1].price)
        return BookTop(bid=bid, ask=ask, mid=(bid + ask) / 2.0)

    def place_limit(
        self, token_id: str, side: str, price: float, size: float
    ) -> dict:
        assert side in (BUY, SELL), f"bad side {side}"
        args = OrderArgs(token_id=token_id, price=price, size=size, side=side)
        signed = self.client.create_order(args)
        return self.client.post_order(signed, OrderType.GTC)

    def cancel_all(self) -> None:
        try:
            self.client.cancel_all()
        except Exception as e:
            log.warning("cancel_all failed: %s", e)

    def open_orders(self) -> list[dict]:
        try:
            return self.client.get_orders() or []
        except Exception as e:
            log.warning("get_orders failed: %s", e)
            return []
