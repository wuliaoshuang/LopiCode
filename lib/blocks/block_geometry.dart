/// 积木排版的结果：每块积木、每个槽位、每个可拼接点在哪。纯数据 + 查找函数，不画东西。
///
/// 坐标都是“这一串脚本自己的坐标”（帽子左上角附近是原点，逻辑像素）；画布上再整体加上脚本的 x / y。
/// 怎么算出来的在 block_layout.dart；怎么画在 block_paint_view.dart。
library;

import 'dart:ui';

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 尺寸表。所有数字集中在这里，画和算用同一份（凹口凸起对不对得上全靠它）。
class BkMetrics {
  const BkMetrics();

  /// 一块积木自己（不算嵌在 C 形口里的）最宽这么多，再长就在积木内部换行。
  double get maxBlockWidth => 320;
  double get minBlockWidth => 88;

  /// 有口的积木（C / E 形）最少这么宽，口才看得出来。
  double get minMouthBlockWidth => 132;

  /// 积木里：左右留白、上下留白、同一行两样东西的间距、两行之间的间距。
  double get padH => 12;
  double get padV => 7;
  double get gap => 6;
  double get rowGap => 4;

  /// 字号和一行字的高度。
  double get fontSize => 14;
  double get textH => 20;

  /// 输入框 / 下拉 / 空槽的高度，左右留白，最窄、最宽（字太长就省略）。
  double get fieldH => 26;
  double get fieldPadH => 9;
  double get fieldMinW => 30;
  double get fieldMaxTextW => 150;

  /// 下拉槽右边小三角占的宽度。
  double get caretW => 12;

  /// 表达式块：左右留白、上下留白；六边形两头尖角的宽度。
  double get exprPadH => 8;
  double get exprPadV => 3;
  double get hexTip => 10;

  /// 表达式越套越窄，但不窄过这个数。
  double get minExprWidth => 96;

  /// 凹口 / 凸起：离积木左边多远、多宽、斜边占多宽、多深。
  double get notchX => 14;
  double get notchW => 24;
  double get notchSlope => 5;
  double get notchD => 5;

  /// 圆角。
  double get corner => 7;

  /// 帽子的圆顶：比普通积木多出来的高度、圆顶的宽度。
  double get hatDome => 13;
  double get hatDomeW => 92;

  /// C 形块：左边那条“胳膊”的宽度、空口的高度、两个口之间那条（写“否则”）的高度、最下面那条的高度。
  double get armW => 14;
  double get mouthMinH => 30;
  double get dividerH => 26;

  /// 多口积木（能加段的）上不带槽的矮横栏（“否则”“都不是”“出错了”）：比 [dividerH] 高一点——横栏右边有“−”小按钮，
  /// 上面那块积木的榫头又会探进来，26 高时字显得挤、偏下。
  double get armBarH => 32;
  double get footerH => 16;

  /// 多口积木上的小按钮（“＋”“−”）：圆的直径；带“＋”的底条的高度。
  double get controlD => 20;
  double get addFooterH => 30;

  /// 立体感：底下那道深色边的厚度。
  double get edgeH => 2;

  /// 普通一行（只有字）时积木的高度；触控目标不小于 40。
  double get minBlockHeight => fieldH + padV * 2;
}

/// 表达式里的路径：从积木的某个参数出发，一步步往里。每一步是字段名（`l` / `r` / `x` / `items`）或列表下标（int）。
/// 空表＝这个参数本身。例：参数 value 是 `bin`，它的左边 → `['l']`；`join` 的第 2 项 → `['items', 1]`。
typedef BkExprPath = List<Object>;

/// 按路径取表达式里的值（表达式、字面量都可能）；走不通返回 null。
Object? bkExprAt(LcBlock block, String arg, BkExprPath path) {
  Object? v = block.argValue(arg);
  for (final step in path) {
    if (step is int) {
      if (v is! List || step < 0 || step >= v.length) return null;
      v = v[step];
    } else {
      if (v is! Map) return null;
      v = v[step];
    }
  }
  return v;
}

