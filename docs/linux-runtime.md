# 本机 Linux 运行环境（PRoot + Ubuntu 24.04）

写于 2026-11-23。下面每一条都标了“核实过”还是“没核实”。**整套东西没有在任何手机上跑过。**

## 现在的状态：PRoot 已随安装包带上，但从没在手机上跑过

2026-11-23 霜霜决定：接受 GPL 义务，带上 PRoot，来源用 Termux 官方现成包。现在安装包的 `lib/arm64-v8a/` 里有四个文件：

| 安装包里的名字 | Termux 包里的原名 | 作用 |
| --- | --- | --- |
| `libproot.so` | `usr/bin/proot` | PRoot 本体 |
| `libproot-loader.so` | `usr/libexec/proot/loader` | PRoot 启动 Ubuntu 里每个程序时用的加载器 |
| `libtalloc.so` | `usr/lib/libtalloc.so.2.5.0` | PRoot 依赖的库 |
| `libandroid-shmem.so` | `usr/lib/libandroid-shmem.so` | PRoot 依赖的库 |

文件内容和 Termux 包里的逐字节一致，只改了文件名（Android 只会把 `lib*.so` 这种名字的文件装进原生库目录）。来源、版本、校验值、许可证见 [`third_party/termux/README.md`](../third_party/termux/README.md)。

“运行环境”页现在有“安装运行环境”按钮。**但 PRoot 在手机上能不能跑起来完全没有验证过**：这些文件在开发机上只用 `readelf`、`strings` 这类只读工具看过，没有执行过，也没有编译过任何 PRoot 源码。

## 做法

| 环节 | 做法 | 核实情况 |
| --- | --- | --- |
| PRoot 放哪 | 四个文件按 `lib*.so` 命名放 jniLibs，装好后在应用的原生库目录里，从那里执行 | 文件已在安装包里（验过包）；真机没验证 |
| 安装包设置 | `useLegacyPackaging = true` ＋ `extractNativeLibs="true"`，让系统把 .so 解到磁盘上（不解出来就没有可执行的文件） | 设置已写入并能打包；真机没验证 |
| Ubuntu 系统包 | 进应用后点“安装运行环境”才下载，解到应用私有目录 `files/…/runtime/rootfs` | 下载、校验、解压在开发机上用真实文件跑过 |
| 启动 | 在伪终端里跑 `libproot.so … /usr/bin/env -i … /bin/bash -l` | 只验证了参数拼装；没有真的启动过 |
| 保活 | 有 Ubuntu 会话或 Agent 命令在跑时开前台服务 ＋ 常驻通知，都关了就撤 | 代码能编译；真机没验证 |

### 启动命令

```
环境变量：PROOT_LOADER=<原生库目录>/libproot-loader.so
          PROOT_TMP_DIR=<runtime>/tmp
          LD_LIBRARY_PATH=<runtime>/hostlib:<原生库目录>
          LD_PRELOAD=（清空）
          PROOT_NO_SECCOMP=1（只在兼容模式下）
<原生库目录>/libproot.so --kill-on-exit --link2symlink -0
  -r <rootfs> -b /dev -b /proc -b /sys -b <rootfs>/tmp:/dev/shm
  -b <项目目录>:/workspace -w /workspace
  /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
     TMPDIR=/tmp TERM=xterm-256color LANG=C.UTF-8 … /bin/bash -l
```

- 这些参数和环境变量名最早是从 termux/proot 源码（提交 `7cbed09235d18cdb4be8eed456038608c10a29a0`，VERSION 5.1.0）的 `src/cli/proot.h` 和 `src/execve/enter.c` 里**读**出来的；2026-11-23 又对着实际带进包的 5.1.107.102 二进制用 `strings` 核对过：`PROOT_LOADER`、`PROOT_TMP_DIR`、`PROOT_NO_SECCOMP`、`--kill-on-exit`、`--link2symlink`、`--rootfs`、`--bind`、`--cwd`、`--root-id` 这些字样都在。只读了文字，没有运行。
- `env -i` 把 Android 塞进来的变量全部清掉，只留上面列的几个（`LD_LIBRARY_PATH` 也不会带进 Ubuntu）。
- DNS：安装时写 `/etc/resolv.conf`（223.5.5.5、119.29.29.29、8.8.8.8）和 `/etc/hosts`。
- apt：写 `/etc/apt/sources.list.d/ubuntu.sources`（arm64 走 ubuntu-ports），并关掉 apt 的降权沙箱（PRoot 里的 root 是假的，切不了用户）。

