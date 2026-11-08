# 本机运行、安装与数据位置

> 首次创建：2026-10-29；最近更新：2026-11-08。
> 本文记录已经验证的工程命令和安装方式；日常操作见 [使用说明](2026-10-29-user-guide.md)，验收依据见 [G1–G4](../archive/tasks/skill-atlas-v1/2026-10-29-gates.md)。

## 启动后端

在项目根目录执行，Docker Desktop 需已运行：

```sh
python3 scripts/local.py up
python3 scripts/local.py health
python3 scripts/local.py status
```

`up` 准备专属本地配置、构建 API 镜像、启动 PostgreSQL、API 与 Caddy，并等待健康检查。Caddy 提供 `https://localhost:8447` 和 `https://127.0.0.1:8447`，通过持久化的私有 CA 自动签发和续期证书；API 只在 Docker 内部监听 HTTP `8080`。数据库端口为本机回环地址 `55437`，Compose 项目为 `skillatlas`。数据库迁移启动时按文件顺序执行，并核对已应用迁移的校验值。首次构建客户端前需先 `up`，取得公开根 CA 资源。

```sh
python3 scripts/local.py down
```

`down` 停止服务并保留数据卷。后续重新运行 `up` 使用同一持久卷。应用不自动启动 Docker Desktop。

## 配置客户端地址

构建 24 起可在登录页“后端地址…”或设置“编辑地址”中保存 HTTPS 服务根地址，例如 `https://localhost:8447`。可以先检查连接，保存后即时切换并跨重启保留；“使用默认地址”会回填应用包默认值，保存后清除自定义覆盖。

当前源码默认后端将应用包内的公开根 CA 或旧叶证书作为信任锚；自定义后端同时采用系统证书信任。两条路径均校验证书链、有效期和主机名，支持根 CA 下的叶证书自动轮换。地址仅含来源，不附加 `/v1`、查询或登录信息。接口与业务数据属于所选后端，配置与验收见[后端地址规格](../specs/2026-10-30-backend-address.md)和[验收记录](../tasks/backend-address/evidence/2026-10-30-implementation.md)。

## 局域网私有 CA 访问

没有自有域名时，可以增加由私有 CA 签发证书的局域网入口。首次在每台 Mac 上信任公开根证书，此后局域网服务端证书由 Caddy 自动签发和续期，客户端无需重新构建。部署契约见[局域网私有 CA 规格](../specs/2026-11-08-lan-private-ca.md)，当前实施状态见[实施任务](../tasks/2026-11-08-lan-private-ca.md)。

本机后端启动后执行：

```sh
python3 scripts/lan.py up
python3 scripts/lan.py health
python3 scripts/lan.py status
```

首次启动会将 macOS 的 `LocalHostName` 加上 `.local` 后缀并保存在 `.runtime/local.env`，默认使用 `8448` 端口。例如本次部署地址为 `https://yzinmac-mini-m6.local:8448`；本机 `https://localhost:8447` 和 `https://127.0.0.1:8447` 同样使用私有 CA 自动续期。客户端填写主机名，无需随 DHCP 地址变化修改证书。需要网络支持 mDNS；跨网段或设备隔离的访客网络需要另外解决解析和连通性。

也可显式指定已有局域网 DNS 主机名和空闲端口：

```sh
python3 scripts/lan.py up --host skillatlas.local --port 8448
```

指定主机名只配置证书和入口，不创建 DNS/mDNS 记录。默认 macOS `.local` 名称由系统公布；使用其他名称时需先保证设备可解析。

### 其他 Mac 首次接入

启用局域网后可直接下载公开根证书，本次部署地址为：

- 主机名地址：`http://yzinmac-mini-m6.local:8081/root.crt`。
- 当前 IP 地址：`http://192.168.5.22:8081/root.crt`。
- 根证书 SHA-256：`43d5f4b8e66b433621eb0bda9d9331185514085011a85adf784b60c4fbfe2614`。

HTTP 下载不要求事先信任 CA，只提供公开根证书，不代理 API。安装前请用本说明里的 SHA-256 核对下载证书，而非仅凭下载来源。HTTPS 入口也提供 `/root.crt`，适合已经信任该 CA 的设备。可运行 `openssl x509 -in root.crt -noout -fingerprint -sha256` 核对指纹，忽略冒号与字母大小写。