/// 按路径把值放进去（替换原来的）。路径走不通返回 false，什么都不改。要在宿主的 edit 里调。
bool bkSetExprAt(LcBlock block, String arg, BkExprPath path, Object? value) {
  if (path.isEmpty) return block.setArgValue(arg, value);
  final parent = bkExprAt(block, arg, path.sublist(0, path.length - 1));
  final last = path.last;
  if (last is int) {
    if (parent is! List || last < 0 || last >= parent.length) return false;
    parent[last] = value;
    return true;
  }
  if (parent is! Map) return false;
  parent[last] = value;
  return true;
}

bool bkSameExprPath(BkExprPath a, BkExprPath b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool bkSameBlockPath(LcBlockPath a, LcBlockPath b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) return false;
    if (i > 0 && !lcSameMouth(a[i], b[i])) return false;
  }
  return true;
}

/// `inner` 是不是 `outer` 那块积木本身或在它里面。
bool bkPathWithin(LcBlockPath outer, LcBlockPath inner) => inner.length >= outer.length && bkSameBlockPath(outer, inner.sublist(0, outer.length));

/// 积木上的一段字。
class BkLabel {
  BkLabel(this.text, this.rect);
  final String text;
  Rect rect;
}

/// 槽位画成什么样。
enum BkSlotLook {
  /// 白底输入框（文字 / 数字，可以就地输入）。
  field,

  /// 深色胶囊 + 小三角（变量 / 控件 / 集合 / 固定选项）。
  dropdown,

  /// 是 / 否开关（六边形）。
  toggle,

  /// 里面嵌着一个表达式块（[BkSlot.expr]）。
  expr,

  /// 空的表达式槽（等着拖一个表达式进来）。
  empty,

  /// 一串值（`join` 的 items）末尾的小“＋”：点一下加一项。[BkSlot.exprPath] 的最后一步是“新的一项会在第几位”。
  /// 参数小块后面的“＋”（加一个参数）也是它，这时 [BkSlot.param] 是“新参数会在第几位”。
  add,

  /// 参数小块（定义帽子上的、匿名函数上的）：点一下改，长按拿出一份当值用。[BkSlot.param] 是第几个参数。
  param,
}

/// 一个参数槽。
class BkSlot {
  BkSlot({
    required this.arg,
    required this.exprPath,
    required this.spec,
    required this.look,
    required this.rect,
    this.text = '',
    this.placeholder = false,
    this.hex = false,
    this.expr,
    this.hatSlotId,
    this.param,
    this.colorKey,
  });

  /// 属于积木的哪个参数（帽子的槽位是空字符串，看 [hatSlotId]）。多口积木某一段的参数是 `@<第几段>:<名字>`（见 `lcArmArg`）。
  final String arg;

  /// 在那个参数里的位置（见 [BkExprPath]）。积木自己的参数是空表。
  final BkExprPath exprPath;

  /// 这个槽的说明（哪种参数、想要什么类型）。帽子槽位、认不出的为 null。
  final LcArgSpec? spec;
  final BkSlotLook look;
  Rect rect;

  /// 显示的字（输入框 / 下拉 / 开关）。
  final String text;

  /// `text` 是不是“还没选”的提示语。
  final bool placeholder;

  /// 六边形（要“是 / 否”的槽）。
  final bool hex;

  /// 嵌在里面的表达式块。
  final BkExpr? expr;

  /// 帽子上的槽位才有：宿主给的槽位名。
  final String? hatSlotId;

  /// 参数小块 / 加参数的“＋”才有：第几个参数。在帽子上时 [arg] 是空的；在带参数表的值上时 [arg] / [exprPath] 指着那个值。
  final int? param;

  /// 参数小块画成什么颜色（＝它拖出来变成的那个值的颜色）。
  final String? colorKey;

  /// 能不能把表达式拖进来（表达式槽、以及放着字面量表达式的槽）。
  bool get acceptsExpr => look != BkSlotLook.add && (spec?.kind == LcArgKind.expr || spec?.kind == LcArgKind.exprList || look == BkSlotLook.expr || look == BkSlotLook.empty);
}

