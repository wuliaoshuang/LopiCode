// 系统提示词里跟着“这个工作区、这台机器”走的两段：
// 1) 工作区根目录的 AGENTS.md（项目自己带的指令）；
// 2) 命令到底在什么环境里跑（Ubuntu 运行环境 / 还没装 / 桌面本机）。
//
// 两段都是每一轮开始时现读现拼（改了文件、装了环境，下一轮就生效），读不到、读坏了都不抛异常。
// 环境那一段里的每个事实都从代码里的真实值来（镜像版本、挂载点、bash、已装的语言清单、命令时限），不凭印象写：
// 判断“命令进不进 Ubuntu”的条件和 lib/runtime/linux_command_runner.dart 里的一模一样。
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';

/// 项目指令文件的名字（只认工作区根目录下、大小写完全一致的这一个）。
const String kAgentsMdName = 'AGENTS.md';

/// AGENTS.md 最多放进系统提示词多少字节（约 8 千个汉字 / 2 万多个英文字符）。超出的截掉，并告诉模型去读全文。
const int kAgentsMdMaxBytes = 24 * 1024;

enum AgentsMdState {
  /// 工作区根目录没有这个文件。
  missing,

  /// 有，但是空的（只有空白）。
  empty,

  /// 读到了，全文都放进去了。
  loaded,

  /// 读到了，但太长，只放了开头一段。
  truncated,

  /// 有这个名字，但读不了（是目录、不是文本、没有权限……）。
  unreadable,
}

/// 读 AGENTS.md 的结果。
class AgentsMd {
  const AgentsMd(this.state, {this.text = '', this.totalBytes = 0, this.problem});
  final AgentsMdState state;

  /// 放进系统提示词的正文（[AgentsMdState.loaded] / [AgentsMdState.truncated] 时才有）。
  final String text;

  /// 文件一共多大。
  final int totalBytes;

  /// 读不了的原因（给人看的话）。
  final String? problem;

  bool get active => state == AgentsMdState.loaded || state == AgentsMdState.truncated;
}

/// 读工作区根目录的 AGENTS.md。任何情况都不抛异常。
///
/// 同步读：系统提示词是同步拼的，而且文件最多只读 [kAgentsMdMaxBytes] 这么一小段。
AgentsMd readAgentsMd(PathGuard guard) {
  try {
    final path = guard.resolve(kAgentsMdName);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return const AgentsMd(AgentsMdState.missing);
    if (type != FileSystemEntityType.file) return const AgentsMd(AgentsMdState.unreadable, problem: '它不是一个普通文件');
    final file = File(path);
    final total = file.lengthSync();
    final handle = file.openSync();
    final List<int> bytes;
    try {
      bytes = handle.readSync(total > kAgentsMdMaxBytes ? kAgentsMdMaxBytes : total);
    } finally {
      handle.closeSync();
    }
    if (bytes.contains(0)) return AgentsMd(AgentsMdState.unreadable, totalBytes: total, problem: '它不是文本文件');
    var text = utf8.decode(bytes, allowMalformed: true);
    final cut = total > kAgentsMdMaxBytes;
    // 截在一个字的中间时，最后会多出一个“�”：去掉。
    if (cut) text = text.replaceFirst(RegExp('\u{FFFD}+\$'), '');
    if (text.trim().isEmpty) return AgentsMd(AgentsMdState.empty, totalBytes: total);
    return AgentsMd(cut ? AgentsMdState.truncated : AgentsMdState.loaded, text: text.trim(), totalBytes: total);
  } on PathGuardException catch (e) {
    return AgentsMd(AgentsMdState.unreadable, problem: e.message);
  } on FileSystemException catch (e) {
    return AgentsMd(AgentsMdState.unreadable, problem: e.osError?.message ?? e.message);
  }
}

