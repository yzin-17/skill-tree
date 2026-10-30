# 原生同步与任务请求保存证据

> 首次创建：2026-10-29；最近更新：2026-10-30。

## 验证范围

对应 M4.4、M8.3、M5.6 的同步和请求保存部分。运行于本机 macOS、Swift 6.4、SwiftData 与 Docker HTTPS 后端。M8.3 的事件同步断言通过；界面及实际系统计时门禁仍未通过。

## 实际结果

- `FocusSyncTests` 3 项通过：成功响应丢失后的同 ID 重传、切换账号时停止应用旧结果、409/500/401 分类处理和账号缓存隔离。
- `Diagnostics/SyncRuntime.swift` 使用真实 URLSession、证书固定、SwiftData SQLite 和 Docker API；受控注入时钟产生两个账号的 70 秒/60 秒记录。分别丢弃事件成功响应和会话成功响应，重开数据库后重试，服务端仍仅有一次对应事实。四种生命周期事件各一次，当前账号 1 XP，第二账号队列在切换前未上传。
- `TaskCommandPersistenceTests` 2 项通过：不确定结果重启后仍保留原始请求与 ID；同 ID 内容冲突、跨账号访问被拒绝；落盘失败回滚；永久拒绝记录保留，下一次明确操作可以创建新请求。
- `TaskContractTests`、`FocusSyncTests`、`FocusPersistenceTests`、`FocusLifecycleTests` 共 9 项通过。
- 原生 Debug 应用于 07:31 构建成功，包含任务成功/失败/重试/撤销界面、专注历史、补录、菜单栏与系统通知接线。

## 证据位置与边界

原始结果位于 `.runtime/acceptance/native-sync-runtime.json`、`.runtime/logs/native-sync-runtime.log`、`.runtime/logs/swift-task-commands.log` 和 `.runtime/logs/macos-build.log`。诊断账号仅用于验证，测试令牌已撤销；凭据未写入报告。

注入时钟不证明实际经过时间，编译也不证明鼠标、菜单栏、通知或睡眠行为。该阶段电脑控制工具返回 Mac 已锁定；后续界面与目标运行结果见 [原生交互记录](2026-10-29-native-ui.md)，门禁状态仅在 Task 维护。
