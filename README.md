# AI Workspace OS

A file-first operating system for long-running, human-supervised AI agent work.

AI Workspace OS gives agents a small, durable protocol: where to start, what they own, how temporary authorization works, and where to leave evidence. It is a template repository with dependency-free PowerShell validators, not an agent runtime.

[简体中文说明](README.zh-CN.md)

## Why This Exists

Most agent frameworks focus on orchestration. AI Workspace OS focuses on what happens after an agent has worked for days or weeks:

- continuity: a new session knows where to begin;
- ownership: agents know what they may edit;
- authorization: cross-owner writes can be reviewed and time-bounded;
- auditability: important actions leave structured evidence;
- recovery: changes include rollback hints and durable decision records.

No package installation, service, or account is required.

## Use in 10 Minutes

1. From this repository, initialize an empty directory or an existing project with no conflicting starter files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\init-workspace.ps1 -Destination path\to\project
```

2. Move into the initialized workspace. Its validators are local, so later commands do not depend on the AI Workspace OS repository checkout:

```powershell
Set-Location path\to\project
```

3. Read `AGENTS.md`, then replace the placeholders in `00_WORKSPACE_INDEX.md`, `00_THIS_WEEK.md`, and `00_agent_handoff.md`. Review `_rules.md` and configure `workspace-policy.json` with real project roles and ownership paths. Keep the delimited ownership summary in `00_WORKSPACE_INDEX.md` aligned with the JSON policy.

4. Start the agent with [the reusable prompt](templates/agent-start-prompt.md) or a provider-specific prompt from [Agent Prompts](docs/agent-prompts.md). Before a write outside the actor's direct ownership, run the destination-local authorization check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

Proceed only on `allow`. Stop and obtain a narrow grant on `needs_approval`; stop on `deny`. Grants and revocations are append-only events in `_ops_log/delegations.jsonl`. See [Authorization](docs/authorization.md) before issuing one.

5. Record audit-worthy completed writes in `_ops_log/agent_action_log.jsonl`, then validate the workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict
```

An untouched starter reports setup warnings until placeholders are replaced and an ADR exists. See [Workspace Health Check](docs/workspace-health-check.md) for error, warning, strict, and parse-safe behavior.

## Protocol at a Glance

### Native Agent Entry

`AGENTS.md` is the shared, provider-neutral entry point. `CLAUDE.md` imports it exactly, so instructions are maintained once. Agents read the workspace index, weekly priorities, relevant handoff and rules, active ADRs, and policy before acting.

### Policy Is the Machine Authority

`workspace-policy.json` defines roles, direct ownership, supported actions, protected paths, narrow standing permissions, default denial, and handoff review settings. The policy summary in `00_WORKSPACE_INDEX.md` is for people; the JSON policy remains authoritative.

### Delegation Is Narrow and Temporary

`_ops_log/delegations.jsonl` records grants and revocations. A grant is bound to one policy revision, grantor, grantee, task, path set, action set, and time window. Delegated rights cannot be delegated again.

### Handoff Is a Session Bootstrap

`00_agent_handoff.md` gives the next session its role, boundary, current state, next step, and review window. It is not a chronological activity log. Its seven English section headings are protocol keys: `Current Role`, `Workspace Boundary`, `Required Reading Order`, `Hard Constraints`, `Current State`, `Next Step`, and `Pending Decisions`.

### Durable Files Hold Durable Truth

`_rules.md` stores stable constraints. Temporary priorities belong in `00_THIS_WEEK.md`; long-lived decisions belong in ADRs; audit-worthy actions belong in `_ops_log/agent_action_log.jsonl`. Chat history alone is not the workspace record.

### Weekly Review Prevents Drift

A weekly review catches expired handoffs, policy/index drift, invalid JSONL, unclear ownership, stale rules, and decisions that need ADRs. Start with [the weekly review template](templates/weekly-review.md).

## Cooperative, Not a Sandbox

AI Workspace OS guides cooperating humans and agents and gives CI a deterministic validation contract. It does not authenticate a claimed role, intercept filesystem writes, sandbox processes, or make logs tamper-proof. Protected paths and authorization decisions are protocol controls, not operating-system security boundaries.

## Who This Is For

- Solo operators using AI agents across weeks or months.
- Developers using Codex, Claude, Cursor, or similar tools on long-running projects.
- Teams that need recoverable agent work without adopting a multi-agent runtime.

## What This Is Not

AI Workspace OS is not an agent runtime, memory database, dashboard, MCP server, complex CLI, identity system, enterprise compliance product, or full business operating system.

## Repository Layout

- [starter-workspace/](starter-workspace/): the complete workspace skeleton used by the initializer.
- [templates/](templates/): reusable ADR, prompt, ownership, delegation, ops log, and weekly review components.
- [examples/solo-business-workspace/](examples/solo-business-workspace/): a fictional, public-safe example.
- [playbook/](playbook/): practical file-first operating guidance.
- [scripts/](scripts/): initialization, authorization, validation, and ADR helpers.
- [tests/](tests/): dependency-free PowerShell regression tests using synthetic fixtures.
- [docs/](docs/): authorization, prompts, health guidance, comparisons, and roadmap.

Reusable templates include:

- [ADR-template.md](templates/ADR-template.md)
- [agent-start-prompt.md](templates/agent-start-prompt.md)
- [delegation-entry.jsonl](templates/delegation-entry.jsonl)
- [ops-log-entry.jsonl](templates/ops-log-entry.jsonl)
- [ownership-check.md](templates/ownership-check.md)
- [weekly-review.md](templates/weekly-review.md)

## Development / Tests

Run the complete suite before opening a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-script-tests.ps1
```

The suite covers policy, delegation, authorization, initialization safety, aggregate workspace health, logs, handoffs, starter integrity, repository quality, and ADR creation. Fixtures must remain synthetic and public-safe. CI runs the same suite on Windows PowerShell 5.1, PowerShell 7 on Windows, and PowerShell 7 on Ubuntu.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution scope. Focused validation and troubleshooting are documented in [Workspace Health Check](docs/workspace-health-check.md).

## Safety

Do not commit real accounts, orders, SKUs, customers, screenshots, platform state, tokens, private handoffs, real ops logs, or internal task identifiers. Read [SECURITY.md](SECURITY.md) before publishing a workspace derived from this repository.

## More Documentation

- [Authorization](docs/authorization.md)
- [Agent Prompts](docs/agent-prompts.md)
- [Workspace Health Check](docs/workspace-health-check.md)
- [Framework Comparisons](docs/comparisons.md)
- [Roadmap](docs/roadmap.md)
- [License](LICENSE)
