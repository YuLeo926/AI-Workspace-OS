# Workspace Rules

These rules apply across the fictional example workspace. Nested rules may add constraints within their owned area but may not weaken these rules.

## File-First Rules

- Read the root index, weekly priorities, handoff, and rules before acting.
- Treat chat history as supporting context, not the only source of truth.
- Keep handoffs concise and record durable decisions as ADRs.

## Ownership Rules

- The coordinator maintains the global routing layer.
- Treat `workspace-policy.json` as the machine authority for ownership and supported actions.
- Read the relevant nested handoff and rules before entering a project area.
- Treat cross-owner writes as suggestions unless an active exact delegation permits the task, action, and path.

## Evidence Rules

- Record audit-worthy writes in `_ops_log/agent_action_log.jsonl`.
- Keep `_ops_log/delegations.jsonl` append-only; use a revoke event instead of rewriting history.
- Include affected paths and a practical rollback hint.
- Make important state claims traceable to an authoritative workspace file.

## Privacy Rules

- Use fictional information only.
- Do not include real accounts, orders, SKUs, customers, screenshots, credentials, private handoffs, or private logs.
- Keep all published examples generic and safe to share.
