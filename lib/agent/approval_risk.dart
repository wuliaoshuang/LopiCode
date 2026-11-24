// 确认卡上那一小处“危险程度”提示怎么定。**只管显示**：哪些操作要确认、能不能“本对话都允许”都不看这里，
// 那些规矩在 agent_tools.dart / toolbox_builder.dart，这里一条都不改。
import 'package:lopicode/agent/agent_tools.dart';

/// 危险程度：普通 / 需留意 / 危险。
enum RiskLevel {
  normal('普通'),
  caution('需留意'),
  danger('危险');

  const RiskLevel(this.label);
  final String label;
}

class ApprovalRisk {
  const ApprovalRisk(this.level, this.reason);
  final RiskLevel level;

  /// 一句话说为什么是这个程度。
  final String reason;
}

/// 只看不改的常见命令（单独一条、没有管道和重定向时算“普通”）。
const Set<String> _readOnlyCommands = {'ls', 'pwd', 'cat', 'head', 'tail', 'wc', 'echo', 'which', 'whoami', 'date', 'uname', 'df', 'du', 'grep', 'tree', 'file', 'stat', 'printenv'};

/// `git` 后面这些子命令只看不改。
const Set<String> _readOnlyGit = {'status', 'log', 'diff', 'show'};

final List<(RegExp, String)> _dangerPatterns = [
  (RegExp(r'(^|[;&|\s])sudo\s'), '用了 sudo，会以最高权限执行'),
  (RegExp(r'(^|[;&|\s])rm\s+(-[a-zA-Z]*[rRf][a-zA-Z]*\s|--recursive|--force)'), '会强制或成批删除文件，删了找不回来'),
  (RegExp(r'(^|[;&|\s])(mkfs|fdisk|shutdown|reboot|halt)(\.|\s|$)'), '会动到整个系统'),
  (RegExp(r'(^|[;&|\s])dd\s+.*\bof='), '会直接覆盖写入目标'),
  (RegExp(r'(^|[;&|\s])(chmod|chown)\s+(-[a-zA-Z]*R|--recursive)'), '会成批改权限'),
  (RegExp(r'(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(sh|bash|zsh)\b'), '会把网上下载的脚本直接执行'),
  (RegExp(r'\bgit\s+push\b.*(\s-f\b|--force)'), '强制推送会覆盖远程仓库的历史'),
  (RegExp(r'\bgit\s+(reset\s+--hard|clean\s+-[a-zA-Z]*f)'), '会丢掉还没提交的改动'),
  (RegExp(r'(^|[;&|\s])(kill\s+-9|killall|pkill)\s'), '会强行结束进程'),
  (RegExp(r'>\s*/dev/(sd|nvme|block)'), '会直接写磁盘设备'),
  (RegExp(r':\(\)\s*\{'), '看起来是会把系统拖垮的命令'),
];

ApprovalRisk approvalRisk(ApprovalRequest request) {
  switch (request.tool) {
    case 'delete_file':
      return ApprovalRisk(RiskLevel.danger, request.title.contains('目录') ? '整个目录都会删掉，删了找不回来' : '删了找不回来');
    case 'schedule_task':
      return const ApprovalRisk(RiskLevel.caution, '保存后会按时间自己运行，运行时没人逐步确认');
    case 'run_command':
      return commandRisk(request.detail);
    default:
      return const ApprovalRisk(RiskLevel.caution, '执行前请核对内容');
  }
}

ApprovalRisk commandRisk(String command) {
  final cmd = command.trim();
  for (final (pattern, reason) in _dangerPatterns) {
    if (pattern.hasMatch(cmd)) return ApprovalRisk(RiskLevel.danger, reason);
  }
  // 有管道、串联、重定向、子命令的，不去猜它安不安全。
  if (!RegExp(r'[;&|<>`$\n]').hasMatch(cmd)) {
    final words = cmd.split(RegExp(r'\s+'));
    final first = words.first;
    if (_readOnlyCommands.contains(first) || (first == 'git' && words.length > 1 && _readOnlyGit.contains(words[1]))) {
      return const ApprovalRisk(RiskLevel.normal, '只查看，不改动文件');
    }
  }
  return const ApprovalRisk(RiskLevel.caution, '会在运行环境里执行，可能改动文件或联网');
}
