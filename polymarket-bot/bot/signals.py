from dataclasses import dataclass
from typing import Callable, Protocol


@dataclass
class Signal:
    """Result of a strategy evaluation.

    fair: model's estimate of the true YES probability in [0, 1].
    confidence: in [0, 1]; 0 means "ignore me".
    """

    fair: float
    confidence: float


class SignalSource(Protocol):
    def evaluate(self) -> Signal | None: ...


class CallableSignal:
    """Adapter so a plain function can be used as a SignalSource."""

    def __init__(self, fn: Callable[[], Signal | None]):
        self.fn = fn

    def evaluate(self) -> Signal | None:
        return self.fn()


def constant_signal(fair: float, confidence: float = 1.0) -> SignalSource:
    """Trivial signal that always reports the same fair value.

    Replace this with a real source: news feed, price oracle, sportsbook line,
    custom model, etc. The trader only cares that `evaluate()` returns a
    Signal or None.
    """

    def fn() -> Signal:
        return Signal(fair=fair, confidence=confidence)

    return CallableSignal(fn)
