# 持续构建与发布实施证据

首次创建：2026-10-31  
最近更新：2026-10-31  
对应任务：[GitHub 发布](../../2026-10-31-github-release.md)

## T1：公共资源与干净构建

基线为本机未提交工作区，版本 `0.1.0`、构建 `26`。新增 `config/distribution/` 的两个公共文件，发布证书为现有后端的 DER 公共证书；未复制私钥或数据库配置。构建脚本支持显式资源目录、独立 DerivedData 与双架构；原本机入口仍从既有 `.runtime` 组装两个公共文件。

执行 `python3 -m unittest discover -s scripts/tests -v`，4 项配置边界测试通过，覆盖正确证书、摘要不匹配、额外私有字段和不安全根地址。执行原入口 `python3 scripts/build-macos.py --generate-only` 通过。

将 `scripts/`、`macos/`、`config/` 复制到不含 `.runtime` 的独立源码目录，执行 `python3 scripts/build-macos.py --release --universal --client-resources config/distribution`，Release 构建通过，仅出现既有 AppIntents 元数据提示。随后 `lipo -archs` 确认同时包含 `arm64` 和 `x86_64`，`codesign --verify --deep --strict` 通过。

首次核验命令将 `lipo -verify_arch` 的文件参数放在架构列表后，工具将其作为架构名解析并报错；改用 `lipo -archs` 对实际输出架构集合断言后通过，未重复构建或改变产物。本轮原始日志与副本位于 `.runtime/github-release-2026-10-31/`。

证据边界：以上为本机干净副本编译和签名证据，不代替 GitHub Actions、远端下载或 Intel 实机运行。

## T2：安装包与校验清单

新增 `scripts/package-macos.py`。输入应用必须匹配源码版本与构建号、包含两种架构、有效签名、公共连接配置和图标；私有密钥、环境配置与运行数据库会被拒绝。输出目录已有同名资产时拒绝覆盖。

在 T1 的实际通用应用上打包 `v0.1.0`：生成 `Skill-Atlas-0.1.0-26-macos-universal.zip`、同名 DMG、`build-info.json` 与 `SHA256SUMS`。ZIP 解包后及只读挂载 DMG 后，均复核应用身份、版本、双架构、签名、公共配置和可执行文件摘要；DMG 包含指向 `/Applications` 的快捷方式，完成后已卸载。

共 7 项发布工具测试通过，新增覆盖标签错配、私有运行数据或密钥被拒绝、公共证书可携带。实际包位于 `.runtime/github-release-2026-10-31/packages/`，ZIP 为 5,825,534 字节，DMG 为 6,711,949 字节。

证据边界：构建信息明确标记 `source_revision=local-uncommitted`，属于本地预检包，不能作为正式 CI 发布资产。正式资产必须由 G1 对应的 Actions 作业重新构建并产生提交和运行链接。

## T3：工作流与发布边界

新增 `.github/workflows/release.yml`，使用固定提交的官方 checkout、setup-go、upload-artifact 和 download-artifact。Linux 临时 PostgreSQL 作业执行 Go 集成测试；macOS 作业执行 Swift 测试、双架构构建和已验证的打包脚本。只有版本标签进入写权限发布作业。

`scripts/publish-release.py` 核对标签、源码提交、CI 运行、架构、签名标记、资产集合和 SHA-256，再创建草稿、上传资产并核对远端大小与摘要；已正式发布的版本拒绝覆盖，不属于本次运行的草稿拒绝接管。缺少远端摘要时下载草稿资产复核，所有检查成功后才正式发布。

`python3 -m unittest discover -s scripts/tests -v` 的 13 项测试通过，包括跨提交或跨运行、篡改与缺失资产、额外文件、正式版本保护及草稿归属。`actionlint .github/workflows/release.yml` 通过。Git 忽略规则补充构建缓存、生成工程、私有密钥与环境文件；发布使用说明已加入 README。

用户已完成 GitHub CLI 设备登录，核对账号为 `yzin-17`；目标仓库尚不存在。以上为本地实现和静态证据，远端作业、正式上传和下载仍由 G1 验收。

### 发布前审查与仓库准备

进一步检查草稿发布副作用后，补充部分上传、远端摘要错配保持草稿，以及完整上传才正式发布的测试，共 16 项通过。成功路径使用受控 CLI 夹具，只证明调用顺序和发布条件，不能计作远端发布。

GitHub CLI 初次登录只包含 `repo`、`read:org` 和 `gist`；提交 `.github/workflows/` 还需 `workflow`，已向用户提供增补设备授权入口。已创建私有空仓库 `https://github.com/yzin-17/skill-tree`，当前目录初始化为 `main`，本地身份使用 GitHub noreply 邮箱。

待纳入源码的 443 个文件约 41.19 MiB；检查运行目录、工具下载、编译缓存、生成工程和私有文件均被忽略。逐文件比对当前 `.runtime/local.env` 的数据库密码和连接串，未发现副本；私钥头检测唯一命中是用于拒绝私钥的短测试夹具，不含实际私钥。

### G1：推送凭据核对

初始本地提交为 `b651156d32bf8fd81312aeffb5940fdd3cbd0167`。用户补齐 `workflow` 权限后，REST 返回的作用域已包含该项，但首次 Git 推送仍被拒绝。核对发现 Git 从 Xcode 系统配置优先调用了旧的凭据 helper，实际凭据与当前 CLI 不同。

仅在本仓库的 `.git/config` 重置 helper 列表并选用 `gh auth git-credential`，不修改系统钥匙串或其他仓库。核对 Git 与 CLI 返回的凭据一致后，继续推送。首次失败没有写入远端分支或创建版本标签。

## 首次真实 CI 与发布修复

源码提交 `8f4fc4c0d2932d0b90b9c0f773f9f49865cec268` 与 `v0.1.0` 标签成功推送。[运行 41110368551](https://github.com/yzin-17/skill-tree/actions/runs/41110368551) 的“源码与后端测试”耗时 2 分 33 秒、macOS 通用安装包耗时 2 分钟，均成功。远端使用 Swift 6.3.3，Release 构建、ZIP 解包与 DMG 挂载核验通过，产物 `13002164738` 为 12,555,042 字节，归档摘要为 `bb063f46a931fff6b110d6955f9cdb56a1385c8e7ca4dfc99c6b34c48f5aa970`。

发布作业在上传四个文件后报“上传后草稿状态不符合预期”，未正式发布。实际草稿编号 `429383902`，目标提交正确，四个资产已完整上传。根因是 [GitHub 按标签查询接口](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name)仅返回已发布版本；草稿应通过有权限的 Release 列表查询。此前受控 CLI 夹具未覆盖这一真实接口差异，故补充 T3.1、T3.2，G1 保持未通过。

T3.1 修改查询方式，新增标签查询 404 仍能发现草稿、真正缺失、403 权限错误的回归用例。实际读取原草稿成功，确认仍为草稿且四个资产完整。T3.2 新增受控接续入口，严格核对原工作流、标签提交、两个必要作业成功及未过期同源产物；实际只读解析原运行通过。原版本标签和应用源码保持不变。

完善发布元数据夹具的最低系统字段后，共 23 项测试通过，`actionlint` 通过。新增用例覆盖来源仓库、工作流、移动标签、不完整作业、过期及异源产物被拒绝；原构建发布失败但测试与打包成功时允许接续。当前仅查询草稿和解析来源，不等于接续发布已经成功。
