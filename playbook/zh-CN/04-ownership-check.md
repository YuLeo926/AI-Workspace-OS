# Ownership Check

ownership check 用来防止 agent 跨 owner 写入。

最小检查：

1. 确认当前角色。
2. 确认目标文件。
3. 确认 owner。
4. 判断是直接写入、授权写入，还是建议。
5. 确认授权是否明确。
6. 判断是否需要 ops log。

如果 owner 不清楚、授权不明确、涉及私有数据、超出边界或无法回滚，就停下来询问。
