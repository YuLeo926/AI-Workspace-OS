# Contributing

AI Workspace OS is a small, file-first workspace protocol. Contributions should keep it inspectable, dependency-free, and usable without a package, account, or service.

## Welcome Contributions

- Improvements to the [starter workspace](starter-workspace/) and reusable [templates](templates/).
- Clearer authorization, health, recovery, and ownership guidance.
- Focused PowerShell fixes with regression tests.
- Script tests, Bash equivalents, or small cross-platform improvements with explicit behavior.
- Fictional examples containing only synthetic, public-safe data.

## Out of Scope for Now

Do not turn this repository into a heavy runtime, dashboard, MCP server, policy daemon, complex CLI, vector-memory service, identity system, enterprise compliance product, or full business operating system. Hooks and hard write interception are also deferred while the portable protocol is being validated.

## Protocol Changes

Treat the public file formats as contracts. A change to policy, delegation, authorization, handoff, action-log, or parse-safe output behavior must:

- explain the compatibility and fail-closed behavior;
- add or update focused regression tests;
- update the starter, public example, templates, and documentation together;
- keep shipped `.ai-workspace-os/` validator copies byte-identical to their source scripts;
- remain compatible with Windows PowerShell 5.1 unless the roadmap explicitly changes that baseline.

In a real workspace, increment `policy_revision` when authorization-relevant policy fields change. Repository test fixtures may use fixed synthetic revisions for deterministic tests.

## Data Safety

Do not contribute real accounts, orders, SKUs, customers or clients, screenshots, platform exports, credentials, tokens, cookies, private handoffs, real action logs, real delegation ledgers, or internal task identifiers. Use generic roles such as `workspace_owner`, `lead`, and `worker`, generic paths, and fixed synthetic timestamps.

Review [SECURITY.md](SECURITY.md) before reporting a vulnerability or suspected data exposure.

## Development

Run the complete suite before opening a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-script-tests.ps1
```

Run the repository quality gate directly when changing docs, templates, entry files, or shipped validator copies:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\repository-quality.tests.ps1
```

CI runs the complete suite with Windows PowerShell 5.1, PowerShell 7 on Windows, and PowerShell 7 on Ubuntu. No test may require network access, package installation, private files, or real operational data.

## Pull Request Checklist

- The repository remains usable without installing a package or running a service.
- Examples and fixtures are synthetic and public-safe.
- New or changed behavior has focused tests and safe parse output.
- Markdown links are relative and valid; text files are strict UTF-8 without a BOM.
- Native entry files and local validator copies remain synchronized.
- Documentation describes cooperative authorization, not identity authentication or filesystem enforcement.
- The complete test suite passes locally.
