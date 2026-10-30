# 工程基础与环境验证

> 首次创建：2026-10-29；最近更新：2026-10-30。
> 对应任务：[M0 执行包](../2026-10-29-m0-foundation.md)；涉及 AC01、AC18、AC21。

## M0.1｜环境盘点通过

- 输入基线：项目初始仅有 19 份规划文档，没有源码和 Git 仓库；没有既有项目数据需要迁移。
- 实际过程：读取项目与上级规则，执行 `sw_vers`、`xcodebuild -version`、`xcrun swift --version`、`xcrun --sdk macosx --show-sdk-version`、Docker 版本与服务连通检查，并检查 Go/PostgreSQL/XcodeGen 的 PATH 和 Homebrew 安装情况。
- 结果：macOS 27.0（26A425）、Xcode 27.1（27A9275）、Swift 6.4、macOS SDK 27.0、Docker 客户端和服务端 29.9.2 可用。Go、PostgreSQL、XcodeGen 未预装；选择项目本地 Go 工具和 Docker PostgreSQL，原生工程直接生成并通过 Xcode 构建。
- 选定边界：最低 macOS 14；本机 `.app`；Go 自管账号；Go API + PostgreSQL 的独立 Docker Compose 项目；业务数据使用专属卷，绑定本机回环端口。
- 证据边界：环境盘点不证明 App、服务、计时或任何业务功能已经通过。

## M0.2｜开发依赖准备

- 从 [Go 官方发布目录](https://go.dev/dl/) 获取稳定版元数据，下载 Darwin ARM64 归档并核对官方 SHA-256；安装到 `.tools/go/`，没有覆盖系统工具。实际 `go version` 为 `go1.27.3 darwin/arm64`。
- 拉取官方 `postgres:17-alpine`，镜像摘要为 `sha256:266d3c257594e195b309ae9d1805e54c788f1d7b375f56bf6c367aac6c917e7b`。
- 本批实际写入：`server/` 的配置、迁移、存储、HTTP 健康服务和测试，`server/Dockerfile`、`dev/compose.yaml`、`scripts/local.py`、`Makefile`、`.gitignore`；凭据/证书和编译工具位于被忽略的 `.runtime/`、`.tools/`。
- 实际验证：`rtk proxy python3 scripts/local.py test` 通过，包含有效配置/缺少数据库或 TLS 的拒绝、真实隔离 PostgreSQL schema 的迁移重放、HTTP 健康 200 和数据库连接关闭后的 503。测试只删除本次生成的独立测试 schema，不清理业务库。
- 实际运行：`rtk proxy python3 scripts/local.py up` 完成 Docker API 构建、数据库迁移和两个服务的健康等待；使用本项目证书校验的 `https://localhost:8447/health` 返回 `status=ok`、`database=ready`、`version=0.1.0`。
- 数据边界：PostgreSQL 数据持久保存在独立 `skillatlas-postgres-v1` 卷；应用使用非超级用户角色；服务仅发布本机回环地址。启动脚本在已有卷且凭据丢失时停止，不重新初始化数据。
- 证据边界：M0.2 通过；尚未证明客户端连通、身份体系、XP 或用户闭环。辅助构建日志位于 `.runtime/logs/foundation-up.log`，上述结果不依赖该临时日志长期存在。

## M0.3 原生窗口与连接（2026-10-29）

- `python3 scripts/build-macos.py`：Xcode 构建成功；实际产物 `.runtime/DerivedData/Build/Products/Debug/SkillAtlas.app`。
- `swift test --package-path macos`：2 项通过，验证服务端时间精度与拒绝明文 HTTP。
- 原生 URLSession 首次拒绝证书：有效期过长、缺少 serverAuth；本机证书改为 365 天、serverAuth、数字签名和 localhost SAN 后实际 HTTPS 返回 `ok / ready`。
- 实际启动原生窗口，`scripts/native-ui.swift` 经 Accessibility 读取“本机服务已就绪”“HTTPS 安全连接 · 数据库已连接 · v0.1.0”；修复前同一窗口显示“连接暂不可用”和重试入口。
- 固定公钥校验同时执行主机名、有效期和证书用途验证；未更改系统信任库，应用仅包含公开证书。
- CUA 初始化连续超时；`screencapture` 无法生成窗口图像。以上为原生窗口文本/交互与网络证据，后续页面视觉和全流程验收仍归 G3。
