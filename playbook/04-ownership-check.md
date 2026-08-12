# Ownership Check

Ownership checks prevent accidental cross-owner writes. Use [the reusable checklist](../templates/ownership-check.md) before changing a file outside an obvious direct boundary.

## Minimum Check

1. Identify the role and stable task ID.
2. Read `workspace-policy.json` and identify the most specific owner for the target.
3. Confirm that the requested action is one of `create`, `modify`, `append`, `delete`, or `move`.
4. Check whether the path is protected.
5. Classify the request as direct ownership, standing permission, temporary delegation, or suggestion only.
6. For any write outside direct ownership, run the destination-local authorization checker.
7. Decide whether the completed write requires an action-log entry and prepare a rollback hint.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

For `move`, include `-DestinationPath`; source and destination must both allow the operation.

## Decision

- `allow` with exit code `0`: proceed within the checked role, task, action, path, and time.
- `needs_approval` with exit code `2`: stop and ask the direct owner for a narrow grant.
- `deny` with exit code `1`: stop; fix invalid input or governance data rather than bypassing the check.

An old, expired, revoked, wrong-task, wrong-action, wrong-path, or stale-policy grant does not authorize the write.

## When to Stop

Stop and ask when:

- the owner is unknown or the path is unowned;
- policy or delegation validation fails;
- authorization is vague or only present in chat;
- the change affects private data;
- the target is outside the assigned boundary;
- the rollback path is unclear.

The checker is read-only cooperative guidance. It does not authenticate the actor or prevent an uncooperative process from writing.
