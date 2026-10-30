# 数据模型与 API 契约

> 文档标识：`skill-atlas-v1-data-api`；首次创建：2026-10-29；最近更新：2026-10-30。

> 归属：[产品 Spec](../2026-10-29-skill-atlas-v1.md) 的数据/API 附件。本文维护逻辑模型；各契约的实际就绪证据以 Task 为准。统一使用 UUID；时间戳存 UTC，展示时按设备时区格式化，统计分桶口径另见 Q10。
> 字段变更先同步本附件、相关业务规则和场景，再更新责任任务及共享 Schema。消费者只能依赖 [契约登记](#contracts) 中经过验证的产物，不能把类型名清单视作就绪证据。

## 1. 关系总览

```text
User 1──N SkillTree 1──N Skill
                        Skill ──parent_skill_id──> Skill（同树父子）
                        SkillLink（前置/普通关联；可跨树）
User 1──N Task 1──N TaskAttempt
             ├──N TaskSkill ──> Skill（每项成功奖励级数）
             └──N FocusSession ──> Skill（主技能，一次会话只归一项）
Skill 1──N GrowthEvent（奖励/修正来源可追溯）
User 1──N CareerTransition
User 1──N UnlockedTitle
```

## 2. 核心实体

### 2.1 `skill_trees`

`id`, `user_id`, `name`, `description?`, `theme_key?`, `sort_order`, `archived_at?`, `created_at`, `updated_at`, `version`。

### 2.2 `skills`

`id`, `user_id`, `tree_id`, `parent_skill_id?`, `name`, `description?`, `icon_key`, `sort_order`, `archived_at?`, `created_at`, `updated_at`, `version`。

- `parent_skill_id` 只能引用同一树；跨树关系使用独立表。
- XP/等级作为**计算后的响应字段**，不要把客户端传来的当前等级当唯一事实来源。

### 2.3 `skill_links`

`id`, `user_id`, `from_skill_id`, `to_skill_id`, `link_type`, `required_level?`, `created_at`。

- `link_type`: `prerequisite`（`from` 技能依赖 `to` 技能）或 `reference`（普通关联）。
- 仅 `prerequisite` 使用 `required_level`；默认 1。
- 允许跨技能树；阻止直接自引用和任意长度的前置循环，不仅检查两节点互相依赖；普通关联不参与前置解锁图。
- 去重约束：未删除的 `(from_skill_id, to_skill_id, link_type)`。关系保留删除标记与历史；前置阈值可用版本号 PATCH 修改。C-LINK 位于 `server/contracts/skill-link.yaml`；软锁只影响提示，缺项随当前等级重新查询。

### 2.4 `tasks`

`id`, `user_id`, `title`, `description?`, `success_criteria?`, `status`, `due_at?`, `created_at`, `updated_at`, `version`。

- `status`: `todo | in_progress | success | failed | canceled`。
- 失败后可以“重试”恢复 `in_progress`，分配下一尝试编号；结算时保存稳定的尝试 UUID，过去的尝试记录仍存在。
- 到期不自动失败。

### 2.5 `task_skills`

`task_id`, `skill_id`, `reward_levels`, `created_at`；主键 `(task_id, skill_id)`。

- `reward_levels` 为非负整数，客户端创建时用户逐个设置，0 表示只关联、不发任务成功奖励。
- 结算成功时，把当时的奖励配置**快照**保存到 `task_rewards`，防止日后编辑配置导致历史变更。

### 2.6 `focus_sessions`

`id`, `user_id`, `skill_id`, `task_id?`, `mode`, `target_seconds?`, `effective_seconds`, `started_at`, `ended_at`, `note?`, `source`, `created_at`, `invalidated_at?`。

- `mode`: `count_up | countdown | pomodoro | manual`。
- 主技能**必选且唯一**；任务**可选**；一个任务通过 `task_id` 与任意多条会话关联。
- 服务端首版接收**结束后的最终会话**；正在进行的计时现场属于本地持久化。
- `effective_seconds` 是所有有效专注段之和，休息/暂停不计入；按秒累积，XP 在跨会话总秒数上取整。
- `id` 由客户端先生成，重复 POST 同一 ID 返回原记录与相同结算结果；若重复 ID 携带冲突内容，返回冲突错误。
- `source` 区分计时器和手动补录，用于日志透明度。

### 2.7 `task_attempts` 和 `task_rewards`

`task_attempts`: `id`, `task_id`, `user_id`, `attempt_no`, `result (success|failed)`, `reason?`, `concluded_at`, `reversed_at?`。

`task_rewards`: `id`, `attempt_id`, `skill_id`, `reward_levels_snapshot`, `xp_amount`；唯一 `(attempt_id, skill_id)`。

- 发起“成功/失败”结算前生成并持久保存稳定尝试 ID；仅**成功**产生任务奖励。重试推进编号，尝试实体在结算时持久化，按 Q07 保留历史。
- 同一次请求失败重试仍携带相同 `attempt_id`，服务端保证同次尝试最多发一次奖励。
- 已经“成功”的任务不直接重复成功结算；再次做同类事项应手动创建新任务。失败可以重新尝试。
- 撤销时记录反向补偿事件/撤销时间，保留原始日志，以便统计和历史解释。
- C-ATTEMPT 的请求与幂等响应以 `server/contracts/attempt.yaml` 为准：结算携带 `id/attempt_no/version/result/reason`；所有结算都保存关联技能快照。重试使用稳定命令 ID；撤销只有最新且未开启后续编号时允许，进入新的进行中编号。返回原结算快照后，当前状态通过 GET 读取。
- 任务详情包含 `attempt_summary`：有效成功/失败数、总数、明确重试次数和可空成功率；取消与已撤销结算不计分母。

### 2.8 `growth_events`

`id`, `user_id`, `skill_id`, `event_type`, `source_id`, `delta_xp`, `note?`, `created_at`, `reverses_event_id?`。

- `event_type` 可含 `focus_accrual | task_success | reversal`。
- 计时产生的 `delta_xp` 根据该技能**本次新增有效秒数导致的累计整分钟差值**确定：
  `floor((old_seconds + new_seconds)/60) - floor(old_seconds/60)`。
- 任务奖励产生 `reward_levels × 60 XP`；撤销发负数补偿事件。
- 对来源做唯一性保护。若后续允许修改/作废会话，需补偿重算相应技能，不直接修改已记录的事件。

### 2.9 `activity_events`

`id`, `user_id`, `type`, `entity_type`, `entity_id`, `summary`, `metadata_json`, `created_at`。

作为可查询的活动时间线，保留任务尝试、技能升级、转职、称号等事件；成长流水与事件日志可通过引用关系关联，不必每次改动都在两份表重复存全部数据。

### 2.10 职业与称号

- `career_nodes`：`id`, `user_id`, `name`, `description`, `badge_key`, `parent_career_id?`, `conditions_json`, `sort_order`。
- `career_transitions`：`id`, `user_id`, `from_career_id?`, `to_career_id`, `confirmed_at`。
- `titles`：`id`, `user_id`, `name`, `description`, `icon_key`, `conditions_json`, `created_at`。
- `user_titles`：`user_id`, `title_id`, `unlocked_at`, `equipped_at?`。

条件首版 JSON 只支持：

```json
{
  "all": [
    { "type": "skill_level", "skill_id": "<uuid>", "gte": 10 },
    { "type": "focus_minutes", "skill_id": "<uuid>", "gte": 600 },
    { "type": "task_success_count", "gte": 5 },
    { "type": "specific_task_success", "task_id": "<uuid>" }
  ]
}
```

`career_nodes` 与 `titles` 首版由用户手动创建；条件的可视化创建器逐项添加，禁止把通用任意表达式作为 v1 的规则引擎。

C-ACHIEVEMENT 以 `server/contracts/achievement.yaml` 为准：1–32 项全部满足的条件，阈值 1–1000000；成功次数可按结算技能快照筛选。证据包括完整聚合值与最多 200 个来源 ID（超限明确标记）。职业分支要求父阶段曾转职，转职携带稳定 ID、配置版本与当前职业；所有配置支持版本编辑。称号解锁和回退取消佩戴与触发的成长操作同事务提交；历史条件与证据永久保留。

## 3. 计算输出（客户端展示）

```json
{
  "skill_id": "<uuid>",
  "total_focus_seconds": 4200,
  "time_xp": 70,
  "task_bonus_xp": 120,
  "total_xp": 190,
  "level": 4,
  "xp_current": 10,
  "xp_required": 60,
  "unlocked": true
}
```

起始等级为 Lv.1。以上例子 4 级 10/60 XP；用户真实专注 70 分钟，任务奖励为 120 XP。

## 4. API 契约（REST）

| 方法 | 路径 | 功能 |
| --- | --- | --- |
| POST | `/v1/auth/register`、`/v1/auth/login`、`/v1/auth/logout` | 注册、登录和撤销当前会话 |
| GET / PATCH | `/v1/me` | 当前用户、登录状态与统计时区 |
| GET / POST | `/v1/skill-trees` | 列表、创建技能树 |
| PATCH | `/v1/skill-trees/{id}` | 编辑、排序/归档 |
| GET / POST | `/v1/skills` | 技能查询、创建（含 `tree_id`、`parent_skill_id`） |
| GET / PATCH | `/v1/skills/{id}` | 详情、编辑、替换图标 |
| GET / POST | `/v1/skill-links` | 查询/创建前置与普通关联 |
| PATCH | `/v1/skill-links/{id}` | 带版本调整前置等级 |
| DELETE | `/v1/skill-links/{id}` | 删除关系 |
| GET / POST | `/v1/tasks` | 任务查询、创建（含关联技能及奖励） |
| GET / PATCH | `/v1/tasks/{id}` | 详情、编辑、取消 |
| POST | `/v1/tasks/{id}/attempts` | 成功/失败结算（请求字段 `id` 表示稳定的尝试 ID） |
| POST | `/v1/tasks/{id}/retry` | 失败后发起下一次尝试 |
| POST | `/v1/task-attempts/{id}/reverse` | 撤销错误结算 |
| POST | `/v1/focus-sessions` | 上传最终专注记录（请求字段 `id` 表示稳定的会话 ID） |
| PATCH | `/v1/focus-sessions/{id}/task` | 变更任务绑定，**不重复经验结算** |
| GET | `/v1/focus-sessions`、`/v1/focus-sessions/{id}` | 记录列表/详情，支持技能、任务、日期和游标 |
| GET | `/v1/tasks/{id}/attempts`、`/v1/task-attempts/{id}` | 尝试历史、快照与补偿链 |
| GET | `/v1/growth-events/{id}`、`/v1/task-retries/{id}` | 成长流水和重试来源 |
| GET | `/v1/progress` | 全部技能当前权威进度 |
| GET | `/v1/skills/{id}/progress` | 等级、XP、时间投入、解锁状态 |
| GET | `/v1/stats/summary` | 时间、成功率、失败/重试等统计 |
| GET / POST | `/v1/activity-events` | 查询时间线 / 上传四类客户端计时事件 |
| GET / POST | `/v1/career-nodes` | 职业路线及条件配置 |
| POST | `/v1/career-nodes/{id}/transition` | 满足条件后确认转职 |
| GET / POST | `/v1/titles` | 称号及条件配置 |
| POST | `/v1/titles/{id}/equip`、`/v1/titles/unequip` | 佩戴或取消佩戴称号 |
| PATCH | `/v1/career-nodes/{id}`、`/v1/titles/{id}` | 带版本编辑配置 |
| GET | `/v1/export` | 导出当前账号 JSON 数据 |

## 5. 示例请求

### 5.1 创建绑定两个技能的任务

```json
POST /v1/tasks
{
  "id": "<task-id>",
  "title": "完成登录接口",
  "description": "",
  "status": "todo",
  "pinned": false,
  "version": 0,
  "success_criteria": "可以正常登录并处理错误密码",
  "skills": [
    { "skill_id": "<go-skill-id>", "reward_levels": 2 },
    { "skill_id": "<db-skill-id>", "reward_levels": 1 }
  ]
}
```

### 5.2 上传同一个任务的两次专注

```json
POST /v1/focus-sessions
{
  "id": "<session-1-id>",
  "task_id": "<task-id>",
  "skill_id": "<go-skill-id>",
  "mode": "countdown",
  "target_seconds": 1500,
  "effective_seconds": 1500,
  "started_at": "2026-10-29T01:00:00Z",
  "ended_at": "2026-10-29T01:25:00Z",
  "source": "timer",
  "pomodoro_rounds": 0,
  "note": ""
}
```

第二次使用新的 `session-2-id`，将目标和有效秒数均改为 2100，并提供对应起止时间。总共 3600 秒 = 60 时间 XP；任务显示**2 次专注、累计 60 分钟**，而不是覆盖第一条。

### 5.3 结算失败后重试成功

```json
POST /v1/tasks/<task-id>/attempts
{ "id": "<attempt-1-id>", "attempt_no": 1, "version": 1, "result": "failed", "reason": "鉴权未完成" }
```

调用 `/v1/tasks/<task-id>/retry`，携带新的稳定 `id`、失败的 `attempt_no` 和失败响应中的任务 `version`。以重试响应的编号、版本再结算成功（以下以编号 2、版本 3 为例）：

```json
POST /v1/tasks/<task-id>/attempts
{ "id": "<attempt-2-id>", "attempt_no": 2, "version": 3, "result": "success", "reason": "" }
```

最终尝试统计：**成功 1 次、失败 1 次，成功率 50%**；任务成功奖励只发一次；计时 XP 不因失败而扣除。

## 6. 数据迁移与索引最低要求

- 每个表按 `user_id` 查询隔离，至少为常用过滤字段建立索引；例如 `focus_sessions(user_id, ended_at)`、`task_attempts(user_id, concluded_at)`、`skills(tree_id, parent_skill_id)`。
- `focus_sessions.id`、`task_attempts.id` 作为幂等唯一键；`task_rewards(attempt_id, skill_id)` 唯一。
- 结算通过事务确保任务尝试、奖励流水、活动日志与必要的汇总更新一致。
- `version` 用于最简单的乐观并发控制；首版不要提前实现全量 CRDT、多主同步或消息队列。

<a id="contracts"></a>
## 7. 契约登记与就绪标准

本表记录契约职责，不维护第二份进度表。当前就绪证据和启动条件以 [Task](../../archive/tasks/2026-10-29-skill-atlas-v1.md#current) 为准。后端共享契约位于 `server/contracts/`，计时契约位于 `macos/Core/FocusEngine/clock-contract.json`。

| 契约 | 责任叶 | 必须明确并验证的内容 | 契约产物 |
| --- | --- | --- | --- |
| C-AUTH | [M0.4](../../archive/tasks/skill-atlas-v1/2026-10-29-m0-foundation.md#m0-4) | 认证/退出失效边界、用户身份、资源越权、认证错误、安全日志及客户端登录所需输入 | `auth.yaml` 与同源 fixture/定向测试 |
| C-SKILL | [M1.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m1-skills.md#m1-1) | 树/技能写入、父子关系、图标键、归档/删除与历史引用、版本冲突 | `skill.yaml` 与同源 fixture/定向测试 |
| C-TASK | [M2.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m2-tasks.md#m2-1) | 任务字段、技能奖励列表、取消/编辑的合法状态、时间字段和版本 | `task.yaml` 与同源 fixture/定向测试 |
| C-CLOCK | [M3.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m3-local-focus.md#m3-1) | 单活动会话、计时状态、番茄阶段、有效时长、持久化恢复与通知时点 | 状态/时间样例与 Swift 定向测试 |
| C-FOCUS | [M4.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m4-focus-sync-xp.md#m4-1) | 会话字段、补录、上传重放/冲突、绑定变更、列表与进度响应、XP 公式 | `focus.yaml` 与同源 fixture/定向测试 |
| C-ATTEMPT | [M5.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m5-attempts-rewards.md#m5-1) | 合法状态转换、尝试 ID/编号、奖励快照、重试/撤销幂等、统计排除 | `attempt.yaml` 与同源 fixture/定向测试 |
| C-LINK | [M6.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m6-skill-graph.md#m6-1) | 关系方向、跨树归属、去重、环检测、锁定行为及对应错误 | `skill-link.yaml` 与同源 fixture/定向测试 |
| C-ACHIEVEMENT | [M7.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m7-achievements.md#m7-1) | 四类条件及证据、条件回退、职业/称号配置与查询、转职/佩戴行为 | `achievement.yaml` 与同源 fixture/定向测试 |
| C-ACTIVITY | [M8.1](../../archive/tasks/skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-1) | 各事件生产者、稳定事件 ID、时间/来源/实体引用、去重、排序与本地事件上报 | `activity.yaml` 与同源 fixture/定向测试 |
| C-STATS | [M8.4](../../archive/tasks/skill-atlas-v1/2026-10-29-m8-activity-statistics.md#m8-4) | 时间分桶、技能/树筛选、尝试去重、失效/补偿记录排除与下钻标识 | `stats.yaml` 与同源 fixture/定向测试 |
| C-EXPORT | [M9.2](../../archive/tasks/skill-atlas-v1/2026-10-29-m9-delivery.md#m9-2) | 导出范围、格式版本、账号归属、记录引用及可读取性判定 | `export.yaml` 与同源 fixture/定向测试 |

就绪必须同时具备：相关 Q 已解决；输入/输出及错误可检查；身份、状态、时间和副作用语义明确；生产者/消费者使用同源样例且契约检查通过；Task 指向实际证据。统一响应为 `data` 或 `error` 包；错误码、游标与筛选、必填性、身份和冲突语义以对应契约文件和定向检查为准。

### 跨领域接口边界

- 技能删除/归档与历史引用行为：C-SKILL 按 Q08 限制引用删除并保留归档。
- 本地开始/暂停/继续等活动事件上报：C-ACTIVITY 依据 Q10 定义；已存在的领域写入事件由服务器产生，避免两端重复生成。
- 职业/称号配置编辑、历史查询、条件证据与当前佩戴状态：C-ACHIEVEMENT 依据 Q09 明确查询和写入协议。
- 导出/备份入口：C-EXPORT 按 Q11 输出带版本的 20 个数据集，客户端保存后校验。

所有关联输入均检查同一认证用户的归属；重复业务请求、同 ID 不同内容、过期版本及并发提交的行为须有明确错误和“不产生额外副作用”的断言。示例中的 `<uuid>` 等表示场景输入，不是可直接发送的真实请求。

## 8. 统计与导出已冻结契约

C-STATS 见 `server/contracts/stats.yaml`。专注整条归入结束日期；时间 XP 按会话结束时间，成功奖励按结算时间，补偿按撤销时间。范围内净 XP 与累计 XP 分开，不能对筛选窗口重新按秒取整。历史尝试与重试按结算技能快照筛选；职业/称号历史按账号及日期显示。响应保留原始来源 ID。

C-EXPORT 见 `server/contracts/export.yaml`。`GET /v1/export` 输出 `skill-atlas-export` 版本 1，包含账号基础资料、20 个业务数据集及数量；在同一可重复读快照读取字段白名单。结构化引用须完整，已删除技能与尚未结束专注的活动来源按历史规则保留。客户端保存后重新解析格式/数量/引用；待上传本地记录不属于服务端导出。

## 统计来源详情补充（2026-10-29）

C-STATS 的 `growth_ids`、`retry_ids` 分别通过 `GET /v1/growth-events/{id}`、`GET /v1/task-retries/{id}` 读取。成长流水返回来源类型、来源 ID、XP 变更及被补偿流水 ID；重试返回任务、前后尝试编号和对应失败尝试 ID。接口只读取当前认证账号，缺失或越权均为 404，非法 ID 为 400。客户端继续跳转既有会话/尝试详情，筛选或图表不改变历史事实。
