// 设计约束（积木怎么画 · 390×844，浅色 + 深色）— 2026-11-24
// - 一块积木＝一个实心圆角色块，白字；按分类上色（变量橙 / 控件蓝 / 流程紫 / 交互青绿 / 网络玫红；事件的“帽子”是金棕，不认识的是灰）。
//   颜色只定义在本文件的 [_tones] 一张表里；白字在色块上、深色字在白胶囊上都 ≥ 4.5:1（算过）。
// - 色块左边一条同色相的粗边（4px）；相邻积木上下只隔 2px，看起来是拼在一起的一条“栈”。
// - 一块积木是一句话；参数是句子里可点的小胶囊（视觉高 30，点按区高 40）。一行放不下自然换行，不横向滚动。
// - 能装积木的（如果 / 重复 / 等一会儿 / 请求网址）画成 C 形：头一行 → 左臂包住的子栈 → （否则一行 → 子栈）→ 收口。
//   每层缩进 12px；第 4 层以后只留 4px 的竖边，免得把内容挤没。
// - 点积木空白处＝选中（描边），操作行出现在积木正下方；长按拖动＝换位置，插入位用一条横条标出来。
import 'package:lopicode/lowcode/logic_block_parts_widgets.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/logic_block_parts_widgets.dart';

/// 一种分类的配色。
class LcTone {
  const LcTone({required this.fill, required this.edge, required this.chip, required this.chipInk});

  /// 色块底色（上面放白字）。
  final Color fill;

  /// 左边的粗边。
  final Color edge;

  /// 参数胶囊的底色和上面的字。
  final Color chip;
  final Color chipInk;
}

/// 帽子积木（事件）用的分类名；不在 [lcBlockCategories] 里。
const String kLcEventCategory = '事件';

/// 积木上的字：两套主题下都是白色（色块本身够深）。
const Color kLcBlockInk = Color(0xFFFFFFFF);

// 每个分类：色块、深一档（浅色主题的粗边和胶囊字）、浅一档（深色主题的粗边和胶囊字）。
const Map<String, (Color, Color, Color)> _tones = {
  kLcEventCategory: (Color(0xFF8F6200), Color(0xFF6B4700), Color(0xFFFFE3A3)),
  '变量': (Color(0xFFB8530A), Color(0xFF8A3A00), Color(0xFFFFD2AD)),
  '控件': (Color(0xFF2962CB), Color(0xFF12359E), Color(0xFFC4DAFF)),
  '流程': (Color(0xFF7446C4), Color(0xFF4F2A96), Color(0xFFDCCBFF)),
  '交互': (Color(0xFF0F7B6C), Color(0xFF075A4E), Color(0xFFB5EDE3)),
  '网络': (Color(0xFFB5307A), Color(0xFF861A56), Color(0xFFFFC9E3)),
};
const (Color, Color, Color) _unknownTone = (Color(0xFF656870), Color(0xFF3C3D45), Color(0xFFD8DCDF));
const Color _darkChip = Color(0xFF15151B);

/// 某个分类在当前主题下的配色；分类不认识（或 null）是灰色。
LcTone lcToneFor(String? category, Brightness brightness) {
  final (fill, deep, tint) = _tones[category] ?? _unknownTone;
  return brightness == Brightness.light ? LcTone(fill: fill, edge: deep, chip: const Color(0xFFFFFFFF), chipInk: deep) : LcTone(fill: fill, edge: tint, chip: _darkChip, chipInk: tint);
}

LcTone lcToneOf(BuildContext context, String? category) => lcToneFor(category, Theme.of(context).brightness);

/// 可以放积木的一个位置：哪一串（`parent` 为空＝处理自己的那一串）的第几个。
typedef LcDropSpot = ({LcBlockPath parent, bool inElse, int index});

/// 正在拖的积木。
typedef LcDragData = ({String handlerId, LcBlockPath path});

enum LcBlockAction { up, down, copy, delete, addBelow }

/// 两条路径是不是指同一块（第一步的 inElse 不算数）。
bool lcSamePath(LcBlockPath a, LcBlockPath b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index || (i > 0 && a[i].inElse != b[i].inElse)) return false;
  }
  return true;
}

/// 路径写成一小段字（给控件的 key 用）：`0.b1.e0`＝第 1 块 › 里面第 2 块 › 否则里第 1 块。
String lcPathKey(LcBlockPath path) => [for (var i = 0; i < path.length; i++) '${i == 0 ? '' : (path[i].inElse ? 'e' : 'b')}${path[i].index}'].join('.');

/// 把 [from] 那块放到 [spot] 行不行：不能放进自己里面；放回原位不算。
bool lcCanDrop(LcBlockPath from, LcDropSpot spot) {
  if (from.isEmpty) return false;
  if (spot.parent.length >= from.length && lcSamePath(from, spot.parent.sublist(0, from.length))) return false;
  final fromParent = from.sublist(0, from.length - 1);
  final sameList = lcSamePath(fromParent, spot.parent) && (fromParent.isEmpty || from.last.inElse == spot.inElse);
  return !(sameList && (spot.index == from.last.index || spot.index == from.last.index + 1));
}