### Termux 的包是给 Termux 自己的目录编的，这里怎么对上

用 `readelf` 和 `strings` 看到的事实（2026-11-23）：

| Termux 包里写死的 | 在 LopiCode 里的问题 | 怎么处理 |
| --- | --- | --- |
| 加载器默认在 `/data/data/com.termux/files/usr/libexec/proot/loader` | 这个路径在 LopiCode 里不存在 | 设 `PROOT_LOADER` 指到原生库目录的 `libproot-loader.so` |
| 临时目录默认 `/data/data/com.termux/files/usr/tmp/` | 同上 | 设 `PROOT_TMP_DIR` 指到 `<runtime>/tmp` |
| 找依赖库的路径（RUNPATH）是 `/data/data/com.termux/files/usr/lib` | 同上，系统在那里找不到库 | 设 `LD_LIBRARY_PATH` |
| 依赖 `libtalloc.so.2`、`libandroid-shmem.so`、`libc.so` | `libtalloc.so.2` 这个名字不是 `lib*.so`，放不进安装包的原生库目录 | 包里叫 `libtalloc.so`；每次启动前在 `<runtime>/hostlib/` 建一个叫 `libtalloc.so.2` 的链接指过去（建不了链接就复制一份），再把这个目录放进 `LD_LIBRARY_PATH` |
| 32 位加载器 `loader32` | 只有在 Ubuntu 里跑 32 位程序才用得到 | 没带，`PROOT_LOADER_32` 不设；Ubuntu 里跑不了 32 位 ARM 程序 |

- 四个文件都是 64 位 ARM（AArch64）ELF。`libproot.so` 是动态链接的可执行文件（解释器 `/system/bin/linker64`），`libproot-loader.so` 是静态链接的。
- **16KB 页对齐**：四个文件的 LOAD 段对齐值都是 `0x4000`（16KB），在 16KB 页的手机上不会因为对齐被拒。没带的 `loader32` 是 4KB 对齐。
- 二进制没有做任何修改（没有改 RUNPATH、没有改依赖名）。`build.gradle.kts` 里给这四个文件设了 `keepDebugSymbols`，打包时不会被裁剪；测试会核对它们的 sha256。
- **没核实**：手机的动态链接器是否按 `LD_LIBRARY_PATH` 找到 `hostlib/libtalloc.so.2` 这个链接并加载成功；不同 Android 版本是否允许从数据目录里的链接加载原生库目录的库。这是这套做法里最没把握的一环，失败的话日志里会是 `library "libtalloc.so.2" not found` 之类的字样。

### Android 的执行限制

- 核实过（termux-exec 文档、agnostic-apollo 的 Android-Docs、一篇已上架 Flutter IDE 作者的文章）：targetSdk 29 以上的应用不能直接 `execve` 自己数据目录里的文件；应用的原生库目录里的文件可以执行。所以 PRoot 本体必须放在原生库目录。
- 从源码读到：PRoot 启动 Ubuntu 里的每个程序都要先执行一个小的“加载器”。默认它把加载器解到临时目录再执行——那正好是数据目录，会被拦。所以加载器也要放原生库目录，用 `PROOT_LOADER` 指过去。
- Ubuntu 里的程序本身（bash、node…）是由加载器映射进内存再跳过去的，不是直接 `execve`，按上面的资料这是允许的。有资料说另一个 Flutter 项目（openclaw-termux，targetSdk 36）就是这么带 PRoot 的。
- **没核实**：在 LopiCode 的 targetSdk 36 下、在真实手机上，这条路是否真的走得通；不同厂商系统是否有额外限制；`PROOT_NO_SECCOMP` 兼容模式在哪些机器上是必需的。

### 启动失败时

