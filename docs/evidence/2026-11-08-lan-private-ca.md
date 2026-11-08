# 局域网私有 CA 验证记录

首次创建：2026-11-08；最近更新：2026-11-08。

对应规格：[局域网私有 CA 访问](../specs/2026-11-08-lan-private-ca.md)；当前状态由[实施任务](../tasks/2026-11-08-lan-private-ca.md)维护。

## 实施范围与运行基线

在 `/Users/yzin/code/skill-tree` 的未提交工作区实施。新增 `dev/Caddyfile.lan`、`scripts/lan.py`、`scripts/tests/test_lan.py` 和本次规格、任务、证据；修改 Compose、原停止命令、README 与运行指南。未构建或安装新的 Skill Atlas。

新增容器 `skillatlas-lan-proxy-1`，固定镜像为 `caddy:2.11.9-alpine@sha256:0bbb055bda6793c999bde78b1b5ce3e89f829fb031af2cf50056ea1246559fee`。入口为 `https://yzinmac-mini-m6.local:8448`，仅新增 IPv4 `0.0.0.0:8448` 端口映射。主机当前局域网地址为 `192.168.5.22`，由 `en1` 提供；macOS `.local` 名称可解析。

原 API、PostgreSQL 容器 ID 与 `.runtime/tls/cert.pem` 的 SHA-256 在部署前后相同，未重建它们或修改业务数据。原有 API 与数据库仍分别只映射 `127.0.0.1:8447`、`127.0.0.1:55437`。本机防火墙原本关闭，本次未修改防火墙。

CA 状态保存在 `skillatlas-lan-ca-v1`，代理只读挂载配置和原 API 公开证书，不挂载原 API 私钥。CA 私钥未导出。公开根证书为：

- 名称：`Skill Atlas LAN - 2026 ECC Root`。
- SHA-256：`43d5f4b8e66b433621eb0bda9d9331185514085011a85adf784b60c4fbfe2614`。
- 有效期：2026-11-08 至 2036-09-16，以证书 UTC 时间为准。
- 公开导出：`.runtime/lan/root.crt`；设备接入包：`dist/lan-setup.zip`。

## 已执行验证

| 验证 | 结果与证明范围 |
| --- | --- |
| `python3 -m unittest discover -s scripts/tests -p test_lan.py -v` | 6 项通过：保留原凭据、配置幂等、原子替换失败保护、主机名与端口拒绝、旧环境默认值、公开根证书导出和健康响应契约 |
| Compose `config --quiet` | 带 `lan` profile 的配置有效；未打印含凭据的展开配置 |
| 固定镜像内执行 `caddy adapt --config /etc/caddy/Caddyfile --validate` | 配置校验通过；明确配置上游证书信任和 `localhost` 校验，没有关闭 TLS 验证 |
| `python3 scripts/lan.py up`、`health` | 真实私有 CA 链与 `.local` 主机名校验通过，返回 `service=Skill Atlas`、`status=ok`、`database=ready` |
| `curl --noproxy "*" --cacert .runtime/lan/root.crt --resolve yzinmac-mini-m6.local:8448:192.168.5.22 https://yzinmac-mini-m6.local:8448/health` | 通过主机局域网 IPv4 地址直连并保持主机名校验，返回实际 API 健康状态 |
| `python3 scripts/lan.py trust-ca` | 根 CA 已加入当前用户钥匙串的 SSL 信任，操作成功 |
| 原生 URLSession 诊断 | 独立 Swift 诊断程序使用系统默认信任、无自定义证书委托，返回 HTTP 200 和实际数据库就绪状态；未重建 App |
| 错误根证书负向验证 | 以原 API 证书作为信任来源连接新入口，抛出 `SSLCertVerificationError`，未绕过证书验证 |
| 代理 `--force-recreate` 后再次导出与健康检查 | 根证书指纹不变，原 API/数据库容器 ID 与原证书不变，实际健康检查通过 |
| Caddy 运行日志 | 已启动证书后台维护；没有等待证书自然到期，因此不声称已观察到一次真实到期续签 |
| 再次运行 `lan.py up` | 代理保持运行，导出根 CA 不变，严格健康检查通过 |

原生诊断源码与可执行文件保存在 `.runtime/lan/verify-trust.swift` 和 `.runtime/lan/verify-trust`，使用 `swiftc -parse-as-library` 构建诊断程序，通过 `https://yzinmac-mini-m6.local:8448` 验证。此检查证明与客户端系统信任分支相同的 URLSession 信任路径，不代替实际 App 界面操作。

第一次部署时健康检查误按无封装对象解析，实际接口使用 `data` 包装，因此脚本错误报告服务状态不匹配；已按现有 API 契约修复并增加健康响应测试，随后真实检查通过。此前未出现 TLS 校验失败。

## 接入交付与证据边界

`dist/lan-setup.zip` 只包含 `root.crt`、`安装信任.command`、`接入说明.txt`。安装命令给接收设备当前用户配置 SSL 根信任；地址和根证书 SHA-256 写入说明。运行指南包含首次接入、账号与本机缓存隔离、停止与恢复、CA 持久卷保留和原 API 证书维护步骤。

目前没有在第二台 Mac 上执行根证书导入、实际 Skill Atlas 检查连接或登录。不能据此宣称已经验收跨设备 mDNS、路由器设备互通或另一台机器的系统信任。相关运行门禁保留在实施任务，解除条件是用户在另一台设备完成首次根信任并提供实际连接结果。

Caddy 自动管理局域网入口证书；原 API 的本机证书仍有自己的有效期和维护流程。更新原 API 证书后，代理需要重建以加载新的上游信任文件；局域网客户端无需重新构建。
