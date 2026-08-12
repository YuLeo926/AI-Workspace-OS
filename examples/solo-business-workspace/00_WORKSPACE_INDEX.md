# Solo Business Workspace Index

This is a fictional example workspace.

It contains no real customer data, orders, SKUs, accounts, platform state, screenshots, or private logs.

## Workspace Purpose

Support a small solo business with product planning, content, client work, and research backlog.

## Directory Map

| Path | Purpose | Owner | Read First |
| --- | --- | --- | --- |
| `00_THIS_WEEK.md` | Weekly attention anchor | coordinator | Yes |
| `00_agent_handoff.md` | Global coordination state and routing boundary | coordinator | Yes |
| `_rules.md` | Workspace-wide operating and privacy rules | coordinator | Yes |
| `00_DECISIONS/` | Durable decisions | lead | When planning |
| `_ops_log/` | Audit-worthy actions | coordinator | When reviewing |
| `business/` | Main work area | lead | Yes |
| `business/product/` | Fictional product planning | worker | When assigned |
| `business/content/` | Fictional content channel | worker | When assigned |
| `business/client-work/` | Fictional client work | worker | When assigned |
| `business/research-backlog/` | Ideas and research | worker | When assigned |

## Required Reading Order

1. `00_WORKSPACE_INDEX.md`
2. `00_THIS_WEEK.md`
3. `00_agent_handoff.md`
4. `_rules.md`
5. Relevant nested `00_agent_handoff.md`
6. Relevant nested `_rules.md`
7. Active ADRs in `00_DECISIONS/`

## Active Decisions

| ADR | Decision | Status |
| --- | --- | --- |
| `00_DECISIONS/ADR-001-file-first-memory.md` | Use file-first memory for agent continuity | Accepted |

## Ownership Rules

`workspace-policy.json` is the machine authority for the ownership summary below.

<!-- BEGIN POLICY SUMMARY -->
| Path | Owner |
| --- | --- |
| `00_WORKSPACE_INDEX.md` | `coordinator` |
| `00_THIS_WEEK.md` | `coordinator` |
| `00_agent_handoff.md` | `coordinator` |
| `_rules.md` | `coordinator` |
| `AGENTS.md` | `coordinator` |
| `CLAUDE.md` | `coordinator` |
| `workspace-policy.json` | `coordinator` |
| `.ai-workspace-os/` | `coordinator` |
| `_ops_log/` | `coordinator` |
| `00_DECISIONS/` | `lead` |
| `business/` | `lead` |
| `business/product/` | `worker` |
| `business/content/` | `worker` |
| `business/client-work/` | `worker` |
| `business/research-backlog/` | `worker` |
<!-- END POLICY SUMMARY -->

- Cross-owner writes require an active exact delegation.
- Policy revisions invalidate active grants recorded for older revisions.
