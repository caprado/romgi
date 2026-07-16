"""
Grouping strategy discovery.

Walks `db/grouping/strategies/`, imports each module, and collects the
`STRATEGY` symbol it exposes. Adding a strategy is a one-file drop — nothing
here or in `make.py` needs editing.
"""
from __future__ import annotations

import importlib
import pkgutil

from .base import GroupingStrategy


def load_strategies() -> list[GroupingStrategy]:
    """Discover and instantiate every strategy plugin, ordered by kind."""
    from . import strategies as pkg

    found: list[GroupingStrategy] = []
    for mod in pkgutil.iter_modules(pkg.__path__):
        module = importlib.import_module(f"{pkg.__name__}.{mod.name}")
        strategy = getattr(module, "STRATEGY", None)
        if strategy is None:
            continue
        if isinstance(strategy, type):
            strategy = strategy()
        if not isinstance(strategy, GroupingStrategy):
            raise TypeError(
                f"{module.__name__}.STRATEGY does not satisfy GroupingStrategy "
                f"(needs a `kind` attr and a `membership()` method)"
            )
        found.append(strategy)

    found.sort(key=lambda s: s.kind)
    return found