- PRoot 启动 3 秒内以非 0 退出，或者根本起不来，算一次启动失败；原因和 PRoot 的输出写进“运行环境”页的日志（也存到 `runtime.log`）。
- **安卓（真机）不退回本机 shell**（2026-11-24 改，见下面“不再用手机自带的命令行”）：一失败终端区就换成“启动失败”页，写着真实原因，出路是 重试 / 用兼容模式重试 / 一键诊断（就在本页跑，跑完列结论）/ 连接 SSH。兼容模式救回来的话会记住；已经定下用兼容模式时“重试”就是兼容模式，不再单独给按钮。Agent 的命令照样交给 PRoot，起不来就把启动错误原样回给模型。
- 桌面平台和宿主机测试（开发调试用）保留老行为：第 1 次失败屏幕上提示、回车重试（自动改用兼容模式）；连续 2 次失败这个会话和之后新开的会话退回本机 shell 并写明原因，Agent 的命令也退回本机；“运行环境”页有“重新尝试进入 Ubuntu”。

### 不再用手机自带的命令行（2026-11-24 霜霜定）

手机自带的 `sh` 没有 git、node、python，跑不了项目。霜霜真机试用后定：“这个默认的终端不用了，强制用户下载。”

- **平台判断只有一处**：`LinuxRuntime.localShellAllowed`，默认 `!Platform.isAndroid`。安卓上是 false；Windows / macOS / Linux 桌面和宿主机上跑测试是 true（那里没有随包的 PRoot，本机 shell 就是调试用的终端，行为和以前一样）。测试要走安卓那条路时构造 `LinuxRuntime(localShellAllowed: false)`，不假装自己是安卓。
- 安卓上环境没装好（`needsSetup`：没装，或装了但安装包里缺 PRoot）：
  - 终端列表一个会话都不开，也没有“新建本机 shell”的入口；终端页整页是安装引导（`lib/ui/terminal_setup_view.dart`）：一句为什么要装、要下载多大占多大（和“运行环境”页同一份数字）、主按钮“安装运行环境”，进度 / 取消 / 失败原因都在本页，走的是同一个 `runtimeProvider`，没有重写下载；次要出路是连 SSH。
  - 装好的那一下终端列表自动开一个 Ubuntu 会话并切过去；环境被卸掉时 Ubuntu 会话收掉，回到引导。
  - 只连着 SSH 时会话可以关到一个不剩（回到引导）；“新建会话”里有“安装 Ubuntu 运行环境”。
  - Agent 的 `run_command`：不出确认卡、不执行，直接回给模型“运行环境还没有安装，命令没有执行……请告诉用户到终端页安装”（正在安装、安装包缺文件各有各的说法）。
  - 后端积木“在终端启动”：什么都不敲，切到终端页就是引导，装好后再点一次。
- “Ubuntu 没有响应”提示条在安卓上的第二个出路从“先用本机 shell”换成“连接 SSH”。
- 没有在真机上验证过。

### 进去了但没反应时（2026-11-23 加）

真机上出现过：会话标题是 Ubuntu，屏幕只有（当时还有的）欢迎语，没有提示符。PRoot 没退出，所以不算“启动失败”。原因**还没查明**，下面这些是为了不再对着空屏、并把证据收上来：

- 卡住检测：进 Ubuntu 后 8 秒内一个字都没输出，终端下方出“Ubuntu 没有响应”提示条：改用兼容模式重试 / 先用本机 shell（安卓上是“连接 SSH”）/ 去做一键诊断。兼容模式下有了输出才记住兼容模式。卡住不计入“连续失败”。
- “只要 3 秒没退出就算启动成功”改成“3 秒没退出**并且有过输出**才算成功”。
- 一键诊断（“运行环境”页）：用普通进程（不走伪终端）带超时依次跑：四个原生库文件、`libtalloc.so.2` 链接、系统文件抽查、`proot --version`、`/bin/echo ok`（默认 / 兼容各一次，各带一次 `PROOT_VERBOSE=9`）、`bash -lc 'echo ok; id; uname -a'`、`ls /workspace`；再做伪终端自检（手机自带的 sh 起伪终端，写一条 echo，核对回显和结果）和“伪终端里跑 PRoot”。结果可整段复制。默认模式不行而兼容模式行时自动记住兼容模式。报告只含路径、命令输出、手机型号和系统版本。

