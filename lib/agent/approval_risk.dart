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
  (RegExp(r'(^|[;&|\s(])(sudo|doas)\s'), '用了 sudo，会以最高权限执行'),
  (RegExp(r'(^|[;&|\s(])su\s+(-|-c\b|root\b)'), '会切换成最高权限的用户执行'),
  // rm：只要带了 -r / -R / -f（不管写在第几个参数、是不是和别的字母连写）就算。
  (RegExp(r'(^|[;&|\s(])rm\s+([^;&|]*\s)?(-[a-zA-Z]*[rRf][a-zA-Z]*(\s|$)|--recursive|--force|--no-preserve-root)'), '会强制或成批删除文件，删了找不回来'),
  (RegExp(r'\bxargs\s+([^;&|]*\s)?rm\b'), '会成批删除文件，删了找不回来'),
  (RegExp(r'(^|[;&|\s(])find\s[^;&|]*\s(-delete\b|-exec\s+rm\b)'), '会成批删除找到的文件，删了找不回来'),
  (RegExp(r'(^|[;&|\s(])(shred|wipefs)\s'), '会把内容彻底抹掉，找不回来'),
  (RegExp(r'(^|[;&|\s(])(mkfs|fdisk|parted|shutdown|reboot|halt|poweroff)(\.|\s|$)'), '会动到整个系统'),
  (RegExp(r'(^|[;&|\s(])dd\s+.*\bof='), '会直接覆盖写入目标'),
  (RegExp(r'(^|[;&|\s(])(chmod|chown|chgrp)\s+([^;&|]*\s)?(-[a-zA-Z]*R[a-zA-Z]*(\s|$)|--recursive)'), '会成批改权限'),
  (RegExp(r'(^|[;&|\s(])chmod\s+([^;&|]*\s)?0?777(\s|$)'), '会把权限放开给所有人'),
  (RegExp(r'(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(sh|bash|zsh|dash|ash|python3?|node)\b'), '会把网上下载的脚本直接执行'),
  (
    RegExp(
      r'(^|[;&|\s(])(sh|bash|zsh)\s+(-c\s+)?["'
      "'"
      r']?\$\((curl|wget)\b',
    ),
    '会把网上下载的脚本直接执行',
  ),
  (RegExp(r'(^|[;&|\s(])(sh|bash|zsh)\s+<\(\s*(curl|wget)\b'), '会把网上下载的脚本直接执行'),
  (RegExp(r'\bgit\s+push\b.*(\s-f\b|--force|\s\+[\w./-]+)'), '强制推送会覆盖远程仓库的历史'),
  (RegExp(r'\bgit\s+push\b.*(\s--delete\b|\s-d\b|\s:[\w./-]+)'), '会删掉远程仓库上的分支或标签'),
  (RegExp(r'\bgit\s+(reset\s+([^;&|]*\s)?--hard|clean\s+([^;&|]*\s)?(-[a-zA-Z]*f|--force))'), '会丢掉还没提交的改动'),
  (RegExp(r'\bgit\s+(checkout|restore)\s+([^;&|]*\s)?(--\s+)?\.(\s|$)'), '会丢掉还没提交的改动'),
  (RegExp(r'\bgit\s+checkout\s+([^;&|]*\s)?(-f\b|--force\b)'), '会丢掉还没提交的改动'),
  (RegExp(r'\bgit\s+stash\s+(drop|clear)\b'), '会丢掉暂存起来的改动'),
  (RegExp(r'\bgit\s+branch\s+([^;&|]*\s)?-D\b'), '会强制删除分支，没合并的提交可能找不回来'),
  (RegExp(r'\bgit\s+(filter-branch|filter-repo)\b|\bgit\s+reflog\s+expire\b|\bgit\s+gc\s+[^;&|]*--prune'), '会改写或清掉仓库历史'),
  (RegExp(r'(^|[;&|\s(])(kill\s+(-9|-KILL|-s\s+(9|KILL))|killall|pkill)\s'), '会强行结束进程'),
  (RegExp(r'>\s*/dev/(sd|nvme|block|mmcblk)'), '会直接写磁盘设备'),
  (RegExp(r':\(\)\s*\{'), '看起来是会把系统拖垮的命令'),
  // 数据库：整库整表删除、清空；不带 WHERE 的 DELETE。
  (RegExp(r'\b(drop\s+(table|database|schema)|truncate\s+(table\s+)?[\w`"]+)', caseSensitive: false), '会删掉或清空数据库里的表 / 库，找不回来'),
  (
    RegExp(
      r'\bdelete\s+from\s+[\w`".]+\s*(;|"|'
      "'"
      r'|$)',
      caseSensitive: false,
    ),
    '没有条件的删除会清空整张表',
  ),
  (RegExp(r'\b(flushall|flushdb)\b', caseSensitive: false), '会清空 Redis 里的数据'),
  // 把东西发布 / 推到外面去，收不回来。
  (RegExp(r'(^|[;&|\s(])(npm|pnpm|yarn)\s+publish\b|(^|[;&|\s(])(cargo|flutter\s+pub|dart\s+pub)\s+publish\b'), '会把包发布到公开仓库，发了收不回来'),
  // 重定向 / 移动 / 复制到工作区外面（绝对路径、主目录、上级目录）。/dev/null、/dev/stdout、/dev/stderr、/tmp 不算。
  (
    RegExp(
      r'(^|[^0-9&<>])[0-9]?>>?\s*["'
      "'"
      r']?(~|\$HOME|\.\./|/(?!dev/(null|stdout|stderr|tty)\b|tmp/))',
    ),
    '会写到工作区以外的文件',
  ),
  (
    RegExp(
      r'\btee\s+([^;&|]*\s)?["'
      "'"
      r']?(~|\$HOME|\.\./|/(?!dev/(null|stdout|stderr|tty)\b|tmp/))',
    ),
    '会写到工作区以外的文件',
  ),
  (RegExp(r'(^|[;&|\s(])mv\s+[^;&|]*\s/dev/null(\s|$)'), '会把文件丢掉，找不回来'),
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
      if (request.alwaysKey?.startsWith('mcp:') ?? false) return const ApprovalRisk(RiskLevel.caution, '会把下面的参数发给外部服务器，由它来执行');
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
