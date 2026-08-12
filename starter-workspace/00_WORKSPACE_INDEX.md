# Workspace Index

This file is the map and routing layer for the workspace.

## Workspace Purpose

{{WORKSPACE_PURPOSE}}

## Directory Map

| Path | Purpose | Owner | Read First |
| --- | --- | --- | --- |
| `00_THIS_WEEK.md` | Weekly priority anchor | Defined by the workspace | Yes |
| `00_DECISIONS/` | Long-lived decision records | Defined by the workspace | When decisions affect work |
| `_ops_log/` | Audit-worthy action logs | Defined by the workspace | When writing or reviewing |
| `{{OWNED_PATH}}` | Owned work area | `{{OWNER_ROLE}}` | When assigned |

## Required Reading Order

1. `00_WORKSPACE_INDEX.md`
2. `00_THIS_WEEK.md`
3. Relevant `00_agent_handoff.md`
4. Relevant `_rules.md`
5. Active ADRs in `00_DECISIONS/`

## Active Decisions

No decisions are recorded yet. Add accepted ADRs here only after they exist.

## Ownership Rules

`workspace-policy.json` is the machine authority. Keep the summary below synchronized whenever ownership changes.

<!-- BEGIN POLICY SUMMARY -->
| Path | Owner |
| --- | --- |
| `00_WORKSPACE_INDEX.md` | `workspace_owner` |
| `00_THIS_WEEK.md` | `workspace_owner` |
| `00_agent_handoff.md` | `workspace_owner` |
| `_rules.md` | `workspace_owner` |
| `00_DECISIONS/` | `workspace_owner` |
| `_ops_log/` | `workspace_owner` |
| `AGENTS.md` | `workspace_owner` |
| `CLAUDE.md` | `workspace_owner` |
| `workspace-policy.json` | `workspace_owner` |
| `.ai-workspace-os/` | `workspace_owner` |
| `work-area/` | `worker` |
<!-- END POLICY SUMMARY -->

- The starter maps `worker` to `work-area/`; replace or extend this with `{{OWNER_ROLE}}` and `{{OWNED_PATH}}` for the real workspace.
- Define every additional ownership boundary in the policy before assigning work.
- Cross-owner writes require an active exact delegation or must be proposed as suggestions.

## Non-Authoritative Sources

List notes, drafts, chats, or generated files that should not be treated as authoritative.

## Recovery Pointers

- Check `_ops_log/agent_action_log.jsonl` for audit-worthy actions.
- Check `_ops_log/delegations.jsonl` for temporary grants and revocations.
- Check ADRs before reopening settled decisions.
- Check `00_THIS_WEEK.md` before treating a recent chat as the full priority system.
