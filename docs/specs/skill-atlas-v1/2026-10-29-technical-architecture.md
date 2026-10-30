# 技术架构与运行环境

> 文档标识：`skill-atlas-v1-architecture`；首次创建：2026-10-29；最近更新：2026-10-31。

> 归属：[产品 Spec](../2026-10-29-skill-atlas-v1.md) 的技术附件；任务状态见 [实施计划](../../archive/tasks/2026-10-29-skill-atlas-v1.md#current)。技术组合与系统版本按 Q01 固定；实际环境、命令和边界见第 3.1 节及 [运行说明](../../guides/2026-10-29-local-operation.md)。

## 1. 技术选型

| 层级 | 方案 | 说明 |
| --- | --- | --- |
| macOS App | **Swift / SwiftUI** | 原生主界面、技能树、表单与交互 |
| 系统集成 | **AppKit NSStatusItem + UserNotifications** | 按需处理窗口、菜单栏、通知与系统生命周期 |
| 图表/图形 | **Swift Charts + SwiftUI Canvas/Path** | 统计图表、技能连线；节点仍是交互视图 |
| 本地数据 | **SwiftData** | 计时状态、账号分区缓存、待上传记录 |
| 网络 | **URLSession + Codable** | 调用 API；明确超时、错误与重试 |
| 云端服务 | **Go（单体、按领域分包）** | 账号数据隔离、任务尝试、XP 结算、职业/称号判定 |
| 云端持久化 | **PostgreSQL** | 共享数据、唯一约束、事务及统计 |
| 账号身份 | Go 自管邮箱/密码账号 | Argon2id 密码散列、不透明会话令牌、默认仅内存及可选 Keychain；数据库凭据只在服务端 |

**明确不使用 Electron、Tauri 或其他跨端框架。** 首发 macOS；以后 iOS/iPadOS 复用部分 SwiftUI、模型和网络层；Android/Windows 需独立原生客户端。

## 2. 总体结构

```text
┌────────────────────────────── macOS App ──────────────────────────────┐
│ SwiftUI / AppKit                                                        │
│   工作台｜技能星图 + Drawer｜任务｜专注｜成就殿堂｜日志统计               │
│                      │                                                │
│  ViewModels / Services（用户操作、会话状态、请求状态）                    │
│          ├── LocalFocusEngine（单调时间/暂停段、计时现场、通知）          │
│          ├── LocalStore（SwiftData，缓存、待同步队列）                   │
│          └── APIClient / SyncService（URLSession、重试、幂等 ID）         │
└───────────────────────────┬───────────────────────────────────────────┘
                            │ HTTPS / JSON
┌───────────────────────────▼───────────────────────────────────────────┐
│ Go API（一个服务，按领域划分）                                           │
│ Auth │ SkillTree │ Task/Attempt │ Focus │ XP │ Profession/Title │ Stats │
│                  Postgres事务、唯一约束、事件/经验账本                    │
└───────────────────────────┬───────────────────────────────────────────┘
                            │
                      PostgreSQL
```

## 3. 源码组织

```text
skill-tree/               # 项目根
  macos/
    SkillAtlas.xcodeproj
    App/                  # App 入口、NSWindow、NSStatusItem、通知
    Features/
      Dashboard/
      SkillTree/          # 布局算法、节点、连线、右侧 Drawer、图标选择
      Tasks/
      Focus/
      Achievements/
      Activity/
    Core/
      Graph/
      API/
      Persistence/
      FocusEngine/
      Sync/
  server/
    cmd/api/
    internal/
      auth/
      skill/
      task/
      focus/
      growth/
      achievement/
      activity/
      stats/
      export/
      storage/
    migrations/
  docs/                   # 本文档目录
```

共享 Codable 模型在 `macos/Core/API/`；纯计时和布局规则在 Core；用户操作控制器及页面在 Features。Xcode 工程由 `scripts/build-macos.py` 按实际源码生成。

### 3.1 已核实的开发基线

2026-10-29 已核实 macOS 27.0、Xcode 27.1、Swift 6.4、macOS SDK 27.0 与 Docker 29.9.2。最低客户端目标为 macOS 14；后端采用 Go 1.27.3 和 PostgreSQL 17。Go 开发工具安装在 `.tools/go/`，运行服务和数据库由独立 Docker Compose 项目管理。工具版本证据见 [工程基础报告](../../archive/tasks/skill-atlas-v1/evidence/2026-10-29-foundation.md)。

本机 HTTPS 使用应用专属证书固定校验；不更改系统证书信任。数据库及 API 仅发布到本机回环地址，数据写入专属持久卷。密码、私钥与本地配置保存到被忽略的 `.runtime/`，不进入文档或版本控制。

客户端支持手动保存 HTTPS 后端来源，默认值来自应用包，自定义来源可使用系统信任证书。账号、钥匙串服务名、本机数据库、缓存及队列按来源隔离；切换时暂停保存旧专注并重建运行态，默认来源保持原目录兼容。详细契约见[后端地址规格](../2026-10-30-backend-address.md)。

## 4. 计时设计

- **界面刷新和实际计时解耦**：界面定时更新数字，真实时长由本机计时服务记录的时间锚点及有效运行区间决定。
- 记录 `started_at`、`last_resumed_at`、`effective_seconds_before_resume`、`paused_at`、`target_seconds`，在暂停、继续、结束时持久化。
- 运行中使用单调时钟计算经过时长；重启后结合已持久化时间和恢复策略恢复，避免单纯依赖 `Timer` 触发次数。
- 对休眠：首版休眠时暂停有效专注，恢复时提示继续；不要把电脑睡眠时间计入 XP。
- 菜单栏与主窗口共享同一个 FocusEngine，不各维护一套倒计时。
- 备注编辑随现场持久化，自动到点、菜单栏结束和重开恢复沿用已保存备注；输入按服务端 Unicode 字符上限校验，存储失败保留原值。
- 会话创建时生成稳定 UUID 并立即持久化；结束时将同一 ID 的最终记录放入待上传队列，恢复和重试不换 ID。客户端可以立刻预览 XP，但服务端返回权威结算。
- **一个任务可以有多次专注**；补充任务绑定是更新关联信息，不执行第二次经验结算。

## 5. 数据与同步策略（首版）

### 5.1 范围控制

- **在线进行**：技能树/技能/任务/关系/职业/称号的增删改；客户端收到服务端返回值后更新缓存。
- **离线保证**：已开始的专注可以暂停、继续、结束并本地保存；恢复网络后自动或手动补传；已缓存页面允许只读查看。
- **不做**：首版全面离线编辑、多个端同时编辑复杂冲突合并、服务端实时推送。

### 5.2 幂等与一致性

- `focus_session.id` 在创建会话时确定，重试上传使用相同 ID；服务端建立唯一约束，同一会话最多结算一次。
- `task_attempt.id` 在用户结算时确定；同一次结算请求重试只返回已保存结果，不重复加 XP。
- 技能的时间经验按**所有有效会话的累计秒数**计算，跨会话余秒不会丢失；不要每个会话独立向下取整后相加。
- 每次结算和 XP 记录在同一数据库事务中写入。
- UI 永远区分“本地已保存/等待同步/云端已确认/同步失败可重试”。
- 任务/技能编辑使用 `version` 乐观并发字段，旧版本写入提示刷新，不静默覆盖。

### 5.3 同步流程

```text
开始专注 → 本地保存现场
  ↓
暂停/继续/结束 → 更新本地现场
  ↓
结束固化 final session（沿用开始时已持久化的 UUID）
  ↓ 有网
POST /v1/focus-sessions（会话 ID 为幂等键）
  ↓
Go 校验账号归属 → Postgres 事务保存 → 计算技能累计时长/XP
  ↓
返回原结算快照 → 标记会话已确认 → GET /v1/progress 刷新当前进度
```

关联到任务时：`PATCH /v1/focus-sessions/{id}/task`，只更新会话与任务的链接；**不产生新的 XP 事件**。

## 6. XP 与成长计算职责

- **Go 是权威**：根据原始计时记录、任务奖励记录和补偿事件计算 XP/等级；任务成功率按尝试记录计算。
- **客户端是展示层**：以相同公式做即时进度预估，上传完成后以服务端结果更新。
- 表示法：`time_xp = floor(total_focus_seconds / 60)`；`bonus_xp = sum(success_awards) - sum(reversals)`；`level = 1 + floor((time_xp + bonus_xp)/60)`。
- 保留 `growth_events` 流水，注明来源 ID、技能 ID、经验变化和撤销关联，以便审计和日志展示；累计秒数与奖励事件是最终事实来源。

## 7. 后端边界与不做过度设计

- 一个 Go 服务即可，不拆微服务，不提前引入消息队列和复杂 Workflow。
- 使用 PostgreSQL 事务和唯一键满足首版结算要求，不额外开发分布式锁系统。
- 条件引擎先支持四类简单可配置条件；职业与称号解锁在相关事件结算后检查，保存配置时同步判定。
- API 按实体组织，通过 HTTPS 传输 JSON；计时长连接不强制使用 WebSocket/SSE。
- 账号支持一个用户的数据隔离；后端验证 Auth token，数据库仅服务端可访问。

身份校验、资源归属和事件存储是首个领域写入的启动前置，由 [M0.4](../../archive/tasks/skill-atlas-v1/2026-10-29-m0-foundation.md#m0-4)、[M8.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-1)/[M8.2](../../archive/tasks/skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-2) 建立；不等到打包时再补。首次真实语义联通由 [I1](../../archive/tasks/skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1) 使用实际 HTTP、Go 处理器和 PostgreSQL 执行“建树/技能/任务 → 上传 20 秒和 50 秒 → 查询 1 XP → 重放不重复 → 冲突拒绝”，早于星图、职业和完整用户闭环。

## 8. 安全与隐私基本项

- 账号令牌默认仅存于进程内存；选择记住登录才使用苹果 Keychain。普通文件及日志不保存令牌，具体生命周期见[手动登录规格](../2026-10-30-optional-login.md)。
- 全部 API 从身份凭据确定用户，不接受客户端传来的任意 `user_id` 作为授权依据。
- 传输使用 HTTPS；本地缓存避免记录敏感令牌；用户可导出数据。
- 若用户手动补录专注，记录来源标记；不必首版引入夸张的反作弊机制，个人工具优先可用。

## 9. 原生平台扩展

- iOS：复用数据模型、APIClient、条件展示规则和部分 SwiftUI；重做窗口导航、后台行为和专注提醒。
- Android/Windows：另写原生客户端，以 Go API 和数据协议共享账号及成长数据。
- 数据库不要存 SF Symbols 的平台专属名称；使用跨端语义 `icon_key` 与平台渲染映射。

## 10. 环境建立与证据要求

- [M0.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m0-foundation.md#m0-1) 只读核实本机 macOS、Xcode/Swift、Go、PostgreSQL 可用性以及建议目录是否适用；确定最低系统版本、构建目标、测试入口与端口/测试库隔离办法。不得把本文建议当作工具已安装的证据。
- [M0.2](../../archive/tasks/skill-atlas-v1/2026-10-29-m0-foundation.md#m0-2)/[M0.3](../../archive/tasks/skill-atlas-v1/2026-10-29-m0-foundation.md#m0-3) 创建工程后，分别登记实际可用的服务启动、迁移、Go 定向测试、Xcode 构建和 Swift 测试命令。实际 scheme 为 `SkillAtlas`；运行入口见 [本机说明](../../guides/2026-10-29-local-operation.md)，证据单独记录。
- 契约测试使用同一份 Schema/权威 fixture；客户端模拟响应不能自行发明第二套 API。契约资产的位置及就绪条件见 [数据与接口](2026-10-29-data-model-api.md#contracts)。
- [G1](../../archive/tasks/skill-atlas-v1/2026-10-29-gates.md#g1) 需要原生 macOS 的窗口、菜单栏、通知、睡眠及退出/恢复操作证据；[G2](../../archive/tasks/skill-atlas-v1/2026-10-29-gates.md#g2) 需要已标识版本的目标服务、HTTPS、账号和迁移状态；[G4](../../archive/tasks/skill-atlas-v1/2026-10-29-gates.md#g4) 根据选定分发渠道验证产物。
- 外部环境未具备时只阻塞相关门禁。现有数据不得因建立测试环境被删除，签名、部署和发布仅按当时已授权范围处理。
