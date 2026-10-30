# M0｜工程与身份基础（P0）

> 执行包标识：`skill-atlas-v1-m0`；首次创建：2026-10-29；最近更新：2026-10-30。
> 归档日期：2026-10-30；首版范围已完成。本文件保留执行与验收历史，不再承担未完成实施工作。
> 所属计划：[首版实施入口](../2026-10-29-skill-atlas-v1.md#current)；[共享执行约束](../2026-10-29-skill-atlas-v1.md#execution-rules)；[验收责任映射](../2026-10-29-skill-atlas-v1.md#coverage)。
> 稳定契约：[产品 Spec](../../../specs/2026-10-29-skill-atlas-v1.md)；[契约登记](../../../specs/skill-atlas-v1/2026-10-29-data-model-api.md#contracts)。

本文件维护所属执行叶的完成条件、当前结果及最新证据；主计划维护整体摘要与审查，目标运行门禁由 [G1–G4](2026-10-29-gates.md) 统一维护。

<a id="m0-1"></a>
- [x] M0.1：形成可检查的开发环境与工程入口清单
  - 验收关联：AC01、AC18、AC21 的前置发现，不证明产品功能。
  - 启动依赖：无；只读盘点不依赖 Q01 已解决。
  - 上下文：[技术架构](../../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md) 第 1、3、10 节，Q01/Q02/Q12。
  - 执行边界：只读本目录及本机工具版本；只写 技术架构 的环境清单、本 Task 当前入口及实际盘点报告；不安装或创建工程。
  - 完成与验证：列出实际可用/缺失工具、最低系统候选及兼容依据、测试启动方式、隔离资源、待解决选择；按现有工作区复查路径，不填虚构 scheme 或服务地址。
  - 下一步：核实工具与目录 → 明确可用组合及缺项 → 回写 Q01 和运行入口 → 更新就绪叶；这是当前唯一展开的操作步骤。
  - 当前结果：盘点通过；Swift/Xcode/Docker 可用，Go 与 PostgreSQL 通过项目工具及 Docker 建立，Q01/Q02/Q12 已明确。证据见 [工程基础报告](evidence/2026-10-29-foundation.md)。

<a id="m0-2"></a>
- [x] M0.2：建立可启动并可连测试库的 Go 服务骨架
  - 验收关联：AC01 的服务启动/健康契约。
  - 启动依赖：[M0.1](#m0-1)；决策：Q01。
  - 上下文：[技术架构](../../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md) 第 3、10 节；`GET /health` 为非业务健康入口。
  - 执行边界：`server/cmd/api/`、`server/internal/config/`、`server/internal/storage/`、基础迁移、`server/go.mod`/`go.sum`、Docker 构建与 `dev/`、`scripts/` 的本机启动工具，以及被忽略的 `.tools/`/`.runtime/`；不实现领域 CRUD。
  - 当前结果：Docker API/PostgreSQL 均健康；HTTPS 已校验证书连接成功，真实数据库迁移重放、健康 200 和不可用 503 检查通过。证据见 [工程基础报告](evidence/2026-10-29-foundation.md)。
  - 完成与验证：空测试库可迁移、服务可启动，健康响应及数据库不可用时错误清楚；运行一条实际 HTTP/测试库集成检查，登记真实启动和测试命令。

<a id="m0-3"></a>
- [x] M0.3：建立原生窗口与健康接口连接页面
  - 验收关联：AC01 的原生启动、导航和连接反馈。
  - 启动依赖：[M0.1](#m0-1)、[M0.2](#m0-2)；决策：Q01。
  - 上下文：[交互规范](../../../specs/skill-atlas-v1/2026-10-29-ux-and-visual.md) 第 2.1 节，[技术架构](../../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md) 第 3 节，[M0.2](#m0-2) 健康响应。
  - 执行边界：`macos/SkillAtlas.xcodeproj`、`macos/App/`、`macos/Core/API/` 的基础网络层及测试；不接入业务数据或身份提供方。
  - 当前结果：Xcode 原生构建、Swift 两项测试与 URLSession 实际 HTTPS 通过；辅助功能树已观察连接失败及修复后的成功状态。窗口截图接口不可用，不据此宣称视觉验收通过。证据见 [工程基础报告](evidence/2026-10-29-foundation.md)。
  - 完成与验证：实际启动原生窗口、请求 [M0.2](#m0-2) 服务并展示成功/失败；登记实际构建与 Swift 测试入口。健康连通不计作领域联通。

<a id="m0-4"></a>
- [x] M0.4：建立认证和资源归属的服务端基础
  - 验收关联：AC18 的认证身份、越权拒绝和安全日志；产出 C-AUTH。
  - 启动依赖：[M0.2](#m0-2)；决策：Q02。
  - 上下文：[产品 Spec](../../../specs/2026-10-29-skill-atlas-v1.md) 第 10 节，[技术架构](../../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md) 第 8 节，[数据与接口](../../../specs/skill-atlas-v1/2026-10-29-data-model-api.md#contracts)。
  - 执行边界：`server/internal/auth/`、认证接线、`server/contracts/auth.yaml`、认证 fixture/测试；不擅自配置真实身份服务。
  - 当前结果：真实 PostgreSQL 认证测试通过；C-AUTH 的同源输入样例被 Go/Swift 消费，密码散列、令牌摘要、过期/撤销及归属断言通过，见 [账号与事件证据](evidence/2026-10-29-auth-activity.md)。
  - 完成与验证：`/v1/me` 和通用归属检查依据已验证身份返回结果；测试未认证、失效凭据、伪造用户 ID、跨账号资源及日志脱敏。发布 C-AUTH 的实际就绪证据；目标身份服务仍归 [G2](2026-10-29-gates.md#g2)。

<a id="m0-5"></a>
- [x] M0.5：实现原生登录与安全令牌生命周期
  - 验收关联：AC18、AC19 的客户端身份与安全保存。
  - 启动依赖：[M0.3](#m0-3)、[M0.4](#m0-4)；决策：Q02。
  - 上下文：C-AUTH，[技术架构](../../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md) 第 8 节。
  - 执行边界：`macos/Features/Account/`、`macos/Core/API/Authentication/`、Keychain 适配及测试；缓存/队列退出恢复界面归 [M9.1](2026-10-29-m9-delivery.md#m9-1)。
  - 当前结果：同一原生账号控制器连接 Docker HTTPS，注册、Keychain 恢复、退出撤销、错误密码、再次登录及过期清除通过，测试会话均已退出，见 [账号与事件证据](evidence/2026-10-29-auth-activity.md)。窗口交互问题仍保留在 G2/G3，未宣称用户全流程通过。
  - 完成与验证：登录结果、过期/失败、重开后的令牌读取和安全清除符合契约，令牌不进入普通缓存/日志；受控认证测试与实际提供方验证明确区分。
