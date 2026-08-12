# ADR 001: Use File-First Memory

Date: 2026-06-18
Status: Accepted

## Decision

This fictional workspace uses file-first memory as the durable source of truth for long-running AI agent work.

## Context

Agent sessions may reset, branch, or lose chat context. The workspace needs a stable way to restart work.

## Reason

- Plain files can be read by many tools.
- Index, handoff, rules, ADRs, and ops logs divide responsibilities cleanly.
- Recovery does not depend on a proprietary memory system.

## Consequences

- Agents must read the workspace files before acting.
- Users must keep handoffs short and current.
- Durable decisions should be captured as ADRs.

## Rollback or Revisit Condition

Revisit if a future tool provides reliable, portable, auditable workspace memory without hiding ownership boundaries.

## Affected Files

- `00_WORKSPACE_INDEX.md`
- `00_THIS_WEEK.md`
- `business/00_agent_handoff.md`
- `business/_rules.md`
