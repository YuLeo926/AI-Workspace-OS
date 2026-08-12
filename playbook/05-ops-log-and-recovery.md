# Ops Log and Recovery

AI Workspace OS uses two append-only JSONL streams with different purposes:

- `_ops_log/agent_action_log.jsonl` records audit-worthy completed actions and recovery context.
- `_ops_log/delegations.jsonl` records temporary authorization grants and revocations.

Do not mix the two contracts or use either as a chronological chat transcript.

## Action Log

Append an action record after an agent changes important files, updates stable rules or policy, edits decision records, touches cross-owner areas, or performs an action that needs recovery context.

Required fields include timestamp, agent or role, action, target, approval state, changed files, rollback hint, and note. Use [the synthetic action-log template](../templates/ops-log-entry.jsonl).

An authorization decision is evidence for the proposed write, but the checker does not write the action log. Record audit-worthy completed work separately and truthfully.

## Delegation Ledger

Append a grant only when a direct owner intentionally approves a narrow cross-owner task. Append a revoke when that approval ends early. Never edit an earlier line to expand scope, change expiry, or reuse an ID; append a revoke and a new grant instead.

Use [the synthetic delegation template](../templates/delegation-entry.jsonl). Grants are bound to policy revision, role, task, path, action, and time. A stale, expired, or revoked grant remains history but no longer authorizes work.

## Recovery Hints

A useful rollback hint names the affected file and a concrete recovery action.

Poor rollback hint:

```text
undo it
```

Useful rollback hint:

```text
Restore work-area/report.md from the previous commit and rerun the strict workspace check.
```

If a policy edit invalidates active grants, increment `policy_revision`, review affected tasks, and append replacement grants only where approval remains valid. Do not rewrite delegation history to hide the transition.

## Health Checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-ops-log.ps1 -Path _ops_log\agent_action_log.jsonl
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-delegations.ps1 -Path _ops_log\delegations.jsonl -PolicyPath workspace-policy.json
```

These checks catch malformed JSONL, blank lines, BOM, NUL bytes, and contract or event-sequence problems. They support recovery and cooperative review; they do not make logs tamper-proof.
