# 文件优先记忆

AI agent 可以记住当前会话，但长期工作需要把关键上下文沉淀到文件里。

文件优先记忆意味着：工作区文件是更稳定的事实来源。

- `00_WORKSPACE_INDEX.md` 是地图。
- `00_THIS_WEEK.md` 是本周注意力锚点。
- `00_agent_handoff.md` 用来启动新会话。
- `_rules.md` 保存稳定规则。
- ADR 保存长期决策。
- `_ops_log/agent_action_log.jsonl` 保存需要审计的动作。

实践原则：当聊天记录和工作区文件冲突时，优先相信工作区文件；如果冲突会影响结果，先问清楚。