/// 一个表达式块（嵌在槽里，或单独摆在积木盒里）。
class BkExpr {
  BkExpr({required this.expr, required this.kind, required this.colorKey, required this.rect, required this.hex, required this.bare, this.unknown = false});

  /// 模型里的那个表达式对象（只读着用；改要走宿主的 edit）。
  final Map<String, dynamic> expr;
  final String kind;
  final String colorKey;
  Rect rect;
  final bool hex;

  /// “光杆”表达式：文字 / 数字 / 是否这种直接填的，只画里面那个输入框，外面不再包一层彩色块。
  final bool bare;
  final bool unknown;
  final List<BkLabel> labels = [];
  final List<BkSlot> slots = [];

  /// “带口的值”才有：里面那个能放语句积木的口占的位置。
  Rect? mouth;

  /// 排版中途用：口里的积木和拼接点（相对这个值自己的左上角）。排完整块以后挪进整串的表里，这两张表就空了。
  List<BkBlock> inner = [];
  List<BkSnap> innerSnaps = [];
}

enum BkShape { hat, stack, mouth, expr }

/// C 形块的一个口。
class BkMouth {
  BkMouth({required this.inElse, required this.rect, this.bar, this.label, this.arm = -1});

  /// false＝body，true＝else。[arm] >= 0 时不看它。
  final bool inElse;

  /// 多口积木中间的第几段（见 `LcBlock.arms`）；-1＝不是段（开头口 / 收尾口）。
  final int arm;

  /// 这一段横栏上的字和槽（“否则如果 <条件> 那么”）。槽同时也在 [BkBlock.slots] 里（排在头上的槽后面）。
  final List<BkLabel> labels = [];
  final List<BkSlot> slots = [];

  /// 口里面的空（左边贴着胳膊，右边到积木右边）。
  Rect rect;

  /// 口上面那条横栏（开头口没有；收尾口的写“否则”“失败后”，在 [label] 里；段的横栏上是一句带槽的话）。
  Rect? bar;
  BkLabel? label;
}

/// 多口积木上的小按钮是干什么的。
enum BkControlKind {
  /// 底条上的“＋”：加一段（收尾口被收起来时，还能把它加回来）。
  add,

  /// 某一段横栏右边的“−”：删掉这一段。
  removeArm,

  /// 收尾口横栏右边的“−”：把收尾口（“否则”）收起来。
  removeTail,
}

/// 多口积木上的一个小按钮。
class BkControl {
  BkControl({required this.kind, required this.rect, this.arm = -1, this.mouth = -1});
  final BkControlKind kind;

  /// 画出来的那个小圆占的位置；点击范围是 [hitRect]（不小于 40×40）。
  Rect rect;

  /// [BkControlKind.removeArm]：第几段。
  final int arm;

  /// 在第几个口的横栏上（[BkBlock.mouths] 的下标）；-1＝在底条上。让位动画里跟着那条横栏走。
  final int mouth;

  Rect get hitRect => Rect.fromCenter(center: rect.center, width: 44, height: 40);
}

/// 一块积木（帽子、语句、C 形）。
class BkBlock {
  BkBlock({required this.path, required this.block, required this.shape, required this.colorKey, required this.rect, required this.head, this.unknown = false});

  /// 模型路径。帽子是空表。
  final LcBlockPath path;

  /// 模型里的积木；帽子为 null。
  final LcBlock? block;
  final BkShape shape;
  final String colorKey;

  /// 整块的外框（C 形块包括口和底下那条；不含底部凸起，凸起再往下伸 [BkMetrics.notchD]）。
  Rect rect;

  /// 上面写字的那一条。普通积木＝[rect]。
  Rect head;
  final bool unknown;
  final List<BkLabel> labels = [];
  final List<BkSlot> slots = [];
  final List<BkMouth> mouths = [];

  /// [slots] / [labels] 里前多少个在头上（其余在各段的横栏上，见 [BkMouth.slots]）。
  int headSlots = 0;
  int headLabels = 0;

