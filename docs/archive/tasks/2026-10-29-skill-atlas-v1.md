# Skill Atlas 首版实施计划

> Task 标识：`skill-atlas-v1`；首次创建：2026-10-29；最近更新：2026-10-30。
> 归档日期：2026-10-30；首版范围已完成。本文件保留执行与验收历史，不再承担未完成实施工作。

对应 Spec：[skill-atlas-v1](../../specs/2026-10-29-skill-atlas-v1.md)；配套入口：[交互](../../specs/skill-atlas-v1/2026-10-29-ux-and-visual.md)、[架构](../../specs/skill-atlas-v1/2026-10-29-technical-architecture.md)、[数据/API](../../specs/skill-atlas-v1/2026-10-29-data-model-api.md)、[验收场景](../../specs/skill-atlas-v1/2026-10-29-acceptance.md)。

<a id="current"></a>
## 当前执行摘要

> 状态核对：2026-10-29。用户已授权实施全部首版任务，选择推荐业务规则、自管账号、本机安装以及 Docker 后端；后续实现细节直接采用推荐做法。
> 当前结论：首版本机交付已完成，全部执行叶、I1、G1–G4 与最终一致性 Review 通过。安装版本 0.1.0（构建 10），Docker API/PostgreSQL 健康；最终 135 条原生导出与另一登录会话一致。详见 [最终审查](skill-atlas-v1/evidence/2026-10-29-final-review.md) 与 [使用说明](../../guides/2026-10-29-user-guide.md)。
> 现场与证据：[工程基础报告](skill-atlas-v1/evidence/2026-10-29-foundation.md)、[实施记录](skill-atlas-v1/records/2026-10-29-implementation.md)。工作区未初始化 Git；保留文件和数据，不创建提交或进行公网发布。

