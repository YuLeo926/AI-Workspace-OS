# AI Workspace OS

面向长期、人类监督下 AI Agent 协作的文件优先工作区协议。英文 [README.md](README.md) 是主要说明。

它通过稳定文件说明从哪里开始、谁拥有目标、临时授权如何记录，以及重要操作如何留下可恢复证据。项目不需要安装包、服务或账号。

## 10 分钟使用流程

1. 在本仓库根目录初始化目标项目：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\init-workspace.ps1 -Destination path\to\project
Set-Location path\to\project
```

2. 阅读 `AGENTS.md`，填写 `00_WORKSPACE_INDEX.md`、`00_THIS_WEEK.md` 和 `00_agent_handoff.md`；按项目调整 `_rules.md` 与 `workspace-policy.json`，并保持 index 中的 ownership 摘要与 JSON policy 一致。

3. 使用 [Agent 启动提示词](templates/agent-start-prompt.md)。跨直接 ownership 写入前，运行目标工作区自带的授权检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-write-authorization.ps1 -WorkspacePath . -ActorRole worker -TaskId TASK-001 -Action modify -TargetPath work-area/report.md -ParseSafe
```

只有 `allow` 可以继续；`needs_approval` 需要追加范围明确、限时的 grant；`deny` 必须停止。完整规则见 [Authorization](docs/authorization.md)。

4. 重要写入完成后记录 `_ops_log/agent_action_log.jsonl`，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .ai-workspace-os\check-workspace.ps1 -Path . -Strict
```

## 核心边界

- `workspace-policy.json` 是角色、ownership、动作、protected path 与 handoff 设置的机器事实来源。
- `_ops_log/delegations.jsonl` 只记录限定任务、路径、动作、时间和 policy revision 的 grant/revoke；授权不能转授权。
- `00_agent_handoff.md` 是会话启动说明，不是流水日志，并包含更新时间与复核期限。
- `_rules.md` 保存稳定约束；本周事项写入 `00_THIS_WEEK.md`；长期决策写 ADR。
- workspace 文件是持久事实来源，不能只依赖聊天历史。
- 这是协作式授权协议，不验证角色身份、不拦截文件系统写入，也不是安全沙箱。

## 开发与安全

提交前运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-script-tests.ps1
```

测试和示例必须使用合成数据。不要提交真实账号、订单、SKU、客户、截图、token、私有 handoff、真实 ops log 或内部任务标识。贡献范围见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全说明见 [SECURITY.md](SECURITY.md)，健康检查见 [Workspace Health Check](docs/workspace-health-check.md)。
