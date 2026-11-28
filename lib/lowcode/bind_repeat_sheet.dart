// 设计约束（低代码 · “重复”的底部面板 · 390×844，浅色 + 深色；第 5 期）
// - 从哪进：面板“常用”页›“数据”›重复。
// - 用途：让这个组件按一张列表重复出现——列表有几项就出现几份，每一份里能用“这一项”。
// - 从上到下，一行一件事：
//     列表（必填）：没选＝灰药丸“选一张列表”；选了＝强调色小牌子。
//     这一项叫什么（默认 item）｜第几个叫什么（默认 i）：两个短输入框各占一行。里面的控件绑定时用这两个名字。
//     每项的标识：小牌子或灰药丸“选一格”。下面一句灰字：选每一项里不会重复的那一格（比如 id），增删挪动时才认得准。
//     列表是空的时候显示：一句文字（可不填）；下面一颗文字按钮“换成一块内容（能放图、按钮）”——点了＝保存，并在这个组件后面
//       加一块只在列表是空的时候出现的容器（repeat_empty.dart）。已经有那一块了：这一行换成一句说明＋“去改它”。
//     画布上先画几份：1–5 一排药丸。
//   底部：左“不重复了”（红字；本来没设就没有），右“取消”“保存”（唯一实心；没选列表、名字写得不对时是灰的，上方一句红字）。
// - 取用的 tokens：Space.x2/x3/x4、textMuted / textFaint、danger。
import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_simple.dart';
import 'package:lopicode/lowcode/inspector_bind_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// “重复”面板的结果。
/// 这张单子里名字那一栏的宽度：最长的名字“每项的标识”五个字（70），留出 18 的空再接右边的药丸。
const double _labelWidth = 88;

class LcRepeatDraft {
  const LcRepeatDraft({required this.list, required this.item, required this.index, this.key, this.empty, required this.preview, this.emptyBlock = false}) : remove = false;
  const LcRepeatDraft.removed() : list = null, item = '', index = '', key = null, empty = null, preview = 3, remove = true, emptyBlock = false;
  final Map<String, dynamic>? list;
  final String item;
  final String index;
  final Map<String, dynamic>? key;
  final String? empty;
  final int preview;
  final bool remove;

  /// 保存以后还要：给它加一块“空的时候显示”的内容（已经有了就是选中那一块）。
  final bool emptyBlock;
}

