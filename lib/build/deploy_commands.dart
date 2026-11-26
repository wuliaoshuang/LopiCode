// “构建与部署”的默认命令：本地构建每一步跑什么、SSH 上默认的编译命令、结果卡里“怎么用”。
// 全是纯函数，命令全文也记在 docs/build-deploy-design.md 第 4 节（改这里要同步改文档）。
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/build/remote_exec.dart';

/// 一步要执行的命令。
class DeployStep {
  const DeployStep(this.title, this.command);
  final String title;
  final String command;
}

/// 本地构建出来的是什么。
enum LocalOutputKind { binary, jar, archive }

class LocalBuildPlan {
  const LocalBuildPlan({required this.steps, required this.output, required this.outputKind, required this.howTo, this.packId, this.unsupported});

  /// 在运行环境里依次执行的命令（从工作区根目录出发）。可以是空的（只打压缩包）。
  final List<DeployStep> steps;

  /// 产物的文件名（在工作区 build/ 下）。
  final String output;
  final LocalOutputKind outputKind;

  /// 结果卡里“怎么用”的几句话。
  final List<String> howTo;

  /// 要用到的语言工具（运行环境清单里的 id）；不需要是 null。
  final String? packId;

  /// 这种项目本地做不了的原因；能做是 null。
  final String? unsupported;
}

String _dir(DeployProject project) => shellQuote(project.dir.isEmpty ? '.' : project.dir);

/// 语法检查时不看的目录（`find` 的 `-not -path`）。
String _prune(List<String> dirs) => [for (final d in dirs) "-not -path './$d/*'"].join(' ');

LocalBuildPlan localBuildPlan(DeployProject project, {required String name, bool amd64 = false, bool npmInstall = false}) {
  final n = deploySafeName(name);
  final cd = 'cd ${_dir(project)}';
  final archive = '$n-${project.lang.id}.tar.gz';
  final unpack = '传到服务器后解压：tar -xzf $archive（会解出一个 $n 目录）。';
  switch (project.lang) {
    case DeployLang.go:
      final arch = amd64 ? 'amd64' : 'arm64';
      final out = '$n-linux-$arch';
      return LocalBuildPlan(
        packId: 'go',
        output: out,
        outputKind: LocalOutputKind.binary,
        steps: [DeployStep('编译（linux/$arch）', 'OUT="\$PWD/build"; mkdir -p "\$OUT" && $cd && CGO_ENABLED=0 GOOS=linux GOARCH=$arch go build -buildvcs=false -o "\$OUT/$out" .')],
        howTo: [amd64 ? '这是给 x86-64 的 Linux 服务器用的，手机上跑不了。' : '这是 arm64 的 Linux 程序：手机的 Ubuntu 环境和 arm64 服务器都能跑；x86-64 的服务器要打开“给服务器用（linux/amd64）”重新编译。', '传到服务器后：chmod +x $out && ./$out'],
      );
    case DeployLang.java:
      final main = project.javaMain;
      final why = switch (project.javaLayout) {
        JavaLayout.maven => '这个 Java 项目用了 Maven（有 pom.xml）。手机上本地编译只支持“所有 .java 放在同一个目录、不带 package”的简单结构；Maven 项目请改用 GitHub 或 SSH 方式（那两种用 mvn 编译）。',
        JavaLayout.gradle => '这个 Java 项目用了 Gradle。手机上本地编译只支持“所有 .java 放在同一个目录、不带 package”的简单结构；Gradle 项目请改用 GitHub 或 SSH 方式。',
        JavaLayout.packaged => '这个 Java 项目的源码带包名（package）或放在 src/main/java 里，但没有 pom.xml / build.gradle。手机上本地编译只支持“所有 .java 放在同一个目录、不带 package”的简单结构。',
        _ => main == null ? '没找到带 main 方法的类，不知道 jar 的入口是谁。' : null,
      };
      return LocalBuildPlan(
        packId: 'java',
        output: '$n.jar',
        outputKind: LocalOutputKind.jar,
        unsupported: why,
        steps: why != null
            ? const []
            : [
                DeployStep(
                  '编译并打成 jar',
                  'OUT="\$PWD/build"; rm -rf "\$OUT/classes-$n" && mkdir -p "\$OUT/classes-$n" && $cd && javac -encoding UTF-8 -d "\$OUT/classes-$n" *.java && '
                      'jar --create --file "\$OUT/$n.jar" --main-class $main -C "\$OUT/classes-$n" .',
                ),
              ],
        howTo: ['传到装了 Java 的服务器后：java -jar $n.jar'],
      );
    case DeployLang.node:
      return LocalBuildPlan(
        packId: 'node',
        output: archive,
        outputKind: LocalOutputKind.archive,
        steps: [
          DeployStep(
            '语法检查（node --check）',
            "$cd && find . -type f \\( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \\) ${_prune(['node_modules', 'build', '.lopicode'])} -print0 | xargs -0 -r -n 1 node --check",
          ),
          if (npmInstall && project.hasPackageJson) DeployStep('装依赖（npm install --omit=dev）', '$cd && npm install --omit=dev'),
        ],
        howTo: [
          unpack,
          if (project.hasPackageJson && !npmInstall) '依赖没有装进包里：到服务器上进目录后先跑 npm install --omit=dev。',
          if (project.hasPackageJson && npmInstall) '依赖已经装进包里（在手机 arm64 上装的；里面有按 CPU 编译的模块时，放到 x86-64 服务器上要重新 npm install）。',
          '启动：node ${project.entry ?? 'server.js'}',
        ],
      );
    case DeployLang.python:
      return LocalBuildPlan(
        packId: 'python',
        output: archive,
        outputKind: LocalOutputKind.archive,
        steps: [
          DeployStep(
            '语法检查（py_compile）',
            "$cd && find . -type f -name '*.py' ${_prune(['.venv', 'venv', 'build', '.lopicode'])} -print0 | PYTHONPYCACHEPREFIX=/tmp/lopicode-pyc xargs -0 -r python3 -m py_compile",
          ),
        ],
        howTo: [unpack, if (project.hasRequirements) '依赖没有装进包里：到服务器上进目录后先跑 python3 -m venv .venv && .venv/bin/pip install -r requirements.txt。', '启动：python3 ${project.entry ?? 'main.py'}'],
      );
    case DeployLang.php:
      return LocalBuildPlan(
        packId: 'php',
        output: archive,
        outputKind: LocalOutputKind.archive,
        steps: [
          DeployStep('语法检查（php -l）', "$cd && find . -type f -name '*.php' ${_prune(['vendor', 'build', '.lopicode'])} -print0 | xargs -0 -r -n 1 php -l"),
        ],
        howTo: [unpack, if (project.hasComposer) '依赖没有装进包里：到服务器上进目录后先跑 composer install --no-dev。', '把目录交给 PHP 服务器（或 php -S 0.0.0.0:8080）。'],
      );
    case DeployLang.other:
      return LocalBuildPlan(
        output: '$n-source.tar.gz',
        outputKind: LocalOutputKind.archive,
        steps: const [],
        howTo: ['没认出语言，只把源码打成了压缩包。传到服务器后解压：tar -xzf $n-source.tar.gz（会解出一个 $n 目录），再按这种语言的办法编译、启动。'],
      );
  }
}

