# 事件上报与尝试契约验证

> 首次创建：2026-10-29；最近更新：2026-10-30。

> 创建及更新：2026-10-29；任务：M8.2b、M5.1。

M8.2b 使用 `server/internal/httpapi/client_activity_test.go` 与真实隔离 PostgreSQL Schema，执行 `python3 scripts/local.py test ./internal/httpapi` 通过。覆盖四次并发重放、同 ID 内容冲突、客户端伪造服务器事件、跨账号技能/会话、事件先于最终会话及最终会话先于事件、未知任务，以及事件不影响 XP。生命周期和最终会话按同一会话锁校验技能/模式一致。

C-ATTEMPT 位于 `server/contracts/attempt.yaml`。稳定命令 ID、结算编号与版本、失败零奖励、奖励快照、重试和撤销边界、有效统计口径已固定。`go test ./internal/task/...` 的共享契约及原任务契约通过。服务端尝试事务与原生界面仍需各自验证。

原生操作当前受 macOS 锁屏阻挡：电脑控制工具明确返回无法自动解锁；已请用户手动解锁。继续执行后端及非桌面检查，G1–G4 不据此勾选。