M0–M9 为执行包分组；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1) 位于 M4，[G1](skill-atlas-v1/2026-10-29-gates.md#g1)–[G4](skill-atlas-v1/2026-10-29-gates.md#g4) 位于门禁文件。叶、AC 和场景编号保持稳定。主入口索引不设置重复复选框，执行叶只在所属文件维护完成状态。

<a id="execution-rules"></a>
## 共享执行约束

- **状态归属**：本文件是当前计划的统一入口；各执行包是其组成部分，并原位维护所属叶/门禁。除非叶中另有实际结果，所有未勾选叶均为未实施；已通过的证据按实际输入版本复用。完成后同步更新主入口摘要、所属执行包的叶结果及最新证据链接；主入口不复制子文件的完整状态表。
- **范围与问题**：每叶继承 Spec 的非目标、身份归属、幂等和历史保留约束。启动依赖是实际前置；决策栏的 Q 必须已经解决并回写 Spec。新的产品选择改变契约时，先重排受影响叶，不假装原计划仍适用。
- **契约前沿**：客户端实现可依赖已经验证的 C-* 与已经编译的共享模型/控制器接口；被引用 UI 叶的视觉与交互验收继续由其自身及对应 G 门禁负责。实现接续不等于把该 UI 叶勾选完成。`C-*` 的负责人及就绪标准在 [数据与接口 第 7 节](../../specs/skill-atlas-v1/2026-10-29-data-model-api.md#contracts)。有共同 Schema、权威 fixture 和通过的契约检查后，客户端才可先于真实生产者实施；本地模拟通过不等于 [G1](skill-atlas-v1/2026-10-29-gates.md#g1)/[G2](skill-atlas-v1/2026-10-29-gates.md#g2)/[G3](skill-atlas-v1/2026-10-29-gates.md#g3) 通过。
- **计划路径**：下文路径相对项目根，为各叶负责的写集，实际存在情况以源码及证据为准。[M0.1](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-1) 核实后同步修订；每叶可写所列模块及其定向测试，不能顺带修改其他模块或共享契约。必要迁移按叶分文件；共享模块的新接口先由其责任叶确认。
- **共用记录**：实际实施批次写入 `docs/tasks/skill-atlas-v1/records/`，验证事实写入 `docs/tasks/skill-atlas-v1/evidence/`；记录日期、任务/AC、输入版本、实际写集/命令、结果、失败修正和边界。任务主入口及执行包只保留各自负责的最新结论与链接。
- **运行入口**：[M0.1](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-1)–[M0.3](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-3) 建立并验证实际命令后登记到 技术架构 与证据。其余叶下列“验证”是必须执行的过程，不是已运行的命令或结果。
- **默认停止条件**：自身断言与检查通过即交接；缺少决策、契约、环境/授权或写集无法容纳剩余工作时停在该叶、记录具体缺口并重拆，不扩大任务。主执行者继续其他已就绪叶。
- **资源与授权**：保留已有改动和数据；测试库、端口、缓存和原生测试配置隔离。默认顺序维护共享 Task；若另有并行授权，派发前明确写集、资源及集成负责人。本文件不要求固定模型或子代理。

<a id="task-index"></a>
## 执行包索引

启动条件以每个叶的依赖和 Spec 问题为准，编号不表示串行顺序。[M8.1](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-1)/[M8.2](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-2) 为首个领域写入提供事件基础；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1) 在早期验证真实后端语义链路。

| 分组 | 执行包 | 主要结果 |
| --- | --- | --- |
| M0 | [工程与身份基础（P0）](skill-atlas-v1/2026-10-29-m0-foundation.md) | 对应分组的执行叶、边界与本地验证 |
| M1 | [手动技能树与技能（P0）](skill-atlas-v1/2026-10-29-m1-skills.md) | 对应分组的执行叶、边界与本地验证 |
| M2 | [任务与多技能绑定（P0）](skill-atlas-v1/2026-10-29-m2-tasks.md) | 对应分组的执行叶、边界与本地验证 |
| M3 | [本地计时与原生生命周期（P0）](skill-atlas-v1/2026-10-29-m3-local-focus.md) | 对应分组的执行叶、边界与本地验证 |
| M4 | [上传、时间 XP 与会话历史（P0）](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md) | 对应分组的执行叶、边界与本地验证 |
| M5 | [任务尝试、奖励与补偿（P0）](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md) | 对应分组的执行叶、边界与本地验证 |
| M6 | [技能关系、星图与右侧详情（P0）](skill-atlas-v1/2026-10-29-m6-skill-graph.md) | 对应分组的执行叶、边界与本地验证 |
| M7 | [职业转职与称号（P1，首版必需）](skill-atlas-v1/2026-10-29-m7-achievements.md) | 对应分组的执行叶、边界与本地验证 |
| M8 | [事件、统计与工作台（P0 基础，P1 视觉精修）](skill-atlas-v1/2026-10-29-m8-activity-statistics.md) | 对应分组的执行叶、边界与本地验证 |
| M9 | [账号恢复、数据交付与分发（P0）](skill-atlas-v1/2026-10-29-m9-delivery.md) | 对应分组的执行叶、边界与本地验证 |
| G | [目标运行与交付门禁](skill-atlas-v1/2026-10-29-gates.md) | 原生、目标账号、完整用户闭环与所选分发渠道门禁 |

<a id="coverage"></a>
## 验收责任映射

表中列出实现及验证责任，不维护重复状态。每叶只证明自身“验收关联”里的断言；共享门禁的当前结果只记录在该门禁，最终 Review 不承接未实现的 AC。

| AC / 断言分工 | 实现责任 | 验证责任与场景 |
| --- | --- | --- |
| AC01 / 服务与原生基础；首页入口 | [M0.2](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-2)/[M0.3](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-3)；[M8.8](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-8) | 各叶本地检查；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、E01 |
| AC02 / 树；技能层级；管理交互 | [M1.1](skill-atlas-v1/2026-10-29-m1-skills.md#m1-1)/[M1.2](skill-atlas-v1/2026-10-29-m1-skills.md#m1-2)；[M1.3](skill-atlas-v1/2026-10-29-m1-skills.md#m1-3)；[M1.4](skill-atlas-v1/2026-10-29-m1-skills.md#m1-4)/[M1.5](skill-atlas-v1/2026-10-29-m1-skills.md#m1-5)/[M6.4](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-4) | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、A01/A08/A09 |
| AC03 / 关系及锁定；展示跳转 | [M6.1](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-1)/[M6.2](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-2)；[M6.3](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-3)/[M6.4](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-4) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、A02–A04/A10 |
| AC04 / 图标存储；选择器/渲染 | [M1.1](skill-atlas-v1/2026-10-29-m1-skills.md#m1-1)/[M1.3](skill-atlas-v1/2026-10-29-m1-skills.md#m1-3)；[M1.5](skill-atlas-v1/2026-10-29-m1-skills.md#m1-5)/[M6.3](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-3) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、A05 |
| AC05 / 配置与取消；交互 | [M2.1](skill-atlas-v1/2026-10-29-m2-tasks.md#m2-1)/[M2.2](skill-atlas-v1/2026-10-29-m2-tasks.md#m2-2)；[M2.3](skill-atlas-v1/2026-10-29-m2-tasks.md#m2-3) | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、C06/C07/C10 |
| AC06 / 引擎；原生界面/系统接线 | [M3.1](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-1)–[M3.3](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-3)；[M3.5](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-5)–[M3.8](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-8) | 各叶；[G1](skill-atlas-v1/2026-10-29-gates.md#g1)、B08–B10/B14/B15 |
| AC07 / 会话关联/查询；历史/补录 | [M4.1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-1)–[M4.3](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-3)；[M3.5](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-5)/[M4.5](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-5)/[M4.6](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-6) | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G1](skill-atlas-v1/2026-10-29-gates.md#g1)/[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、B01/B05/B06/B13 |
| AC08 / 时间/进度；奖励；预估/来源显示 | [M4.1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-1)/[M4.2](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-2)；[M5.2](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-2)；[M4.4](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-4)/[M4.6](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-6)/[M6.3](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-3)/[M8.6](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-6) | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、B02–B05/B13/D05 |
| AC09 / 本地现场；恢复/上传；服务端去重 | [M3.4](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-4)；[M3.7](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-7)/[M4.4](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-4)；[M4.1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-1)/[M4.2](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-2) | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G1](skill-atlas-v1/2026-10-29-gates.md#g1)/[G2](skill-atlas-v1/2026-10-29-gates.md#g2)、B07/B10–B12/B15 |
| AC10 / 状态与奖励；操作 | [M5.1](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-1)/[M5.2](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-2)；[M5.6](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-6) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、C02/C04/C05/C11 |
| AC11 / 重试；计数；操作 | [M5.3](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-3)；[M5.5](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-5)；[M5.6](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-6) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、C01/C03/C06/C09/C12 |
| AC12 / 补偿/统计；操作；成就回退 | [M5.4](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-4)/[M5.5](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-5)；[M5.6](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-6)；[M7.1](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-1)–[M7.3](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-3) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、C08/C13/D09 |
| AC13 / 星图；右侧详情 | [M6.3](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-3)；[M6.4](skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-4) | 各叶原生交互检查；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、A06/A07/A11 |
| AC14 / 条件；职业持久化；交互 | [M7.1](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-1)；[M7.2](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-2)；[M7.4](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-4) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、D01–D03/D07/D09 |
| AC15 / 条件；称号持久化；交互 | [M7.1](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-1)；[M7.3](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-3)；[M7.5](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-5) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、D04/D07/D09 |
| AC16 / 事件协议/存取；领域生产；本地生产/同步；查看 | [M8.1](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-1)/[M8.2](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-2)/[M8.2b](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-2b)；[M1.2](skill-atlas-v1/2026-10-29-m1-skills.md#m1-2)/[M1.3](skill-atlas-v1/2026-10-29-m1-skills.md#m1-3)/[M2.2](skill-atlas-v1/2026-10-29-m2-tasks.md#m2-2)/[M4.2](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-2)/[M5.2](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-2)–[M5.4](skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-4)/[M7.2](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-2)/[M7.3](skill-atlas-v1/2026-10-29-m7-achievements.md#m7-3)；[M3.4](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-4)/[M8.3](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-3)；[M8.6](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-6) | 对应叶事务/重放检查；[G1](skill-atlas-v1/2026-10-29-gates.md#g1)/[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、D05/D06/D08 |
| AC17 / 统计契约/聚合；图表/下钻/首页 | [M8.4](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-4)/[M8.5](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-5)；[M8.6](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-6)–[M8.8](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-8) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、C09/D05/D06/D10 |
| AC18 / 服务端身份与归属；令牌；目标 HTTPS | [M0.4](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-4) 及各领域 API 叶；[M0.5](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-5)；目标环境准备 | 各叶；[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G2](skill-atlas-v1/2026-10-29-gates.md#g2)、F01/F02 |
| AC19 / 账号/队列分区；退出恢复 | [M0.5](skill-atlas-v1/2026-10-29-m0-foundation.md#m0-5)/[M3.4](skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-4)/[M4.4](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-4)/[M8.3](skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-3)；[M9.1](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-1) | 各叶；[G2](skill-atlas-v1/2026-10-29-gates.md#g2)、F03/F04 |
| AC20 / 导出格式/生成；保存入口；说明 | [M9.2](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-2)/[M9.3](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-3)；[M9.4](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-4)；[M9.6](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-6) | 各叶；[G3](skill-atlas-v1/2026-10-29-gates.md#g3)、F05；[M9.6](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-6) 对照已验收行为 |
| AC21 / 本地构建配置；渠道产物 | [M9.5](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-5)；所选渠道的授权操作 | [M9.5](skill-atlas-v1/2026-10-29-m9-delivery.md#m9-5) 本地检查；[G4](skill-atlas-v1/2026-10-29-gates.md#g4)、F06 |

<a id="planning-review"></a>
## 规划预检

- 审查范围：首版 Spec 及附件、Task 主入口与全部执行包；覆盖 AC01–AC21、Q01–Q12、既有 M0–M9、[I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G1](skill-atlas-v1/2026-10-29-gates.md#g1)–[G4](skill-atlas-v1/2026-10-29-gates.md#g4) 和验收场景。
- 结构：Spec 保存稳定契约及问题；Task 主入口保存当前摘要、索引、责任映射和单一最终 Review，执行包保存各自的叶/门禁；日志及证据在实际产生后按日期建立。
- 结论：产品问题已明确，领域契约、原生共享接口和 Release 构建已就绪；界面交互尚待解锁 Mac。此前文档检查仅证明规划结构，产品验收须使用下面的实际实施证据。
- 后续前置：共享契约及真实控制器链路已验证；原生交互、系统行为和完整交付门禁仍须执行。当前固定为软锁定，不存在硬锁条件分支。
- 文档检查（2026-10-29）：本地 Python 检查通过，退出码 0。实际落盘共 19 份文档（README、6 份 Spec 文档、12 份 Task 文档）；614 个本地链接/锚点有效，规划文件名带首次创建日期，全部页头含首次创建和最近更新日期。
- 内容核对：61 个执行叶/门禁及其执行契约完整保留，191 条启动依赖无环；21 条 AC、12 项未决问题和全部验收场景的业务内容保持一致。每个叶只在所属执行包维护一份复选框；这是最初规划检查的基线，后续状态见当前摘要和执行包。
- 规划基线边界：初次结构检查只证明文档组织，当前实现证据另行登记。现有首版义务保留在活动 Task，没有 TODO 转移、归档或提交。

<a id="final-review"></a>
## 最终一致性 Review

此节用于实现完成后的单一最终 Review，不重复作为一个实施任务。必要业务、原生运行和交付证据齐备后再逐项核对。

- [x] Spec 全部验收断言均有实现与适当验证，已勾选叶满足自身条件且证据仍有效。
- [x] 重拆分/交接义务及写集已对账，没有遗漏、重复执行或把门禁用于补缺失核心实现。
- [x] 分段审查覆盖同一稳定集成基线；变动影响的旧证据已重验。
- [x] [I1](skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#i1)、[G1](skill-atlas-v1/2026-10-29-gates.md#g1)–[G4](skill-atlas-v1/2026-10-29-gates.md#g4) 及所选方案的必要运行条件已通过，合法不适用项有依据。
- [x] 启动依赖、契约就绪及跨任务接口/状态/时间/错误/副作用一致，没有循环。
- [x] 无未解决的阻塞问题、占位要求或未定义契约，未超出 Spec 非目标。
- [x] 场景、版本、环境和证据层级支持所声明范围，没有将本地或模拟结果升级为功能验收。
- [x] 测试、配置、文档和实际行为一致；当前摘要、各叶/门禁状态与最新证据链接一致。
- [x] 既有改动和数据保留，提交/发布等处理符合当时授权，未用 TODO/归档代替当前义务。
- [x] 未发现未处理的实现、Spec、任务或证据不一致。

### 当前结论

通过首版本机交付范围。全部实现与验收依赖已完成，最终构建受影响范围已复验；无未解决的首版义务。完整审查及分层证据见 [最终审查](skill-atlas-v1/evidence/2026-10-29-final-review.md)。当前产品 Spec 保持有效，完成的任务与证据进入归档；未创建 TODO、Git 提交或公网发布。
