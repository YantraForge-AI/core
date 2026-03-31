# ADR-001: Disable Paperclip Default Heartbeat Prompts

**Status:** Accepted
**Date:** 2026-03-30
**Decision makers:** CTO, CEO

## Context

Paperclip ships default heartbeat skills for each role tier:
- `paperclip-ic.md` — for individual contributor agents
- `paperclip-pm.md` — for manager/lead agents

These provide a generic heartbeat protocol (check inbox, do work, update status).

YantraForge defines its own heartbeat protocol in `HEARTBEAT.md` per agent, which
includes org-specific steps: PARA memory extraction, platform constraint enforcement,
event logging hooks, cross-team delegation rules, and COO learning loop integration.

Running both Paperclip defaults and YantraForge heartbeat instructions simultaneously
creates **conflicting instructions**. Agents receive two different step sequences for
the same lifecycle, leading to:
- Duplicated status updates
- Conflicting checkout/release semantics
- Ignored YantraForge-specific steps (event emission, memory extraction)

## Decision

**Disable Paperclip's default heartbeat prompts for all YantraForge agents.**

Each agent uses YantraForge's `AGENTS.md` (loaded via `instructionsFilePath`) as its
sole instruction source. This file includes the agent's HEARTBEAT.md, SOUL.md, and
TOOLS.md references which together form the complete heartbeat protocol.

The Paperclip `paperclip` skill remains installed company-wide for API coordination
(checkout, comment, status updates), but the skill's heartbeat protocol is superseded
by YantraForge's instructions.

## Verification

Verified 2026-03-30 via `GET /api/companies/{id}/agents`:
- No agent has `paperclip-ic.md` or `paperclip-pm.md` in `adapterConfig`
- All agents with active adapters use YantraForge's managed `AGENTS.md` path
- The `paperclip` skill is installed at company level (all agents see it)
- Skill usage is constrained via agent prompts, not adapter config

## Consequences

### Positive
- Single source of truth for agent behavior per heartbeat
- YantraForge-specific features (event logging, PARA memory, budget checks) are always executed
- No instruction conflicts or duplicated steps

### Negative
- If Paperclip updates its default heartbeat protocol with new features, YantraForge
  agents will not automatically benefit. The CTO must review Paperclip changelog and
  manually port relevant improvements into YantraForge's heartbeat instructions.

### Neutral
- Agents without YantraForge instructions configured will still receive Paperclip
  defaults (this is correct — those agents are not YantraForge-managed).

## Billing Model Decision (Sprint 0)

**Chosen model:** Subscription (Claude Code via Paperclip local adapter)

**Rationale:**
- All 10 agents run on Claude Code subscription via `claude_local` adapter
- Paperclip cannot meter subscription usage — budget tracking is decorative
- `budgetMonthlyCents` values are set per-agent as soft limits for operational awareness
- Actual cost control is at the subscription level, not per-token

**Budget enforcement accuracy:** Approximate. Agent spend figures reflect Paperclip's
internal tracking, not actual API costs. Acceptable for Sprint 0. Revisit when/if
agents migrate to pay-per-token API mode.

**Future consideration:** Hybrid model (subscription for high-frequency agents like
COO/CTO, API for low-frequency agents like Technical Writer/Academic Researcher)
may improve cost visibility. Evaluate after Sprint 1 usage data.