/// 系统提示词里 AGENTS.md 那一段；没读到返回 null。
String? agentsMdSection(AgentsMd md) {
  if (!md.active) return null;
  final cut = md.state == AgentsMdState.truncated ? '\n\n（$kAgentsMdName 共 ${md.totalBytes} 字节，太长，上面只放了开头约 ${kAgentsMdMaxBytes ~/ 1024}KB。后面的内容没有给你：需要时用 read_file 读 $kAgentsMdName，按行分段看。）' : '';
  return '这个项目根目录的 $kAgentsMdName（项目自带的说明，来源是工作区里的文件；必须遵守。和上面用户手填的规则冲突时，以用户手填的为准）：\n${md.text}$cut';
}

/// 系统提示词里“命令在什么环境里跑”那一段。
///
/// [guestCwd]：工作区本来就是 Ubuntu 里的目录时，它在环境里的路径；否则项目挂在 [guestWorkspace]。
/// [customRunner]：测试 / 调试换掉了执行环境时，照它自己的说明写。
String environmentSection(LinuxRuntime runtime, {String? guestCwd, CommandRunner? customRunner}) {
  if (customRunner != null) return '命令执行环境：${customRunner.description}。';
  final linuxOnly = !runtime.localShellAllowed;
  final useLinux = linuxOnly ? runtime.usable : runtime.shouldUseLinux;
  if (linuxOnly && !runtime.usable) {
    final why = runtime.busy
        ? 'Ubuntu 运行环境正在安装，还没装完'
        : runtime.installed
        ? 'Ubuntu 运行环境已经下载，但这个安装包里缺少进入它要用的文件，进不去'
        : 'Ubuntu 运行环境还没有安装';
    return '命令执行环境：$why。现在 run_command 不会执行任何命令（会直接返回“没有执行”），不要反复尝试。'
        '需要跑命令时，请用户先到底部“终端”页或侧边栏“运行环境”页把运行环境装好；读写文件、改页面这些不需要命令的事可以照常做。';
  }
  if (!useLinux) {
    final local = LocalShellRunner();
    return '命令执行环境：${local.description}（${Platform.operatingSystem} ${Platform.operatingSystemVersion}），不是手机上的 Ubuntu 运行环境。'
        '这台机器上装了什么要自己先查（例如 command -v node），不要假设；每条命令最长 ${LinuxCommandRunner(runtime).commandTimeout.inSeconds} 秒。';
  }
  final arch = runtime.image.fileName.contains('arm64') ? ' arm64' : '';
  final installed = [
    for (final pack in runtime.packs)
      if (runtime.packInstalled(pack)) pack,
  ];
  final missing = [
    for (final pack in runtime.packs)
      if (!runtime.packInstalled(pack)) pack.title,
  ];
  final shell = guestRun('').first;
  final lines = <String>[
    '命令执行环境（run_command 就在这里面跑）：',
    '- 系统：Ubuntu ${runtime.image.version}$arch，通过 PRoot 跑在手机上（PRoot 用 -0 把你装成 root，并不是真正的系统权限）。',
    '- 用户是 root，不需要也没有 sudo；shell 是 $shell（每条命令用 bash -lc 执行）。',
    '- 项目目录在 ${guestCwd ?? guestWorkspace}，命令从这里开始执行；文件工具用的相对路径就是相对它。',
    '- 装软件用 apt（先 apt-get update；加 -y，不要等人输入）。软件源：${runtime.aptMirror.label}。',
    if (installed.isNotEmpty) '- 已经装好的语言 / 工具：${installed.map((p) => p.commands.isEmpty ? p.title : '${p.title}（命令 ${p.commands.join('、')}）').join('；')}。',
    if (missing.isNotEmpty) '- 还没装的：${missing.join('、')}。要用时可以用 apt 装，或者请用户到“运行环境”页一键安装。',
    '- 每条命令最长 ${LinuxCommandRunner(runtime).commandTimeout.inMinutes} 分钟，超时会被强制结束。',
  ];
  return lines.join('\n');
}
