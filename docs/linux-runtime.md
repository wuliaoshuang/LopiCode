# 本机 Linux 运行环境（PRoot + Ubuntu 24.04）

写于 2026-11-23。下面每一条都标了“核实过”还是“没核实”。**整套东西没有在任何手机上跑过。**

## 现在的状态：安装包里还没有 PRoot

应用这一侧的代码、界面、测试都做完了，但 **PRoot 可执行文件没有放进安装包**，原因有两个，都需要霜霜决定：

1. **许可证**：PRoot 是 GPL-2.0-or-later，它依赖的 talloc 是 LGPL（见下面“许可证”一节）。带上它，LopiCode 发安装包时就多了开源义务。
2. **来源**：从 `github.com/termux/proot` 克隆下来的源码被这台机器的安全检查拦下（判定为有执行风险），不允许在这里编译或运行它。

所以这一版安装包里，“运行环境”页会如实写“安装包里没有带 PRoot 启动器”，不提供安装按钮；终端仍是原来的本机 shell。等 `libproot.so`、`libproot-loader.so` 放进 `android/app/src/main/jniLibs/arm64-v8a/` 重新打包，其余功能自动生效，不用再改代码。

## 做法

| 环节 | 做法 | 核实情况 |
| --- | --- | --- |
| PRoot 放哪 | 命名成 `libproot.so`、`libproot-loader.so` 放 jniLibs，装好后在应用的原生库目录里，从那里执行 | 见“Android 的执行限制” |
| 安装包设置 | `useLegacyPackaging = true` ＋ `extractNativeLibs="true"`，让系统把 .so 解到磁盘上（不解出来就没有可执行的文件） | 设置已写入并能打包；真机没验证 |
| Ubuntu 系统包 | 进应用后点“安装运行环境”才下载，解到应用私有目录 `files/…/runtime/rootfs` | 下载、校验、解压在开发机上用真实文件跑过 |
| 启动 | 在伪终端里跑 `libproot.so … /usr/bin/env -i … /bin/bash -l` | 只验证了参数拼装；没有真的启动过 |
| 保活 | 有 Ubuntu 会话或 Agent 命令在跑时开前台服务 ＋ 常驻通知，都关了就撤 | 代码能编译；真机没验证 |

### 启动命令

```
环境变量：PROOT_LOADER=<原生库目录>/libproot-loader.so
          PROOT_TMP_DIR=<runtime>/tmp
          LD_PRELOAD=（清空）
          PROOT_NO_SECCOMP=1（只在兼容模式下）
<原生库目录>/libproot.so --kill-on-exit --link2symlink -0
  -r <rootfs> -b /dev -b /proc -b /sys -b <rootfs>/tmp:/dev/shm
  -b <项目目录>:/workspace -w /workspace
  /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
     TMPDIR=/tmp TERM=xterm-256color LANG=C.UTF-8 … /bin/bash -l
```

- 这些参数和环境变量名是从 termux/proot 源码（提交 `7cbed09235d18cdb4be8eed456038608c10a29a0`，VERSION 5.1.0）的 `src/cli/proot.h` 和 `src/execve/enter.c` 里**读**出来的，只读了文字，没有编译运行。
- `env -i` 把 Android 塞进来的变量全部清掉，只留上面列的几个。
- DNS：安装时写 `/etc/resolv.conf`（223.5.5.5、119.29.29.29、8.8.8.8）和 `/etc/hosts`。
- apt：写 `/etc/apt/sources.list.d/ubuntu.sources`（arm64 走 ubuntu-ports），并关掉 apt 的降权沙箱（PRoot 里的 root 是假的，切不了用户）。

### Android 的执行限制

- 核实过（termux-exec 文档、agnostic-apollo 的 Android-Docs、一篇已上架 Flutter IDE 作者的文章）：targetSdk 29 以上的应用不能直接 `execve` 自己数据目录里的文件；应用的原生库目录里的文件可以执行。所以 PRoot 本体必须放在原生库目录。
- 从源码读到：PRoot 启动 Ubuntu 里的每个程序都要先执行一个小的“加载器”。默认它把加载器解到临时目录再执行——那正好是数据目录，会被拦。所以加载器也要放原生库目录，用 `PROOT_LOADER` 指过去。
- Ubuntu 里的程序本身（bash、node…）是由加载器映射进内存再跳过去的，不是直接 `execve`，按上面的资料这是允许的。有资料说另一个 Flutter 项目（openclaw-termux，targetSdk 36）就是这么带 PRoot 的。
- **没核实**：在 LopiCode 的 targetSdk 36 下、在真实手机上，这条路是否真的走得通；不同厂商系统是否有额外限制；`PROOT_NO_SECCOMP` 兼容模式在哪些机器上是必需的。

### 启动失败时

- PRoot 启动 3 秒内以非 0 退出，或者根本起不来，算一次启动失败；原因和 PRoot 的输出写进“运行环境”页的日志（也存到 `runtime.log`）。
- 第 1 次失败：屏幕上提示，回车重试，重试自动改用兼容模式。兼容模式救回来的话会记住。
- 连续 2 次失败：这个会话和之后新开的会话退回本机 shell，并写明原因；Agent 的命令也退回本机。“运行环境”页有“重新尝试进入 Ubuntu”。

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

**这三项的安装脚本一次都没有真的执行过**（要先有能跑的 PRoot）。

## 许可证

| 东西 | 许可证 | 现在带没带 |
| --- | --- | --- |
| PRoot（termux/proot） | GPL-2.0-or-later（源码 `COPYING` 和文档里写明） | 没带 |
| talloc（PRoot 链接的库） | LGPL-3.0-or-later（凭已知信息，这次没有再核对原文） | 没带 |
| Ubuntu 基础包、Node.js、Python | 用户自己点了才从上游下载，不在安装包里 | 不随包分发 |
| dsh-Go | AGPL-3.0 | 只参考了它的做法，没有复制任何代码 |

如果以后把 PRoot 带进安装包：

- LopiCode 只是把 PRoot 当成一个独立程序来启动，不和它链接。通常的理解是这属于“放在一起分发”，LopiCode 自己的代码不会因此变成 GPL。**这是通常的理解，不是法律意见。**
- 但分发 PRoot 这个二进制本身有义务：附上 GPL 许可证全文和版权声明；向拿到安装包的人提供与这个二进制**完全对应**的源码（PRoot ＋ 静态链接进去的 talloc ＋ 构建脚本），或者附一份至少三年有效的书面提供承诺；改过的地方要标明。
- 到时这里要补记：二进制的来源、版本、提交号、sha256、构建方式。

## 只在开发机上验证过的 / 必须真机验证的

开发机上跑过（`flutter test`）：断点续传（中断、卡死、服务器不支持续传、半截文件损坏、取消）、大小与 sha256 校验、tar.gz 解压（含真实的 Ubuntu 基础包）、PRoot 命令拼装、源切换、安装流程、空间不足、启动失败回退、Agent 命令走向、各状态界面在 390×844 浅色/深色下的渲染。

必须真机才能验证：PRoot 能不能启动；Ubuntu 的 bash、apt、node、python 能不能跑；用应用自带的解压代码在手机文件系统上解出来的系统是否完整可用（符号链接、权限）；`/workspace` 绑定后项目文件是否可见可写；前台服务在切后台后是否真的保住进程；Android 13 以上的通知权限弹窗；磁盘剩余空间读数。
