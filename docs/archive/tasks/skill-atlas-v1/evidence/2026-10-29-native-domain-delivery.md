# 原生领域联通与本机安装证据

> 首次创建：2026-10-29；最近更新：2026-10-30。

## 首次安装阶段的结论

原生页面、控制器、导出和 Release 应用已实现并编译。M8.6a 的来源详情与 M9.5 的本机分发配置完成；其余原生交互叶保留未勾选。本阶段电脑控制工具两次返回 Mac 已锁定；后续实际界面、安装和系统操作见 [原生交互记录](2026-10-29-native-ui.md)，本文保留当时的控制器及构建证据。

## 领域联通

`macos/Diagnostics/DomainRuntime.swift` 直接使用应用的 AccountController、SkillLibrary、TaskLibrary、AchievementLibrary、SwiftData、URLSession 和固定证书连接真实 Docker API。测试账号与临时缓存独立，结束后撤销令牌并清理临时缓存。

实际检查通过：

- 两棵树的技能关系按 `from` 依赖 `to` 保存，未满足的跨树前置可查询。
- 70 秒补录与受控时钟的 60 秒计时共同获得 2 时间 XP；补录不进入计时成就条件。
- 同一任务失败、重试、成功后为 50% 成功率；多技能分别获得 120/60 XP；本机持久请求得到确认后清理。
- 四类条件共同达标；职业需显式转职，称号首次自动解锁并可唯一佩戴。
- 撤销成功扣回 180 奖励 XP，2 时间 XP 保留；前置恢复未满足；职业历史保留，称号自动取消佩戴且解锁证据保留。
- 原生统计 DTO、事件类型、成长流水与重试来源详情读取成功；JSON 导出包含两条会话、两次尝试、一次撤销，保存后重新校验数量、引用及禁止字段。
- 时区更新并通过真实 Keychain 恢复；第二账号无法读取第一账号来源，导出为自己的空数据；SQLite 重开保留缓存。

原始记录：`.runtime/logs/native-domain-runtime.log`、`.runtime/acceptance/native-domain-runtime.json`、`.runtime/acceptance/native-domain-export.json`。其中计时使用受控输入，不作为实际界面计时证据。

## 测试与构建

- `swift test --package-path macos`：32 项全部通过，涵盖时钟、恢复、落盘失败、账号队列、图布局、四类条件、任务请求保存和导出读取。
- 新增来源详情的实际数据库 HTTP 测试通过：所有者查询、另一账号 404、未认证 401、无效 ID 400、重试失败来源和奖励补偿链。后端 HTTP 测试包整体通过，`go vet ./...` 通过。
- 复用此前已通过的完整后端竞争检查；新增来源详情另做定向竞争检查，结果保存在 `.runtime/logs/backend-source-race.log`。
- Release 构建通过，最低 macOS 14，当前 Apple Silicon 产物。应用包没有 TLS 私钥或本地数据库凭据。

## 真实时钟与备注修正

`macos/Diagnostics/RealClockRuntime.swift` 使用实际 `DispatchTime.now` 和真实等待运行正计时、倒计时、两轮番茄钟，中间暂停 3 秒。三条会话合计 70 有效秒，经原生同步上传后得到 1 时间 XP；暂停时长被排除，倒计时与番茄钟在规定目标结束。结果位于 `.runtime/acceptance/native-real-clock.json` 和 `.runtime/logs/native-real-clock.log`。此检查没有操作窗口、菜单栏或真实系统睡眠，不能替代 G1。

最后核对修复了自动结束时输入备注未保存的问题：备注编辑现在随现场写入 SQLite，恢复后及菜单栏结束时沿用已保存值；超过服务端 Unicode 字符上限时拒绝输入。新增两项测试验证自动结束/重开保留和存储失败回滚。32 项 Swift 测试全部通过，构建 3 已安装。原有真实时钟证据的时间计算路径没有变化，备注路径由新增测试覆盖。

原生领域诊断随后在当前 Core 上重跑，并新增同一账号的另一真实登录会话，确认取得不同令牌且读取到相同任务状态、尝试编号和导出记录数量。

## 安装与更新配置

`python3 scripts/install-macos.py` 已将 `Skill Atlas.app` 安装到 `~/Applications/Skill Atlas.app`。随后从 0.1.0 构建 1 更新到构建 3；版本由 `macos/version.json` 维护，旧包保留在 Applications 同目录的隐藏备份路径。包签名、标识、可执行权限和安装前后可执行文件校验通过。脚本不写入应用数据库、Keychain 或 PostgreSQL 卷。

安装报告在 `.runtime/acceptance/macos-install-*.json`，实际命令和数据位置见 [本机运行说明](../../../../guides/2026-10-29-local-operation.md)。本机签名适用于已选本机交付；公众公证和商店提交不适用。

## 首次安装阶段尚未验证的层级

界面点击、布局可读性、小窗口 Drawer、通知授权/投递、菜单栏与关闭窗口、真实系统休眠、退出和重开、实际双账号 UI、原生保存面板，以及安装后启动和数据保留验收仍缺证据。编译、控制器诊断和文件复制不替代这些条件。完整使用说明 M9.6 等待 G3 实际用户闭环完成；全部活动任务继续保留，未转入 TODO 或归档。
