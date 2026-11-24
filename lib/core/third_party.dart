/// 随安装包分发的第三方组件：来源、版本、校验值、许可证、对应源码在哪。
///
/// 这份清单是“第三方声明”页、README 和 third_party/termux/README.md 的同一份事实，
/// 改这里的同时要改那两处（test/third_party_test.dart 会核对文件校验值）。
class BundledBinary {
  const BundledBinary({required this.fileName, required this.originalPath, required this.size, required this.sha256});

  /// 在安装包里的名字（lib/arm64-v8a/ 下）。
  final String fileName;

  /// 在 Termux 包里原来的路径。
  final String originalPath;
  final int size;
  final String sha256;
}

class ThirdPartyComponent {
  const ThirdPartyComponent({
    required this.name,
    required this.version,
    required this.purpose,
    required this.license,
    required this.licenseAssets,
    required this.copyright,
    required this.packageUrl,
    required this.packageSha256,
    required this.sourceUrl,
    required this.sourceNote,
    required this.binaries,
  });

  final String name;
  final String version;
  final String purpose;

  /// 许可证的名字（SPDX 写法）。
  final String license;

  /// 许可证全文在安装包里的位置（assets/licenses/ 下），按阅读顺序。
  final List<String> licenseAssets;
  final String copyright;

  /// 二进制的来源：Termux 官方软件源里的包。
  final String packageUrl;
  final String packageSha256;

  /// 对应源码的获取地址。
  final String sourceUrl;
  final String sourceNote;
  final List<BundledBinary> binaries;
}

const String termuxRepoBase = 'https://packages.termux.dev/apt/termux-main';

/// 取包那天软件源索引的日期（Release 文件里的 Date）。
const String termuxIndexDate = '2026-11-23 05:26:57 UTC';

const List<ThirdPartyComponent> bundledComponents = [
  ThirdPartyComponent(
    name: 'PRoot（Termux 版）',
    version: '5.1.107.102',
    purpose: '不需要 root 就能进入 Ubuntu 环境的启动器。LopiCode 只是把它当成独立程序来启动。',
    license: 'GPL-2.0-or-later',
    licenseAssets: ['assets/licenses/GPL-2.0.txt'],
    copyright: 'Copyright (C) 2015 STMicroelectronics，以及 PRoot 与 Termux 的贡献者',
    packageUrl: '$termuxRepoBase/pool/main/p/proot/proot_5.1.107.102_aarch64.deb',
    packageSha256: '10a394b585c2fc2b2c8502544f4e5f1be581dc8bfff79e8ba62f16207423e030',
    sourceUrl: 'https://github.com/termux/proot/archive/v5.1.107.102.zip',
    sourceNote:
        'Termux 的构建脚本（termux-packages 仓库 packages/proot/build.sh）写明用的就是这份源码，'
        '并记了它的 sha256：30d12a6e2cc4147123756ff58edea262d3083bbc238c12d0ab9b39e3d1c40852。',
    binaries: [
      BundledBinary(fileName: 'libproot.so', originalPath: 'usr/bin/proot', size: 259832, sha256: '3621937c1c5a98d0d39ca599af573a6bc15128690606d535e8b05da00cec4f41'),
      BundledBinary(fileName: 'libproot-loader.so', originalPath: 'usr/libexec/proot/loader', size: 18136, sha256: '1da54355333cca3fb6ee10e3b82a24df24fb230c99241ce83809bf9e240609b5'),
    ],
  ),
  ThirdPartyComponent(
    name: 'talloc',
    version: '2.5.0',
    purpose: 'PRoot 运行时要用的内存管理库。',
    license: 'LGPL-3.0-or-later',
    licenseAssets: ['assets/licenses/LGPL-3.0.txt', 'assets/licenses/GPL-3.0.txt'],
    copyright: 'Copyright (C) Andrew Tridgell 2004-2005；Copyright (C) Stefan Metzmacher 2006',
    packageUrl: '$termuxRepoBase/pool/main/libt/libtalloc/libtalloc_2.5.0_aarch64.deb',
    packageSha256: '556591f43bb773ad8777e1a29522640866a55f95dab71914418b94a8c58ad5a7',
    sourceUrl: 'https://www.samba.org/ftp/talloc/talloc-2.5.0.tar.gz',
    sourceNote:
        '许可证以包里 talloc.h 开头的声明为准（LGPL 第 3 版或更新版本）。'
        'Termux 的包把它的版权文件指到了 GPL-3.0，和源码里的声明不一样，这里按源码。'
        'Termux 怎么构建它见 termux-packages 仓库 packages/libtalloc/。',
    binaries: [BundledBinary(fileName: 'libtalloc.so', originalPath: 'usr/lib/libtalloc.so.2.5.0', size: 33592, sha256: '742b438c4d09e276985a61d44164c9de207b6d8cc268f3018cb3001961bcb309')],
  ),
  ThirdPartyComponent(
    name: 'libandroid-shmem',
    version: '0.7',
    purpose: 'PRoot 运行时要用的共享内存库。',
    license: 'BSD-3-Clause',
    licenseAssets: ['assets/licenses/libandroid-shmem.txt'],
    copyright: 'Copyright (c) 2013, Sergii Pylypenko；Copyright (c) 2017, Fredrik Fornwall',
    packageUrl: '$termuxRepoBase/pool/main/liba/libandroid-shmem/libandroid-shmem_0.7_aarch64.deb',
    packageSha256: '0da3a24d558b93c92bcf8d611e0826a99ff96e396b148e6cdf33b47c47c57ff6',
    sourceUrl: 'https://github.com/termux/libandroid-shmem',
    sourceNote: '许可证全文取自包里自带的版权文件。',
    binaries: [BundledBinary(fileName: 'libandroid-shmem.so', originalPath: 'usr/lib/libandroid-shmem.so', size: 14432, sha256: '84475798e07c8174dbbfaec70a827fdb02f19ffa69a589380c13e7507fd0e731')],
  ),
];

