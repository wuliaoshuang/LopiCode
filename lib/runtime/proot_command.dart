/// 一条可以直接交给系统执行的 PRoot 命令。
class ProotCommand {
  const ProotCommand({required this.executable, required this.arguments, required this.environment});
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

/// 安装包里 PRoot 两个文件的名字。Android 只允许执行安装包自带的原生库目录里的文件，
/// 而且只会解出名字是 lib*.so 的文件，所以可执行文件也得起这种名字。
abstract final class ProotFiles {
  static const proot = 'libproot.so';
  static const loader = 'libproot-loader.so';
}

/// 环境里固定的 PATH。
const String guestPath = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

/// 拼出进入 Ubuntu 环境的命令。
///
/// 参数都对照 PRoot 源码里的选项表核对过（termux/proot，src/cli/proot.h）：
/// - `-r` 指定根目录；`-b 主机路径:环境里的路径` 把手机上的目录挂进去；`-w` 是进去后的当前目录；
/// - `-0` 让当前用户看起来是 root（apt 需要）；
/// - `--link2symlink` 用符号链接顶替硬链接（应用目录里建不了硬链接，dpkg 会用到）；
/// - `--kill-on-exit` 主命令退出时把它留下的子进程一起结束。
///
/// PRoot 自己的环境变量：
/// - `PROOT_LOADER`：环境里每个程序其实都是由这个加载器“代为启动”的。它必须放在安装包的
///   原生库目录里——放在应用数据目录的文件，Android 10 以上不允许直接执行；
/// - `PROOT_TMP_DIR`：PRoot 自己的临时目录；
/// - `PROOT_NO_SECCOMP=1`：兼容模式，个别手机的内核过滤规则会让默认模式起不来。
///
/// 环境里的命令用 `env -i` 起头，把 Android 注入的变量（LD_PRELOAD 之类）全部清掉，
/// 只留下这里列出的几个。
ProotCommand buildProotCommand({
  required String nativeLibDir,
  required String rootfs,
  required String tmpDir,
  required List<String> guestCommand,
  String? projectDir,
  String term = 'xterm-256color',
  bool noSeccomp = false,
  Map<String, String> guestEnv = const {},
}) {
  final env = <String, String>{
    'HOME': '/root',
    'USER': 'root',
    'LOGNAME': 'root',
    'SHELL': '/bin/bash',
    'TERM': term,
    'LANG': 'C.UTF-8',
    'PATH': guestPath,
    'TMPDIR': '/tmp',
    ...guestEnv,
  };
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
      if (projectDir != null) ...['-b', '$projectDir:$guestWorkspace'],
      '-w', projectDir != null ? guestWorkspace : '/root',
      '/usr/bin/env', '-i',
      for (final e in env.entries) '${e.key}=${e.value}',
      ...guestCommand,
    ],
    environment: {
      'PROOT_LOADER': '$nativeLibDir/${ProotFiles.loader}',
      'PROOT_TMP_DIR': tmpDir,
      'LD_PRELOAD': '',
      if (noSeccomp) 'PROOT_NO_SECCOMP': '1',
    },
  );
}

/// 项目目录在环境里的位置。
const String guestWorkspace = '/workspace';

/// 交互式登录 shell。
const List<String> guestLoginShell = ['/bin/bash', '-l'];

/// 执行一条命令（Agent、一键安装用）。
List<String> guestRun(String script) => ['/bin/bash', '-lc', script];