### 终端打开就是干净的提示符（2026-11-24 第二轮真机反馈）

霜霜真机截图：提示符 `root@localhost:/workspace#` 前面有两类“莫名其妙的文字”，都去掉了。

**(a) 欢迎语不打了。** 以前建会话时往屏幕上写“LopiCode 终端 · Ubuntu 24.04 / 项目目录挂在 /workspace……”。现在 Ubuntu 会话、本机 shell 会话（只在桌面调试有）建出来屏幕都是空的，第一行就是 shell 自己的提示符。留着的只有真正的状态：SSH 的“正在连接…”、连接 / 启动失败的原因、“会话已结束”、“没有响应”，以及桌面上“本该进 Ubuntu 却连续失败 / 缺文件，所以先用本机 sh”那一句。
副作用：PRoot 卡住时，头 8 秒屏幕是全空的（以前有欢迎语垫着），之后照旧出“Ubuntu 没有响应”提示条。

**(b) 四行 `groups: cannot find name for group ID 3003 / 9997 / 20556 / 50556`。**

- 这几个编号是什么：安卓给应用进程挂的附加组——3003 是 inet（联网权限）、9997 是 everybody，20xxx / 50xxx 是按应用编号派生的（截图里应用编号是 10556，所以是 20556、50556）。PRoot 的 `-0` 只把 uid / gid 伪装成 0，附加组还是真的（改附加组要 `CAP_SETGID`，普通应用没有）。
- 谁打印的：Ubuntu 基础包的 `/etc/bash.bashrc` 末尾有一段“sudo 提示”：`case " $(groups) " in *\ admin\ *|*\ sudo\ *)`。它只在交互式 shell、而且 `$HOME` 下没有 `.sudo_as_admin_successful` 和 `.hushlogin` 时执行；`/etc/profile` 在 `PS1` 有值时会 source 这个文件，所以 `bash -l` 的终端每次打开都跑一遍 `groups`。`groups` 查不到名字就往 stderr 写这一行，一个组一行。（2026-11-24 解开本地缓存的 `ubuntu-base-24.04.5-base-arm64.tar.gz` 逐行看过 `etc/bash.bashrc`、`etc/profile`、`etc/group`、`etc/gshadow`、`etc/nsswitch.conf`：基础包的 `/etc/group` 里最大到 100 和 65534，没有这几个编号；`group: files`，所以只要 `/etc/group` 里有就查得到。）
- 怎么修（`lib/runtime/guest_groups.dart`）：**每次启动 PRoot 之前**，读当前进程的组，`rootfs/etc/group` 里缺哪个编号就在末尾追加一行 `aid_编号:x:编号:`。
  - 组从哪来：读 `/proc/self/status` 的 `Gid:` 和 `Groups:` 两行（纯 Dart）；读不到再问系统自带的 `id -G`；都不行就不补，往运行环境日志里记一行，不影响进终端。一个进程活着的时候组不会变，所以只读一次。
  - 入口只有一个：`LinuxRuntime.syncGuestGroups()`，`prootCommand()` 里调——终端会话、Agent 的 `run_command`、一键安装运行时都走它；一键诊断自己拼命令，也单独调了；刚解压完的收尾里也调一次。所以**已经装好的旧环境不用重装**，下次开终端就补上。
  - 不重复：按编号判断，已经有名字的（不管叫什么）不动；都齐了就只读一次文件、不写。原有内容一个字节不改（按 latin1 读写，不是 UTF-8 的字节也原样保留；结尾没换行先补换行）。空行、注释、段数不对的怪行不参与判断、原样留着。`aid_编号` 这个名字被别的组占了就在后面加下划线。
  - 写法：先写同目录的 `group.lopicode-tmp` 再改名。`/etc/group` 是链接或目录不动（不顺着链接写到别处）；`etc` 目录不存在（没装）不动；`etc` 在而 `group` 不在就新建（`root:x:0:` 加要补的）。读写失败不抛异常，只记日志。
  - `/etc/gshadow`：查组名用不到它（`groups` / `id` 只查 `/etc/group`），但它是 group 的影子账本，两边对不上 `grpck` 会抱怨，所以文件存在时同步追加 `aid_编号:!::`；不存在不造。
  - `/etc/passwd`：**不用补**。用户编号被 `-0` 伪装成 0，`root` 在 passwd 里本来就有；报错的只有组。
  - 名字叫 `aid_*` 是照 Termux proot-distro 的叫法（它把宿主的安卓用户和组登记成 `aid_<名字>`，写进 passwd / shadow / group / gshadow）；dsh-Go 是在安装时往 `/etc/group` 追加。我们只学“登记进 /etc/group”这个做法，代码自己写的；和它们不同的是每次启动前都核对，旧环境也能补。
