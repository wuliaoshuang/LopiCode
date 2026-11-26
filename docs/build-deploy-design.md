# 打包页按项目类型区分：后端项目的“构建与部署”（设计）

2026-11-26。霜霜原话：“后端项目默认打包形式应该和 apk 区分开。本地打包就是能编译的就编译。github 和 ssh，这两个分别是推送代码并启动部署工作流和操作 ssh 直接编译部署。”

这份文档先写、后实现。实现和这里不一致的地方以文末“实施记录”为准。

## 1. 项目类型怎么认

三类：**网页类**（走现在的 APK 流程，一行为不变）、**后端类**（换成“构建与部署”）、**其它类**（Flutter / 原生等，保持现状：远程打 APK）。

识别是同步的、只看文件在不在（最多读一个不超过 2 MB 的 package.json 和 backend.lc.json），不起进程。代码在 `lib/build/deploy_project.dart` 的 `detectDeployProject`。按下面顺序，先中先算：

1. **她手动选过**（设置键 `deploy.kind.<工作区 id>`＝`web` / `backend` / `other`）：照她选的。
2. 根目录有 `pubspec.yaml`，或有 Gradle 文件并且有 `AndroidManifest.xml`（`app/src/main/` 或 `src/main/`）：**其它类**。
3. 模板标记是“后端服务（积木）”“后端服务（代码）”：**后端类**。
4. 模板标记是“前端网页”“低代码页面”“前端 + 后端”，并且网页还在（根目录 `index.html` / `page.lc.json` / `web/index.html`）：**网页类**。
   “前端 + 后端”默认算网页类（和现在一样把 `web/` 打成 APK）；要部署它的后端，手动把类型改成“后端”。
5. 根目录有 `page.lc.json`、`index.html`，或 `package.json` 里有 build 脚本（要构建的前端工程）：**网页类**。
6. 有后端特征：**后端类**。在根目录找，找不到再依次看 `server/`、`backend/`、`api/`：
   - `backend.lc.json`（后端积木；语言读文件里的 `language`）
   - Go：`go.mod` 或 `main.go`
   - Java：`pom.xml`、不带安卓清单的 `build.gradle(.kts)`、目录里有 `*.java`、或有 `src/main/java`
   - Python：`requirements.txt`、`pyproject.toml`、目录里有 `*.py`
   - PHP：`composer.json`、目录里有 `*.php`
   - Node：`package.json`（没有 build 脚本）、或 `server.js` / `index.js` / `app.js` / `main.js`
7. `dist`、`build`、`out`、`www`、`public`、`web` 里有 `index.html`：**网页类**。
8. 都不是：**其它类**。

语言：Node / Python / Go / Java / PHP 五种有完整支持；后端类但语言不在这五种里的（起步模板里的 Rust、Ruby、Kotlin、C#、Dart）记为“其它语言”：本地只打压缩包、GitHub 只上传源码产物、SSH 的编译命令留空让她自己填。

认错了能手动改：后端页最上面有一行“项目类型”；网页 / 其它页为了不改现有页面，入口放在顶栏右上角的图标里。选择按工作区记住，可以改回“自动识别”。

Java 再分四种结构：`flat`（所有 `.java` 在同一个目录、都不带 `package`——后端积木生成的和“后端 · 代码”起步模板都是这种）、`maven`（有 `pom.xml`）、`gradle`、`packaged`（带包名或 `src/main/java` 但没有构建文件）。

## 2. 三种方式

三选一还是 本地 / GitHub / SSH，标签换成“本地构建”“GitHub 部署”“SSH 部署”。选哪种按工作区记（设置键 `deploy.mode.<工作区 id>`，没存过＝本地），和 APK 的 `apk.buildMode` 互不影响。

### 2.1 本地：能编译的就编译

都在手机的 Ubuntu 运行环境里做（桌面调试 / 宿主机测试没装环境时用本机 shell）。

