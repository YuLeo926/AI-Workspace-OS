# Workspace Agent Instructions

## Read Before Acting

1. Read `00_WORKSPACE_INDEX.md`.
2. Read `00_THIS_WEEK.md`.
3. Read the relevant `00_agent_handoff.md`.
4. Read the relevant `_rules.md`.
5. Read active ADRs in `00_DECISIONS/`.
6. Read `workspace-policy.json` before any write.

Workspace files are the durable source of truth. Chat history can provide context, but it is not the only authority for workspace state.

## Before Writing

Confirm the actor role, task ID, action, and target path. For any write outside the actor's direct ownership, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole <role> -TaskId <task-id> -Action <action> -TargetPath <path> -ParseSafe
```

- Continue only on `allow`.
- Stop and request explicit approval on `needs_approval`.
- Stop on `deny` and correct the input or workspace state.
- Do not write across ownership boundaries without an active, exact delegation.
- Do not edit protected paths unless the policy permits the acting role directly.

This check is cooperative guidance. It does not authenticate identity or enforce filesystem permissions.

## After Writing

- Record audit-worthy actions by appending one valid JSON object to `_ops_log/agent_action_log.jsonl`.
- Include affected workspace-relative paths and a practical rollback hint.
- Keep rules stable, handoffs concise, and current state out of chat-only memory.
- Run the local aggregate check before handing off:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -ParseSafe
```
