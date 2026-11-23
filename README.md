# LopiCode

在手机上通过 Agent 完成代码项目的 Flutter 应用：让 Agent 读写项目文件、跑命令，自己也能改代码、看网页预览、拖拽搭页面、远程打包 APK。界面全部是简体中文，按手机屏幕（390×844）设计，浅色、深色都有。

> 这是第一版。下面“现状”一节写清楚了哪些是测试里跑通的、哪些还没在真机上验证。

## 功能

| 功能 | 说明 |
| --- | --- |
| 项目 | 项目就是应用文档目录下的文件夹。三种模板：空项目、前端网页（HTML + CSS + JS）、低代码页面。可重命名、删除（要确认） |
| 文件与编辑器 | 文件列表、新建 / 重命名 / 删除；编辑器带标签页、行号、语法高亮、查找替换、撤销重做，保存后预览自动刷新 |
| Agent | 每个项目一个对话。接任何 OpenAI 兼容的 Chat Completions 接口（设置里填接口地址、模型名、API Key）。流式回复；工具：列文件、读文件、写文件、删文件、执行命令、读 / 改低代码页面 |
| 终端 | 终端仿真（xterm），多个会话：本机 shell（伪终端）或 SSH 远程主机；底下一排 Esc / Tab / Ctrl（粘滞）/ 方向键 / 常用符号 |
| 预览 | 应用内起一个本地 HTTP 服务器，WebView 打开项目网页，相对路径的资源都能加载；手机 / 平板 / 桌面三种宽度；控制台面板显示 console 输出和报错 |
| 低代码 | 组件栏（容器 / 行 / 列 / 卡片 / 文本 / 按钮 / 图片 / 输入框 / 列表 / 分割线 / 间隔）点一下添加或长按拖到画布，可嵌套、排序；选中后改属性（文字、尺寸、内外边距、颜色、对齐、圆角）；图层树；撤销 / 重做。页面存成项目里的 `page.lc.json`，每次保存自动导出 `index.html` + `style.css`（预览直接能看），也可以导出 Flutter 代码到 `export/page.dart` |
| APK 打包 | 手机上跑不了 Android SDK 和 Gradle，所以是“遥控”打包，两种方式：① 把项目推到你的 GitHub 仓库 → 触发 GitHub Actions → 等它跑完 → 把 APK 下载回手机（带两份现成的工作流模板：Flutter 项目、网页套壳成 App）；② SSH 构建机：把项目传到你的服务器 → 运行你填的构建命令（日志实时显示）→ 用 SFTP 把 APK 拉回手机 |

### Agent 的安全规则写在代码里，不靠提示词

- 路径只能在项目目录内：`..`、绝对路径、符号链接逃逸一律拒绝（`lib/core/path_guard.dart`）。
- 一次请求最多 12 轮工具调用，到了就停。
- 执行命令、删除文件前弹确认卡，你点“允许这一次”才执行；可以在对话页右上角 ⋮ 菜单（或输入卡片里的盾牌按钮）里对单个项目开启自动批准。
- API Key 不写进普通设置、不进日志、不出现在报错里。

## 现状（2026-11-23）

**测试里跑通的**（`flutter test`，166 个，全在开发机上，没有调用任何真实接口）：路径限制；Agent 工具循环（对本地假模型服务器，包括模型想逃出项目目录、超过轮数上限、没批准就想执行命令 / 删除、参数乱写、中途停止、Key 不对）；低代码模型 ↔ JSON、撤销重做、HTML 和 Dart 导出（导出的 Dart 代码真的编译并渲染过）；预览服务器；GitHub 客户端和整个打包流程（对本地假 GitHub 服务器）；各主要界面在 390×844 浅色 / 深色下渲染无异常。第二阶段新增：

- 密钥存储包装（对假的安全后端）：读写删；插件缺失或系统密钥库报错时退回内存并如实标成“不持久”。
- 终端：伪终端能开时按键原样送进去、窗口大小跟着变、shell 退出后回车重开；伪终端开不出来时退回管道模式并在屏幕上说明；粘滞 Ctrl、方向键 / Tab / Esc 的转义序列。
- SSH：表单校验；首次连接指纹确认、指纹变了拒绝、忘记后重新问；错误说明；连一个没人监听的本机端口、连一个不是 SSH 的本机假服务。
- SSH 构建流程（对假的远程执行器）：上传 → 构建 → 下载；命令失败、APK 路径不对、连不上、中途停止。
- 编辑器：打开文件有行号；查找并替换、全部替换、保存落盘。

