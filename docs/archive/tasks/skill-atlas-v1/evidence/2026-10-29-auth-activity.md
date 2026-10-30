# 账号与事件基础验证

> 首次创建：2026-10-29；最近更新：2026-10-30。任务：M0.4、M0.5 局部、M8.1、M8.2；关联 AC18、AC19、AC16。

## 已通过的验证

- `python3 scripts/local.py test ./internal/httpapi`：真实 PostgreSQL 隔离 Schema 中通过认证、健康与事件集成测试。
- C-AUTH：注册/重复账号、登录错误、身份字段拒绝、两个账号的身份和归属检查、30 天会话、撤销重放、失效令牌拒绝、Argon2id 及 SHA-256 存储断言。未记录密码、令牌或连接串。
- `swift test --package-path macos`：4 项通过；包括同源认证 fixture、真实 Keychain 独立测试命名空间的读取/替换/删除。
- C-ACTIVITY：事务内追加，回滚后不存在事件，重复来源约束，时间倒序和游标续页、技能筛选、跨账号空结果及无效分页参数拒绝。
- `python3 scripts/build-macos.py`：原生登录页编译通过；应用内 NSView 实际渲染输出 `.runtime/native-account.png`，人工检查布局。该检查图不含账号或密码。

## 验证边界

M0.5 使用应用同一 AccountController 的原生诊断程序已验证完整令牌生命周期；窗口输入/点击及真实进程重启后的全流程仍待 G2。C-AUTH 本地通过不替代 G2。当前 native Accessibility 的窗口引用出现循环，正在修复/补充目标交互检查；主窗口已由 AppKit 承载 SwiftUI。客户端计时事件的真实引用与重放归 M8.2b；尚未实现的领域生产者不因事件基础通过而完成。

## 原生账号控制器实连（2026-10-29）

编译 `macos/Diagnostics/AccountLifecycle.swift` 与实际 API/Keychain/AccountController 源文件后运行 `.runtime/account-lifecycle .runtime`：通过注册、Keychain 新实例恢复、退出后服务端拒绝旧令牌、错误密码反馈、再次登录身份一致以及本地过期清除。Keychain 使用独立测试服务名并清除；测试会话全部撤销。仅保留无业务数据的验收账号，其 ID 在 `.runtime/acceptance/account-*.json`，不保存密码或令牌。
