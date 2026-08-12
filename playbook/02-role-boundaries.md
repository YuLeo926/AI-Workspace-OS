# Role Boundaries

Roles keep agent work owner-aware. `workspace-policy.json` is the machine-readable authority; role descriptions in prose are explanatory only.

A small workspace can use neutral labels:

- `workspace_owner`: owns governance controls and human override decisions;
- `lead`: owns a defined project or decision area;
- `worker`: executes tasks inside a defined boundary.

Use only roles declared by the policy. Retire a role that appears in delegation history instead of deleting it.

## Direct Ownership

Each ownership entry names a workspace-relative path, one owner, and allowed actions. Directory paths end with `/`; file paths match one file. The most specific match wins, unmatched paths are denied, and protected paths override ordinary rules.

Direct ownership is not a statement about job seniority. It identifies who can authorize and perform the listed writes under the cooperative protocol.

## Standing Permission

A standing permission gives a non-owner one durable, narrow action without changing ownership. Keep it to shared append-only sinks such as action and delegation logs. It cannot authorize further delegation or bypass a protected path.

## Temporary Delegation

For a cross-owner task, the direct owner may append a grant to `_ops_log/delegations.jsonl`. The grant must identify the current policy revision, grantor, grantee, task, paths, actions, issue time, and expiry. Delegated rights cannot be delegated again.

Before the non-owner write, run the authorization checker. Continue only on `allow`; obtain a new narrow grant on `needs_approval`; stop on `deny`.

## Write Boundary

Before writing, ask:

- What declared role and task ID am I using?
- Who directly owns the target under `workspace-policy.json`?
- Is the action directly owned, a standing append, or covered by a current exact grant?
- Is the path protected?
- Does the completed action need an action-log entry?

If ownership is unclear, the policy is invalid, or the checker does not return `allow`, stop and propose a change instead of editing.

The protocol does not authenticate the claimed role or enforce filesystem access. Human review and operating-system controls remain separate responsibilities.
