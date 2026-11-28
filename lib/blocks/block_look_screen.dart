// 设计约束（“新建积木 / 编辑积木 / 包成积木”页，390 宽，浅色 + 深色）— 2026-11-25
// - 全屏页，统一顶栏（PageBar）：左边返回，右边唯一的主要动作“完成”（顶栏胶囊里的强调色文字）；别的都是次要的。
// - 层级：① 预览（真的积木，钉在顶栏下面不滚，键盘弹起时也看得见）→ ② 名字、积木上写的字（最常改，排最前）
//   → ③ 参数（一个参数一张卡）→ ④ 形状、颜色、说明（次要，排最后）。
// - 一行只做一件事：每个输入框、每组分段按钮各占一行；小标题 14 号半粗，说明文字用小一号的中性色。
// - 间距：行与行 12；组与组（小标题上面）24——组间距大于组内间距。
// - 报错贴在出问题的那一行下面，说真正的原因。名字空着这一条等点了“完成”才报（刚进来不该一片红）；别的边写边报。
// - 写文案省事：没写就用“名字 + 每个参数一个槽”；加参数自动在文案末尾接上 {参数}，改名跟着改，删掉跟着拿掉；
//   文案下面一排“＋{参数}”小按钮，把还没写进去的参数插到光标处（手机上打花括号麻烦）。
// - 编辑已有积木时删参数：别处在用就先问“有 N 处在用，槽里的东西会丢掉”。
// - “包成积木”时参数是算出来的（那一段用到的外面的变量）：名字不能改、不能增删，只能改种类和先放什么。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_look_form_widgets.dart';
import 'package:lopicode/blocks/block_look_preview.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 页面的结果：外观、参数名（按顺序）、每个参数原来是第几个（新加的为 null）。
class BkLookResult {
  const BkLookResult(this.look, this.params, this.origin);
  final CustomBlockLook look;
  final List<String> params;
  final List<int?> origin;
}

/// 打开“新建积木”页。`editing`＝改已有的一块（`uses`＝它在别处用了几次）；`wrapParams`＝“包成积木”（参数是算出来的）。
Future<BkLookResult?> showBlockLookPage(BuildContext context, {required BlockHost host, BlockCustom? editing, int uses = 0, List<String>? wrapParams}) {
  return Navigator.of(context).push<BkLookResult>(
    MaterialPageRoute(
      builder: (_) => BlockLookScreen(host: host, editing: editing, uses: uses, wrapParams: wrapParams),
    ),
  );
}

class BlockLookScreen extends StatefulWidget {
  const BlockLookScreen({super.key, required this.host, this.editing, this.uses = 0, this.wrapParams});
  final BlockHost host;
  final BlockCustom? editing;
  final int uses;
  final List<String>? wrapParams;

  @override
  State<BlockLookScreen> createState() => _BlockLookScreenState();
}

