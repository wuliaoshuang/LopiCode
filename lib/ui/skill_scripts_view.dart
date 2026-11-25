// 设计约束（技能附带的脚本 · 390×844）— 2026-11-25
// - 技能清单那一行：描述下面多一行淡字“带 N 个脚本”，没有脚本就没有这一行；不加图标、不加颜色。
// - 技能全文页：正文下面多一组〔附带的脚本〕，一行一个脚本（等宽的相对路径），不可点；
//   组底下的说明一句话讲清：Agent 在哪跑它、要不要确认、现在跑不跑得了。没有脚本这一组不出现。
// - 没有主操作。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/skill_scripts.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 技能清单里接在描述后面的那一行；没有脚本是空字符串。
String skillScriptsBadge(Skill skill) {
  if (skill.files.tooBig) return '\n附带的文件太多，脚本用不了';
  return skill.scripts.isEmpty ? '' : '\n带 ${skill.scripts.length} 个脚本';
}

/// 技能全文页里的〔附带的脚本〕。
class SkillScriptsGroup extends ConsumerWidget {
  const SkillScriptsGroup({super.key, required this.skill});
  final Skill skill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = skill.files;
    if (files.tooBig) {
      return const SettingsGroup(
        title: '附带的脚本',
        footer: '这个技能文件夹里的文件超过 $kSkillMaxFiles 个或 ${kSkillMaxBytes ~/ (1024 * 1024)}MB，不会放进运行环境，里面的脚本 Agent 跑不了。技能的文字说明照常能用。',
        children: [SettingsRow(title: '附带的文件太多或太大', enabled: false)],
      );
    }
    if (files.scripts.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    // 运行环境装没装好：只决定底下那句说明怎么写。
    final (usable, needsSetup) = ref.watch(runtimeProvider.select((r) => (r.usable, r.needsSetup)));
    return SettingsGroup(
      key: const Key('skill-scripts'),
      title: '附带的脚本（${files.scripts.length} 个）',
      footer: needsSetup
          ? '运行环境还没装好，这些脚本现在跑不了，Agent 只会照文字说明做。装好运行环境后，Agent 才能用“执行命令”跑它们（照样每次要你确认）。'
          : usable
          ? 'Agent 读这个技能时会知道这些脚本在运行环境的 $kGuestSkillsDir/${skill.name}/ 里，用“执行命令”来跑——和别的命令一样，每次要你确认（完全权限除外）。放进去的是副本，脚本改不到这里的原件。'
          : 'Agent 读这个技能时会知道这些脚本在哪，用“执行命令”来跑——和别的命令一样，每次要你确认（完全权限除外）。',
      padded: true,
      children: [
        for (final s in files.scripts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Text(
              s,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.text),
            ),
          ),
      ],
    );
  }
}
