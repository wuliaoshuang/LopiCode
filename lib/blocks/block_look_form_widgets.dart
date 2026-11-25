// 设计约束（“新建积木”页里的几样零件，390 宽，浅色 + 深色）— 2026-11-25
// - 预览条：画布底色的一块圆角区域，里面就是那块真的积木（和积木盒里用同一套画法），放不下就整体缩小、不滚动、不裁。
//   它钉在顶栏下面不跟着滚：键盘弹起时也一直看得见。
// - 一个参数一张卡，卡里从上到下一行一件事：名字（右边是删除）→ 种类（三选一的分段按钮）→ 这种槽先放什么 / 选项。
//   卡片用略暗的底色和大一点的外间距分开（组与组之间的间距 > 组内的间距），不用线框。
// - 颜色：一排圆点，选中的外面一圈描边 + 下面一行小字说它是哪一类的颜色（不只靠颜色认）。
// - 报错：贴在出问题的那一行下面，危险色小字，说真正的原因；不弹对话框。
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 页面上一个参数的草稿（输入框各自带着控制器）。
class BkLookParamDraft {
  BkLookParamDraft({String name = '', this.kind = CustomSlotKind.value, Object? defaultValue, List<String> options = const [], this.origin, this.locked = false})
    : name = TextEditingController(text: name),
      lastName = name,
      value = TextEditingController(text: kind == CustomSlotKind.value ? _show(defaultValue) : ''),
      options = TextEditingController(text: options.join('、')),
      on = defaultValue == true,
      keptChoice = defaultValue is String ? defaultValue : null;

  factory BkLookParamDraft.of(CustomBlockSlot s, {int? origin, bool locked = false}) =>
      BkLookParamDraft(name: s.name, kind: s.kind == CustomSlotKind.boolean || s.kind == CustomSlotKind.choice ? s.kind : CustomSlotKind.value, defaultValue: s.defaultValue, options: s.options, origin: origin, locked: locked);

  final TextEditingController name;
  final TextEditingController value;
  final TextEditingController options;
  CustomSlotKind kind;
  bool on;

  /// 原来选中的那一项（改了选项以后它还在就留着）。
  final String? keptChoice;

  /// 上一次的名字（改名时把文案里的 {旧名} 换成 {新名}）。
  String lastName;

  /// 编辑已有积木时：它原来是第几个参数（新加的为 null）。
  final int? origin;

  /// 名字不许改、不许删（“包成积木”时参数是算出来的）。
  final bool locked;

  String get trimmed => name.text.trim();

  List<String> get optionList => [
    for (final o in options.text.split(RegExp(r'[、,，\n]')))
      if (o.trim().isNotEmpty) o.trim(),
  ];

  CustomBlockSlot get slot => switch (kind) {
    CustomSlotKind.boolean => CustomBlockSlot(trimmed, kind: kind, defaultValue: on ? true : null),
    CustomSlotKind.choice => CustomBlockSlot(trimmed, kind: kind, options: optionList, defaultValue: optionList.contains(keptChoice) ? keptChoice : null),
    _ => CustomBlockSlot(trimmed, defaultValue: _parse(value.text)),
  };

  void dispose() {
    name.dispose();
    value.dispose();
    options.dispose();
  }

  static String _show(Object? v) => v == null ? '' : (v is bool ? (v ? '是' : '否') : (v is num ? bkLookNumber(v) : '$v'));

  /// 像数字的当数字，别的当文字；空＝不先放东西。
  static Object? _parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    return n != null && n.isFinite ? n : t;
  }
}

/// 顶栏下面钉着的预览条。
class BkLookPreview extends StatelessWidget {
  const BkLookPreview({super.key, required this.layout, required this.kit, required this.revision});
  final BkScriptLayout layout;
  final BkKit kit;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('bk-look-preview'),
      margin: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x3),
      padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x4),
      constraints: const BoxConstraints(minHeight: 84, maxHeight: 148),
      width: double.infinity,
      decoration: BoxDecoration(
        color: kit.palette.canvas,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: BkLayoutView(layout: layout, kit: kit, revision: revision),
      ),
    );
  }
}

