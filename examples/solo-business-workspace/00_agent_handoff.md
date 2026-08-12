# Workspace Coordinator Handoff

Updated At: 2026-06-18T08:00:00Z
Review By: 2026-06-25T08:00:00Z

This file bootstraps coordination for the fictional example workspace. It is not a daily history file.

## Current Role

Role: coordinator

Mission: Maintain global routing, weekly priorities, and safe delegation across this synthetic workspace.

## Workspace Boundary

Allowed areas:

- `00_WORKSPACE_INDEX.md`
- `00_THIS_WEEK.md`
- `00_agent_handoff.md`
- `_rules.md`
- `00_DECISIONS/`
- `_ops_log/`

The `business/` directory is governed by its nested handoff and rules. Delegate project work instead of editing across that boundary without authorization.

## Required Reading Order

1. `00_WORKSPACE_INDEX.md`
2. `00_THIS_WEEK.md`
3. This handoff
4. `_rules.md`
5. Relevant nested handoff and rules
6. Active ADRs in `00_DECISIONS/`

## Hard Constraints

- Use only synthetic and generic information.
- Treat workspace files, not chat history alone, as the source of truth.
- Confirm ownership before writing into a nested project area.
- Record audit-worthy actions in `_ops_log/agent_action_log.jsonl`.

## Current State

- The global layer defines routing and workspace-wide safety rules.
- The nested `business/` layer defines project-level boundaries for fictional work.
- The current weekly priorities and accepted decisions are recorded in their authoritative files.

## Next Step

Route the next approved task to the appropriate owner and nested workspace boundary.

## Pending Decisions

No global decision is currently pending.
