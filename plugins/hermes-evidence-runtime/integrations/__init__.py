"""Optional integration backend helpers for hermes-evidence-runtime.

These helpers are adapters and capability detectors only. They do not vendor or
reimplement external projects, and their outputs are raw evidence, not final
acceptance.
"""

from __future__ import annotations

from .agentguard import agentguard_capability, security_decision
from .dynamic_workflows import dynamic_workflows_capability, orchestration_result

__all__ = [
    "agentguard_capability",
    "dynamic_workflows_capability",
    "orchestration_result",
    "security_decision",
]
