# File-First Memory

AI agents can remember chat context for a session, but long-running work needs durable memory outside the chat.

File-first memory means the workspace files are the source of truth:

- `00_WORKSPACE_INDEX.md` maps the workspace.
- `00_THIS_WEEK.md` anchors current priorities.
- `00_agent_handoff.md` bootstraps a new session.
- `_rules.md` stores durable judgment rules.
- ADRs record decisions.
- `_ops_log/agent_action_log.jsonl` records audit-worthy actions.

## Practice

Start each substantial session by reading the index, this week file, relevant handoff, rules, and ADRs.

When chat history and workspace files disagree, treat the workspace as the durable record and ask for clarification if the conflict matters.

## Anti-Pattern

Do not make the latest chat message the full priority system. It may be urgent, but it is not necessarily complete.