/// 随包的图标（不是二进制，单独记）。清单与校验值在 third_party/lobe-icons/ 和 third_party/material-icon-theme/。
class BundledIconPack {
  const BundledIconPack({
    required this.name,
    required this.version,
    required this.purpose,
    required this.license,
    required this.licenseAsset,
    required this.copyright,
    required this.packageUrl,
    required this.packageIntegrity,
    required this.sourceUrl,
    required this.trademarkNote,
  });

  final String name;
  final String version;
  final String purpose;
  final String license;
  final String licenseAsset;
  final String copyright;
  final String packageUrl;

  /// npm 登记的包完整性校验值（sha512，下载后核对过）。
  final String packageIntegrity;
  final String sourceUrl;
  final String trademarkNote;
}

const BundledIconPack providerIconPack = BundledIconPack(
  name: 'Lobe Icons（@lobehub/icons-static-svg）',
  version: '1.106.0',
  purpose: '“模型与渠道”里各家服务商的图标。只带了预设用到的那几个 SVG 文件，内容没有改动。',
  license: 'MIT',
  licenseAsset: 'assets/licenses/lobe-icons-MIT.txt',
  copyright: 'Copyright (c) 2023 LobeHub',
  packageUrl: 'https://registry.npmmirror.com/@lobehub/icons-static-svg/-/icons-static-svg-1.106.0.tgz',
  packageIntegrity: 'sha512-yRLkEGfCKg7ztuAmwPKOlRY2nDvB6GJHtHvb8YGWZaZkCzMXrUOcvUbTNO3RDE0QVrR/nYD7p5oPWhUTpEi/uA==',
  sourceUrl: 'https://github.com/lobehub/lobe-icons',
  trademarkNote: '图标里的品牌标志和名称是各家公司的商标，归它们各自所有。这里只用来标明渠道连的是哪家服务，不代表它们与 LopiCode 有合作或认可关系。MIT 许可证只管图标文件本身，不授予商标权利。',
);

/// 文件树、编辑器标签、语言选择里的文件 / 文件夹 / 语言图标。清单与校验值在 third_party/material-icon-theme/。
const BundledIconPack fileIconPack = BundledIconPack(
  name: 'Material Icon Theme（material-icon-theme）',
  version: '5.40.0',
  purpose: '文件列表、编辑器标签和语言选择里的文件、文件夹、语言图标。只带了挑出来的一部分 SVG 文件，内容没有改动。',
  license: 'MIT',
  licenseAsset: 'assets/licenses/material-icon-theme-MIT.txt',
  copyright: 'Copyright (c) 2025 Material Extensions',
  packageUrl: 'https://registry.npmmirror.com/material-icon-theme/-/material-icon-theme-5.40.0.tgz',
  packageIntegrity: 'sha512-IrvgusbwtqxhUtVgUy0nToJcfN7CYVRdbBxKMfbo0vab9flVBHA5INZ9UiE5SgRj+PM6opCl5nn5TZdpm2UaxA==',
  sourceUrl: 'https://github.com/material-extensions/vscode-material-icon-theme',
  trademarkNote: '图标里出现的编程语言、框架和工具的标志与名称是各自所有者的商标。这里只用来标明文件是什么类型，不代表它们与 LopiCode 有合作或认可关系。MIT 许可证只管图标文件本身，不授予商标权利。',
);

/// 随包的图标包，按“第三方声明”页的显示顺序。
const List<BundledIconPack> bundledIconPacks = [providerIconPack, fileIconPack];

/// 许可证全文文件的显示名。
String licenseTitle(String asset) => switch (asset) {
  'assets/licenses/GPL-2.0.txt' => 'GNU 通用公共许可证 第 2 版（GPL-2.0）全文',
  'assets/licenses/GPL-3.0.txt' => 'GNU 通用公共许可证 第 3 版（GPL-3.0）全文',
  'assets/licenses/LGPL-3.0.txt' => 'GNU 宽通用公共许可证 第 3 版（LGPL-3.0）全文',
  'assets/licenses/libandroid-shmem.txt' => 'libandroid-shmem 许可证全文',
  'assets/licenses/lobe-icons-MIT.txt' => 'Lobe Icons 许可证（MIT）全文',
  'assets/licenses/material-icon-theme-MIT.txt' => 'Material Icon Theme 许可证（MIT）全文',
  _ => asset,
};
