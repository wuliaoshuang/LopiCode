# 服务商图标（Lobe Icons）

“模型与渠道”里各家服务商的图标，来自 npm 包 `@lobehub/icons-static-svg`。

- 版本：1.106.0（2026-11-23 取）
- 下载地址：https://registry.npmmirror.com/@lobehub/icons-static-svg/-/icons-static-svg-1.106.0.tgz
- 包的完整性校验值（npm 登记的 sha512，下载后核对一致）：
  `sha512-yRLkEGfCKg7ztuAmwPKOlRY2nDvB6GJHtHvb8YGWZaZkCzMXrUOcvUbTNO3RDE0QVrR/nYD7p5oPWhUTpEi/uA==`
- 项目仓库：https://github.com/lobehub/lobe-icons
- 许可证：MIT，Copyright (c) 2023 LobeHub。全文见本目录 `LICENSE`（取自仓库 master 分支的 LICENSE 文件），
  安装包里的同一份在 `assets/licenses/lobe-icons-MIT.txt`，应用内“设置 › 关于 › 第三方声明”可以看。

## 带了哪些

只带预设用到的 18 个文件，放在 `assets/provider_icons/`，**内容没有改动**；每个文件的 sha256 在本目录 `SHA256SUMS`
（`test/provider_presets_test.dart` 会核对：文件正好是预设用到的那些、校验值一致）。

文件名不带 `-color` 的是单色图标（用 `currentColor`），应用里按深浅色着色；带 `-color` 的是彩色版，原样显示。

## 商标

图标里的品牌标志和名称是各家公司的商标，归它们各自所有。LopiCode 只用它们标明渠道连的是哪家服务，
不代表这些公司与 LopiCode 有合作或认可关系。MIT 许可证只管图标文件本身，不授予任何商标权利。

## 以后要加图标

1. 从同一个版本的包里取 `icons/{id}.svg`（换版本要同时改这里、`lib/core/third_party.dart` 的 `providerIconPack`）。
2. 放进 `assets/provider_icons/`，重新生成 `SHA256SUMS`（`cd assets/provider_icons && sha256sum *.svg > ../../third_party/lobe-icons/SHA256SUMS`）。
3. 预设的接口地址必须先对着官方文档核对，记进 `docs/api-notes.md`。
