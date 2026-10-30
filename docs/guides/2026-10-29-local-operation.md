# 本机运行、安装与数据位置

> 首次创建：2026-10-29；最近更新：2026-10-31。
> 本文记录已经验证的工程命令和安装方式；日常操作见 [使用说明](2026-10-29-user-guide.md)，验收依据见 [G1–G4](../archive/tasks/skill-atlas-v1/2026-10-29-gates.md)。

## 启动后端

在项目根目录执行，Docker Desktop 需已运行：

```sh
python3 scripts/local.py up
python3 scripts/local.py health
python3 scripts/local.py status
```

`up` 准备专属本地配置、构建 API 镜像、启动 PostgreSQL 和 API，并等待健康检查。API 监听 `https://localhost:8447`，数据库端口为本机回环地址 `55437`，Compose 项目为 `skillatlas`。数据库迁移启动时按文件顺序执行，并核对已应用迁移的校验值。

```sh
python3 scripts/local.py down
```

`down` 停止服务并保留数据卷。后续重新运行 `up` 使用同一持久卷。应用不自动启动 Docker Desktop。

## 配置客户端地址

构建 24 起可在登录页“后端地址…”或设置“编辑地址”中保存 HTTPS 服务根地址，例如 `https://localhost:8447`。可以先检查连接，保存后即时切换并跨重启保留；“使用默认地址”会回填应用包默认值，保存后清除自定义覆盖。

自定义后端采用系统证书信任；与应用包相同且主机名匹配的本机证书也可连接。默认本机后端继续固定校验应用包证书。地址仅含来源，不附加 `/v1`、查询或登录信息。接口与业务数据属于所选后端，配置与验收见[后端地址规格](../specs/2026-10-30-backend-address.md)和[验收记录](../tasks/backend-address/evidence/2026-10-30-implementation.md)。

## 构建与安装

```sh
python3 scripts/install-macos.py
```

脚本生成 Xcode 工程并构建 Release 产物，校验本机签名后安装到 `~/Applications/Skill Atlas.app`。已存在同一应用时，旧包移到同目录的 `.SkillAtlas-backup-日期时间-标识.app`；出现复制或校验错误时保留原应用。安装不修改应用数据或 PostgreSQL 卷。

版本和构建编号由 `macos/version.json` 维护。更新源码后调整构建编号，重新执行安装命令。

更新前，先在旧版本的设置中退出账号，再从应用菜单退出；随后执行安装命令并重新登录。退出会暂停并保存专注，缓存和待传记录按账号保留；保存失败时会保留窗口并提示。应用包替换本身不会结束正在运行的旧进程。

需要恢复同一应用的旧包时，可执行 `python3 scripts/install-macos.py --source /完整路径/备份.app`。脚本校验备份的包标识与签名，再保存当前包并替换安装位置；用户数据保持原位。构建 18 起默认进入账号密码登录页。选择“记住登录”才保存令牌；恢复无法静默完成时返回登录页。只在身份确认后继续上传当前账号的记录，详见[手动登录规格](../specs/2026-10-30-optional-login.md)。

开发构建可使用：

```sh
python3 scripts/build-macos.py
python3 scripts/build-macos.py --release
```

最低目标为 macOS 14；当前产物在 Apple Silicon 本机构建。包标识为 `local.skillatlas.app`，使用 ad hoc 本机签名。所选交付方式是本机安装，Developer ID 公证及 App Store 提交不适用。

当前交付为 0.1.0（构建 26），新应用图标已完成系统读回验收，见[图标验收](../reviews/2026-10-31-app-icon.md)；手动后端地址见[后端地址验收](../tasks/backend-address/evidence/2026-10-30-implementation.md)；界面文字精简见[界面精简验收](../reviews/2026-10-30-ui-labels.md)；星图工具栏和初始缩放见[星图工具栏验收](../reviews/2026-10-30-skill-toolbar.md)；任务图钉直接操作见[图钉交互验收](../reviews/2026-10-30-task-pin.md)；默认手动登录、原账号数据及月历见[登录验收](../tasks/optional-login/evidence/2026-10-30-implementation.md)和[月历验收](../tasks/activity-calendar/evidence/2026-10-30-implementation.md)。首版安装与系统交互历史证据保留于 [G4](../archive/tasks/skill-atlas-v1/2026-10-29-gates.md#g4)。

## 数据和认证

| 内容 | 位置与保留方式 |
| --- | --- |
| 服务端业务数据 | Docker 卷 `skillatlas-postgres-v1`；保留迁移、账号和全部业务历史 |
| 本机专注、队列和缓存 | 默认后端为 `~/Library/Application Support/SkillAtlas/focus.sqlite`；自定义后端为同目录 `backends/<地址摘要>/focus.sqlite`，各后端内按账号隔离 |
| 当前登录令牌 | 默认仅内存；主动选择记住登录时存入按后端区分的 macOS Keychain 服务，普通缓存与日志不保存令牌 |
| 客户端后端地址 | 应用偏好中的 `backend.address`，恢复默认并保存时清除覆盖；不含登录令牌 |
| 本机数据库配置与 TLS 私钥 | 项目 `.runtime/`；受本机文件权限保护并被忽略 |
| App 中的服务配置 | 本机 URL 与公开证书；不含数据库密码或 TLS 私钥 |
| JSON 导出 | 由用户在应用设置中选择位置；保存后重新解析格式、数量和引用 |

客户端精确校验本机服务证书、有效期和主机名。若证书到期，可执行 `python3 scripts/local.py renew-certificate`，然后重新 `up` 并重新安装应用，使两端公开证书一致；不修改系统证书信任。

导出仅包含服务端已经确认的数据。本机仍在计时或等待上传的记录，需要结束并同步后再导出。当前首版提供导出和可读取性校验，不提供恢复导入。

## 验证命令

```sh
python3 scripts/local.py test ./...
swift test --package-path macos
python3 scripts/check-docs.py
```

后端测试使用隔离 Schema 并仅清理自己的测试对象；不删除业务数据卷。原生诊断位于 `macos/Diagnostics/`，测试账号与临时缓存独立，原始日志位于 `.runtime/logs/`。测试层级、版本输入和未验证项见 [当前计划](../archive/tasks/2026-10-29-skill-atlas-v1.md#current)。