- 这只是给编号起名字，不是隔离：环境里的进程照旧带着应用的这些组。
- Agent 的 `run_command` 用的是 `bash -lc`（非交互，`PS1` 没值，不会 source `bash.bashrc`），本来就不会在开头冒这四行；但命令里自己跑 `id` / `groups` 时以前会带出这种报错，现在也没有了。

### 软键盘输入（2026-11-23 改）

xterm 4.0.0 自带的软键盘处理在输入法“攒字”（预编辑）期间不往终端写任何东西，只把攒着的字画在光标格上、再把光标盖在第一个字上（`custom_text_edit.dart` 的 `updateEditingValue`、`render.dart` 的 `_paintComposingText` + `paintCursor`）。现在 `TerminalView` 只开实体键盘（`hardwareKeyboardOnly`），软键盘由 `lib/terminal/terminal_input.dart` 接管：

- 默认“直接输入”：键盘类型用“可见密码”（多数输入法因此逐键提交）；仍被攒着的英文边打边写进终端，输入法改主意时用退格对齐。
- 键盘行的“中文”点亮后：拼音攒着不写入，画在光标格之后、带下划线，光标画在它后面；选定后一次写入。
- 输入法的完成 / 换行 / 发送键都发回车；退格靠编辑框里垫的两个空格识别。
- xterm 4.0.0 的 `TerminalView.onTapUp` 从不触发，点屏幕弹键盘改用指针事件判断。

## 下载源（2026-11-23 逐个请求核实）

### Ubuntu 系统包

文件：`ubuntu-base-24.04.5-base-arm64.tar.gz`，29,936,675 字节，
sha256 `a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2`
（清华、中科大、阿里云、官方四处的 SHA256SUMS 里这个值一致）。

| 源 | 地址 | 结果 |
| --- | --- | --- |
| 清华大学镜像（默认） | `https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release` | 200，支持断点续传；实际整包下载过，校验一致 |
| 阿里云镜像 | `https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release` | 200，支持断点续传（只请求了文件头） |
| Ubuntu 官方 | `https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release` | 200，支持断点续传（只请求了文件头） |
| 中科大镜像 | — | 文件请求回 403，没有收进来 |

解压后（开发机上量的）：2562 个文件、655 个目录、194 个符号链接、2 个硬链接；文件内容共 100,784,109 字节，占磁盘约 103 MB。界面上按“下载 28.5 MB，解压后约 103 MB，建议留出 150 MB”提示。

### apt 软件源（arm64 是 ubuntu-ports）

| 源 | 地址 | 结果 |
| --- | --- | --- |
| 清华大学镜像（默认） | `http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports` | `dists/noble/InRelease` 200 |
| 阿里云镜像 | `http://mirrors.aliyun.com/ubuntu-ports` | 200 |
| Ubuntu 官方 | `http://ports.ubuntu.com/ubuntu-ports` | 200 |

用 http 是因为基础包里没有 CA 证书，刚装好时 apt 走不了 https；软件包本身由 apt 用 Ubuntu 的签名钥匙校验。

### 常用运行时

| 项目 | 怎么装 | 核实情况 |
| --- | --- | --- |
| Node.js 24 | 下载官方 `linux-arm64` 包（国内源 `npmmirror.com/mirrors/node`，官方源 `nodejs.org/dist`），用同目录的 `SHASUMS256.txt` 核对后解到 `/usr/local` | 两处的目录和文件都在。**注意**：npmmirror 的 `latest-v24.x` 是 v24.9.0，比官方的 v24.22.3 旧 |
| Python 3.12 | `apt install python3 python3-pip python3-venv` | noble 源里有 python3 3.12.3 |
| Git | `apt install git` | noble 源里有 git 2.43.0 |

