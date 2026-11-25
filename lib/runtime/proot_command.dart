/// 一条可以直接交给系统执行的 PRoot 命令。
class ProotCommand {
  const ProotCommand({required this.executable, required this.arguments, required this.environment});
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

/// 安装包里 PRoot 相关文件的名字。Android 只允许执行安装包自带的原生库目录里的文件，
/// 而且只会解出名字是 lib*.so 的文件，所以可执行文件也得起这种名字。
///
/// 四个文件都是 Termux 官方软件源里现成包的原样文件，只改了文件名（见 docs/linux-runtime.md）。
abstract final class ProotFiles {
  /// PRoot 本体（Termux 包里的 `bin/proot`）。
  static const proot = 'libproot.so';

  /// 加载器（Termux 包里的 `libexec/proot/loader`）。
  static const loader = 'libproot-loader.so';

  /// PRoot 依赖的 talloc 库（Termux 包里的 `lib/libtalloc.so.2.5.0`）。
  static const talloc = 'libtalloc.so';

  /// PRoot 依赖的共享内存库（Termux 包里的 `lib/libandroid-shmem.so`，名字没变）。
  static const shmem = 'libandroid-shmem.so';

  /// PRoot 本体里写死要找的 talloc 文件名。这个名字不是 lib*.so 结尾，进不了安装包，
  /// 所以运行前在应用私有目录里建一个叫这个名字的链接，指向安装包里的 [talloc]。
  static const tallocSoname = 'libtalloc.so.2';

  /// 安装包里必须齐全的文件。
  static const bundled = [proot, loader, talloc, shmem];
}

/// 环境里固定的 PATH。
const String guestPath = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

/// 拼出进入 Ubuntu 环境的命令。
///
/// 参数都对照 PRoot 源码里的选项表核对过（termux/proot，src/cli/proot.h）：
/// - `-r` 指定根目录；`-b 主机路径:环境里的路径` 把手机上的目录挂进去；`-w` 是进去后的当前目录；
///   （`-b` 没有“只读”的写法——2026-11-25 对照安装包里这一版 PRoot 自带的帮助核对过——所以技能目录挂的是副本，见 lib/agent/skill_mirror.dart）
/// - `-0` 让当前用户看起来是 root（apt 需要）；
/// - `--link2symlink` 用符号链接顶替硬链接（应用目录里建不了硬链接，dpkg 会用到）；
/// - `--kill-on-exit` 主命令退出时把它留下的子进程一起结束。
///
/// PRoot 自己的环境变量：
/// - `PROOT_LOADER`：环境里每个程序其实都是由这个加载器“代为启动”的。它必须放在安装包的
///   原生库目录里——放在应用数据目录的文件，Android 10 以上不允许直接执行；
/// - `PROOT_TMP_DIR`：PRoot 自己的临时目录（Termux 的包默认用 Termux 自己的目录，我们没有，必须指定）；
/// - `LD_LIBRARY_PATH`：告诉系统去哪找 PRoot 依赖的两个库。Termux 的包里写的查找路径是
///   Termux 自己的目录，在我们这里不存在，所以要另外指：先找 [libDir]（里面有
///   `libtalloc.so.2` 这个链接），再找安装包的原生库目录。这个变量只给 PRoot 自己用，
///   进不到 Ubuntu 里面（下面的 `env -i` 会清掉）；
/// - `PROOT_NO_SECCOMP=1`：兼容模式，个别手机的内核过滤规则会让默认模式起不来。
///
/// 环境里的命令用 `env -i` 起头，把 Android 注入的变量（LD_PRELOAD 之类）全部清掉，
/// 只留下这里列出的几个。
ProotCommand buildProotCommand({
  required String nativeLibDir,
  required String libDir,
  required String rootfs,
  required String tmpDir,
  required List<String> guestCommand,
  String? projectDir,
  String? guestCwd,
  String term = 'xterm-256color',
  bool noSeccomp = false,
  Map<String, String> guestEnv = const {},
  List<(String host, String guest)> extraBinds = const [],
}) {
  final env = <String, String>{'HOME': '/root', 'USER': 'root', 'LOGNAME': 'root', 'SHELL': '/bin/bash', 'TERM': term, 'LANG': 'C.UTF-8', 'PATH': guestPath, 'TMPDIR': '/tmp', ...guestEnv};
  return ProotCommand(
    executable: '$nativeLibDir/${ProotFiles.proot}',
    arguments: [
      '--kill-on-exit',
      '--link2symlink',
      '-0',
      '-r', rootfs,
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      // Android 没有 /dev/shm，拿环境自己的 /tmp 顶上。
      '-b', '$rootfs/tmp:/dev/shm',
      // [guestCwd]：工作区本来就是环境里的目录，不用挂载，直接进去。
      if (projectDir != null && guestCwd == null) ...['-b', '$projectDir:$guestWorkspace'],
      // 额外挂进去的目录（技能镜像挂在 /skills）。每个 `主机路径:环境路径` 是单独一个参数，不经过 shell，路径里有空格、中文都没关系。
      for (final (host, guest) in extraBinds) ...['-b', '$host:$guest'],
      '-w', guestCwd ?? (projectDir != null ? guestWorkspace : '/root'),
      '/usr/bin/env', '-i',
      for (final e in env.entries) '${e.key}=${e.value}',
      ...guestCommand,
    ],
    environment: {'PROOT_LOADER': '$nativeLibDir/${ProotFiles.loader}', 'PROOT_TMP_DIR': tmpDir, 'LD_LIBRARY_PATH': '$libDir:$nativeLibDir', 'LD_PRELOAD': '', if (noSeccomp) 'PROOT_NO_SECCOMP': '1'},
  );
}

/// 项目目录在环境里的位置。
const String guestWorkspace = '/workspace';

/// 交互式登录 shell。
const List<String> guestLoginShell = ['/bin/bash', '-l'];

/// 执行一条命令（Agent、一键安装用）。
List<String> guestRun(String script) => ['/bin/bash', '-lc', script];
