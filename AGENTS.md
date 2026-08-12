# AI Workspace OS Contributor Instructions

## Read First

1. Read `README.md` for the public project scope.
2. Read the relevant design or implementation plan in `docs/superpowers/` when one exists locally.
3. Read the scripts and tests that own the behavior being changed.

## Public Repository Boundary

- Use only synthetic, generic examples.
- Do not read or copy private workspaces, private handoffs, real operational logs, accounts, orders, SKUs, customers, screenshots, credentials, tokens, or internal identifiers.
- Keep AI Workspace OS file-first and dependency-free. Do not turn it into a runtime service, dashboard, MCP server, package, or complex CLI.

## Change Rules

- Preserve Windows PowerShell 5.1 and PowerShell 7 compatibility.
- Keep authorization cooperative and read-only; do not claim identity verification or filesystem enforcement.
- Update focused tests with behavior changes, then run the complete suite:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-script-tests.ps1
```

- Do not create a remote, stage, commit, push, publish, or release unless the user explicitly authorizes that action.
