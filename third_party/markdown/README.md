# markdown（Dart 官方的 Markdown 解析包）

聊天正文渲染 Markdown 时用它**只做解析**（把文字变成语法树）；怎么画出来是我们自己写的（`lib/markdown/`、`lib/ui/md_*.dart`），
没有用它的 HTML 输出，也没有用任何带界面的 Markdown 包。

- 版本：7.3.1（2026-11-26 加，`pubspec.yaml` 里写的是 `^7.3.1`，实际版本以 `pubspec.lock` 为准）
- 来源：https://pub.dev/packages/markdown
- pub 登记的包校验值（sha256，记在 `pubspec.lock`）：`ee85086ad7698b42522c6ad42fe195f1b9898e4d974a1af4576c1a3a176cada9`
- 许可证：BSD-3-Clause。全文见本目录 `LICENSE`（从 pub 缓存里的包原样拷的）。
- 纯 Dart，没有原生代码，不要任何权限。加它之前不在 `pubspec.lock` 里（不是别的包带进来的）。

代码是通过 pub 取的，**没有拷进仓库、没有改动**。和别的 Dart / Flutter 依赖一样，它的许可证由 Flutter 在打包时自动收进应用的许可证页；
所以没有登记进 `lib/core/third_party.dart`（那里只登记随安装包分发的原生文件和图标，并有测试逐个核对文件）。