  /// 多口积木上的小按钮（加一段、删一段、收起收尾口）。
  final List<BkControl> controls = [];

  bool get isHat => shape == BkShape.hat;

  /// 点有没有落在积木“实心”的地方（C 形块的口不算）。
  bool solidContains(Offset p) {
    if (!rect.contains(p)) return false;
    for (final m in mouths) {
      if (m.rect.contains(p)) return false;
    }
    return true;
  }
}

enum BkSnapKind { statement, expr }

/// 一个可拼接点。
class BkSnap {
  BkSnap.statement({required this.parent, required this.inElse, required this.index, required this.anchor, required this.width, this.arm = -1})
    : kind = BkSnapKind.statement,
      arg = null,
      exprPath = const [],
      rect = Rect.fromLTWH(anchor.dx, anchor.dy, width, 0),
      hex = false;

  BkSnap.expr({required LcBlockPath block, required String this.arg, required this.exprPath, required this.rect, required this.hex})
    : kind = BkSnapKind.expr,
      parent = block,
      inElse = false,
      arm = -1,
      index = 0,
      anchor = rect.centerLeft,
      width = rect.width;

  final BkSnapKind kind;

  /// 语句：插进哪块积木里（空＝这一串的最外层）；表达式：槽在哪块积木上。
  final LcBlockPath parent;

  /// 语句：插进 body 还是 else。
  final bool inElse;

  /// 语句：插进第几段的口（多口积木，见 `LcBlock.arms`）；-1＝不是段，看 [inElse]。
  final int arm;

  /// 语句：插在第几位（0＝最前，等于列表长度＝最后）。正好对应 `LcBlockTree.insertBlock(parent, b, inElse:, index:)`。
  final int index;

  /// 表达式：哪个参数、参数里的哪个位置（[bkSetExprAt] 的后两个参数）。
  final String? arg;
  final BkExprPath exprPath;

  /// 语句：被拖的那块的左上角应该吸到这里。表达式：槽的左边中点。
  final Offset anchor;

  /// 语句：这个位置上积木的参考宽度（画落点阴影用）。
  final double width;

  /// 表达式：槽的位置和大小；语句：一条高度为 0 的线。
  final Rect rect;

  /// 表达式：这个槽是不是六边形（要“是 / 否”）。
  final bool hex;

  /// 挪一下位置（别的都不变）。
  BkSnap shifted(Offset d) => kind == BkSnapKind.statement
      ? BkSnap.statement(parent: parent, inElse: inElse, arm: arm, index: index, anchor: anchor + d, width: width)
      : BkSnap.expr(block: parent, arg: arg!, exprPath: exprPath, rect: rect.shift(d), hex: hex);

  /// 一个点离这个拼接点多远。语句看和 [anchor] 的距离（竖直方向算足，水平方向打对折——手指左右偏一点不该错过）；
  /// 表达式看离槽的矩形多远（在里面是 0）。
  double distanceTo(Offset p) {
    if (kind == BkSnapKind.statement) {
      final dx = (p.dx - anchor.dx) * 0.5, dy = p.dy - anchor.dy;
      return Offset(dx, dy).distance;
    }
    final dx = p.dx < rect.left ? rect.left - p.dx : (p.dx > rect.right ? p.dx - rect.right : 0.0);
    final dy = p.dy < rect.top ? rect.top - p.dy : (p.dy > rect.bottom ? p.dy - rect.bottom : 0.0);
    return Offset(dx, dy).distance;
  }
}

/// 点到了什么。
class BkHit {
  const BkHit(this.block, {this.slot, this.expr, this.control});

  /// 点到的积木（表达式块、槽位也算在它所在的积木头上）。
  final BkBlock block;

  /// 点到的最里面那个槽位（没点到槽位为 null）。
  final BkSlot? slot;

  /// 点到的最里面那个表达式块（它所在的槽是 [slot]）。
  final BkExpr? expr;

