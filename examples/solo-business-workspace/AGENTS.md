# Example Workspace Agent Instructions

## Read Before Acting

1. Read `00_WORKSPACE_INDEX.md`.
2. Read `00_THIS_WEEK.md`.
3. Read `00_agent_handoff.md`.
4. Read `_rules.md`.
5. Read the relevant nested handoff and rules.
6. Read active ADRs in `00_DECISIONS/`.
7. Read `workspace-policy.json` before any write.

Workspace files are the durable source of truth. Chat history is supporting context only.

## Authorization

Stay inside the acting role's direct ownership. Before a cross-owner write, run the local read-only decision command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole <role> -TaskId <task-id> -Action <action> -TargetPath <path> -ParseSafe
```

Continue only on `allow`. Stop and request approval on `needs_approval`; stop and correct the workspace or request on `deny`. This cooperative check does not authenticate identity or enforce filesystem permissions.

## Evidence And Safety

- Append audit-worthy completed actions to `_ops_log/agent_action_log.jsonl`.
- Keep delegation history append-only in `_ops_log/delegations.jsonl`.
- Use only fictional, generic data in this public example.
- Run `.ai-workspace-os\check-workspace.ps1 -Path . -ParseSafe -Strict` before handoff.
