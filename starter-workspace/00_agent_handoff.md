# Agent Handoff

Updated At: {{UPDATED_AT}}
Review By: {{REVIEW_BY}}

This file bootstraps a new agent session. It is not a daily history file.

## Current Role

Role: {{OWNER_ROLE}}

Mission: Support the workspace purpose within the assigned ownership boundary.

## Workspace Boundary

Allowed areas:

- `{{OWNED_PATH}}`

Do not edit files owned by another role unless explicitly authorized.

## Required Reading Order

1. `00_WORKSPACE_INDEX.md`
2. `00_THIS_WEEK.md`
3. This handoff
4. Relevant `_rules.md`
5. Relevant ADRs

## Hard Constraints

- Treat workspace files, not chat history alone, as the source of truth.
- Do not write across ownership boundaries without an ownership check.
- Do not put long chronological logs in this handoff.
- Record audit-worthy actions in `_ops_log/agent_action_log.jsonl`.
- Do not add private data, credentials, account exports, screenshots, or customer information.

## Current State

{{CURRENT_STATE}}

## Next Step

{{NEXT_STEP}}

## Pending Decisions

No decisions are pending. Add only decisions that require an owner and durable resolution.