**写好了但还没在真机上验证的**：

- **真实的 SSH 连接一次都没连过。** 开发机上没有 SSH 服务端，测试里用的是假的执行器和假服务；登录、远程 shell、SFTP 上传下载都没有对真实服务器跑过。
- **真正的伪终端没跑过。** 开发机的测试加载不了 flutter_pty 的原生库，测试里的终端截图是“退回管道模式”的样子；`vi`、`top`、Tab 补全要在真机上看。
- flutter_secure_storage 在真机上的读写（测试里是假的后端）。
- 编辑器在触屏上的手感（选区、长按菜单、软键盘遮挡）。
- WebView 预览、拖拽手感、把 APK 存到手机存储。
- GitHub Actions 打包没有对真实的 GitHub 跑过，两份工作流模板也没在真实的 Actions 上跑过。

**四处原先的简化实现，现在都换回了原计划**：

| 部分 | 现在用的 | 说明 |
| --- | --- | --- |
| 终端 | xterm 4.0.0 + flutter_pty 0.4.2 | 真正的终端仿真。伪终端开不出来时自动退回“一次一条命令”的管道模式，屏幕上会写明 |
| SSH 终端、SSH 构建机 | dartssh2 4.1.0 | 终端 ＋ 里可以连 SSH 主机；APK 打包页可以选“SSH 构建机”。两处共用一台主机的设置。第一次连接要确认主机指纹，之后指纹变了会拒绝连接 |
| 编辑器 | re_editor 0.10.0 | 行号、语法高亮、查找替换、撤销重做、自动换行开关 |
| 密钥存储 | flutter_secure_storage 11.2.0 | 手写的 Keystore 通道已删。因此最低支持 Android 7.0（minSdk 24） |

**其他已知限制**

- 本机 Linux 运行环境的应用侧逻辑（下载续传、校验、解压、PRoot 命令拼装、启动失败回退、Agent 命令走向）有测试；PRoot 已带进包，但真机上一次都没跑过，能不能启动未知。
- 手机自带的 `sh` 只有 `ls`、`cat`、`cp`、`mkdir` 这类基础命令，没有 git、node、python 和编译器。终端里也写了这句话；要完整工具链就连 SSH 主机。
- SSH 只存一台主机（终端和构建机共用）；Agent 自己跑的命令仍然在本机 shell 里，不走 SSH。
- SSH 构建时点“停止并断开”是断开连接，远程命令一般会随会话结束，但不保证。
- 编辑器只高亮 HTML / CSS / JS / TS / JSON / Dart / Markdown / YAML / Shell / Kotlin / Python；没有代码折叠。
- 低代码：一行里固定宽度的组件加起来超过屏幕宽度时，导出的 Flutter 页面会溢出（调试模式下出现黄黑条）。
- 导出的 Flutter 代码用 `package:flutter/material.dart`，各版本 Flutter 都认；Flutter 3.47 以后会有一条“已弃用”的提示，不影响运行。
- 推送项目文件时跳过单个超过 5 MB 的文件和 `.lopicode/` 内部目录。
- GitHub Token 要有仓库的 Contents、Actions 读写权限；要推送 `.github/workflows/` 下的文件还需要 Workflows 权限。

## 本机 Linux 运行环境（进行中）

侧边栏“运行环境”：在手机上用 PRoot 跑一个不需要 root 的 Ubuntu 24.04，让终端和 Agent 能用 apt、node、python。系统包不在安装包里，点“安装运行环境”才下载（约 28.5 MB，解压后约 103 MB），支持断点续传和校验，下载源可在清华、阿里云、官方之间切换。

PRoot 启动器已随安装包带上（Termux 官方软件源的现成包，文件没有改动），“运行环境”页有安装按钮。**这部分没有在任何手机上跑过**，PRoot 能不能启动要真机验证；启动不了时终端会自动退回本机 shell 并在“运行环境”页的日志里写明原因。细节见 [docs/linux-runtime.md](docs/linux-runtime.md)。

