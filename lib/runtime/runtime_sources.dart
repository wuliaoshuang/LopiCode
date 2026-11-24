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

/// 一键安装的语言 / 工具（“运行环境”页的清单、后端积木“运行”前的自动安装都用这一份）。
///
/// - [script] 在环境里用 bash 执行，要能重复跑（上次装到一半被取消，再跑一次能接着装好）；
/// - [marker] 是装好后环境里会出现的文件，用来不进 Ubuntu 就判断“已安装”；
/// - [commands] 是装好后终端里应该直接能用的命令（进 Ubuntu 用 `command -v` 核对用）；
/// - [downloadBytes] / [diskBytes] 是大约要下载多少、装好后占多少，null＝没核对过，界面上不显示数字。
///   数字的来源和核对日期记在 docs/api-notes.md 的“语言工具的一键安装”一节。
class RuntimePack {
  const RuntimePack({required this.id, required this.title, required this.subtitle, required this.marker, required this.script, this.commands = const [], this.downloadBytes, this.diskBytes});
  final String id;
  final String title;
  final String subtitle;
  final String marker;
  final String script;
  final List<String> commands;
  final int? downloadBytes;
  final int? diskBytes;

  /// 下载量到了 [kPackConfirmBytes]：自动安装之前先问一次（体积小的直接装，只在终端里说明）。
  bool get needsConfirm => (downloadBytes ?? 0) >= kPackConfirmBytes;

  /// 给人看的体积说明；没核对过数字的返回 null。
  String? get sizeNote {
    final down = downloadBytes, disk = diskBytes;
    if (down == null) return null;
    return disk == null ? '下载约 ${_mb(down)}' : '下载约 ${_mb(down)}，装好后占约 ${_mb(disk)}';
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

/// 自动安装前要先问一次的下载量门槛：100 MB。
/// 现在只有 JDK（约 130 MB）过线；Ubuntu 基础包（约 29 MB）、Go（约 61 MB）、PHP 都直接装。
const int kPackConfirmBytes = 100 * 1024 * 1024;

const int _mib = 1024 * 1024;

/// 先把上次被打断的安装收个尾（没有就什么都不做），再更新清单、安装。
const String _aptInstall = 'export DEBIAN_FRONTEND=noninteractive; dpkg --configure -a >/dev/null 2>&1 || true; apt-get update && apt-get install -y --no-install-recommends';

/// Node.js 官方包的下载源（和基础系统包的下载源同一个选择：国内 / 官方）。
String nodeDistBase(String sourceId) => sourceId == 'official' ? 'https://nodejs.org/dist' : 'https://npmmirror.com/mirrors/node';

/// Go 官方包的下载源：官方站，或 Go 官方给国内开的同内容站点。
String goDistBase(String sourceId) => sourceId == 'official' ? 'https://go.dev/dl' : 'https://golang.google.cn/dl';

/// 装哪一版 Go：版本、文件名、校验值都写死（校验值抄自 go.dev/dl，不信任下载源）。
const String goVersion = '1.26.11';
const String goArchive = 'go$goVersion.linux-arm64.tar.gz';
const String goArchiveSha256 = '6c2f29b458b5add0835f18b776f69c8881a6d88428f1484a6da55755e620757e';

List<RuntimePack> runtimePacks(String sourceId) => [
  RuntimePack(
    id: 'node',
    title: 'Node.js 24',
    subtitle: '官方 arm64 包，自带 npm',
    marker: 'usr/local/bin/node',
    commands: const ['node'],
    // 版本号从官方的校验清单里读出来，下载后先核对 sha256 再解压。
    // 校验没过就把下到的文件删掉：留着的话下次“接着下”会一直失败。上次已经下完整的（校验能过）就不再下。
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
grep " \$FILE\\\$" node-sums.txt | sha256sum -c - >/dev/null 2>&1 || curl -fL --retry 3 -C - "\$BASE/\$FILE" -o "\$FILE"
grep " \$FILE\\\$" node-sums.txt | sha256sum -c - || { rm -f "\$FILE"; echo "校验没通过，已删掉下到的文件"; exit 1; }
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
    commands: ['python3'],
    script: 'set -e\n$_aptInstall python3 python3-pip python3-venv\npython3 --version\n',
  ),
  const RuntimePack(id: 'git', title: 'Git', subtitle: 'Ubuntu 软件源里的 git', marker: 'usr/bin/git', commands: ['git'], script: 'set -e\n$_aptInstall ca-certificates git\ngit --version\n'),
  RuntimePack(
    id: 'go',
    title: 'Go $goVersion',
    subtitle: '官方 arm64 包，装到 /usr/local/go',
    marker: 'usr/local/bin/go',
    commands: const ['go'],
    downloadBytes: 61 * _mib,
    diskBytes: 240 * _mib,
    // /usr/local/go/bin 不在环境的 PATH 里，所以在 /usr/local/bin 放两个链接。
    script:
        '''
set -e
$_aptInstall ca-certificates curl
cd /tmp
FILE=$goArchive
echo "下载 \$FILE（约 61 MB）"
echo "$goArchiveSha256  \$FILE" | sha256sum -c - >/dev/null 2>&1 || curl -fL --retry 3 -C - "${goDistBase(sourceId)}/\$FILE" -o "\$FILE"
echo "$goArchiveSha256  \$FILE" | sha256sum -c - || { rm -f "\$FILE"; echo "校验没通过，已删掉下到的文件"; exit 1; }
echo "解压到 /usr/local/go"
rm -rf /usr/local/go
tar -xzf "\$FILE" -C /usr/local --no-same-owner
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
rm -f "\$FILE"
go version
''',
  ),
  const RuntimePack(
    id: 'java',
    title: 'Java（JDK 21）',
    subtitle: 'Ubuntu 软件源里的 OpenJDK 21，带 javac，不带图形界面部分',
    marker: 'usr/bin/javac',
    commands: ['java', 'javac'],
    downloadBytes: 130 * _mib,
    diskBytes: 300 * _mib,
    script: 'set -e\n$_aptInstall openjdk-21-jdk-headless\njava -version\njavac -version\n',
  ),
  const RuntimePack(id: 'php', title: 'PHP 8.3', subtitle: 'Ubuntu 软件源里的 PHP 命令行版', marker: 'usr/bin/php', commands: ['php'], script: 'set -e\n$_aptInstall php-cli\nphp --version\n'),
];

/// 按 id 找一项；没有返回 null。后端积木的语言 id（node / python / go / java / php）和这里的 id 是同一套。
RuntimePack? runtimePackById(List<RuntimePack> packs, String id) {
  for (final pack in packs) {
    if (pack.id == id) return pack;
  }
  return null;
}
