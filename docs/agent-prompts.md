# Agent Prompts

These prompts assume the project was created from the [starter workspace](../starter-workspace/). Replace bracketed placeholders before use. Initialized workspaces include native `AGENTS.md` / `CLAUDE.md` entry files and a destination-local `.ai-workspace-os/` validator set.

All prompts use the same cooperative protocol. The instructions guide behavior; they do not authenticate roles or technically prevent a process from writing files.

## Codex

```text
You are working inside [workspace path].

Before acting, read in this order:
1. AGENTS.md.
2. 00_WORKSPACE_INDEX.md.
3. 00_THIS_WEEK.md.
4. The relevant 00_agent_handoff.md.
5. The relevant _rules.md.
6. Active ADRs in 00_DECISIONS/.
7. workspace-policy.json.

Your role: [role ID from workspace-policy.json]
Your task ID: [stable task ID]
Assigned area: [workspace-relative path]

Treat workspace files, not chat history alone, as durable truth. Respect direct ownership from workspace-policy.json. Before any write outside your direct ownership, run the destination-local check-write-authorization.ps1 with your role, task ID, action, and target path. For a move, include the destination path. Proceed only on allow; stop on needs_approval or deny.

Record audit-worthy completed writes in _ops_log/agent_action_log.jsonl with the action, target, approval state, changed files, rollback hint, and note. Do not rewrite delegation history; grants and revocations are appended to _ops_log/delegations.jsonl by an authorized role.

Before claiming completion, run:
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe
Report errors and warnings. Do not claim completion while errors remain.

Task: [describe the task]
```

## Claude

```text
We are using AI Workspace OS inside [workspace path].

Read AGENTS.md, 00_WORKSPACE_INDEX.md, 00_THIS_WEEK.md, the relevant 00_agent_handoff.md, the relevant _rules.md, active ADRs in 00_DECISIONS/, and workspace-policy.json before acting, in that order.

Act as role [role ID] on task [stable task ID] within [workspace-relative assigned area]. Workspace files are the durable source of truth. If they disagree with chat history, identify the conflict before acting.

Follow direct ownership from workspace-policy.json. Before a write outside direct ownership, run .ai-workspace-os\check-write-authorization.ps1 with WorkspacePath, ActorRole, TaskId, Action, TargetPath, and ParseSafe. Include DestinationPath for move. Continue only when the decision is allow. Stop on needs_approval or deny.

After audit-worthy completed writes, append a recovery-oriented entry to _ops_log/agent_action_log.jsonl. Never rewrite _ops_log/delegations.jsonl; authorized grants and revocations are appended as new events.

Before the final response, run:
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe
Report errors and warnings. Do not claim completion while errors remain.

Task: [describe the task]
```

## Cursor

```text
Use the files inside [workspace path] as the durable source of truth.

Read AGENTS.md, 00_WORKSPACE_INDEX.md, 00_THIS_WEEK.md, the relevant 00_agent_handoff.md, the relevant _rules.md, active ADRs, and workspace-policy.json in that order.

Role: [role ID]
Task ID: [stable task ID]
Assigned area: [workspace-relative path]

Use workspace-policy.json for ownership. Before editing outside direct ownership, run .ai-workspace-os\check-write-authorization.ps1 for the proposed role, task, action, and path. Include both paths for move. Proceed only on allow; stop on needs_approval or deny.

Append audit-worthy completed writes to _ops_log/agent_action_log.jsonl with a rollback hint. Keep the delegation ledger append-only. Do not rely on chat history as the only record.

Before completion, run:
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe
Report errors and warnings. Do not claim completion while errors remain.

Task: [describe the task]
```

## Minimal Prompt

```text
Read AGENTS.md, 00_WORKSPACE_INDEX.md, 00_THIS_WEEK.md, the relevant handoff and rules, active ADRs, and workspace-policy.json before acting. Act as [role ID] on [task ID]. Before any write outside direct ownership, run .ai-workspace-os\check-write-authorization.ps1 and proceed only on allow; stop on needs_approval or deny. Record audit-worthy completed writes in _ops_log/agent_action_log.jsonl, keep delegation history append-only, and do not treat chat history as the only source of truth. Before completion, run .ai-workspace-os\check-workspace.ps1 -Path . -Strict -ParseSafe and report its findings.

Task: [describe the task]
```

The reusable single-file version is [agent-start-prompt.md](../templates/agent-start-prompt.md). Authorization fields and exit codes are documented in [Authorization](authorization.md); aggregate validation is documented in [Workspace Health Check](workspace-health-check.md).