class _BlockLookScreenState extends State<BlockLookScreen> with BkKitHolder {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.look.name ?? '');
  late final TextEditingController _template = TextEditingController(text: widget.editing?.look.template ?? '');
  late final TextEditingController _hint = TextEditingController(text: widget.editing?.look.hint ?? '');
  final FocusNode _templateFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  late CustomBlockShape _shape = _wrapping ? CustomBlockShape.statement : (widget.editing?.look.shape ?? CustomBlockShape.auto);
  late String _color = widget.editing?.look.colorKey ?? kCustomBlockDefaultColor;
  late final List<BkLookParamDraft> _params = [
    if (widget.editing case final e?)
      for (final (i, s) in e.slots.indexed) BkLookParamDraft.of(s, origin: i)
    else
      for (final n in widget.wrapParams ?? const <String>[]) BkLookParamDraft(name: n, locked: true),
  ];
  bool _tried = false;
  int _rev = 0;

  bool get _wrapping => widget.wrapParams != null;

  @override
  void dispose() {
    _name.dispose();
    _template.dispose();
    _hint.dispose();
    _templateFocus.dispose();
    _scroll.dispose();
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() => _rev++);

  // —— 草稿 → 外观 ——

  List<String> get _names => [for (final p in _params) p.trimmed];

  /// 名字合适的那些参数（预览、对模板都只认它们；不合适的在各自的卡片下面报）。
  List<BkLookParamDraft> get _valid {
    final bad = bkParamNameProblems(_names);
    return [
      for (final (i, p) in _params.indexed)
        if (bad[i] == null) p,
    ];
  }

  CustomBlockLook _look(List<BkLookParamDraft> params, {String? name}) =>
      CustomBlockLook(name ?? _name.text.trim(), shape: _shape, template: _template.text.trim(), slots: [for (final p in params) p.slot], colorKey: _color, hint: _hint.text.trim());

  List<BlockLookProblem> get _problems {
    final valid = _valid;
    final names = [for (final p in valid) p.trimmed];
    final look = _look(valid);
    final custom = widget.host.custom;
    final taken = [
      for (final c in custom?.customs ?? const <BlockCustom>[])
        if (c.id != widget.editing?.id) c.look.name,
    ];
    return [...bkCheckLook(look, names, taken: taken), ...?custom?.check(look, names, editing: widget.editing?.id)];
  }

  // —— 文案跟着参数变 ——

  void _retemplate(List<LookSegment> Function(List<LookSegment> segments) change) {
    if (_template.text.trim().isEmpty) return;
    final next = formatLookTemplate(change(parseLookTemplate(_template.text))).replaceAll(RegExp(' {2,}'), ' ').trim();
    _template.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _renamed(BkLookParamDraft p) {
    final from = p.lastName, to = p.trimmed;
    // 新名字不合适（空的、和别的参数重名…）：文案先不动，等改成合适的名字再跟。
    if (bkParamNameProblems(_names)[_params.indexOf(p)] == null) {
      if (from != to && from.isNotEmpty) {
        // 文案里已经写了 {新名字}：它就是这个参数的槽，旧的那个拿掉；不然把旧槽改名。
        final has = lookTemplateSlots(_template.text).contains(to);
        _retemplate(
          (segs) => [
            for (final s in segs)
              if (!(s.isSlot && s.text == from)) s else if (!has) LookSegment.slot(to),
          ],
        );
      }
      p.lastName = to;
    }
    _changed();
  }

  void _addParam() {
    if (_params.length >= kCustomBlockMaxSlots) return;
    // 文案里先写了 {谁} 却还没有这个参数：新参数直接叫“谁”（不用再打一遍）；不然起个新名字、在文案末尾接上它的槽。
    final names = _names;
    final orphan = lookTemplateSlots(_template.text).where((n) => !names.contains(n) && bkParamNameProblem(n, names) == null).firstOrNull;
    final name = orphan ?? bkFreshParamName(names);
    if (orphan == null) _retemplate((segs) => [...segs, const LookSegment.text(' '), LookSegment.slot(name)]);
    _params.add(BkLookParamDraft(name: name));
    _changed();
    // 新卡片在下面：滚过去让人看见。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) unawaited(_scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    });
  }

  Future<void> _deleteParam(int i) async {
    final p = _params[i];
    if (p.origin != null && widget.uses > 0) {
      final ok = await confirmDialog(context, title: '删掉参数“${p.lastName}”？', message: '有 ${widget.uses} 处在用，槽里的东西会丢掉。', confirmLabel: '删除', danger: true);
      if (!ok || !mounted) return;
    }
    final name = p.lastName;
    _retemplate(
      (segs) => [
        for (final s in segs)
          if (!(s.isSlot && s.text == name)) s,
      ],
    );
    _params.remove(p);
    _changed();
    // 输入框可能还握着焦点：等这一帧画完再收。
    WidgetsBinding.instance.addPostFrameCallback((_) => p.dispose());
  }

  /// 把 {参数} 插到文案的光标处（文案还空着就先填上默认的样子）。
  void _insertSlot(String name) {
    final sel = _template.selection;
    final text = _template.text;
    final at = sel.isValid && _templateFocus.hasFocus ? sel.start.clamp(0, text.length) : text.length;
    final piece = '{$name}';
    final lead = at > 0 && !text.substring(0, at).endsWith(' ') ? ' ' : '';
    final next = text.substring(0, at) + lead + piece + text.substring(at);
    _template.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + lead.length + piece.length),
    );
    _changed();
  }

  void _done() {
    if (_name.text.trim().isEmpty || _problems.isNotEmpty || bkParamNameProblems(_names).any((p) => p != null)) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() => _tried = true);
      if (_scroll.hasClients) unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
      return;
    }
    Navigator.pop(context, BkLookResult(_look(_params), _names, [for (final p in _params) p.origin]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final valid = _valid;
    final validNames = [for (final p in valid) p.trimmed];
    final problems = _problems;
    List<String> of(BlockLookField f, {String? slot}) => [
      for (final p in problems)
        if (p.field == f && (slot == null || p.slot == slot)) p.message,
    ];
    final nameBad = bkParamNameProblems(_names);
    final nameErrors = [if (_tried && _name.text.trim().isEmpty) '给这块积木起个名字', ...of(BlockLookField.name).where((m) => _name.text.trim().isNotEmpty)];
    // 预览：名字还空着时先写“积木名字”，看得出这块长什么样。
    final previewHost = BkLookPreviewHost(widget.host, _look(valid, name: _name.text.trim().isEmpty ? '积木名字' : null), validNames);
    final preview = previewHost.layout(kit.engine(previewHost));
    final inTemplate = lookTemplateSlots(_template.text).toSet();
    final missing = _template.text.trim().isEmpty
        ? const <String>[]
        : [
            for (final n in validNames)
              if (!inTemplate.contains(n)) n,
          ];
    final title = _wrapping ? '包成积木' : (widget.editing == null ? '新建积木' : '编辑积木');
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(
        background: c.canvas,
        title: Text(title),
        actions: [
          // 顶栏会把操作装进一个悬浮胶囊：里面放一个强调色的字就够显眼，再套实心按钮就成了“胶囊套胶囊”。
          TextButton(
            key: const ValueKey('bk-look-done'),
            onPressed: _done,
            style: TextButton.styleFrom(
              minimumSize: const Size(72, RoundIconButton.kSize),
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              shape: const StadiumBorder(),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
      body: ContentWidth(
        child: BelowBar(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BkLookPreview(layout: preview, kit: kit, revision: _rev),
              Expanded(
                child: ListView(
                  key: const ValueKey('bk-look-form'),
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x8 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    TextField(
                      key: const ValueKey('bk-look-name'),
                      controller: _name,
                      autofocus: widget.editing == null,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '名字', hintText: '如：问好'),
                      onChanged: (_) => _changed(),
                    ),
                    BkLookErrors(nameErrors, id: 'name'),
                    const SizedBox(height: Space.x3),
                    TextField(
                      key: const ValueKey('bk-look-template'),
                      controller: _template,
                      focusNode: _templateFocus,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '积木上写的字', hintText: '向 {名字} 问好', helperText: '花括号里写参数名就是一个槽。不写＝名字后面跟着每个参数。'),
                      onChanged: (_) => _changed(),
                    ),
                    if (missing.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.x2),
                        child: Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x1,
                          children: [
                            for (final n in missing)
                              ActionChip(
                                key: ValueKey('bk-look-insert-$n'),
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.add_rounded, size: 16),
                                label: Text('{$n}'),
                                onPressed: () => _insertSlot(n),
                              ),
                          ],
                        ),
                      ),
                    BkLookErrors(of(BlockLookField.template), id: 'template'),
                    BkLookCaption('参数', note: _wrapping ? (_params.isEmpty ? '这一段没用到外面的变量' : '这一段用到的外面的变量') : '积木上的槽，用的时候往里填'),
                    for (final (i, p) in _params.indexed)
                      BkLookParamCard(
                        key: ObjectKey(p),
                        index: i,
                        draft: p,
                        errors: [
                          if (nameBad[i] != null) nameBad[i]!,
                          if (nameBad[i] == null) ...of(BlockLookField.options, slot: p.trimmed),
                          if (nameBad[i] == null) ...of(BlockLookField.slot, slot: p.trimmed),
                        ],
                        onChanged: _changed,
                        onRename: () => _renamed(p),
                        onDelete: p.locked ? null : () => unawaited(_deleteParam(i)),
                      ),
                    if (!_wrapping && _params.length < kCustomBlockMaxSlots)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(key: const ValueKey('bk-look-param-add'), onPressed: _addParam, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('加一个参数')),
                      ),
                    const BkLookCaption('形状'),
                    SegmentedButton<CustomBlockShape>(
                      key: const ValueKey('bk-look-shape'),
                      showSelectedIcon: false,
                      segments: [
                        if (!_wrapping) const ButtonSegment(value: CustomBlockShape.auto, label: Text('自动')),
                        const ButtonSegment(value: CustomBlockShape.statement, label: Text('语句')),
                        if (!_wrapping) const ButtonSegment(value: CustomBlockShape.value, label: Text('值')),
                        if (!_wrapping) const ButtonSegment(value: CustomBlockShape.boolean, label: Text('是否')),
                      ],
                      selected: {_shape},
                      onSelectionChanged: (s) {
                        _shape = s.first;
                        _changed();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: Space.x1),
                      child: Text(
                        switch (_shape) {
                          CustomBlockShape.statement => _wrapping ? '包起来的是一段语句，所以是语句积木' : '一块能上下拼的语句积木',
                          CustomBlockShape.value => '一个能放进槽里的值（它的定义里要有“返回”）',
                          CustomBlockShape.boolean => '一个“是 / 否”的值，能放进条件槽',
                          _ => '定义里有“返回”就是值，没有就是语句',
                        },
                        key: const ValueKey('bk-look-shape-note'),
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                      ),
                    ),
                    const BkLookCaption('颜色'),
                    BkLookColorRow(
                      palette: kit.palette,
                      selected: _color,
                      onPick: (k) {
                        _color = k;
                        _changed();
                      },
                    ),
                    const BkLookCaption('说明', note: '可不填'),
                    TextField(
                      key: const ValueKey('bk-look-hint'),
                      controller: _hint,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(hintText: '一句话说它是干什么的'),
                      onChanged: (_) => _changed(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
