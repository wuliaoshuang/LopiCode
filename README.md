# LopiCode

在手机上通过 Agent 完成代码项目的 Flutter 应用：让 Agent 读写项目文件、跑命令，自己也能改代码、看网页预览、拖拽搭页面、远程打包 APK。界面全部是简体中文，按手机屏幕（390×844）设计，浅色、深色都有。

> 这是第一版。下面“现状”一节写清楚了哪些是测试里跑通的、哪些还没在真机上验证、哪些因为依赖包装不上暂时用了简化实现。

## 功能

| 功能 | 说明 |
| --- | --- |
| 项目 | 项目就是应用文档目录下的文件夹。三种模板：空项目、前端网页（HTML + CSS + JS）、低代码页面。可重命名、删除（要确认） |
| 文件与编辑器 | 文件列表、新建 / 重命名 / 删除；编辑器带标签页和语法高亮（html / css / js / json / dart / yaml / sh / md），保存后预览自动刷新 |
| Agent | 每个项目一个对话。接任何 OpenAI 兼容的 Chat Completions 接口（设置里填接口地址、模型名、API Key）。流式回复；工具：列文件、读文件、写文件、删文件、执行命令、读 / 改低代码页面 |
| 终端 | 基础终端：一次一条命令，多个会话，输入框上方有 Esc / Tab / Ctrl+C / Ctrl+D / 方向键一排 |
| 预览 | 应用内起一个本地 HTTP 服务器，WebView 打开项目网页，相对路径的资源都能加载；手机 / 平板 / 桌面三种宽度；控制台面板显示 console 输出和报错 |
| 低代码 | 组件栏（容器 / 行 / 列 / 卡片 / 文本 / 按钮 / 图片 / 输入框 / 列表 / 分割线 / 间隔）点一下添加或长按拖到画布，可嵌套、排序；选中后改属性（文字、尺寸、内外边距、颜色、对齐、圆角）；图层树；撤销 / 重做。页面存成项目里的 `page.lc.json`，每次保存自动导出 `index.html` + `style.css`（预览直接能看），也可以导出 Flutter 代码到 `export/page.dart` |
| APK 打包 | 手机上跑不了 Android SDK 和 Gradle，所以是“遥控”打包：把项目推到你的 GitHub 仓库 → 触发 GitHub Actions → 等它跑完 → 把 APK 下载回手机。应用里带两份现成的工作流模板（Flutter 项目、网页套壳成 App） |

### Agent 的安全规则写在代码里，不靠提示词

- 路径只能在项目目录内：`..`、绝对路径、符号链接逃逸一律拒绝（`lib/core/path_guard.dart`）。
- 一次请求最多 12 轮工具调用，到了就停。
- 执行命令、删除文件前弹确认卡，你点“允许这一次”才执行；可以在“工具 → 项目设置”里对单个项目开启自动批准。
- API Key 不写进普通设置、不进日志、不出现在报错里。

## 现状（2026-11-23）

**测试里跑通的**（`flutter test`，全在本机，没有调用任何真实接口）：路径限制；Agent 工具循环（对本地假模型服务器，包括模型想逃出项目目录、超过轮数上限、没批准就想执行命令 / 删除、参数乱写、中途停止、Key 不对）；低代码模型 ↔ JSON、撤销重做、HTML 和 Dart 导出（导出的 Dart 代码真的编译并渲染过）；预览服务器；GitHub 客户端和整个打包流程（对本地假 GitHub 服务器）；各主要界面在 390×844 浅色 / 深色下渲染无异常。

**写好了但还没在真机上验证的**：

- **APK 还没打出来过。** 开发环境下载 Gradle 时连接被中断（TLS 握手被对方终止），访问 gradle.org 和 google.com 需要的授权还没批下来。所以 Android 原生那部分（`MainActivity.kt` 里的加密存储）还没编译过。
- WebView 预览、Android 上的 shell、拖拽手感、把 APK 存到手机存储，都需要真机。
- GitHub Actions 打包没有对真实的 GitHub 跑过，两份工作流模板也没在真实的 Actions 上跑过。

**和原计划不一样的地方**（原因都是同一个：开发环境访问 pub.dev 的授权超时了，这几个依赖包装不上）：

| 原计划 | 现在 | 影响 |
| --- | --- | --- |
| 终端用 xterm + flutter_pty | 自己写的基础终端（管道方式跑 `sh`） | 没有真正的终端仿真：`vim`、`top` 这类全屏程序用不了，不能 Tab 补全；Ctrl+C 是结束并重启 shell |
| SSH 终端、SSH 构建机（dartssh2） | **没有** | 终端里 SSH 入口是灰的；APK 打包只有 GitHub Actions 一条路。接口留好了（`TerminalBackend`、`lib/build/remote_exec.dart`） |
| 编辑器用 re_editor | 自己写的输入框 + 正则高亮 | 没有行号、代码折叠、查找替换；大文件会慢 |
| flutter_secure_storage | 自己写的 Android Keystore 通道（AES-256-GCM） | 功能等价，但没编译、没上真机。通道不可用时 Key 只留在内存里，界面会提示 |

**其他已知限制**

- 手机自带的 `sh` 只有 `ls`、`cat`、`cp`、`mkdir` 这类基础命令，没有 git、node、python 和编译器。终端里也写了这句话。
- 低代码：一行里固定宽度的组件加起来超过屏幕宽度时，导出的 Flutter 页面会溢出（调试模式下出现黄黑条）。
- 导出的 Flutter 代码用 `package:flutter/material.dart`，各版本 Flutter 都认；Flutter 3.47 以后会有一条“已弃用”的提示，不影响运行。
- 推送项目文件时跳过单个超过 5 MB 的文件和 `.lopicode/` 内部目录。
- GitHub Token 要有仓库的 Contents、Actions 读写权限；要推送 `.github/workflows/` 下的文件还需要 Workflows 权限。

## 目录结构

```
lib/
  main.dart, app.dart          入口
  app_services.dart            全局服务（设置、密钥、项目仓库）
  project_session.dart         打开一个项目后的状态（终端、预览服务器、Agent 对话）
  core/                        路径守卫、项目仓库、模板、设置与密钥存储
  agent/                       Chat Completions 客户端、工具箱、工具循环、命令执行
  terminal/                    终端会话与后端接口
  preview/                     本地预览服务器
  lowcode/                     页面模型、HTML 导出、Dart 导出、搭建器界面
  build/                       GitHub 客户端、打包流程、打包界面、工作流模板
  theme/                       设计 tokens（颜色、间距、圆角、字号）和主题
  ui/                          项目列表、项目主界面的五个标签页、设置、通用组件
test/                          单元测试、界面测试；support/ 里是假模型服务器等
tool/gen_sample_export.dart    重新生成 Dart 导出的编译检查样本
docs/api-notes.md              OpenAI / GitHub 接口核对笔记
docs/screenshots/              390×844 截图（浅色、深色）
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
