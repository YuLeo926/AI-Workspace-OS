# Authorization

AI Workspace OS protocol v0.2 adds a machine-checkable authorization contract to a file-first workspace. It helps cooperating humans and agents decide whether a proposed write is directly owned, temporarily delegated, or blocked.

This is cooperative governance. It does not authenticate the role named by a caller, intercept filesystem writes, sandbox a process, or make repository history tamper-proof.

## Machine Facts

`workspace-policy.json` is the sole machine-readable authority for write decisions. `00_WORKSPACE_INDEX.md` mirrors a small ownership summary for people, but the JSON policy wins if they differ.

The policy is strict JSON encoded as UTF-8 without a BOM. Its fields are:

- `protocol_version`: must be `0.2`.
- `policy_revision`: a positive integer. Increase it whenever an authorization-relevant field changes.
- `default_write`: must be `deny` in v0.2.
- `human_override_role`: one declared active role used for protected human decisions and permitted revocations.
- `roles`: unique stable role IDs, descriptions, and `active` or `retired` status.
- `ownership`: workspace-relative paths, direct owners, and allowed actions.
- `standing_permissions`: narrow non-owner permissions. In v0.2 these are intended for append-only shared log files.
- `protected_paths`: paths that require a named role and cannot be authorized by an ordinary delegation.
- `handoff`: the maximum review window and whether an expired handoff produces a warning.

Supported write actions are `create`, `modify`, `append`, `delete`, and `move`. Paths use `/`, remain relative to the workspace, and are matched with ordinal case-sensitive comparison on every operating system. A path ending in `/` includes descendants; a file path matches only that file. The most specific ownership path wins.

Retire a role that appears in delegation history instead of deleting it. A retired role cannot receive new ownership, standing permissions, or grants.

## Policy Revisions

Increment `policy_revision` after changing roles, ownership, actions, standing permissions, protected paths, default behavior, or other authorization-relevant policy fields. An otherwise active grant issued for an older revision becomes inactive and requires fresh approval. Historical expired or revoked events may keep their original revision.

After a policy change:

1. Update `workspace-policy.json` and increment `policy_revision`.
2. Update the delimited ownership summary in `00_WORKSPACE_INDEX.md`.
3. Review active work that depended on delegation.
4. Append new, narrow grants under the new revision where approval still applies.
5. Run the aggregate workspace check in strict mode.

## Standing Permissions

A standing permission allows a declared non-owner role to perform a narrow action without a temporary grant. Use it only for stable shared append sinks, such as `_ops_log/agent_action_log.jsonl` or `_ops_log/delegations.jsonl`.

Standing permissions do not change ownership, cannot overlap protected paths, and cannot authorize further delegation. Avoid broad directory paths or destructive actions.

## Delegation Ledger

`_ops_log/delegations.jsonl` is an append-only event ledger by protocol convention. Every nonblank line is one compact JSON object. Do not edit an old grant to change its scope; append a revoke event and, if approved, append a new grant with a new ID.

Start from the synthetic [delegation template](../templates/delegation-entry.jsonl).

### Grant

A grant binds all of these dimensions:

- one unique `delegation_id`;
- the current `policy_revision`;
- an active direct-owner `grantor_role`;
- a different active `grantee_role`;
- one stable `task_id`;
- a nonempty set of normalized paths;
- a nonempty set of supported actions;
- `issued_at` and later `expires_at` timestamps with offsets;
- a note, which may be empty.

The grantor can delegate only paths and actions it directly owns. Rights received through delegation cannot be delegated again. A grant is inactive before `issued_at`, at or after `expires_at`, after an effective revocation, or when its policy revision is stale.

Example:

```json
{"event":"grant","delegation_id":"DLG-001","policy_revision":1,"grantor_role":"lead","grantee_role":"worker","task_id":"TASK-001","paths":["work-area/report.md"],"actions":["create","modify"],"issued_at":"2026-08-12T08:00:00Z","expires_at":"2026-08-13T08:00:00Z","note":"Prepare the reviewed draft."}
```

### Revoke

A revoke references an earlier active grant. It must be appended by the original grantor or the policy's human override role, include an offset timestamp, and state a nonempty reason.

```json
{"event":"revoke","delegation_id":"DLG-001","revoked_by_role":"lead","timestamp":"2026-08-12T12:00:00Z","reason":"Task scope changed."}
```

Delegation IDs are never reused. A repeated revoke, an unknown ID, an invalid event sequence, malformed JSONL, a blank line, or a NUL byte makes the ledger invalid. An invalid ledger fails authorization closed.

## Check a Proposed Write

Run the checker from an initialized workspace. It is read-only and uses the destination-local validator set:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

For `move`, provide both legs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action move -TargetPath work-area/draft.md -DestinationPath work-area/final.md -ParseSafe
```

The source and destination are evaluated independently. Both must allow the move.

### Decisions and Exit Codes

| Decision | Exit code | Meaning |
| --- | ---: | --- |
| `allow` | `0` | Direct ownership, a narrow standing permission, a current matching grant, or a valid human-owner action permits the write. |
| `needs_approval` | `2` | The path has a known owner, but this role and task lack a current grant. Stop and request approval. |
| `deny` | `1` | Input, role, action, path, policy, ledger, ownership, or protected-path rules make the request invalid. Stop. |

`-ParseSafe` emits stable JSON fields without source records or absolute workspace paths. Omitting it gives human-readable output. The checker never performs the requested write, appends a grant, edits policy, or writes an action log.

## Protected Paths and Fail-Closed Behavior

Protected paths override ordinary ownership and delegation. The required role must also have a valid direct action under policy; a delegation cannot bypass the protection. `workspace-policy.json` itself is protected.

Absolute paths, drive-qualified paths, URI paths, `.` or `..` segments, backslash-form policy paths, workspace escapes, and reparse-point escapes are denied. Invalid policy or delegation data also produces `deny` rather than guessing.

## Validation

Use the focused validators when diagnosing policy or ledger problems:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace-policy.ps1 -Path workspace-policy.json -ParseSafe
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-delegations.ps1 -Path _ops_log\delegations.jsonl -PolicyPath workspace-policy.json -ParseSafe
```

Before completion, run the aggregate check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe
```

See [Workspace Health Check](workspace-health-check.md) for drift signals and recovery guidance.