| Go 1.26.11 | 下载官方 `go1.26.11.linux-arm64.tar.gz`（国内源 `golang.google.cn/dl`，官方源 `go.dev/dl`），用写死在代码里的 sha256 核对后解到 `/usr/local/go`，在 `/usr/local/bin` 放 `go`、`gofmt` 两个链接 | 两个下载页列出的文件、大小（61MB）、sha256 一致（2026-11-25 核对）；文件本身没有下载过 |
| Java（JDK 21） | `apt install openjdk-21-jdk-headless`（带 javac，不带图形界面部分） | noble 源里有这个包（arm64 79.7MB，依赖 openjdk-21-jre-headless 44.8MB）；总下载量“约 130 MB”是估的 |
| PHP 8.3 | `apt install php-cli`（noble 里指向 php8.3-cli） | noble 源里有；总下载量没核对，界面上不写数字 |

这六项是同一份清单（`lib/runtime/runtime_sources.dart` 的 `runtimePacks`），安装、取消、失败原因分类在 `lib/runtime/pack_install.dart`。
后端积木点“运行”时，所选语言对应的那一项没装会自动装好再启动（`lib/state/backend_run.dart`，2026-11-25 真机反馈第三轮）；
下载量过 100 MB 的（现在只有 JDK）先问一次。来源和核对情况见 [api-notes.md](api-notes.md) 的“语言工具的一键安装”。

**这六项的安装脚本一次都没有真的执行过**（开发机是 x86，没有 PRoot arm64 环境；要在真机上验）。

## 许可证

| 东西 | 许可证 | 现在带没带 |
| --- | --- | --- |
| PRoot 5.1.107.102（Termux 版） | GPL-2.0-or-later。依据：二进制和手册里的声明“Copyright (C) 2015 STMicroelectronics, licensed under GPL v2 or later”；Termux 构建脚本写 `TERMUX_PKG_LICENSE="GPL-2.0"` | 随包分发（`libproot.so`、`libproot-loader.so`） |
| talloc 2.5.0 | LGPL-3.0-or-later。依据：包里 `talloc.h` 开头的声明原文（“version 3 of the License, or (at your option) any later version”，GNU Lesser General Public License）。注意 Termux 的包把版权文件指到了 GPL-3.0，和源码声明不一致，这里按源码，并把 LGPL-3.0 和 GPL-3.0 两份全文都附上（LGPL-3.0 是在 GPL-3.0 上加条款，本来也要两份一起看） | 随包分发（`libtalloc.so`，动态库，没有静态链接进 PRoot） |
| libandroid-shmem 0.7 | BSD 3 条款。依据：包里自带的版权文件 | 随包分发（`libandroid-shmem.so`） |
| Ubuntu 基础包、Node.js、Python、Git、Go、OpenJDK、PHP | 用户自己点了（或点后端“运行”时自动）才从上游下载，不在安装包里 | 不随包分发 |
| dsh-Go | AGPL-3.0 | 只参考了它的做法，没有复制任何代码 |

已经做到的：

- 许可证全文（GPL-2.0、GPL-3.0、LGPL-3.0、libandroid-shmem 的许可证）在安装包里（`assets/licenses/`），应用内“设置 › 第三方声明”可以看；仓库里 `third_party/termux/licenses/` 也有一份。GPL / LGPL 文本取自开发机 `/usr/share/common-licenses/`（Debian 随系统带的官方文本）。
- 版权声明、每个文件的来源地址、版本、sha256、对应源码地址：应用内同一页、`third_party/termux/README.md`、`lib/core/third_party.dart`。
- 没有改动这些二进制，只改了文件名，并在声明里写明。
- LopiCode 只是把 PRoot 当成一个独立程序来启动，不和它链接。通常的理解是这属于“放在一起分发”，LopiCode 自己的代码不会因此变成 GPL。**这是通常的理解，不是法律意见。**

还没做到 / 要霜霜知道的：

