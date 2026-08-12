# Workspace Health Check

Use the destination-local aggregate validator to detect drift across an initialized AI Workspace OS workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path .
```

The checker validates required files, policy, delegation history, handoff structure and freshness, action logs, ADR presence, starter placeholders, and the ownership summary mirrored in `00_WORKSPACE_INDEX.md`. It reports source-safe findings without printing policy records, ledger events, ops log entries, or absolute workspace paths.

## Errors, Warnings, and Output

- **Errors** indicate a broken contract, such as invalid policy, malformed JSONL, missing handoff fields, an invalid delegation sequence, a missing core file, or a child validator failure. Any error returns exit code `1`.
- **Warnings** indicate drift requiring review, such as an expired handoff, UTF-8 BOM, unresolved setup placeholders, no ADRs, or policy/index mismatch. Warnings do not fail the default check.
- **`-Strict`** makes warnings fail. Use it before claiming a configured workspace is healthy.
- **`-ParseSafe`** returns stable JSON with relative paths, issue codes, line numbers, child summaries, and counts. It does not echo source lines or private records.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe
```

An untouched starter is expected to warn until placeholders are replaced and an ADR exists. A configured workspace and the shipped public example should pass strict validation.

## Focused Validators

### Policy

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace-policy.ps1 -Path workspace-policy.json -ParseSafe
```

Use this for protocol version, revision, roles, normalized paths, ownership actions, standing permissions, protected paths, and handoff settings. The policy must be strict UTF-8 JSON without a BOM.

### Delegations

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-delegations.ps1 -Path _ops_log\delegations.jsonl -PolicyPath workspace-policy.json -ParseSafe
```

Use this for malformed JSONL, invalid grantor scope, duplicate IDs, revocation sequence, expiry, stale active policy revisions, and attempted self or transitive delegation. The validator reads the complete append-only history and never prints source events.

### Proposed Write

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

This read-only check returns `allow`, `needs_approval`, or `deny`. It does not perform or block the filesystem write. See [Authorization](authorization.md).

### Handoff

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-handoff-size.ps1 -Path 00_agent_handoff.md
```

Every handoff needs `Updated At` and `Review By` directly below its title plus the seven required English protocol headings. Policy controls the maximum review window and whether an expired review date warns.

### Action Log

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-ops-log.ps1 -Path _ops_log\agent_action_log.jsonl
```

Every nonblank line must be one complete JSON object matching the action log contract. Start new entries from the synthetic [JSONL template](../templates/ops-log-entry.jsonl).

## Drift Signals and Recovery

### Handoff Became Long or Stale

A handoff bootstraps the next session. If it grows into history, move completed events to the action log, priorities to `00_THIS_WEEK.md`, and durable choices to ADRs. If `Review By` has passed, review the role, boundary, current state, and next step; then update both timestamps deliberately. Validators never rewrite them.

### Policy and Index Disagree

`workspace-policy.json` is authoritative. A missing, malformed, or differing delimited ownership summary in `00_WORKSPACE_INDEX.md` produces `policy_index_drift` or a marker warning. Review the JSON policy first, then make the human summary match. Do not infer permissions from surrounding prose.

### Policy Revision Changed

An authorization-relevant policy edit requires a higher `policy_revision`. Otherwise-active grants tied to an older revision become inactive and require fresh approval. Review current tasks and append new narrow grants only where approval still applies; do not rewrite historical events.

### Delegation Ledger Is Invalid

Malformed records, blank lines, duplicate IDs, invalid revoke order, grantor scope errors, or stale active grants prevent the ledger from authorizing work. Stop cross-owner writes. Recover the intended history from version control or append a valid event where protocol permits; never silently delete evidence from published history.

### Rules Became Temporary Notes

`_rules.md` holds stable constraints. Temporary work belongs in `00_THIS_WEEK.md`; audit events belong in the action log.

### Ownership Is Unclear

Every governed path needs one direct owner and explicit actions in `workspace-policy.json`. Use the [ownership checklist](../templates/ownership-check.md). An unowned path is denied; do not guess from chat or prose.

### ADRs Are Missing

Repeated debates, cross-owner decisions, policy changes, and choices with important rollback conditions should become ADRs. From the AI Workspace OS repository, create one with [new-adr.ps1](../scripts/new-adr.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-adr.ps1 -Title "Decision title" -Destination path\to\project\00_DECISIONS
```

## Weekly Review

Review priorities, handoff freshness, policy revision, policy/index alignment, active delegations, action log health, ownership boundaries, stable rules, and missing decisions once a week. Use the [weekly review template](../templates/weekly-review.md).

These checks support cooperative behavior and CI. They do not authenticate role claims, intercept writes, or replace operating-system access controls.