启动后同时生成 `dist/lan-setup.zip`，其中只有公开根证书 `root.crt`、`安装信任.command` 和 `接入说明.txt`。将此压缩包复制到其他 Mac，解压并核对说明中的根证书指纹，随后双击安装命令，或在终端运行：

```sh
security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" /完整路径/root.crt
```

该命令只给当前用户配置 SSL 根信任；macOS 可能显示确认或认证提示。也可使用“钥匙串访问”导入根证书，并将其 SSL 信任设为“始终信任”。只安装自己信任的服务端提供的根证书，不传递 CA 私钥。

然后在 Skill Atlas 登录页“后端地址…”或设置“编辑地址”中，输入接入说明里的 HTTPS 地址，检查连接并保存，使用原有账号登录。自定义地址使用系统证书信任。切换后端地址会建立独立的本机缓存和登录状态，原服务端账号和业务数据保持一致。

旧版安装包默认 `localhost` 固定信任旧叶证书，在服务器切换后需要一次性保存自定义 `https://127.0.0.1:8447` 或上述局域网地址；后续叶证书续期不要求再次切换或重装。当前源码已支持以应用包根 CA 验证默认地址，未来新构建也可直接使用 `localhost`。

当前服务端这台 Mac 若也要使用自定义入口，可执行：

```sh
python3 scripts/lan.py trust-ca
```

### 维护与停止

Caddy 的 CA 私钥、根证书、中间证书及自动续期状态保存在独立卷 `skillatlas-lan-ca-v1`。停止、升级或重建代理时保留此卷，避免所有设备重新信任。公开根证书可随时重新导出：

```sh
python3 scripts/lan.py export-ca
python3 scripts/lan.py down
```

`lan.py down` 关闭局域网 HTTPS 和 HTTP 根证书下载站点，本机 `8447` 保持运行；再次运行 `lan.py up` 恢复。`local.py down` 停止整个后端并保留所有持久卷。`local.py up` 按已保存的局域网开关恢复完整服务；首次启用局域网时运行 `lan.py up`。

Caddy 的本机 `8447` 仅映射回环地址，局域网提供 `8448` HTTPS 和 `8081` 公开根证书下载。API 没有宿主机端口映射，以显式代理模式仅在 Docker 内部提供 HTTP；数据库仍只映射回环地址。运行链路不再加载旧 `.runtime/tls/cert.pem` 或私钥，两个外部 HTTPS 入口均由 Caddy 自动管理，无需手动运行续期命令。根 CA 本身仍有有效期，应保留其持久卷并妥善备份。

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
| 本机数据库配置 | 项目 `.runtime/local.env`；受本机文件权限保护并被忽略 |
| 私有 CA 私钥与证书续期状态 | Docker 卷 `skillatlas-lan-ca-v1`；不导出至证书下载目录或接入包 |
| App 中的服务配置 | 本机 URL 与公开根 CA；不含数据库密码或 TLS 私钥 |
| JSON 导出 | 由用户在应用设置中选择位置；保存后重新解析格式、数量和引用 |

客户端校验证书链、有效期和主机名。服务端叶证书由 Caddy 自动续期，`renew-certificate` 仅保留为兼容提示，不再生成手动证书。根 CA 有效期届满或主动更换 CA 时，需重新分发公开根证书；正常叶证书续期无需更新客户端。

导出仅包含服务端已经确认的数据。本机仍在计时或等待上传的记录，需要结束并同步后再导出。当前首版提供导出和可读取性校验，不提供恢复导入。

## 验证命令

```sh
python3 scripts/local.py test ./...
swift test --package-path macos
python3 scripts/check-docs.py
```

后端测试使用隔离 Schema 并仅清理自己的测试对象；不删除业务数据卷。原生诊断位于 `macos/Diagnostics/`，测试账号与临时缓存独立，原始日志位于 `.runtime/logs/`。测试层级、版本输入和未验证项见 [当前计划](../archive/tasks/2026-10-29-skill-atlas-v1.md#current)。