/// 积木栈向外要的东西：一个处理卡片实现它。
abstract interface class LcStackHost {
  LcDocument get doc;
  LcHandler get handler;
  bool isSelected(LcBlockPath path);

  /// 选中的那块用它当 key（“跳到这块”时靠它滚过去）；别的返回 null。
  Key? anchorFor(LcBlockPath path);
  List<LcLogicIssue> issuesAt(LcBlockPath path);
  void select(LcBlockPath path);
  void editArg(LcBlockPath path, LcArgSpec arg);
  void addAt(LcDropSpot spot);
  void act(LcBlockPath path, LcBlockAction action);
  void showIssues(LcBlockPath path);

  /// 拖动：现在指着的插入位（没有就是 null）、指到了哪、松手。
  LcDropSpot? get dropHint;
  void hover(LcDropSpot? spot);
  void drop(LcDragData data, LcDropSpot spot);

  /// 开始 / 结束拖动（页面据此在手指靠近上下边缘时自动滚动）。
  void dragging(bool active);
}

/// 第几层的 C 形左臂多宽（含 4px 的粗边）。
double lcArmWidth(int depth) => depth < 4 ? 12 : 4;

const double kLcBlockRadius = 8;
const double _kEdge = 4;
const TextStyle kLcBlockWords = TextStyle(color: kLcBlockInk, fontSize: FontSize.sm, fontWeight: FontWeight.w600, height: 1.3);

/// 一串积木。空的时候是一个虚线占位。
class LcBlockStack extends StatelessWidget {
  const LcBlockStack({super.key, required this.host, required this.blocks, required this.parent, this.inElse = false, this.depth = 0});
  final LcStackHost host;
  final List<LcBlock> blocks;
  final LcBlockPath parent;
  final bool inElse;
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      final LcDropSpot spot = (parent: parent, inElse: inElse, index: 0);
      return LcAddSlot(key: ValueKey('lc-slot-${host.handler.id}-${lcPathKey(parent)}-${inElse ? 'e' : 'b'}'), host: host, spot: spot, label: '点这里加积木');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: LcBlockView(
              host: host,
              block: blocks[i],
              path: [
                ...parent,
                lcStep(i, inElse: inElse),
              ],
              depth: depth,
              isLast: i == blocks.length - 1,
            ),
          ),
      ],
    );
  }
}

/// 一块积木（连同嵌在里面的）。
class LcBlockView extends StatelessWidget {
  const LcBlockView({super.key, required this.host, required this.block, required this.path, required this.depth, required this.isLast});
  final LcStackHost host;
  final LcBlock block;
  final LcBlockPath path;
  final int depth;
  final bool isLast;

  LcBlockPath get _parent => path.sublist(0, path.length - 1);
  LcDropSpot _spot(int index) => (parent: _parent, inElse: path.last.inElse, index: index);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = lcBlockSpecs[block.op];
    final tone = lcToneOf(context, spec?.category);
    final selected = host.isSelected(path);
    final issues = host.issuesAt(path);
    final index = path.last.index;
    final isC = spec != null && spec.hasBody;
    final id = '${host.handler.id}-${lcPathKey(path)}';

    final head = LcDropZone(
      host: host,
      spotFor: (upper) => upper ? _spot(index) : (isC ? (parent: path, inElse: false, index: 0) : _spot(index + 1)),
      child: LongPressDraggable<LcDragData>(
        data: (handlerId: host.handler.id, path: path),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () => host.dragging(true),
        // 松手（放下或取消）都会走到这里。
        onDragEnd: (_) {
          host.hover(null);
          host.dragging(false);
        },
        feedback: LcDragGhost(text: describeBlock(block, host.doc), tone: tone),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => host.select(path),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_kEdge + 8, 2, 4, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Sentence(host: host, block: block, spec: spec, path: path, tone: tone, issues: issues),
                ),
                if (issues.isNotEmpty) LcIssueDot(key: ValueKey('lc-issue-$id'), error: issues.any((i) => i.isError), onTap: () => host.showIssues(path)),
              ],
            ),
          ),
        ),
      ),
    );

    Widget cut(List<LcBlock> list, bool inElse) => Padding(
      padding: EdgeInsets.only(left: lcArmWidth(depth)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 0, 2),
          child: LcBlockStack(host: host, blocks: list, parent: path, inElse: inElse, depth: depth + 1),
        ),
      ),
    );

    final elseLabel = spec?.elseLabel;
    final shape = ClipRRect(
      borderRadius: BorderRadius.circular(kLcBlockRadius),
      child: ColoredBox(
        color: tone.fill,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                if (isC) cut(block.body, false),
                if (isC && elseLabel != null) ...[
                  LcDropZone(
                    host: host,
                    spotFor: (_) => (parent: path, inElse: true, index: 0),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(_kEdge + 8, 6, 8, 6),
                      child: Text(elseLabel, style: kLcBlockWords),
                    ),
                  ),
                  cut(block.orElse, true),
                ],
                // 收口：C 形的下沿；拖到这里＝放在这块后面。
                if (isC) LcDropZone(host: host, spotFor: (_) => _spot(index + 1), child: const SizedBox(height: 10)),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _kEdge,
              child: ColoredBox(color: tone.edge),
            ),
          ],
        ),
      ),
    );

    final hint = host.dropHint;
    final hintHere = hint != null && lcSamePath(hint.parent, _parent) && (_parent.isEmpty || hint.inElse == path.last.inElse);
    final barAbove = hintHere && hint.index == index;
    final barBelow = hintHere && isLast && hint.index == index + 1;

    return Column(
      key: host.anchorFor(path),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              key: ValueKey('lc-block-$id'),
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kLcBlockRadius),
                border: selected ? Border.all(color: c.text, width: 2) : null,
              ),
              child: shape,
            ),
            if (barAbove) Positioned(left: 0, right: 0, top: -3, child: LcDropBar(color: c.accent)),
            if (barBelow) Positioned(left: 0, right: 0, bottom: -3, child: LcDropBar(color: c.accent)),
          ],
        ),
        if (selected) LcActionRow(host: host, path: path, editable: spec != null),
      ],
    );
  }
}

