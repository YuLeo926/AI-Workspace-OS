# Rules

Rules are stable constraints and judgment rules. Put temporary attention in `00_THIS_WEEK.md` and long-lived decisions in an ADR.

## File-First Rules

1. Read the workspace index and weekly priorities before acting.
2. Use relevant handoffs, rules, and ADRs as the durable source of truth.
3. Keep handoff files concise and current rather than chronological.
4. Do not treat chat history as the only record of workspace state.

## Ownership Rules

- Confirm the current role and owned paths before writing.
- Treat `workspace-policy.json` as the machine authority for roles, actions, ownership, and protected paths.
- Write only inside the current ownership boundary unless an active exact delegation allows the task, action, and path.
- Treat a policy revision change as invalidating active grants from older revisions.
- When ownership is unclear, propose a change instead of editing directly.

## Evidence Rules

- Record audit-worthy writes in `_ops_log/agent_action_log.jsonl`.
- Append grants and revocations to `_ops_log/delegations.jsonl`; do not rewrite delegation history.
- Include affected paths and a practical rollback hint.
- Cite the workspace file that supports any claim affecting future work.

## Privacy Rules

- Do not add real accounts, orders, SKUs, customers, screenshots, tokens, credentials, private handoffs, or private logs.
- Use synthetic or generic content in shared examples.
- Redact operational details before publishing workspace material.

## Decision Rules

- Use ADRs for decisions that should not be repeatedly reopened.
- Record assumptions and revisit conditions for decisions that may expire.
- Prefer reversible changes when confidence is low.