- **对应源码目前只给了上游地址，仓库里没有存一份源码。** GPL-2.0 第 3 条要求分发二进制时“随附源码”或“附一份至少三年有效的书面承诺，谁来要都给”。只指向别人的下载地址，严格说不算满足。应用里现在写了一句“地址打不开时可以向 LopiCode 的发布者索取对应源码”，这句话等于霜霜做了这个承诺——要兑现它，她手里得留一份这三个组件的源码包。PRoot 的源码在这台开发机上被安全检查拦过，所以这里没有下载、也没有存它；需要霜霜自己从“对应源码”的地址下载留存，或者决定换一种写法。
- 没有核对 Termux 软件源 Release 文件的 GPG 签名，完整性只靠 HTTPS ＋ sha256 一环套一环（Release → Packages → 包）。
- Termux 构建时打的补丁和编译参数在 termux-packages 仓库（`packages/proot/`、`packages/libtalloc/`、`packages/libandroid-shmem/`），没有记下取包当天那个仓库的提交号。

## 只在开发机上验证过的 / 必须真机验证的

开发机上跑过（`flutter test`）：断点续传（中断、卡死、服务器不支持续传、半截文件损坏、取消）、大小与 sha256 校验、tar.gz 解压（含真实的 Ubuntu 基础包）、PRoot 命令拼装（含依赖库路径和 `libtalloc.so.2` 链接的准备）、随包文件的校验值、源切换、安装流程、空间不足、启动失败回退、Agent 命令走向、各状态界面在 390×844 浅色/深色下的渲染。

必须真机才能验证：PRoot 能不能启动（系统能不能找到并加载 `libtalloc.so.2`、`libandroid-shmem.so`；加载器能不能从原生库目录执行）；Ubuntu 的 bash、apt、node、python 能不能跑；用应用自带的解压代码在手机文件系统上解出来的系统是否完整可用（符号链接、权限）；`/workspace` 绑定后项目文件是否可见可写；前台服务在切后台后是否真的保住进程；Android 13 以上的通知权限弹窗；磁盘剩余空间读数。

组名补写（2026-11-24）：开发机上测过解析、补写、幂等、坏文件，以及“起伪终端 / 跑命令之前文件已经改好”；**真机上那四行是否真的消失没有验证**（开发机不是安卓，起不了 PRoot）。要看：装着旧环境直接升级后开终端，第一行是不是提示符；`cat /etc/group | tail` 有没有 `aid_*`；“运行环境”日志里有没有“已在 Ubuntu 的 /etc/group 里登记安卓的组”。

## 技能目录挂在 /skills（2026-11-25）

- 带附带文件的技能（技能文件夹里除了 `SKILL.md` 还有脚本等）会出现在 Ubuntu 环境的 `/skills/<技能名>/`。
- **挂进去的是副本，不是原目录。** PRoot 的 `-b` 没有“只读”的写法（对照过安装包里这一版自带的帮助），直接挂原目录的话环境里的命令能改掉技能文件。
  所以每次进环境前（拼 PRoot 命令时）先把开着的技能复制 / 对齐到 `<运行环境目录>/skills-mirror/<工作区>/`，再把这份副本挂到 `/skills`：
  环境里怎么改都碰不到原件，下一条命令进环境前副本又会按原件复原。代码在 `lib/agent/skill_mirror.dart`。
- 没有技能目录、目录是空的、技能都不带附带文件：不挂，也不报错。一个技能附带的文件超过 200 个或 4MB 就不放进去（文字说明照常能用）。
- 模型用 `read_skill` 读全文时，后面会接一段“脚本在 /skills/<名字>/…，用 run_command 跑”。跑脚本就是普通命令，确认规则不变。
  运行环境没装好时这段写的是“脚本现在跑不了”。副本里的文件不保证带执行权限，所以说明里让模型用解释器跑（`bash …`、`python3 …`）。
- 真机上还没验证过绑定是否生效。验收办法：技能文件夹里放一个 `hello.sh`，终端里 `ls /skills/<名字>`、`bash /skills/<名字>/hello.sh`；
  在 `/skills` 里改掉或删掉文件，再开一条命令，应当复原，手机上的原件不变。
