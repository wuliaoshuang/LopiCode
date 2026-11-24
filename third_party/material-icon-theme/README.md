# 文件 / 文件夹 / 语言图标（Material Icon Theme）

文件列表、编辑器标签和语言选择里的图标，来自 npm 包 `material-icon-theme`
（VS Code 扩展 Material Icon Theme 的图标与映射数据，霜霜 2026-11-24 指定用它）。

- 版本：5.40.0（2026-11-24 取，当天 npm 上的最新版）
- 下载地址：https://registry.npmmirror.com/material-icon-theme/-/material-icon-theme-5.40.0.tgz
  （npm 镜像；它会转到同一镜像的 cdn.npmmirror.com 下载）
- 包的完整性校验值（npm 登记的 sha512，下载后核对一致）：
  `sha512-IrvgusbwtqxhUtVgUy0nToJcfN7CYVRdbBxKMfbo0vab9flVBHA5INZ9UiE5SgRj+PM6opCl5nn5TZdpm2UaxA==`
- 包的 sha1（npm 登记的 shasum，核对一致）：`3ffad32f5a2afeefc243b38799ed526189ccbae3`
- 包的 sha256（下载后自己算的）：`6ea13a2dece7ca953c0315b1e93348660c02bb235706275d215be69f09d98efb`
- 项目仓库：https://github.com/material-extensions/vscode-material-icon-theme
- 许可证：MIT，Copyright (c) 2025 Material Extensions。全文见本目录 `LICENSE`（取自包里自带的 LICENSE 文件；
  仓库页面标的也是 MIT License），安装包里的同一份在 `assets/licenses/material-icon-theme-MIT.txt`，
  应用内“设置 › 关于 › 第三方声明”可以看。

## 带了哪些

包里一共 1256 个图标（约 1MB），只带了挑出来的 488 个（281,597 字节，约 275KB），放在 `assets/file_icons/`，
**内容没有改动**，文件名也和包里 `icons/` 下的一样；每个文件的 sha256 在本目录 `SHA256SUMS`
（`test/file_icons_test.dart` 会核对：文件正好是清单里那些、校验值一致、总大小不超过 300KB）。

- 文件与语言图标 278 个：默认文件图标、主流语言、常见配置文件和工具（清单是 `tool/gen_file_icons.py` 里的 `FILE_ICONS`），
  其中 19 个是官方给浅色主题准备的 `名字_light.svg`（原图标在浅色底上看不清的才有）。
- 文件夹图标 210 个：默认文件夹、根文件夹，加 103 种特殊文件夹（清单是 `FOLDER_ICONS`），合上 / 展开各一张。

## 映射表

“扩展名 / 文件名 / 文件夹名 / 语言 id → 图标”取自包里的 `dist/material-icons.json`（官方生成的 VS Code 图标主题清单），
只保留指向已打包图标的条目，由 `tool/gen_file_icons.py` 生成为 `lib/core/file_icons_*_data.dart`。
带路径的文件名条目（如 `.config/xxx`）没有收。查找逻辑在 `lib/core/file_icons.dart`（LopiCode 自己写的）。

## 商标

图标里出现的编程语言、框架和工具的标志与名称是各自所有者的商标。LopiCode 只用它们标明文件是什么类型，
不代表这些所有者与 LopiCode 有合作或认可关系。MIT 许可证只管图标文件本身，不授予任何商标权利。

## 以后要加图标 / 换版本

1. 自己下载包并核对校验值（脚本不联网）。
2. 改 `tool/gen_file_icons.py` 里的 `FILE_ICONS` / `FOLDER_ICONS`，然后：
   `python3 tool/gen_file_icons.py 路径/material-icon-theme-版本.tgz && dart format lib/core/file_icons_*_data.dart`
   （它会重写 `assets/file_icons/`、本目录的 `SHA256SUMS` 和 `LICENSE`、`assets/licenses/material-icon-theme-MIT.txt`、映射表；
   总大小超过 300KB 会直接报错、什么都不动）。
3. 换版本要同时改这里的版本与校验值、`lib/core/third_party.dart` 的 `fileIconPack`、根目录 `README.md` 里的数字。
4. 跑 `flutter test test/file_icons_test.dart`。