## 第三方声明

- 安装包内的 Dart / Flutter 依赖见 `pubspec.yaml`，各自的许可证由 Flutter 的许可证页面汇总。
- 随安装包分发的三个原生组件（应用内“设置 › 第三方声明”有同样的内容和许可证全文）：

| 组件 | 版本 | 许可证 | 安装包里的文件 | 对应源码 |
| --- | --- | --- | --- | --- |
| PRoot（Termux 版） | 5.1.107.102 | GPL-2.0-or-later | `libproot.so`、`libproot-loader.so` | https://github.com/termux/proot/archive/v5.1.107.102.zip |
| talloc | 2.5.0 | LGPL-3.0-or-later | `libtalloc.so` | https://www.samba.org/ftp/talloc/talloc-2.5.0.tar.gz |
| libandroid-shmem | 0.7 | BSD-3-Clause | `libandroid-shmem.so` | https://github.com/termux/libandroid-shmem |

  二进制取自 Termux 官方软件源 `https://packages.termux.dev/apt/termux-main`，内容没有改动，只改了文件名。每个文件的来源地址、sha256、版权声明见 [third_party/termux/README.md](third_party/termux/README.md)；许可证全文在 [third_party/termux/licenses/](third_party/termux/licenses/)；还没做到的地方（仓库里没有存源码副本等）见 [docs/linux-runtime.md](docs/linux-runtime.md) 的“许可证”一节。
- Ubuntu 基础系统、Node.js、Python、Git：由用户在应用内点击后从上游或镜像下载，不随安装包分发。
- dsh-Go（AGPL-3.0）只作为做法参考，没有使用它的代码。

## 目录结构

```
lib/
  main.dart, app.dart          入口
  app_services.dart            全局服务（设置、密钥、项目仓库）
  project_session.dart         打开一个项目后的状态（终端、预览服务器、Agent 对话）
  core/                        路径守卫、项目仓库、模板、设置与密钥存储
  agent/                       Chat Completions 客户端、工具箱、工具循环、命令执行
  terminal/                    终端会话（xterm）、本机后端（flutter_pty，回退管道）
  ssh/                         SSH 主机设置、连接与指纹核对、远程终端后端、主机表单
  preview/                     本地预览服务器
  lowcode/                     页面模型、HTML 导出、Dart 导出、搭建器界面
  build/                       GitHub 客户端与打包流程、SSH 构建（remote_exec、ssh_build_controller）、打包界面、工作流模板
  theme/                       设计 tokens（颜色、间距、圆角、字号）和主题
  ui/                          界面。没有底部导航，所有去处都在侧边栏里：
    home_gate.dart             打开应用先到哪：上次的项目，或项目列表
    shell.dart                 统一顶栏（汉堡按钮 + 两行标题）和侧边栏
    project_shell.dart         项目外壳：对话页为主屏，侧边栏去文件 / 终端 / 预览 / 低代码搭建 / APK 打包
    chat_screen.dart           Agent 对话：大圆角输入卡片、确认卡、工具调用、项目规则、多段对话
    code_editor.dart           re_editor 编辑区和手机宽度的查找 / 替换面板
    files_tab / terminal_tab / preview_tab / project_list_screen / settings_screen / widgets
test/                          单元测试、界面测试；support/ 里是假模型服务器等
tool/gen_sample_export.dart    重新生成 Dart 导出的编译检查样本
docs/api-notes.md              OpenAI / GitHub 接口核对笔记
docs/screenshots/              390×844 截图（浅色、深色）
assets/licenses/               随包组件的许可证全文（应用内“第三方声明”读这里）
third_party/termux/            PRoot 等随包二进制的来源记录、原始包、校验值、许可证
```

## 怎么构建

需要 Flutter 3.50.1（稳定版）、JDK 21、Android SDK（platform 36、build-tools 36.0.0）。

```
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

- 重新生成截图：`LOPI_SHOTS=1 flutter test test/screens_test.dart`（需要系统里有 Noto Sans CJK 字体）。
- 改了 Dart 导出器之后：`dart run tool/gen_sample_export.dart`。
- 内存紧张的机器：`android/gradle.properties` 里已经把 Gradle 堆限制在 1536 MB、关掉守护进程。
