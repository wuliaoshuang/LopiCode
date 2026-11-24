/// 本机 Linux 运行环境用到的下载地址和固定数值。
/// 这里的每个地址都在 2026-11-23 实际请求过（见 docs/linux-runtime.md）。
library;

/// Ubuntu 24.04 基础系统包（arm64）。大小和校验值来自官方 SHA256SUMS，
/// 三个下载源给出的值一致。
class RootfsImage {
  const RootfsImage({required this.version, required this.fileName, required this.size, required this.sha256});
  final String version;
  final String fileName;
  final int size;
  final String sha256;

  static const ubuntu2404Arm64 = RootfsImage(
    version: '24.04.5',
    fileName: 'ubuntu-base-24.04.5-base-arm64.tar.gz',
    size: 29936675,
    sha256: 'a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2',
  );

  /// 解压后大约占多少（主机上实测 103 MB），安装前提示用。
  static const int extractedBytes = 103 * 1024 * 1024;

  /// 安装时建议至少留出的空间：压缩包 + 解压后 + 一点余量。
  static const int requiredBytes = 150 * 1024 * 1024;
}

/// 一个可选的下载源。
class MirrorOption {
  const MirrorOption(this.id, this.label, this.base);
  final String id;
  final String label;
  final String base;
}

/// 基础系统包从哪下。默认国内镜像，可以切回官方。
const List<MirrorOption> rootfsSources = [
  MirrorOption('tuna', '清华大学镜像', 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release'),
  MirrorOption('aliyun', '阿里云镜像', 'https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release'),
  MirrorOption('official', 'Ubuntu 官方', 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release'),
];

/// 环境里 apt 装软件从哪下（arm64 走 ubuntu-ports）。
/// 基础系统里没有证书包，所以这里一律用 http；软件包本身有 apt 的签名校验。
const List<MirrorOption> aptMirrors = [
  MirrorOption('tuna', '清华大学镜像', 'http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports'),
  MirrorOption('aliyun', '阿里云镜像', 'http://mirrors.aliyun.com/ubuntu-ports'),
  MirrorOption('official', 'Ubuntu 官方', 'http://ports.ubuntu.com/ubuntu-ports'),
];

MirrorOption mirrorById(List<MirrorOption> list, String id) => list.firstWhere((m) => m.id == id, orElse: () => list.first);

/// apt 的软件源文件内容（deb822 格式，和基础系统自带的文件同一格式）。
String aptSourcesFor(MirrorOption mirror) =>
    '''
Types: deb
URIs: ${mirror.base}
Suites: noble noble-updates noble-backports noble-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
''';

/// 域名解析服务器：先国内的，再通用的。
const String guestResolvConf = 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n';

/// 一键安装的常用运行时。[script] 在环境里用 bash 执行；
/// [marker] 是装好后环境里会出现的文件，用来判断“已安装”。
class RuntimePack {
  const RuntimePack({required this.id, required this.title, required this.subtitle, required this.marker, required this.script});
  final String id;
  final String title;
  final String subtitle;
  final String marker;
  final String script;
}

const String _aptInstall = 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y --no-install-recommends';

/// Node.js 官方包的下载源（和基础系统包的下载源同一个选择：国内 / 官方）。
String nodeDistBase(String sourceId) => sourceId == 'official' ? 'https://nodejs.org/dist' : 'https://npmmirror.com/mirrors/node';

List<RuntimePack> runtimePacks(String sourceId) => [
  RuntimePack(
    id: 'node',
    title: 'Node.js 24',
    subtitle: '官方 arm64 包，自带 npm',
    marker: 'usr/local/bin/node',
    // 版本号从官方的校验清单里读出来，下载后先核对 sha256 再解压。
    script:
        '''
set -e
$_aptInstall ca-certificates curl xz-utils
BASE=${nodeDistBase(sourceId)}/latest-v24.x
cd /tmp
curl -fsSL "\$BASE/SHASUMS256.txt" -o node-sums.txt
FILE=\$(grep -o 'node-v[0-9.]*-linux-arm64\\.tar\\.xz' node-sums.txt | head -n 1)
test -n "\$FILE"
echo "下载 \$FILE"
curl -fL --retry 3 -C - "\$BASE/\$FILE" -o "\$FILE"
grep " \$FILE\\\$" node-sums.txt | sha256sum -c -
tar -xJf "\$FILE" -C /usr/local --strip-components=1 --no-same-owner
rm -f "\$FILE" node-sums.txt
node --version
npm --version
''',
  ),
  const RuntimePack(
    id: 'python',
    title: 'Python 3.12',
    subtitle: 'Ubuntu 软件源里的，带 pip 和 venv',
    marker: 'usr/bin/python3',
    script: 'set -e\n$_aptInstall python3 python3-pip python3-venv\npython3 --version\n',
  ),
  const RuntimePack(id: 'git', title: 'Git', subtitle: 'Ubuntu 软件源里的 git', marker: 'usr/bin/git', script: 'set -e\n$_aptInstall ca-certificates git\ngit --version\n'),
];