/// [emptyBlock]：null＝这里不能加“空的时候显示的一块内容”（改不了整份文档的地方）；true＝已经有那一块了；false＝还没有。
Future<LcRepeatDraft?> showLcRepeatSheet(BuildContext context, {required InspectorEdit ed, LcRepeat? current, bool? emptyBlock}) => showModalBottomSheet<LcRepeatDraft>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _RepeatSheet(ed: ed, current: current, emptyBlock: emptyBlock),
);

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.ed, this.current, this.emptyBlock});
  final InspectorEdit ed;
  final LcRepeat? current;
  final bool? emptyBlock;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late Map<String, dynamic>? _list = widget.current == null ? null : lcSrcExpr(widget.current!.list);
  late Map<String, dynamic>? _key = widget.current?.key == null ? null : lcSrcExpr(widget.current!.key!);
  late final _item = TextEditingController(text: widget.current?.item ?? 'item');
  late final _index = TextEditingController(text: widget.current?.index ?? 'i');
  late final _empty = TextEditingController(text: widget.current?.empty ?? '');
  late int _preview = widget.current?.preview ?? 3;

  @override
  void dispose() {
    _item.dispose();
    _index.dispose();
    _empty.dispose();
    super.dispose();
  }

  String? get _problem {
    final item = _item.text.trim(), index = _index.text.trim();
    if (_list == null) return '还没选列表';
    if (!kLcLocalName.hasMatch(item) || !kLcLocalName.hasMatch(index)) return '两个名字都要字母开头，只用字母、数字和 _';
    if (item == index) return '“这一项”和“第几个”不能叫同一个名字';
    return null;
  }

  LcRepeatDraft _draft({bool emptyBlock = false}) => LcRepeatDraft(
    list: _list,
    item: _item.text.trim(),
    index: _index.text.trim(),
    key: _key,
    empty: _empty.text.trim().isEmpty ? null : _empty.text.trim(),
    preview: _preview,
    emptyBlock: emptyBlock,
  );

  Future<void> _pickList() async {
    // 列表从外面来：这一层自己带出来的名字还不能用。
    final r = await lcPickBinding(context, widget.ed, title: '重复用的列表', want: 'list', current: _list, self: false);
    if (r != null && mounted) setState(() => _list = r.clear ? null : r.source);
  }

  Future<void> _pickKey() async {
    final list = lcSrcExprOf(_list);
    final env = LcBindEnv.of(widget.ed.doc);
    final v = list == null ? null : lcEval(list, env);
    final locals = [
      ...lcLocalsOf(widget.ed, self: false),
      LcLocal(_item.text.trim(), '这一项', isIndex: false, sample: v is List && v.isNotEmpty ? v.first : null),
      LcLocal(_index.text.trim(), '第几个（从 0 数）', isIndex: true),
    ];
    final r = await lcPickBinding(context, widget.ed, title: '每项的标识', want: 'any', current: _key, locals: locals);
    if (r != null && mounted) setState(() => _key = r.clear ? null : r.source);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final problem = _problem;
    final listExpr = lcSrcExprOf(_list), keyExpr = lcSrcExprOf(_key);
    Widget pick(String id, String ask, Map<String, dynamic>? expr, VoidCallback open) => Align(
      alignment: Alignment.centerLeft,
      child: expr == null ? InspectorChip(key: Key('lc-repeat-$id'), label: ask, selected: false, onTap: open) : LcVarBadge(key: Key('lc-repeat-$id'), label: lcDescribeExpr(expr), onTap: open),
    );
    Widget name(String id, String label, TextEditingController ctl) => InspectorRow(
      labelWidth: _labelWidth,
      label: label,
      scroll: false,
      child: TextField(key: Key('lc-repeat-$id'), controller: ctl, decoration: const InputDecoration(isDense: true), onChanged: (_) => setState(() {})),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('重复', style: t.titleMedium),
              const SizedBox(height: Space.x1),
              Text('列表有几项，这个组件就出现几份；每一份里的控件可以用“这一项”。', style: t.bodySmall?.copyWith(color: c.textMuted)),
              const SizedBox(height: Space.x2),
              InspectorRow(labelWidth: _labelWidth, label: '列表', scroll: false, child: pick('list', '选一张列表', listExpr, _pickList)),
              name('item', '这一项叫', _item),
              name('index', '第几个叫', _index),
              InspectorRow(
                labelWidth: _labelWidth,
                label: '每项的标识',
                scroll: false,
                below: Text('选每一项里不会重复的那一格（比如 id）。列表增删、挪动时靠它认出谁是谁。', style: t.bodySmall?.copyWith(color: c.textFaint)),
                child: pick('key', '选一格', keyExpr, _pickKey),
              ),
              InspectorRow(
                labelWidth: _labelWidth,
                label: '空的时候',
                scroll: false,
                below: widget.emptyBlock == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('lc-repeat-empty-block'),
                          onPressed: problem != null ? null : () => Navigator.pop(context, _draft(emptyBlock: true)),
                          child: Text(widget.emptyBlock! ? '保存，并去改那一块' : '换成一块内容（能放图、按钮）'),
                        ),
                      ),
                child: widget.emptyBlock == true
                    ? Text(
                        '显示它后面那一块内容（画布上角标“条件”、颜色淡的那个容器）。',
                        key: const Key('lc-repeat-empty-has-block'),
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                      )
                    : TextField(
                        key: const Key('lc-repeat-empty'),
                        controller: _empty,
                        decoration: const InputDecoration(isDense: true, hintText: '列表是空的时候显示的一句话（可不填）'),
                      ),
              ),
              InspectorRow(
                labelWidth: _labelWidth,
                label: '画布先画',
                child: Row(
                  children: [
                    for (var i = 1; i <= kLcRepeatPreviewMax; i++) InspectorChip(key: Key('lc-repeat-preview-$i'), label: '$i 份', selected: _preview == i, onTap: () => setState(() => _preview = i)),
                  ],
                ),
              ),
              if (problem != null && (_list != null || widget.current != null)) ...[
                const SizedBox(height: Space.x2),
                Text(
                  problem,
                  key: const Key('lc-repeat-problem'),
                  style: t.bodySmall?.copyWith(color: c.danger),
                ),
              ],
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  if (widget.current != null)
                    TextButton(
                      key: const Key('lc-repeat-remove'),
                      onPressed: () => Navigator.pop(context, const LcRepeatDraft.removed()),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      child: const Text('不重复了'),
                    ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  const SizedBox(width: Space.x2),
                  FilledButton(key: const Key('lc-repeat-save'), onPressed: problem != null ? null : () => Navigator.pop(context, _draft()), child: const Text('保存')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
