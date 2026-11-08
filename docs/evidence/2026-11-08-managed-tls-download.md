# 统一自动证书与下载入口验证记录

首次创建：2026-11-08；最近更新：2026-11-08。

对应[规格](../specs/2026-11-08-lan-private-ca.md)与[实施任务](../tasks/2026-11-08-lan-private-ca.md)。本记录替代[首次部署记录](2026-11-08-lan-private-ca.md)中关于静态上游证书、本机入口旧证书和容器保持原样的当前部署说明；首次部署的根 CA 身份继续沿用。

## 当前实施结果

Caddy 同时管理 `localhost:8447`、`127.0.0.1:8447` 和 `yzinmac-mini-m6.local:8448`，三个站点均使用 `tls internal` 自动签发、续期叶证书。API 以 `TLS_TERMINATED_BY_PROXY=true` 显式启用 Docker 内部 HTTP `8080`，不再挂载静态 TLS 文件，不向宿主机发布 API 端口。独立运行默认仍要求配置 TLS，拒绝代理模式与 TLS 文件混用或歧义开关值。

本机 `8447` 只映射 `127.0.0.1`。局域网 `8448` 与下载端口 `8081` 映射 IPv4 所有接口。`lan.py down` 只关闭后两者的站点监听，本机站点继续运行；`local.py up` 根据保存的站点开关恢复全部服务。证书签发数据保存在原 `skillatlas-lan-ca-v1` 卷，数据库沿用原容器和数据卷。

根证书身份保持不变，已经导入该根证书的设备无需再次导入：

```text
43d5f4b8e66b433621eb0bda9d9331185514085011a85adf784b60c4fbfe2614
```

根证书下载地址为 `http://yzinmac-mini-m6.local:8081/root.crt`，本次 IP 地址形式为 `http://192.168.5.22:8081/root.crt`；两个地址均已通过真实下载验证。HTTPS 三个站点也提供 `/root.crt`。HTTP 下载目录单独只读挂载，里面只有公开根证书；CA 卷未作为静态文件目录。

## 改动范围

- 后端：`server/internal/config/config.go`、对应配置测试、`server/cmd/api/main.go`、`server/internal/httpapi/runtime_test.go` 与 `server/Dockerfile`。
- 部署与运维：`dev/compose.yaml`、`dev/Caddyfile`、`dev/Caddyfile.lan`、`dev/Caddyfile.lan-disabled`、`scripts/local.py`、`scripts/lan.py`、`scripts/tests/test_lan.py`。
- 客户端源码：`macos/Core/API/APIClient.swift` 以应用包证书作为信任锚验证链，支持根 CA 与旧叶证书；自定义后端同时接受系统根信任。新增独立诊断 `macos/Diagnostics/ManagedTLS.swift`。
- 文档：当前 Spec、Task、本文、后端地址规格、README 与本机运行指南。

工作区未提交。实际重建并部署了 API 与代理，没有重新构建、安装或重启现有 Skill Atlas，没有修改其后端偏好。诊断程序单独编译，不是 App 安装包更新。

## 验证结果

| 检查 | 结果与证明范围 |
| --- | --- |
| Go 定向配置与实际进程测试 | `TestRequiresDatabaseAndTLS`、`TestProxyTLSRequiresExplicitUnambiguousConfiguration` 与 `TestI1ActualAPIProcessAndRestart` 通过；后者分别运行独立 TLS 和代理 HTTP，验证真实业务持久化、重启与 `-healthcheck` 命令 |
| Python 脚本测试 | `python3 -m unittest discover -s scripts/tests`，30 项全部通过；其中局域网定向测试 7 项涵盖原凭据保护、配置原子性、主机名/端口、启停开关、公开证书导出和真实 API 响应契约 |
| Swift 后端地址测试 | `swift test --package-path macos --filter BackendAddressTests`，8 项通过；覆盖规范化、地址隔离、探测与来源/重定向约束 |
| Compose 与 Caddy 配置 | 配置校验通过；补充 `default_sni 127.0.0.1`，解决 IP 客户端不发送 SNI 时无法选择证书的问题 |
| 三个 HTTPS 入口 | 严格根 CA 与主机名/IP 校验后 `/health` 均返回实际 `database=ready`；`/root.crt` 返回字节与原 CA 一致 |
| HTTP 下载 | 主机名和当前局域网 IPv4 均返回 200、正确根证书字节及附件响应头，无须先安装 CA |
| 下载隔离负向检查 | `/`、`/health`、`/v1/tasks`、根/中间私钥路径、卷路径和普通/编码遍历路径均返回 404 |
| macOS 原生系统信任 | 原生 URLSession 通过 `localhost`、`127.0.0.1` 和局域网入口连接，返回 HTTP 200 与实际健康状态 |
| 实际客户端代码诊断 | 使用 APIClient 真实源码和根 CA 验证三个入口；固定旧叶证书会拒绝新证书；旧叶证书加自定义地址系统信任可以连接 |
| 重新签发演练 | 仅将卷内 `localhost` 叶证书缓存移至卷内临时备份，再启动代理；Caddy 签发新叶证书，指纹确实变化，根 CA 不变；同一个客户端诊断可执行文件无需重编译即可再次通过所有连接验证 |
| 局域网开关 | `lan.py down` 后本机健康通过、局域网 TLS 和 HTTP 下载均不可访问；再次 `lan.py up` 后全部恢复且 CA 不变 |
| 完整启动入口 | 最终通过 `python3 scripts/local.py up` 重新构建当前源码并恢复全部服务，严格健康检查通过 |
| 数据库与部署隔离 | 数据库容器 ID 与首次部署基线相同；API 无宿主机端口、没有 `/tls` 挂载，其他项目容器未操作 |

Go 测试通过本机工具链在 `server` 中执行：

```sh
go test ./internal/config ./internal/httpapi -run 'TestRequiresDatabaseAndTLS|TestProxyTLSRequiresExplicitUnambiguousConfiguration|TestI1ActualAPIProcessAndRestart' -count=1
```

测试数据库使用原有隔离 Schema 测试机制，凭据只通过进程环境传递，没有打印数据库连接地址。

客户端源码诊断编译与运行方式：

```sh
swiftc -parse-as-library macos/Core/API/APIClient.swift macos/Core/API/Backend/BackendAddress.swift macos/Diagnostics/ManagedTLS.swift -o .runtime/lan/verify-managed-tls
.runtime/lan/verify-managed-tls .runtime/tls/cert.der .runtime/lan/legacy-cert.der https://yzinmac-mini-m6.local:8448
```

旧叶证书 DER 为首次部署保留的公开证书转换产物，不含私钥。新客户端公开构建资源来自根 CA，不再来自旧叶证书。重新签发结果保存在 `.runtime/lan/rotation-result.json`，该演练验证自动管理与轮换兼容性，不冒充等待一次自然到期的定时续期验证。

## 接入与验收边界

旧版 App 的默认 `localhost` 使用旧固定叶证书，无法接受已轮换的服务端证书。现有安装包只需一次性改为自定义 `https://127.0.0.1:8447` 或原局域网地址，采用已安装的系统根信任，此后不随叶证书续期更新安装包。当前源码的默认地址支持应用包根 CA，未来构建不再固定某一张叶证书。

接入压缩包和说明已同步加入实际下载 URL 与本机地址切换方法。HTTP 下载用于分发公开证书；证书身份需用独立提供的根指纹核对。

实际第二台 Mac 的信任安装和 App 登录仍未执行，保留原任务 I1。当前新增服务端自动证书、下载 URL、轮换兼容性及本机运行验证已完成；未宣称跨设备实际登录已通过。
