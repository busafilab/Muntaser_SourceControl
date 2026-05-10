import json
import os
import time
from dataclasses import dataclass, field

from .config import Config
from .logger import get_logger

log = get_logger("risk")
STATE_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "state.json")


@dataclass
class DayState:
    day: str
    realized_pnl_usdc: float = 0.0
    open_notional_usdc: float = 0.0
    halted: bool = False
    notes: list[str] = field(default_factory=list)


def _today() -> str:
    return time.strftime("%Y-%m-%d", time.gmtime())


def load_state() -> DayState:
    if not os.path.exists(STATE_PATH):
        return DayState(day=_today())
    with open(STATE_PATH) as f:
        raw = json.load(f)
    s = DayState(**raw)
    if s.day != _today():
        log.info("New UTC day; resetting daily PnL")
        return DayState(day=_today())
    return s


def save_state(s: DayState) -> None:
    with open(STATE_PATH, "w") as f:
        json.dump(s.__dict__, f)


class RiskGate:
    """Hard-limit gate that every order must pass through."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.state = load_state()

    def check(self, price: float, size_shares: float) -> tuple[bool, str]:
        if self.state.halted:
            return False, "kill switch engaged"
        notional = price * size_shares
        if notional <= 0:
            return False, "non-positive notional"
        if notional > self.cfg.max_order_usdc:
            return False, f"order ${notional:.2f} > MAX_ORDER_USDC ${self.cfg.max_order_usdc}"
        if self.state.open_notional_usdc + notional > self.cfg.max_open_notional_usdc:
            return False, "would exceed MAX_OPEN_NOTIONAL_USDC"
        if self.state.realized_pnl_usdc <= -self.cfg.max_daily_loss_usdc:
            self.halt(f"daily loss limit hit: {self.state.realized_pnl_usdc:.2f}")
            return False, "daily loss limit hit"
        if not (self.cfg.min_price <= price <= self.cfg.max_price):
            return False, f"price {price} outside [{self.cfg.min_price}, {self.cfg.max_price}]"
        return True, "ok"

    def record_open(self, notional: float) -> None:
        self.state.open_notional_usdc += notional
        save_state(self.state)

    def record_close(self, notional: float, pnl: float) -> None:
        self.state.open_notional_usdc = max(0.0, self.state.open_notional_usdc - notional)
        self.state.realized_pnl_usdc += pnl
        save_state(self.state)

    def halt(self, reason: str) -> None:
        self.state.halted = True
        self.state.notes.append(reason)
        save_state(self.state)
        log.error("HALTED: %s", reason)
