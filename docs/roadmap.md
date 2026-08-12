# Roadmap

AI Workspace OS remains a file-first protocol. The roadmap favors transparent templates and small, dependency-free validators over runtime features.

## v0.1 Foundation

- placeholder-based starter workspace and safe initialization;
- handoff, rules, weekly priorities, ADRs, and JSONL action logs;
- aggregate and focused health checks;
- fictional examples, playbook, tests, and minimal CI.

## v0.1.1 Usability Increment

- native `AGENTS.md` and `CLAUDE.md` project entry points;
- explicit handoff update and review timestamps;
- destination-local read-only validators in initialized workspaces.

## v0.2 Authorization Protocol

- strict `workspace-policy.json` roles, ownership, actions, standing permissions, and protected paths;
- append-only grant and revoke events in `_ops_log/delegations.jsonl`;
- read-only `allow`, `needs_approval`, and `deny` write decisions;
- policy/index drift, stale grant revision, delegation, and handoff freshness checks;
- full tests on Windows PowerShell 5.1 and PowerShell 7 on Windows and Ubuntu.

The v0.2 layer is cooperative governance. It does not authenticate identities or enforce filesystem access.

## Next

- Harden the v0.2 contracts from public usage feedback.
- Add Bash equivalents only when behavior can remain explicit, fail-closed, and testable.
- Improve diagnostics and portability without adding a service dependency.
- Consider JSON Schema only after the policy and JSONL contracts are stable.

## Explicitly Deferred

- hooks or hard pre-write interception;
- role identity authentication or cryptographic signing;
- tamper-proof audit storage;
- npm or pip packages;
- a heavy agent runtime or orchestration layer;
- a dashboard, MCP server, policy daemon, or complex CLI;
- automatic policy, delegation, handoff, or action-log rewriting;
- enterprise compliance features.

Hooks and hard interception remain deferred because v0.2 first needs evidence that the portable file contract is understandable and stable. Adding provider-specific enforcement now would increase runtime and security claims without creating identity verification or an operating-system sandbox.
