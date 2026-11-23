# 随安装包带的 Termux 现成二进制

记于 2026-11-23。这里的内容和应用内“设置 › 第三方声明”、`lib/core/third_party.dart` 是同一份事实；`test/third_party_test.dart` 会核对文件的校验值。

## 从哪里来

- 软件源：Termux 官方源 `https://packages.termux.dev/apt/termux-main`（termux-packages 的 Mirrors 说明里列的主源）。
- 索引：`dists/stable/Release`，日期 `Mon, 23 Nov 2026 05:26:57 UTC`。
  - 它记的 `main/binary-aarch64/Packages.gz` sha256：`cad46566e8cbf869b0120f969a294ffdc07b075528eb2841679fc676c8bdad2f`（下载到的一致）
  - 它记的 `main/binary-aarch64/Packages` sha256：`bbd59930ec722d619a4feaddcba2d37a88bb828a80e94c1a87426ebca65b7494`（解压后一致）
- 三个包的 sha256 都和 `Packages` 索引里记的一致。
- **没有核对 Release 的 GPG 签名**，完整性靠 HTTPS ＋ 上面这条 sha256 链。

## 三个包

| 包 | 版本 | 地址（接在软件源地址后面） | 大小 | sha256 |
| --- | --- | --- | --- | --- |
| proot | 5.1.107.102 | `pool/main/p/proot/proot_5.1.107.102_aarch64.deb` | 103028 | `10a394b585c2fc2b2c8502544f4e5f1be581dc8bfff79e8ba62f16207423e030` |
| libtalloc | 2.5.0 | `pool/main/libt/libtalloc/libtalloc_2.5.0_aarch64.deb` | 34036 | `556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7` |
| libandroid-shmem | 0.7 | `pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_aarch64.deb` | 7216 | `0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6` |

原始包原样留在 `debs/`。

## 取出来的四个文件

放在 `android/app/src/main/jniLibs/arm64-v8a/`。**内容没有任何改动，只改了文件名**（Android 只把 `lib*.so` 装进原生库目录）。

| 安装包里的名字 | 来自哪个包 | 包里的原路径 | 大小 | sha256 |
| --- | --- | --- | --- | --- |
| `libproot.so` | proot | `data/data/com.termux/files/usr/bin/proot` | 259832 | `3621937c1c5a98d0d39ca599af573a6bc15128690606d535e8b05da00cec4f41` |
| `libproot-loader.so` | proot | `data/data/com.termux/files/usr/libexec/proot/loader` | 18136 | `1da54355333cca3fb6ee10e3b82a24df24fb230c99241ce83809bf9e240609b5` |
| `libtalloc.so` | libtalloc | `data/data/com.termux/files/usr/lib/libtalloc.so.2.5.0` | 33592 | `742b438c4d09e276985a61d44164c9de207b6d8cc268f3018cb3001961bcb309` |
| `libandroid-shmem.so` | libandroid-shmem | `data/data/com.termux/files/usr/lib/libandroid-shmem.so` | 14432 | `84475798e07c8174dbbfaec70a827fdb02f19ffa69a589380c13e7507fd0e731` |

没有带的：proot 包里的 `loader32`（32 位加载器，sha256 `c429996fee730e1a4fe12625b22dab5a5bc2847a4cae274d36fd4a19cd8299a8`）、`termux-chroot` 脚本、手册；libtalloc 包里的头文件等。

`SHA256SUMS` 是上面这些校验值的机器可读版本（在本目录下 `sha256sum -c` 核对 `debs/`；`jniLibs/` 开头的几行对应 `android/app/src/main/jniLibs/arm64-v8a/` 里的文件）。

用只读工具（`readelf`、`strings`）看到的：四个文件都是 64 位 ARM ELF；LOAD 段都按 16KB（0x4000）对齐；`libproot.so` 依赖 `libtalloc.so.2`、`libandroid-shmem.so`、`libc.so`，RUNPATH 是 `/data/data/com.termux/files/usr/lib`。这些文件在开发机上**没有执行过**。

## 许可证和版权

| 组件 | 许可证 | 版权声明 | 全文 |
| --- | --- | --- | --- |
| PRoot（Termux 版）5.1.107.102 | GPL-2.0-or-later | Copyright (C) 2015 STMicroelectronics，以及 PRoot 与 Termux 的贡献者 | `licenses/GPL-2.0.txt` |
| talloc 2.5.0 | LGPL-3.0-or-later | Copyright (C) Andrew Tridgell 2004-2005；Copyright (C) Stefan Metzmacher 2006 | `licenses/LGPL-3.0.txt`、`licenses/GPL-3.0.txt` |
| libandroid-shmem 0.7 | BSD 3 条款 | Copyright (c) 2013, Sergii Pylypenko；Copyright (c) 2017, Fredrik Fornwall | `licenses/libandroid-shmem.txt` |

- PRoot 的许可证依据：二进制和手册里的声明原文“Copyright (C) 2015 STMicroelectronics, licensed under GPL v2 or later”，Termux 构建脚本 `TERMUX_PKG_LICENSE="GPL-2.0"`。
- talloc 的许可证依据：libtalloc 包里 `usr/include/talloc.h` 开头的声明原文（GNU Lesser General Public License，version 3 or later）。Termux 的包把它的版权文件指到 GPL-3.0，与源码声明不一致，这里按源码声明，两份全文都附。
- GPL / LGPL 全文取自 Debian 的 `/usr/share/common-licenses/`；libandroid-shmem 的取自它的包。

## 对应源码在哪

| 组件 | 源码 | 备注 |
| --- | --- | --- |
| PRoot | https://github.com/termux/proot/archive/v5.1.107.102.zip | Termux 构建脚本（https://github.com/termux/termux-packages/blob/master/packages/proot/build.sh ，2026-11-23 读到）写的 `TERMUX_PKG_SRCURL` 和 `TERMUX_PKG_SHA256=30d12a6e2cc4147123756ff58edea262d3083bbc238c12d0ab9b39e3d1c40852`。编译参数：`-C src PROOT_WITH_LIBANDROID_SHMEM=true`，`PROOT_UNBUNDLE_LOADER=$TERMUX_PREFIX/libexec/proot`，`-DARG_MAX=131072` |
| talloc | https://www.samba.org/ftp/talloc/talloc-2.5.0.tar.gz | 2026-11-23 确认地址能访问（690172 字节），没有下载留存。Termux 的补丁和构建脚本在 termux-packages 仓库 `packages/libtalloc/` |
| libandroid-shmem | https://github.com/termux/libandroid-shmem | 构建脚本在 termux-packages 仓库 `packages/libandroid-shmem/` |

**没做到的，如实记下：**

- 本仓库里**没有存这些源码的副本**。PRoot 的源码在开发机上被安全检查拦过，没有再下载。GPL-2.0 第 3 条要的是“随附源码”或“三年有效的书面承诺”；应用里写了“可以向 LopiCode 的发布者索取对应源码”，要兑现需要发布者自己留一份源码包。
- PRoot 源码包的 sha256 是从 Termux 构建脚本里抄的，没有自己下载核对。
- 没有记下取包当天 termux-packages 仓库的提交号（Termux 的补丁以那个仓库为准）。