/// SSH 上默认的“编译 / 装依赖”命令（在远程目录里执行）；拿不准的给空，让她自己填。
String defaultRemoteBuildCommand(DeployProject project) => switch (project.lang) {
  DeployLang.go => 'go build -buildvcs=false -o server .',
  DeployLang.java => switch (project.javaLayout) {
    JavaLayout.flat => 'javac -encoding UTF-8 -d out *.java',
    JavaLayout.maven => 'mvn -B package',
    JavaLayout.gradle => 'gradle build',
    _ => '',
  },
  DeployLang.node => project.hasPackageJson ? 'npm install --omit=dev' : (project.entry == null ? '' : 'node --check ${shellQuote(project.entry!)}'),
  DeployLang.python =>
    project.hasRequirements ? 'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt' : (project.entry == null ? '' : 'python3 -m py_compile ${shellQuote(project.entry!)}'),
  DeployLang.php => project.hasComposer ? 'composer install --no-dev' : (project.entry == null ? '' : 'php -l ${shellQuote(project.entry!)}'),
  DeployLang.other => '',
};

/// 上传到远程目录里的压缩包叫什么（每次覆盖，不删）。
const String kRemoteArchiveName = 'lopicode-upload.tar.gz';

/// `~/x` 这种路径不能整个加引号（加了就不展开了）。
String quoteRemotePath(String path) {
  if (path == '~') return '~';
  if (path.startsWith('~/')) return '~/${shellQuote(path.substring(2))}';
  return shellQuote(path);
}

/// SSH 部署的整张步骤清单（开始前原样显示给她）。第 2 步（上传）先用 [sshResolveDirCommand] 查出目录的完整路径（SFTP 不认 `~`），再传文件。
List<DeployStep> sshDeploySteps({required String remoteDir, required String buildCommand, String? restartCommand}) {
  final dir = quoteRemotePath(remoteDir);
  return [
    DeployStep('建目录', 'mkdir -p $dir'),
    DeployStep('上传代码', 'cd $dir && pwd   # 查出目录的完整路径，然后用 SFTP 把代码打成的 $kRemoteArchiveName 传进去'),
    DeployStep('解压（同名文件覆盖，远端多出来的文件不动）', 'cd $dir && tar -xzf $kRemoteArchiveName --strip-components=1'),
    if (buildCommand.trim().isNotEmpty) DeployStep('编译 / 装依赖', 'cd $dir && ${buildCommand.trim()}'),
    if (restartCommand != null && restartCommand.trim().isNotEmpty) DeployStep('重启服务', 'cd $dir && ${restartCommand.trim()}'),
  ];
}

/// 上传前查远程目录完整路径的命令（只读）。
String sshResolveDirCommand(String remoteDir) => 'cd ${quoteRemotePath(remoteDir)} && pwd';
