# Ownership and Authorization Check

Use this checklist before writing files.

## Actor and Task

- What active role from `workspace-policy.json` am I claiming?
- What stable task ID identifies this work?
- What workspace files establish the current scope beyond chat history?

## Target and Action

- What normalized workspace-relative path will change?
- Is the action `create`, `modify`, `append`, `delete`, or `move`?
- For `move`, what is the destination path?
- Which most-specific ownership entry applies to each path?
- Is either path protected?

## Authority Type

Choose one:

- direct owner action: the role directly owns the path and action;
- standing permission: policy narrowly permits this non-owner action;
- temporary delegation: a current grant exactly matches role, task, path, action, time, and policy revision;
- suggestion only: no current authority permits the write.

Delegated authority cannot be delegated again.

## Pre-Write Decision

For a write outside direct ownership, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

- `allow`: proceed only within the checked scope.
- `needs_approval`: stop and request a narrow, time-bounded grant.
- `deny`: stop and correct the input or governance data; do not bypass the result.

## Logging and Recovery

- Is the completed action audit-worthy?
- Which files will be listed in `files_changed`?
- What concrete rollback hint will be recorded?
- Did the work change policy and therefore require a higher `policy_revision` and grant review?

## Limitation

This checklist and checker coordinate cooperative actors. They do not authenticate role identity or enforce operating-system file access.