步骤：
1. 运行环境没装：不开始，页面上是一张引导卡，按钮“去装运行环境”打开“运行环境”页。
2. 核对这种语言的工具在不在（先看文件，再进 Ubuntu `command -v`）。不在就替她装（同 `backend_run`：清单和脚本在 `runtime_sources.dart`）；下载量过 100 MB 的（JDK）先问一次。输出实时可见，可取消。
3. 按语言跑命令（全文见 §4）：
   - Go → 可执行文件 `build/<名字>-linux-arm64`；开关“给服务器用（linux/amd64）”打开时是 `-linux-amd64`。纯环境变量交叉编译，`CGO_ENABLED=0`。
   - Java（`flat` 结构）→ `build/<名字>.jar`（`javac` + `jar`，不用 Maven / Gradle）。其余三种结构本地不支持，页面写清原因并建议改用 GitHub / SSH（那两种用 `mvn` / `gradle`）。
   - Node / Python / PHP：语法检查（`node --check`、`python3 -m py_compile`、`php -l`，逐个文件）→ 打成 `build/<名字>-<语言>.tar.gz`。
     依赖默认**不装进包**：`requirements.txt`、`composer.json` 只在结果卡里提醒“到服务器上装”；Node 有一个开关“把依赖装进包（npm install --omit=dev）”，默认关（node_modules 里常有按 CPU 架构编译的东西，手机 arm64 装的放到 amd64 服务器上会坏）。
   - 其它语言：只打压缩包。
4. 压缩包由应用自己打（现有依赖 `archive`，tar + gzip，在后台 isolate 里），不靠 Ubuntu 里的 tar。包里一层目录 `<名字>/`。

产物在工作区 `build/`；结果卡写文件名、大小、位置、怎么用。失败讲清停在哪一步、退出码，命令输出留在卡片里。取消＝停掉正在跑的命令（整棵进程树）。

### 2.2 GitHub：推送代码并启动部署工作流

沿用现有 GitHub 设置（`github.owner` / `github.repo` / `github.ref`，令牌在安全存储 `github_token`）和 `GitHubClient`。工作流文件名单独记（`github.deployWorkflow`，默认 `deploy.yml`），不和 APK 的 `android.yml` 混。

步骤：
1. 填仓库、分支、令牌（和 APK 那边是同一份）。
2. 工作流：一行“查看 / 修改工作流”打开面板，里面是按语言生成的全文，可以改；点“写进项目”才写到 `.github/workflows/deploy.yml`（已有同名文件会先问要不要覆盖）。
   模板默认只“构建并上传产物”；部署步骤在模板里但默认不跑（触发时 `deploy` 输入为 false），要跑需要她在 GitHub 仓库 Settings › Secrets and variables › Actions 里配 `DEPLOY_HOST`、`DEPLOY_USER`、`DEPLOY_SSH_KEY`、`DEPLOY_PATH`。模板里只有 `${{ secrets.XXX }}` 占位，**任何密钥都不写进工作流文件和仓库**。
3. 点“推送并启动”→ 先出确认清单：仓库 / 分支、要推的文件（可展开）、被挡在外面的文件和原因、接下来会做的事（推送、触发）。她点“确认”才动。
4. 推送（一次提交，只增改不删）→ 触发 `workflow_dispatch` → 轮询运行状态 → 显示结论和运行页链接。

失败处理：
- 403 并且这次推送里有工作流文件：大白话告诉她缺的是“改工作流文件”的权限——细粒度令牌要给这个仓库开 **Workflows：Read and write**，经典令牌要勾 **workflow**，到 GitHub › Settings › Developer settings › Personal access tokens 里改。
- 超时 / 连不上：用 `GitHubClient` 现成的人话。
- 工作流跑失败：给运行页链接看日志。
- 取消＝停止等待（已触发的运行不会被取消，说明白）。

运行页链接：应用现在没有“打开外部浏览器”的能力（要加原生代码或新依赖，这次不允许），所以是“复制链接”。见“要霜霜定的事”。

### 2.3 SSH：连主机直接编译部署

沿用现有 SSH 主机配置（`ssh.*`）、指纹确认和 `RemoteExec`。

