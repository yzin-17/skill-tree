# Skill Atlas｜macOS 原生技能树项目

> 首次创建：2026-10-29；最近更新：2026-10-31；文档版本：v1.0。
> 范围：首版实现、运行说明与验收。交付范围与审查结论见 [交付记录](docs/archive/tasks/2026-10-29-skill-atlas-v1.md#current)。

这是一个以**手动创建**为核心的个人成长工具：手动组织技能树、创建任务、按次专注、结算成功或失败，使用经验、等级、阶段进阶和称号可视化成长。

## 关键规则

- **有效专注 1 分钟 = 1 XP**；每 **60 XP 升 1 级**（固定升级成本）。
- 任务**成功**时发放用户自定义的技能等级奖励，`+N 级 = +60N XP`；**失败不发完成奖励**，已积累的专注 XP 保留。
- **一个任务可关联多个技能，也可绑定多次专注**；每次专注选择一个主技能。专注记录重新绑定任务不会重复发放 XP。
- 任务由用户手动确认成功、失败或取消；支持失败后重试并保存每次尝试的结果；成功率统计按尝试次数计算。
- 技能树支持**父子层级、前置依赖、跨树前置和跨树普通关联**。节点详情使用**右侧 Drawer**。
- 技能图标由用户在**固定图标库中手动选择**，不随机生成；成长阶段和称号强调游戏化呈现。
- **不做周期待办、不做模板、不默认自动生成任务**。

## 技术路线

- 客户端首发：**macOS 原生 Swift + SwiftUI**，使用 AppKit `NSStatusItem`、UserNotifications 和 Swift Charts。
- 本地：SwiftData（SQLite 文件保存计时现场、账号分区缓存和待上传队列）。
- 后端：**Go 单体 API + PostgreSQL**，集中计算经验、等级、任务尝试结果、成功率、成长阶段与称号。
- 网络：URLSession + JSON API；离线计时，联网同步。Go 自管邮箱/密码账号，默认手动登录，令牌仅保存在本次内存；选择“记住登录”时使用 Keychain。
- 未来：iOS/iPadOS 尽量共享 Swift 代码；Android/Windows 若需要则各写原生客户端，共享后端 API 和业务规则。

## 本机运行

```sh
python3 scripts/local.py up
python3 scripts/local.py health
python3 scripts/install-macos.py
```

后端地址为 `https://localhost:8447`；数据库使用独立 Docker 持久卷 `skillatlas-postgres-v1`。安装脚本生成 Release 应用并安装到 `~/Applications/Skill Atlas.app`，更新前保留旧应用副本。详见 [本机运行与安装](docs/guides/2026-10-29-local-operation.md)。

当前已验收版本为 0.1.0（构建 26），默认 Go/PostgreSQL 在 Docker 中运行，支持手动配置 HTTPS 后端地址。星图的范围选择与搜索靠左排列，新建技能集中在标题行；任务图钉可直接切换置顶；成长日志默认打开月历，按天查看有效完成、专注和原始记录；默认账号密码登录，记住登录为可选。日常操作见 [使用说明](docs/guides/2026-10-29-user-guide.md)，本次结果见[图标验收](docs/reviews/2026-10-31-app-icon.md)，后端配置见[后端地址验收](docs/tasks/backend-address/evidence/2026-10-30-implementation.md)，界面精简见[界面精简验收](docs/reviews/2026-10-30-ui-labels.md)，星图布局见[星图工具栏验收](docs/reviews/2026-10-30-skill-toolbar.md)，既有结果见[图钉交互验收](docs/reviews/2026-10-30-task-pin.md)、[月历原生验收](docs/tasks/activity-calendar/evidence/2026-10-30-implementation.md)与[登录修复验收](docs/tasks/optional-login/evidence/2026-10-30-implementation.md)。首版、8 组界面及成长路径的证据保留于[交付记录](docs/archive/tasks/2026-10-29-skill-atlas-v1.md#current)、[界面验收记录](docs/tasks/ui-remediation/evidence/2026-10-30-native-acceptance.md)和[成长路径验收](docs/tasks/growth-paths/evidence/2026-10-30-implementation.md)。

全界面说明文字补充清理已完成，构建 16 已通过逐页原生复验；结果见 [已完成文案清理任务](docs/archive/tasks/2026-10-30-ui-copy-cleanup.md)。

## 文档导航

| 文档 | 维护内容 |
| --- | --- |
| [GitHub 构建与发布](docs/guides/2026-10-31-github-release.md) | CI 触发、通用安装包、版本标签与 Release；[当前任务](docs/tasks/2026-10-31-github-release.md) |
| [产品 Spec](docs/specs/2026-10-29-skill-atlas-v1.md) | 目标、范围、业务规则、稳定 AC、未决问题与测试策略；首版稳定契约入口 |
| [界面修复 Spec](docs/specs/2026-10-30-ui-remediation.md) | 筛选、操作层级、密度、成长表达、成果与可访问性的当前契约 |
| [成长日志月历 Spec](docs/specs/2026-10-30-activity-calendar.md) | 月历、日期详情与统计口径；[已完成任务](docs/archive/tasks/2026-10-30-activity-calendar.md) |
| [后端地址 Spec](docs/specs/2026-10-30-backend-address.md) | 地址保存、检查、切换及后端范围隔离；[已完成任务](docs/archive/tasks/2026-10-30-backend-address.md) |
| [手动登录 Spec](docs/specs/2026-10-30-optional-login.md) | 默认手动登录与可选记住登录；[已完成任务](docs/archive/tasks/2026-10-30-optional-login.md) |
| [成长路径 Spec](docs/specs/2026-10-30-growth-paths.md) | 成就树、阶段术语、右侧详情及简洁文案；[已完成任务](docs/archive/tasks/2026-10-30-growth-paths.md) |
| [界面修复记录](docs/archive/tasks/2026-10-30-ui-remediation.md) | 8 组问题的实施、原生验收门禁及最终审查 |
| [页面与交互设计](docs/specs/skill-atlas-v1/2026-10-29-ux-and-visual.md) | Spec 的交互与视觉附件 |
| [原生架构与同步](docs/specs/skill-atlas-v1/2026-10-29-technical-architecture.md) | Spec 的技术边界、运行环境要求与源码组织 |
| [数据模型与接口契约](docs/specs/skill-atlas-v1/2026-10-29-data-model-api.md) | Spec 的数据/API 附件；契约资产、字段和就绪条件 |
| [交付记录](docs/archive/tasks/2026-10-29-skill-atlas-v1.md) | 首版已完成执行叶、依赖、门禁与最终审查 |
| [使用说明](docs/guides/2026-10-29-user-guide.md) | 安装版主要操作、同步、错误处理与导出 |
| [验收场景](docs/specs/skill-atlas-v1/2026-10-29-acceptance.md) | 可复现输入、操作、预期及 AC 对应关系；不维护另一份完成状态 |
| [决策依据](docs/specs/skill-atlas-v1/2026-10-29-decisions.md) | 需求来源、已确认选择及决策维护规则；未决问题回链 Spec |

稳定产品规格及附件放在 `docs/specs/`；已完成首版任务及支持文件归档在 `docs/archive/tasks/`，后续新任务使用 `docs/tasks/`。规划文件名使用首次创建日期前缀，页头维护首次创建和最近更新日期；后续修订保持首次创建日期与文件名稳定。任务主入口维护当前摘要、依赖入口、AC 映射和审查，各执行包原位维护所属叶/门禁，不重复维护完成清单。

本次实施过程在 `docs/archive/tasks/skill-atlas-v1/records/` 和 `docs/archive/tasks/skill-atlas-v1/evidence/` 保留带日期的实施记录与证据。未来平台等探索性建议保留在 Spec 的可选范围。

## 首版范围

首版打通「新建技能树与技能 → 创建任务 → 绑定多次专注 → XP/等级变化 → 任务成败结算 → 成功率统计 → 星图技能树与右侧抽屉 → 本地记录上传到 Go 后端」。称号和成长阶段先采用**少量可配置条件**，不做复杂规则引擎。

公式、身份方案、计时恢复和分发方式已按用户选择固定，见 [Spec 实施决定](docs/specs/2026-10-29-skill-atlas-v1.md#questions)。契约与实际验证证据在 Task 中逐项关联。身份隔离与真实后端联通在主链路早期验证，目标 macOS、同步和分发验收分别保留门禁。

> 本地测试、原生控制器、实际界面、系统生命周期及安装运行的证据层级分别记录，最终本机交付已通过。
