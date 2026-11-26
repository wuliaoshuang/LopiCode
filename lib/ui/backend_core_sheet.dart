// 设计约束（后端积木·“类型与类”面板，390 宽，浅色 + 深色）— 2026-11-26
// - 内容排序：主＝已有的类型（一种一行：名字在左最显眼，右边小字说它是哪一种、有几样东西）；
//   次＝“新建…”（面板底部一颗实心按钮，点了再选是哪一种——六种不摊开）；三＝说明小字。
// - 一行只做一件事：点一行＝进这个类型的面板去改；这里不放删除、改名（都在那个面板里）。
// - 空状态：没有类型时只有一句说明和“新建…”，不出现空列表。
// - 颜色全取主题值；间距只用 Space 里的档；层级：标题 > 行的名字 > 行右边的小字（次要色）。
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_type_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 面板的统一骨架：标题一行、说明小字、出问题时的一行、能滚的内容、底部的按钮。
class BeSheetFrame extends StatelessWidget {
  const BeSheetFrame({super.key, required this.title, this.hint, this.problem, required this.children, this.footer});

  final String title;
  final String? hint;
  final String? problem;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x2, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    ),
                    TextButton(key: const ValueKey('be-sheet-done'), onPressed: () => Navigator.pop(context), child: const Text('好了')),
                  ],
                ),
              ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: Text(hint!, style: t.bodySmall?.copyWith(color: c.textMuted)),
                ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.x3),
                      child: Text(
                        problem!,
                        key: const ValueKey('be-sheet-problem'),
                        style: t.bodyMedium?.copyWith(color: c.text),
                      ),
                    ),
                  ),
                ),
              Flexible(child: ListView(shrinkWrap: true, children: children)),
              if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一小节的标题（小、次要色——它是标签，不是大标题）。
class BeSheetSection extends StatelessWidget {
  const BeSheetSection(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x1),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w600),
    ),
  );
}

/// 一行：左边名字，右边一个次要的值，最右可以再放一样东西（开关、⋯）。点整行做一件事。
class BeSheetRow extends StatelessWidget {
  const BeSheetRow({super.key, required this.label, this.value, this.onTap, this.trailing, this.indent = false, this.muted = false});

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool indent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(left: indent ? Space.x6 + Space.x2 : Space.x4, right: trailing == null ? Space.x4 : Space.x1),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(color: muted ? c.textMuted : c.text),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: Space.x3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                ),
              ],
              if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// “加一个…”那一行（强调色的文字，前面一个加号）。
class BeSheetAdd extends StatelessWidget {
  const BeSheetAdd({super.key, required this.label, required this.onTap, this.indent = false});
  final String label;
  final VoidCallback onTap;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.only(left: indent ? Space.x6 + Space.x2 : Space.x4, right: Space.x4),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 20, color: c.accent),
              const SizedBox(width: Space.x2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _summary(BeTypeDef t) => switch (t.kind) {
  BeTypeKind.record => '记录 · ${t.fields.length} 个字段',
  BeTypeKind.enumeration => '枚举 · ${t.cases.length} 种情况',
  BeTypeKind.variant => '变体 · ${t.cases.length} 种情况',
  BeTypeKind.error => '错误种类 · ${t.fields.length} 个字段',
  BeTypeKind.klass => '类 · ${t.fields.length} 个字段、${t.methods.length} 个方法',
  BeTypeKind.interface => '接口 · ${t.methods.length} 个方法',
};

const Map<BeTypeKind, String> _kindHint = {
  BeTypeKind.record: '几样东西打包在一起；建好不能改',
  BeTypeKind.enumeration: '只能是固定几种里的一种',
  BeTypeKind.variant: '几种情况，每种带的东西不一样',
  BeTypeKind.error: '自己的一种错误，可以多带几样东西',
  BeTypeKind.klass: '有字段、有方法；点开有它自己的画布',
  BeTypeKind.interface: '只约定要有哪些方法',
};

/// “类型与类”面板。在里面点了“打开它的画布”会进那个类的画布，面板关掉。
Future<void> showBeCoreTypes(BuildContext context, BeBlockHost host) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (sheet) => StatefulBuilder(
    builder: (sheet, refresh) {
      final c = sheet.colors;
      final t = Theme.of(sheet).textTheme;
      Future<void> open(String id) async {
        final went = await showBeCoreType(sheet, host, id);
        if (!sheet.mounted) return;
        if (went) {
          Navigator.pop(sheet);
        } else {
          refresh(() {});
        }
      }

      Future<void> add() async {
        final kind = await showModalBottomSheet<BeTypeKind>(
          context: sheet,
          builder: (pick) => BeSheetFrame(
            key: const ValueKey('be-core-kinds'),
            title: '新建哪一种',
            children: [
              for (final k in BeTypeKind.values)
                InkWell(
                  key: ValueKey('be-core-add-${k.tag}'),
                  onTap: () => Navigator.pop(pick, k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k.label, style: t.bodyLarge),
                        const SizedBox(height: 2),
                        Text(_kindHint[k]!, style: t.bodySmall?.copyWith(color: c.textMuted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
        if (kind == null || !sheet.mounted) return;
        final id = host.addType(kind);
        refresh(() {});
        if (id != null) await open(id);
      }

      final types = host.core.types;
      return BeSheetFrame(
        key: const ValueKey('be-core-types'),
        title: '类型与类',
        hint: types.isEmpty ? '把几样东西打包成“记录”、把固定的几种情况列成“枚举”、把数据和做法放进“类”。建好以后，积木盒的“类型”一页里就能用。' : null,
        footer: FilledButton(key: const ValueKey('be-core-add'), onPressed: add, child: const Text('新建…')),
        children: [for (final x in types) BeSheetRow(key: ValueKey('be-core-type-${x.name}'), label: x.name, value: _summary(x), onTap: () => open(x.id))],
      );
    },
  ),
);