步骤（开始前把每一步要执行的命令完整列成清单，她确认后才跑）：
1. 建目录：`mkdir -p <远程目录>`（默认 `~/lopicode-deploy/<名字>`，可改，按工作区记）。
2. 上传：把代码打成一个 `lopicode-upload.tar.gz`，SFTP 传到远程目录里。
3. 解压：`tar -xzf lopicode-upload.tar.gz --strip-components=1`。同名文件会被覆盖，远端多出来的文件**不动**；传上去的压缩包留在原地（下次覆盖），不删。
4. 编译 / 装依赖：按语言给默认命令（§4），可改，可留空跳过。
5. 重启服务（默认关）：她自己填命令。

某一步失败就停，讲清是第几步、退出码；输出实时可见；取消＝断开连接。默认命令里没有任何删除远端东西的命令。她自己填的命令原样执行，但开始前会原样显示在清单里。

## 3. 安全边界

**不会被推送 / 上传 / 打进压缩包的**（`lib/build/deploy_files.dart`，三种方式共用一份规则）：
- 目录：顶层的 `.lopicode`、`build`；任何一层的 `.git`、`node_modules`（本地打包打开“把依赖装进包”时例外）、`__pycache__`、`.venv`、`venv`、`.gradle`、`.idea`。
- 密钥类文件（不分大小写，任何一层）：`.env*`、`*.pem`、`*.key`、`*.p12`、`*.pfx`、`*.jks`、`*.keystore`、`id_rsa*`、`id_dsa*`、`id_ecdsa*`、`id_ed25519*`、`credentials*`、`.netrc`、`.npmrc`、`.pypirc`、签名钥匙备份（`lopicode-key-backup-*`）。
- `*.class`、`*.pyc`、`*.apk`。
- 符号链接（一律不跟）。
- 太大的单个文件（见下）。
被挡掉的在确认清单里列出来（文件 + 原因），不是悄悄丢掉。

**上限（自定）**：GitHub 推送最多 2000 个文件、单个 5 MB、总共 50 MB；SSH 上传 / 本地压缩包最多 5000 个、单个 50 MB、总共 100 MB。单个超限的跳过并列出；个数或总量超限直接不做，告诉她超了多少。

**要她亲手确认的**：写工作流文件、推送＋触发、SSH 的整张命令清单、过 100 MB 的语言安装。**令牌 / 密码**只从安全存储读，不进日志、不进状态、不进报错。

## 4. 默认命令全文

下面 `D`＝后端所在目录（根目录时是 `.`），`N`＝工作区 id 收拾成只含字母数字 `._-` 的名字。

本地（在工作区根目录执行）：

| 语言 | 步骤 | 命令 |
| --- | --- | --- |
| Go | 编译 | `OUT="$PWD/build"; mkdir -p "$OUT" && cd 'D' && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -buildvcs=false -o "$OUT/N-linux-arm64" .`（amd64 时两处 arm64 换成 amd64） |
| Java | 编译并打 jar | `OUT="$PWD/build"; rm -rf "$OUT/classes-N" && mkdir -p "$OUT/classes-N" && cd 'D' && javac -encoding UTF-8 -d "$OUT/classes-N" *.java && jar --create --file "$OUT/N.jar" --main-class 主类 -C "$OUT/classes-N" .` |
| Node | 语法检查 | `cd 'D' && find . -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -not -path './node_modules/*' -not -path './build/*' -not -path './.lopicode/*' -print0 \| xargs -0 -r -n 1 node --check` |
| Node | 装依赖（开关，默认关） | `cd 'D' && npm install --omit=dev` |
| Python | 语法检查 | `cd 'D' && find . -type f -name '*.py' -not -path './.venv/*' -not -path './venv/*' -not -path './build/*' -not -path './.lopicode/*' -print0 \| PYTHONPYCACHEPREFIX=/tmp/lopicode-pyc xargs -0 -r python3 -m py_compile` |
| PHP | 语法检查 | `cd 'D' && find . -type f -name '*.php' -not -path './vendor/*' -not -path './build/*' -not -path './.lopicode/*' -print0 \| xargs -0 -r -n 1 php -l` |

