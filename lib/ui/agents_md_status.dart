// 设计约束
// - 这一组只回答一件事：项目里的 AGENTS.md 现在有没有被读到。
// - 一行：左边文件名，右边一个短状态（已读到 / 没有这个文件 / 读不了 / 太长）；细节放在副标题里，一句话说完。
// - 没有按钮：文件在“文件”页里改，这里只看状态。说明放在组的脚注，弱化显示。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/prompt_context.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

String _size(int bytes) => bytes >= 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '$bytes 字节';

/// “项目规则”页里显示 AGENTS.md 状态的那一组。工作区文件一变就重读。
class AgentsMdStatusGroup extends ConsumerWidget {
  const AgentsMdStatusGroup({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(filesRevProvider(session));
    final md = readAgentsMd(session.guard);
    final (value, subtitle) = switch (md.state) {
      AgentsMdState.loaded => ('已读到', '共 ${_size(md.totalBytes)}，全文都会交给 Agent'),
      AgentsMdState.truncated => ('太长', '共 ${_size(md.totalBytes)}，只把开头 ${kAgentsMdMaxBytes ~/ 1024} KB 交给 Agent，后面的它需要时自己去读'),
      AgentsMdState.empty => ('是空的', '文件里没有内容，不会生效'),
      AgentsMdState.missing => ('没有这个文件', '在工作区最外层新建一个 $kAgentsMdName 就会生效'),
      AgentsMdState.unreadable => ('读不了', '原因：${md.problem ?? '未知'}。这一轮不会用它'),
    };
    return SettingsGroup(
      title: '项目里的 $kAgentsMdName',
      footer: '项目里的 $kAgentsMdName 会自动生效：放在工作区最外层，Agent 每一轮开始时都会重新读一遍，不用在这里再抄一份。和上面手填的规则同时存在时两样都生效，有冲突以手填的为准。',
      children: [SettingsRow(key: const Key('agents-md-row'), icon: Icons.description_outlined, title: kAgentsMdName, subtitle: subtitle, value: value, valueKey: const Key('agents-md-state'))],
    );
  }
}
