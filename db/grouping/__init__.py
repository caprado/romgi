"""Entry grouping: pluggable strategies that relate catalog entries.

Public surface used by the build pipeline:
    load_strategies()  -> discover strategy plugins
    build_groups(...)  -> bucket + promote memberships into groups
"""
from __future__ import annotations

from .base import EntryRef, GroupingStrategy, Membership
from .build import EntryGroup, GroupMember, build_groups
from .registry import load_strategies

__all__ = [
    "EntryRef",
    "GroupingStrategy",
    "Membership",
    "EntryGroup",
    "GroupMember",
    "build_groups",
    "load_strategies",
]