  /// 点到的是多口积木上的小按钮（这时 [slot] / [expr] 都是 null）。
  final BkControl? control;
}

/// 一串脚本排好以后的样子。
class BkScriptLayout {
  BkScriptLayout({required this.scriptId, required this.blocks, required this.snaps, required this.size, this.loose});

  /// 哪一串（积木盒里的样品、拖着的那一截是空字符串）。
  final String scriptId;

  /// 所有积木：帽子在最前（如果有），然后从上到下、从外到里。
  final List<BkBlock> blocks;

  /// 所有可拼接点。
  final List<BkSnap> snaps;

  /// 整串占多大（含底部凸起）。
  final Size size;

  /// 单独摆着的一个表达式块（积木盒里的样品 / 拖着的表达式）；这时 [blocks] 为空。
  final BkExpr? loose;

  BkBlock? get hat => blocks.isNotEmpty && blocks.first.isHat ? blocks.first : null;

  /// 按模型路径找积木（空路径＝帽子）。
  BkBlock? blockAt(LcBlockPath path) {
    for (final b in blocks) {
      if (bkSameBlockPath(b.path, path) && b.isHat == path.isEmpty) return b;
    }
    return null;
  }

  /// 这个点上是什么。没点到积木返回 null。
  BkHit? hitTest(Offset p) {
    // 后面的在里层（先外后里排的），所以倒着找。
    for (var i = blocks.length - 1; i >= 0; i--) {
      final b = blocks[i];
      if (!b.solidContains(p)) continue;
      // 小按钮：先看有没有正好点在圆上（它旁边可能紧挨着槽），再往下看槽。
      for (final c in b.controls) {
        if (c.rect.inflate(3).contains(p)) return BkHit(b, control: c);
      }
      final found = _hitSlots(b.slots, p);
      if (found == null) {
        // 没点到槽：小按钮的点击范围放大到 40 以上（只在积木实心的地方算）。
        for (final c in b.controls) {
          if (c.hitRect.contains(p)) return BkHit(b, control: c);
        }
      }
      return BkHit(b, slot: found?.$1, expr: found?.$2);
    }
    return null;
  }

  static (BkSlot, BkExpr?)? _hitSlots(List<BkSlot> slots, Offset p) {
    for (final s in slots) {
      if (!s.rect.contains(p)) continue;
      final e = s.expr;
      if (e != null) {
        final inner = _hitSlots(e.slots, p);
        if (inner != null) return (inner.$1, inner.$2 ?? (e.bare ? null : e));
        return (s, e.bare ? null : e);
      }
      return (s, null);
    }
    return null;
  }

  /// 离这个点最近的可拼接点；超过 `maxDistance` 的不算。
  ///
  /// `kind`：拖的是语句积木还是表达式。语句传被拖那块的**左上角**；表达式传被拖块的**左边中点**（或手指的位置）。
  /// `exclude`：正在拖的那块积木的路径——它自己里面的位置不算（不能把积木拖进自己肚子里）。
  /// 紧贴它上下的位置照样会返回（放回去等于没动，由调用方判断）。
  BkSnap? nearestSnap(Offset p, {required BkSnapKind kind, double maxDistance = 36, LcBlockPath? exclude}) {
    BkSnap? best;
    var bestD = maxDistance;
    for (final s in snaps) {
      if (s.kind != kind) continue;
      if (exclude != null && bkPathWithin(exclude, s.parent)) continue;
      final d = s.distanceTo(p);
      if (d <= bestD) {
        // 一样近时取后面的（更里层的）。
        best = s;
        bestD = d;
      }
    }
    return best;
  }

  /// 所有的槽位（含嵌在表达式里的），从外到里。
  Iterable<(BkBlock, BkSlot)> get allSlots sync* {
    Iterable<BkSlot> walk(List<BkSlot> slots) sync* {
      for (final s in slots) {
        yield s;
        final e = s.expr;
        if (e != null) yield* walk(e.slots);
      }
    }

    for (final b in blocks) {
      for (final s in walk(b.slots)) {
        yield (b, s);
      }
    }
  }
}