/// 一句话的一小段：一段字，或一个参数。
typedef _Seg = ({String? text, String? arg});

_Seg _t(String text) => (text: text, arg: null);
_Seg _a(String name) => (text: null, arg: name);

/// 每种积木的句式。目录里有、这里没有的（以后新加的积木）退回“名字 + 逐个参数”。
List<_Seg> _sentenceOf(LcBlockSpec spec) => switch (spec.op) {
  'setVar' => [_t('把'), _a('name'), _t('设为'), _a('value')],
  'changeVar' => [_t('把'), _a('name'), _t('加上'), _a('by')],
  'setProp' => [_t('把'), _a('node'), _t('的'), _a('prop'), _t('改成'), _a('value')],
  'if' => [_t('如果'), _a('cond'), _t('那么')],
  'repeat' => [_t('重复'), _a('times'), _t('次')],
  'wait' => [_t('等'), _a('ms'), _t('毫秒，然后')],
  'alert' => [_t('弹出提示'), _a('message')],
  'navigate' => [_t('跳转到'), _a('url')],
  'log' => [_t('写到控制台'), _a('value')],
  'fetch' => [_t('用'), _a('method'), _t('请求'), _a('url'), _t('结果放进'), _a('into'), _t('成功后')],
  _ => [
    _t(spec.label),
    for (final a in spec.args) ...[_t(a.label), _a(a.name)],
    if (spec.bodyLabel != null) _t(spec.bodyLabel!),
  ],
};

class _Sentence extends StatelessWidget {
  const _Sentence({required this.host, required this.block, required this.spec, required this.path, required this.tone, required this.issues});
  final LcStackHost host;
  final LcBlock block;
  final LcBlockSpec? spec;
  final LcBlockPath path;
  final LcTone tone;
  final List<LcLogicIssue> issues;

  String _chipText(LcArgSpec a) {
    final v = block.args[a.name];
    switch (a.kind) {
      case LcArgKind.variable:
        return v is String && v.isNotEmpty ? v : (a.optional ? '不存' : '选变量');
      case LcArgKind.node:
        return describeNode(host.doc, v is String ? v : null);
      case LcArgKind.choice:
        // 积木上只留短的那半截（“GET（取数据）”→“GET”），完整的说明在选择面板里。
        return v is String ? a.choiceLabel(v).split('（').first : '请选择';
      default:
        return describeExpr(v, host.doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = spec;
    Widget words(String text) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Text(text, style: kLcBlockWords),
      ),
    );
    if (s == null) {
      final inside = block.body.length + block.orElse.length;
      return words('${describeBlock(block, host.doc)}${inside > 0 ? ' · 里面还有 $inside 块' : ''}');
    }
    final stray = (s.hasBody ? 0 : block.body.length) + (s.hasElse ? 0 : block.orElse.length);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final seg in _sentenceOf(s))
          if (seg.text != null)
            words(seg.text!)
          else if (s.arg(seg.arg!) case final a?)
            LcArgChip(
              key: ValueKey('lc-arg-${host.handler.id}-${lcPathKey(path)}-${a.name}'),
              text: _chipText(a),
              tone: tone,
              dropdown: a.kind != LcArgKind.expr && a.kind != LcArgKind.exprList,
              flagged: issues.any((i) => i.arg == a.name),
              onTap: () => host.editArg(path, a),
            ),
        if (stray > 0) words('（里面多出 $stray 块，导出时忽略）'),
      ],
    );
  }
}
