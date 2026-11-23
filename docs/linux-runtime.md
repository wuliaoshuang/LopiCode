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
- 第 1 次失败：屏幕上提示，回车重试，重试自动改用兼容模式。兼容模式救回来的话会记住。
- 连续 2 次失败：这个会话和之后新开的会话退回本机 shell，并写明原因；Agent 的命令也退回本机。“运行环境”页有“重新尝试进入 Ubuntu”。

### 进去了但没反应时（2026-11-23 加）

真机上出现过：会话标题是 Ubuntu，屏幕只有欢迎语，没有提示符。PRoot 没退出，所以不算“启动失败”。原因**还没查明**，下面这些是为了不再对着空屏、并把证据收上来：

- 卡住检测：进 Ubuntu 后 8 秒内一个字都没输出，终端下方出“Ubuntu 没有响应”提示条：改用兼容模式重试 / 先用本机 shell / 去做一键诊断。兼容模式下有了输出才记住兼容模式。卡住不计入“连续失败”。
- “只要 3 秒没退出就算启动成功”改成“3 秒没退出**并且有过输出**才算成功”。
- 一键诊断（“运行环境”页）：用普通进程（不走伪终端）带超时依次跑：四个原生库文件、`libtalloc.so.2` 链接、系统文件抽查、`proot --version`、`/bin/echo ok`（默认 / 兼容各一次，各带一次 `PROOT_VERBOSE=9`）、`bash -lc 'echo ok; id; uname -a'`、`ls /workspace`；再做伪终端自检（手机自带的 sh 起伪终端，写一条 echo，核对回显和结果）和“伪终端里跑 PRoot”。结果可整段复制。默认模式不行而兼容模式行时自动记住兼容模式。报告只含路径、命令输出、手机型号和系统版本。

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

**这三项的安装脚本一次都没有真的执行过**（要在真机上先确认 PRoot 能跑）。

## 许可证

| 东西 | 许可证 | 现在带没带 |
| --- | --- | --- |
| PRoot 5.1.107.102（Termux 版） | GPL-2.0-or-later。依据：二进制和手册里的声明“Copyright (C) 2015 STMicroelectronics, licensed under GPL v2 or later”；Termux 构建脚本写 `TERMUX_PKG_LICENSE="GPL-2.0"` | 随包分发（`libproot.so`、`libproot-loader.so`） |
| talloc 2.5.0 | LGPL-3.0-or-later。依据：包里 `talloc.h` 开头的声明原文（“version 3 of the License, or (at your option) any later version”，GNU Lesser General Public License）。注意 Termux 的包把版权文件指到了 GPL-3.0，和源码声明不一致，这里按源码，并把 LGPL-3.0 和 GPL-3.0 两份全文都附上（LGPL-3.0 是在 GPL-3.0 上加条款，本来也要两份一起看） | 随包分发（`libtalloc.so`，动态库，没有静态链接进 PRoot） |
| libandroid-shmem 0.7 | BSD 3 条款。依据：包里自带的版权文件 | 随包分发（`libandroid-shmem.so`） |
| Ubuntu 基础包、Node.js、Python | 用户自己点了才从上游下载，不在安装包里 | 不随包分发 |
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
