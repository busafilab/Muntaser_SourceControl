import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()


def _req(name: str) -> str:
    v = os.getenv(name)
    if not v:
        raise RuntimeError(f"Missing required env var: {name}")
    return v


def _f(name: str, default: float) -> float:
    return float(os.getenv(name, default))


def _i(name: str, default: int) -> int:
    return int(os.getenv(name, default))


@dataclass(frozen=True)
class Config:
    private_key: str
    clob_host: str
    chain_id: int
    signature_type: int
    funder_address: str | None
    yes_token_id: str
    no_token_id: str
    max_order_usdc: float
    max_open_notional_usdc: float
    max_daily_loss_usdc: float
    min_price: float
    max_price: float
    signal_threshold: float
    poll_interval_seconds: int
    live: bool


def load() -> Config:
    funder = os.getenv("FUNDER_ADDRESS") or None
    sig_type = _i("SIGNATURE_TYPE", 0)
    if sig_type in (1, 2) and not funder:
        raise RuntimeError("FUNDER_ADDRESS is required when SIGNATURE_TYPE is 1 or 2")
    return Config(
        private_key=_req("PRIVATE_KEY"),
        clob_host=os.getenv("CLOB_HOST", "https://clob.polymarket.com"),
        chain_id=_i("CHAIN_ID", 137),
        signature_type=sig_type,
        funder_address=funder,
        yes_token_id=_req("YES_TOKEN_ID"),
        no_token_id=_req("NO_TOKEN_ID"),
        max_order_usdc=_f("MAX_ORDER_USDC", 25),
        max_open_notional_usdc=_f("MAX_OPEN_NOTIONAL_USDC", 100),
        max_daily_loss_usdc=_f("MAX_DAILY_LOSS_USDC", 50),
        min_price=_f("MIN_PRICE", 0.05),
        max_price=_f("MAX_PRICE", 0.95),
        signal_threshold=_f("SIGNAL_THRESHOLD", 0.03),
        poll_interval_seconds=_i("POLL_INTERVAL_SECONDS", 15),
        live=os.getenv("LIVE", "0") == "1",
    )