本地 Java 那条里的 `rm -rf` 只删工作区 `build/` 下我们自己上一次留下的 class 目录（不删的话旧 class 会混进新 jar）。

SSH（在远程目录里执行）：

| 情况 | 默认的“编译 / 装依赖”命令 |
| --- | --- |
| Go | `go build -buildvcs=false -o server .` |
| Java · flat | `javac -encoding UTF-8 -d out *.java` |
| Java · maven | `mvn -B package` |
| Java · gradle | `gradle build` |
| Java · packaged | （空，她自己填） |
| Node，有 package.json | `npm install --omit=dev` |
| Node，没有 | `node --check 入口文件` |
| Python，有 requirements.txt | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` |
| Python，没有 | `python3 -m py_compile 入口文件` |
| PHP，有 composer.json | `composer install --no-dev` |
| PHP，没有 | `php -l 入口文件` |
| 其它语言 | （空） |

固定的三步：`mkdir -p 远程目录`、上传（先 `cd 远程目录 && pwd` 查出完整路径，再用 SFTP 传 `lopicode-upload.tar.gz`）、`cd 远程目录 && tar -xzf lopicode-upload.tar.gz --strip-components=1`。

GitHub 工作流模板按语言生成（`lib/build/deploy_workflows.dart`），构建步骤和上表 SSH 的命令是同一套思路；全文在应用里“查看 / 修改工作流”能看到。

## 5. 和现有 APK 流程怎么共存

- `build_screen.dart` 只加分叉：先认类型；后端类把标题换成“构建与部署”、正文换成新面板 `DeployPanel`；网页 / 其它类正文一行不动，只在顶栏右上角多一个“项目类型”图标。
- 任何一边正在跑的时候不切类型（不然进度就看不到了）。
- `apk.buildMode`、三张 APK 表单、它们的设置键都不动。新东西全在新文件里：`lib/build/deploy_*.dart`、`lib/state/deploy_*.dart`。
- 状态照 AGENTS.md：不可变快照 + Notifier，按工作区分身，带代次；取消、工作区关掉以后回来的结果丢掉。

## 6. 页面结构（390×844，Refactoring UI：先层级、再排版、最后上色）

后端页从上到下，一行只做一件事：

1. 项目类型（一行，可点）：“后端 · Go（自动识别）”。
2. 三选一轨道：本地构建 / GitHub 部署 / SSH 部署；下面一句弱色小字说明这种方式做什么。
3. 这种方式的分组卡片（和设置页同一套）：
   - 本地：① 这次会做什么（步骤清单，只读）→ ② 选项（Go 的 amd64 开关 / Node 的依赖开关；没有选项的语言不出现这组）→ 主按钮“开始构建”。
   - GitHub：① 仓库（仓库、分支、令牌各一行）→ ② 工作流（文件名一行、“查看 / 修改工作流”一行、“要部署到服务器需要配的 Secrets”一行）→ 主按钮“推送并启动”。
   - SSH：① 主机（一行跳转）→ ② 目录与命令（远程目录、编译命令、重启开关、重启命令各一行）→ 主按钮“查看步骤并开始”。
4. 进度 / 结果卡（和 APK 的进度卡同一个样子）：一句结论最显眼 → 失败原因 / 产物位置 → 过程（弱色小字）→ 命令输出（等宽框）。

层级：主按钮每种方式只有一个；确认清单、文件清单、工作流全文都收进底部面板。颜色：强调色只给选中的方式、主按钮、“完成”；红色只给失败。

## 7. 没法在这里验证的

- 手机 PRoot 里 Go / Java 真编译、npm install：开发机是 x86、没有手机的 Ubuntu 环境，验证不了。命令本身在开发机上对样例项目真跑（结果见实施记录）。
- 工作流模板没在真实的 GitHub Actions 上跑过；没有对真实 GitHub 发过请求；没有连过真实 SSH 主机。
