# GitHub 构建、打包与发布

首次创建：2026-10-31  
最近更新：2026-10-31  
对应规格：[发布规格](../specs/2026-10-31-github-release.md)  
当前状态与证据：[实施任务](../tasks/2026-10-31-github-release.md)

## 下载与安装

正式安装包发布到目标仓库的 Releases 页面，名称包含应用版本、构建号和 `macos-universal`。每个版本提供 `.dmg`、`.zip`、`build-info.json` 和 `SHA256SUMS`。

DMG 中将 Skill Atlas 拖到 Applications 即可安装；ZIP 可直接解压使用。要求 macOS 14 或以上，同时包含 Apple Silicon 和 Intel 架构。当前为 ad hoc 临时签名，尚未经过 Apple 公证；首次打开如受到系统阻止，可在系统设置的隐私与安全性中处理。

将四个文件放在同一目录后执行：

```sh
shasum -a 256 -c SHA256SUMS
```

后端单独运行，见[本机运行说明](2026-10-29-local-operation.md)。登录页与设置均可编辑 HTTPS 后端地址。发布配置中的公共证书对应当前本机 Docker 后端；自定义后端保持现有证书校验。更换当前本机服务证书时需同步公共发布配置，私钥继续留在本机。

## 工作流入口

`.github/workflows/release.yml` 在 Pull Request、手动运行与推送 `v*` 标签时启动。前两者完成测试和打包，将四个文件上传为 Actions artifact；版本标签额外触发正式 Release 发布。

作业顺序为：文档和发布边界校验、临时 PostgreSQL 上的 Go 测试 → Swift 核心测试、双架构构建、ZIP 与 DMG 验证、上传产物 → 下载同次产物、核对来源和摘要、草稿上传、完整校验后正式发布。构建产物保留 14 天；正式 Release 资产独立保留。

仅发布作业持有 `contents: write`。已正式发布的版本会拒绝覆盖；上传失败时保留草稿，只有相同提交和相同 CI 运行才能接续该草稿。

## 发布新版本

先更新 `macos/version.json` 的版本与递增构建号，完成提交与推送，再创建与版本完全一致的标签。例如版本文件为 `0.1.1` 时：

```sh
git tag v0.1.1
git push origin v0.1.1
```

在 GitHub Actions 查看“构建与发布”，成功后检查对应 Release 的四个资产和 `build-info.json` 中的源码提交及运行链接。标签和版本不一致时不会正式发布。

## 本地预检

本地预检使用与 CI 相同的公共发布资源；不需要运行后端或读取数据库凭据：

```sh
python3 -m unittest discover -s scripts/tests -v
actionlint .github/workflows/release.yml
python3 scripts/build-macos.py --release --universal --client-resources config/distribution
python3 scripts/package-macos.py --app .runtime/DerivedData/Build/Products/Release/SkillAtlas.app --output dist --tag v0.1.0
```

示例标签按当前版本替换；输出目录已有同名资产时工具拒绝覆盖。原有 `python3 scripts/install-macos.py` 保持本机构建与安装方式，默认继续使用本机 `.runtime` 公共连接资料。