/// 一行的小标题（上面留的空比下面多：它属于下面那一行）。
class BkLookCaption extends StatelessWidget {
  const BkLookCaption(this.text, {super.key, this.note});
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.x6, bottom: Space.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (note != null) ...[
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(note!, style: t.bodySmall?.copyWith(color: c.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    );
  }
}

/// 贴在某一行下面的报错。
class BkLookErrors extends StatelessWidget {
  const BkLookErrors(this.messages, {super.key, required this.id});
  final List<String> messages;
  final String id;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      key: ValueKey('bk-look-error-$id'),
      padding: const EdgeInsets.only(top: 6, left: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 6),
                    child: Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
                  ),
                  Expanded(
                    child: Text(m, style: t.bodySmall?.copyWith(color: c.danger, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一个参数的卡片。
class BkLookParamCard extends StatelessWidget {
  const BkLookParamCard({super.key, required this.index, required this.draft, required this.errors, required this.onChanged, required this.onRename, required this.onDelete});
  final int index;
  final BkLookParamDraft draft;
  final List<String> errors;
  final VoidCallback onChanged;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    InputDecoration field(String label, {String? hint, String? helper}) => InputDecoration(labelText: label, hintText: hint, helperText: helper, fillColor: c.surface);
    return Container(
      key: ValueKey('bk-look-param-$index'),
      margin: const EdgeInsets.only(bottom: Space.x3),
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x3),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('bk-look-param-name-$index'),
                  controller: draft.name,
                  enabled: !draft.locked,
                  textInputAction: TextInputAction.done,
                  decoration: field('参数 ${index + 1} 的名字', hint: '如：名字'),
                  onChanged: (_) => onRename(),
                ),
              ),
              if (onDelete != null)
                IconButton(key: ValueKey('bk-look-param-delete-$index'), tooltip: '删掉这个参数', onPressed: onDelete, icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted)),
            ],
          ),
          const SizedBox(height: Space.x3),
          SegmentedButton<CustomSlotKind>(
            key: ValueKey('bk-look-param-kind-$index'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: CustomSlotKind.value, label: Text('值')),
              ButtonSegment(value: CustomSlotKind.boolean, label: Text('是否')),
              ButtonSegment(value: CustomSlotKind.choice, label: Text('固定选项')),
            ],
            selected: {draft.kind},
            onSelectionChanged: (s) {
              draft.kind = s.first;
              onChanged();
            },
          ),
          const SizedBox(height: Space.x3),
          switch (draft.kind) {
            CustomSlotKind.boolean => InkWell(
              key: ValueKey('bk-look-param-on-$index'),
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () {
                draft.on = !draft.on;
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: Space.x1),
                child: Row(
                  children: [
                    Expanded(child: Text('拿出来时先是“是”', style: t.bodyMedium)),
                    IgnorePointer(child: Switch(value: draft.on, onChanged: (_) {})),
                  ],
                ),
              ),
            ),
            CustomSlotKind.choice => TextField(
              key: ValueKey('bk-look-param-options-$index'),
              controller: draft.options,
              textInputAction: TextInputAction.done,
              decoration: field('有哪些选项', hint: '客气、随便', helper: '用顿号或逗号隔开；第一个是先选中的'),
              onChanged: (_) => onChanged(),
            ),
            _ => TextField(
              key: ValueKey('bk-look-param-value-$index'),
              controller: draft.value,
              textInputAction: TextInputAction.done,
              decoration: field('槽里先放什么（可不填）', hint: '空着'),
              onChanged: (_) => onChanged(),
            ),
          },
          BkLookErrors(errors, id: 'param-$index'),
        ],
      ),
    );
  }
}

/// 颜色那一行能选的：颜色的名字 → 给人看的叫法。
const List<(String, String)> kBkLookColors = [
  (BlockColorKey.custom, '我的积木'),
  (BlockColorKey.function, '函数'),
  (BlockColorKey.control, '流程'),
  (BlockColorKey.variable, '变量'),
  (BlockColorKey.operator, '运算'),
  (BlockColorKey.text, '文字'),
  (BlockColorKey.list, '列表'),
  (BlockColorKey.dict, '字典'),
];

class BkLookColorRow extends StatelessWidget {
  const BkLookColorRow({super.key, required this.palette, required this.selected, required this.onPick});
  final BkPalette palette;
  final String selected;
  final void Function(String key) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final label = kBkLookColors.where((e) => e.$1 == selected).firstOrNull?.$2 ?? selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.x1,
          runSpacing: Space.x1,
          children: [
            for (final (key, name) in kBkLookColors)
              Semantics(
                button: true,
                selected: key == selected,
                label: '$name的颜色',
                child: InkResponse(
                  key: ValueKey('bk-look-color-$key'),
                  radius: 22,
                  onTap: () => onPick(key),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: key == selected ? c.text : Colors.transparent, width: 2),
                    ),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(color: palette.tone(key).fill, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: Space.x1),
          child: Text('和“$label”一个颜色', key: const ValueKey('bk-look-color-label'), style: t.bodySmall?.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}
