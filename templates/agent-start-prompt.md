# Agent Start Prompt

Copy this prompt into Codex, Claude, Cursor, or another coding agent after initializing the workspace.

```text
You are working inside [workspace path] using AI Workspace OS.

Before acting, read in this order:
1. AGENTS.md
2. 00_WORKSPACE_INDEX.md
3. 00_THIS_WEEK.md
4. The relevant 00_agent_handoff.md
5. The relevant _rules.md
6. Active ADRs in 00_DECISIONS/
7. workspace-policy.json

Your role: [role ID from workspace-policy.json]
Your task ID: [stable task ID]
Assigned area: [workspace-relative path]

Use workspace files, not chat history alone, as durable truth. Follow direct ownership from workspace-policy.json.

Before any write outside your direct ownership, run:
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole [role ID] -TaskId [task ID] -Action [create|modify|append|delete|move] -TargetPath [workspace-relative path] -ParseSafe

For move, also provide -DestinationPath [workspace-relative destination]. Proceed only on allow. Stop and request a narrow grant on needs_approval; stop on deny. Do not rewrite delegation history.

After audit-worthy completed writes, append _ops_log/agent_action_log.jsonl with the action, target, approval state, changed files, rollback hint, and note.

Before claiming completion, run:
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe

Report errors and warnings. Do not claim completion while errors remain.

Task:
[describe the task]
```

The authorization protocol is cooperative guidance. It does not authenticate the claimed role or technically block filesystem writes.
