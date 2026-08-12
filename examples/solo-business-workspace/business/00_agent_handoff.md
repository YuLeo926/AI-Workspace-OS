# Business Agent Handoff

Updated At: 2026-06-18T08:00:00Z
Review By: 2026-06-25T08:00:00Z

This file bootstraps the fictional business work area.

It is not a daily history file.

## Current Role

Role: worker

Mission: Support delegated product, content, client-work, and research tasks inside the fictional example workspace.

## Workspace Boundary

Allowed areas:

- `business/product/`
- `business/content/`
- `business/client-work/`
- `business/research-backlog/`

Do not edit:

- `00_WORKSPACE_INDEX.md`
- `00_THIS_WEEK.md`
- `00_DECISIONS/`
- `_ops_log/`

Unless explicitly delegated by coordinator or lead.

## Required Reading Order

1. `../00_WORKSPACE_INDEX.md`
2. `../00_THIS_WEEK.md`
3. `00_agent_handoff.md`
4. `_rules.md`
5. `../00_DECISIONS/ADR-001-file-first-memory.md`

## Hard Constraints

- Use only fictional examples.
- Do not introduce real orders, SKUs, accounts, customers, screenshots, or platform statuses.
- Ask before writing outside the business subfolders.
- Suggest ADRs for durable decisions.

## Current State

- The example workspace has been initialized.
- Product, content, client-work, and research folders exist as safe placeholders.
- The first accepted ADR establishes file-first memory.

## Next Step

Draft a one-page fictional product concept in `business/product/`.

## Pending Decisions

| Decision | Owner | Needed By | Notes |
| --- | --- | --- | --- |
| Product scope | lead | 2026-06-25 | May become ADR-002 |
