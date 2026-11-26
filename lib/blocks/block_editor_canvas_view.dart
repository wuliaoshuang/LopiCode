// 设计约束（可编辑的积木画布，390 宽，浅色 + 深色）— 2026-11-24
// - 整块区域只有画布一样东西：点阵底 + 一串串积木。没有“进入编辑模式”这一步。
// - 一根手指滑动一律是平移画布，起点落在积木上也一样（积木铺满屏幕时也能放心滑着看）；两根手指是缩放（50%–200%）。
// - 拖积木要先按住不动 0.28 秒（长按）：震一下、积木被“拿起”（略放大带投影），之后才跟手。
//   按住的这 0.28 秒里手指动了超过 8 像素＝这次是平移，不再拿起。
// - 长按落在哪决定做什么：直接填的槽（输入框、空槽，里面没有值积木）＝弹“换成…”小卡；
//   槽里的值积木＝拿起它（拿起后没挪就松手＝弹“换成…”小卡，挪了＝拖走）；积木身上别的地方＝拿起这块（帽子＝整串）。
// - 没动就抬起（不到 0.28 秒）＝点一下。
// - 没摆过位置的脚本自动从上往下排，算出来的位置不写回模型（不进撤销、不落盘）。
// - 画的时候只画一次排版结果；拖动时画的是“拿走以后 + 让出落点”的预览排版，模型一个字不动。
// - 让位是滑过去的（约 150 毫秒）：两头的位置由 block_motion.dart 算，这里只出一个 0–1 的进度；系统开了“减弱动态效果”就直接到位。
// - 拖动时，能接的地方亮一个很淡的小点（语句：每个凸起上；表达式：每个能放值的槽一圈细线），教人“可以放这”。
// - 双击空白处＝回到 100%、回到起始位置。
// - 画布从屏幕最顶铺起，顶栏是浮在它上面的（沉浸式）：顶栏盖住的那一段（coveredTop）和积木盒盖住的那一段一样算“看不见”。
//   起始位置、双击回 100%、跳到某块积木、缩放的中心都按露出来的那一段算；积木可以从顶栏按钮下面滑过去。
import 'dart:async';
import 'dart:math' as math;

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_motion.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/blocks/block_shapes.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

enum _Touch { none, pending, pan, drag, pinch, held }

/// 画布这一层：排版缓存、平移缩放、选中、把手指的动作分成“点 / 长按 / 拖积木 / 平移 / 缩放”。
mixin BkEditorCanvas on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider {
  static const double minZoom = 0.5, maxZoom = 2.0;

  /// 手指移动多远算“滑”而不是“点 / 按住”。
  static const double dragSlop = 8;

  /// 按住不动多久算长按（拿起积木 / 弹“换成…”）。比系统默认的 0.5 秒短：拖积木是常用动作，不能等太久；
  /// 又比一次轻点（通常不到 0.2 秒）长，点一下不会误拿。
  static const Duration longPressAfter = Duration(milliseconds: 280);

  BlockHost get host => widget.host;

  final GlobalKey viewKey = GlobalKey(debugLabel: 'bk-editor-view');

  /// 画布上的点 × [zoom] + [pan] + [viewOrigin] ＝ 编辑区里的点。`pan` 为零＝起始位置（画布原点正好在悬浮顶栏的下沿）。
  Offset pan = Offset.zero;
  double zoom = 1;
  Size viewSize = Size.zero;

  /// 编辑区最上面被悬浮顶栏（连同状态栏）盖住多高。整页每次搭界面时告诉这里。
  double coveredTop = 0;

  /// 起始位置时画布原点在编辑区的哪里：悬浮顶栏的下沿。
  Offset get viewOrigin => Offset(0, coveredTop);

  BlockLayoutEngine? _engine;
  BkCanvasLayout? _layout;
  int _layoutRev = -1;
  List<BlockIssue> issues = const [];

  /// [issues] 按串分好（画标记、点角标用）。
  Map<String, BkIssueMarks> issueMarks = const {};
  BlockSelection? selection;

  late final AnimationController flashAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  // —— 动效 ——
  /// 让位滑动多久；落下以后轻弹多久。
  static const Duration roomTime = Duration(milliseconds: 150);
  static const Duration pulseTime = Duration(milliseconds: 100);

  /// 系统开了“减弱动态效果”（`MediaQuery.disableAnimations`）：所有动画直接到终态。每次 build 时更新。
  bool reduceMotion = false;

  final BkMotion motion = BkMotion();
  late final AnimationController roomAnim = AnimationController(vsync: this, duration: roomTime, value: 1);
  late final AnimationController pulseAnim = AnimationController(vsync: this, duration: pulseTime, value: 1);
  ({String scriptId, BkRoom? range, ({LcBlockPath block, String arg, BkExprPath path})? slot})? _pulse;

  /// 让位滑到哪了（0–1，已经过了缓动）。
  double get roomT => reduceMotion ? 1 : Curves.easeOutCubic.transform(roomAnim.value);

  /// 画布换成 `next` 这个排布：积木从现在看到的位置滑过去。`room`＝`next` 里让出来 / 新放进去的那一截（它不滑）。
  /// `always`＝没有积木要滑也把进度从头走一遍（落点换了：手上积木被“吸”过去、落点阴影淡入都跟这个进度）。
  void slideTo(BkCanvasLayout next, {BkRoom? room, bool always = false}) {
    if (reduceMotion) {
      motion.jump(next, room: room);
      roomAnim.value = 1;
      return;
    }
    motion.retarget(next, room: room, progress: roomT);
    if (motion.moving || room != null || always) {
      unawaited(roomAnim.forward(from: 0));
    } else {
      roomAnim.value = 1;
    }
  }

  /// 刚落下的积木轻弹一下：`range`＝哪一段（null＝整串）；`slot`＝表达式落进的那个槽（只闪描边）。
  void pulseBlocks(String scriptId, {BkRoom? range, ({LcBlockPath block, String arg, BkExprPath path})? slot}) {
    if (reduceMotion) return;
    _pulse = (scriptId: scriptId, range: range, slot: slot);
    unawaited(pulseAnim.forward(from: 0));
  }

  /// 某块积木此刻画在画布的哪里（让位动画进行中是中间位置）。`path` 是它在“现在画的排布”里的路径，空＝帽子。测试用。
  Rect? shownRect(String scriptId, LcBlockPath path) {
    final placed = (drag?.display ?? previewLayout ?? layout).placed(scriptId);
    final b = path.isEmpty ? placed?.layout.hat : placed?.layout.blockAt(path);
    if (placed == null || b == null) return null;
    return motion.frameOf(b, roomT)?.rect ?? b.rect.shift(placed.origin);
  }

  final Map<int, Offset> _pointers = {};
  _Touch _touch = _Touch.none;
  int _primary = -1;
  Offset _downAt = Offset.zero;
  ({BkPlaced script, BkHit hit})? _downHit;

  /// 长按拿起积木以后，手指有没有挪过（超过 [dragSlop]）。
  bool _liftMoved = false;
  Timer? _longPress;
  double _pinchDist = 1, _pinchZoom = 1;
  Timer? _blankTap1;
  Offset _blankTapPos = Offset.zero;

  /// 手指按下的地方（画布坐标）。
  Offset get downCanvas => toCanvas(_downAt);

  // —— 别的几层提供的 ——
  BkDragSession? get drag;
  bool get busy;

  /// 松手后的动画还没走完时又有新的操作：立刻走完（该改的模型马上改好）。返回现在能不能接新手势。
  bool settleNow();

  /// 就地输入时的预览排布（正在改的输入框跟着字变宽）；没在输入为 null。
  BkCanvasLayout? get previewLayout;
  void dragStartFromCanvas(BkPlaced script, BkHit hit, Offset viewAt);
  void dragMove(Offset viewAt);
  void dragEnd();
  void dragCancel();
  void onTapHit(BkPlaced script, BkHit hit);

  /// 长按参数小块：拿出一份。拿起来了返回 true。
  bool liftParam(BkPlaced script, BkHit hit, Offset viewAt) => false;

  /// 长按拿起来、没挪就松手：这样东西有自己的菜单就放回原处并弹出来，返回 true；没有返回 false（照老样子）。
  bool onLiftRelease(BkPlaced script, BkHit hit) => false;

  /// 长按的地方有没有“换成…”可弹：`open`＝有就弹出来；否则只是问一声。返回有没有。
  bool onLongPressHit(BkPlaced script, BkHit hit, {bool open = true});

  BlockLayoutEngine get engine => _engine ??= kit.engine(host);

  @override
  void kitChanged() {
    _engine = null;
    _layout = null;
  }

  /// 现在的排布（没在拖的时候的样子）。
  BkCanvasLayout get layout {
    if (_layout == null || _layoutRev != host.revision) {
      _layout = layoutBlockCanvas(host, engine);
      _layoutRev = host.revision;
      _readIssues();
      final sel = selection;
      if (sel != null && _layout!.placed(sel.scriptId)?.layout.blockAt(sel.path) == null) selection = null;
    }
    return _layout!;
  }

  void dropLayout() {
    _engine = null;
    _layout = null;
  }

  Offset toCanvas(Offset view) => (view - viewOrigin - pan) / zoom;
  Offset toView(Offset canvas) => canvas * zoom + pan + viewOrigin;
  Rect rectToView(Rect canvas) => Rect.fromPoints(toView(canvas.topLeft), toView(canvas.bottomRight));

  /// 屏幕上的点换成编辑区里的点。
  Offset viewOf(Offset global) {
    final box = viewKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  Offset globalOf(Offset view) {
    final box = viewKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.localToGlobal(view) : view;
  }

  /// 底下被积木盒盖住多高（画布露出来的部分＝上面这一段）。
  double get coveredBottom;

  void setPan(Offset next) {
    final ext = (drag?.display ?? layout).extent * zoom;
    const keep = 72.0;
    // 露出来的那一段（顶栏下沿到积木盒上沿）有多高：内容至少留 keep 在这一段里。
    final w = viewSize.width, h = math.max(keep * 2, viewSize.height - coveredTop - coveredBottom);
    pan = Offset(next.dx.clamp(math.min(keep - ext.width, 0), math.max(w - keep, 0)).toDouble(), next.dy.clamp(math.min(keep - ext.height, 0), math.max(h - keep, 0)).toDouble());
  }

  void setZoom(double next, Offset focalView) {
    final z = next.clamp(minZoom, maxZoom).toDouble();
    final at = toCanvas(focalView);
    zoom = z;
    setPan(focalView - viewOrigin - at * z);
  }

  void select(BlockSelection? s) {
    if (s == null ? selection == null : s.same(selection)) return;
    setState(() => selection = s);
  }

  /// 取校验结果。宿主那边内容没变不会重查；查得慢时它先给旧的，稍后查完会通知重画，那时这里再取一次。
  void _readIssues() {
    final next = host.liveIssues;
    if (identical(next, issues)) return;
    issues = next;
    issueMarks = BkIssueMarks.byScript(next);
  }

  /// 点在角标上：选中那块积木，贴着角标弹出问题小卡。返回点没点中。
  bool _tapBadge(Offset viewAt) {
    if (drag != null || issueMarks.isEmpty) return false;
    final hit = bkIssueBadgeAt(layout, issueMarks, toCanvas(viewAt), kit.metrics, 15 / zoom);
    if (hit == null) return false;
    select(BlockSelection(hit.script.id, hit.block.isHat ? const [] : hit.block.path));
    final at = toView(bkIssueBadgeCenter(hit.block, kit.metrics) + hit.script.origin);
    final r = 9 * zoom;
    // 小卡贴着角标、放在这块积木头部的下面（不盖住它自己）；下面放不下时放到角标上面。
    final foot = toView(hit.block.head.bottomRight + hit.script.origin).dy;
    unawaited(showBlockIssueCard(context, anchor: Rect.fromPoints(globalOf(at - Offset(r, r)), globalOf(Offset(at.dx + r, math.max(at.dy + r, foot)))), issues: hit.issues));
    return true;
  }

  /// 打开问题列表；点了能定位的一条就关掉列表、跳到那块积木。顶栏的“问题”按钮和外面的“查看问题”都走这里。
  Future<void> openIssues() async {
    final picked = await showBlockIssues(context, host.issues);
    if (!mounted || picked == null) return;
    final id = picked.scriptId;
    if (id != null) jumpTo(id, picked.path);
  }

  /// 跳到某块积木：选中、挪到看得见的地方（缩得太小看不清、或大得一屏放不下时顺手调一下缩放）、闪一下。
  void jumpTo(String scriptId, LcBlockPath path) {
    final placed = layout.placed(scriptId);
    final block = placed?.layout.blockAt(path) ?? placed?.layout.hat;
    if (placed == null || block == null) return;
    // 画布露出来的部分：按编辑器此刻真实的大小算（上面被悬浮顶栏盖住、底下被积木盒盖住多少都算进去）。
    final top = coveredTop, h = viewSize.height - coveredBottom;
    final head = block.head.shift(placed.origin);
    var z = zoom;
    if (z < 0.75) z = 1;
    if (viewSize.width > 96 && head.width * z > viewSize.width - 32) z = (viewSize.width - 32) / head.width;
    if (z != zoom) zoom = z.clamp(minZoom, maxZoom).toDouble();
    final rect = rectToView(block.rect.shift(placed.origin));
    setState(() {
      selection = BlockSelection(scriptId, block.isHat ? const [] : block.path);
      if (rect.top < top + 56 || rect.bottom > h - 16 || rect.left < 0 || rect.left > viewSize.width - 80) {
        setPan(pan + Offset(16 - rect.left, top + math.max(64, (h - top) * 0.3) - rect.top));
      }
    });
    unawaited(flashAnim.forward(from: 0));
  }

  // —— 手指 ——
  void _clearLongPress() {
    _longPress?.cancel();
    _longPress = null;
  }

  void pointerDown(PointerDownEvent e) {
    // 动画不挡手：上一次松手的动画还在走，这一下按下去就让它立刻走完，然后照常接这次手势。
    if (busy && !settleNow()) return;
    final at = viewOf(e.position);
    _pointers[e.pointer] = at;
    if (_pointers.length >= 2) {
      _clearLongPress();
      if (_touch == _Touch.drag) return; // 拖着积木时第二根手指不管。
      final ps = _pointers.values.toList();
      _pinchDist = math.max(1, (ps[0] - ps[1]).distance);
      _pinchZoom = zoom;
      _touch = _Touch.pinch;
      return;
    }
    _primary = e.pointer;
    _downAt = at;
    _downHit = layout.hitTest(toCanvas(at));
    _touch = _Touch.pending;
    _clearLongPress();
    if (_downHit != null) _longPress = Timer(longPressAfter, _longPressed);
  }

  /// 按住没动满了 [longPressAfter]：拿起积木，或者弹“换成…”。
  void _longPressed() {
    final hit = _downHit;
    if (!mounted || _touch != _Touch.pending || hit == null) return;
    _touch = _Touch.held;
    if (hit.hit.slot?.look == BkSlotLook.param) {
      // 参数小块：长按＝拿出一份当值用。
      if (!liftParam(hit.script, hit.hit, _downAt)) return;
    } else {
      // 直接填的槽（里面没有值积木可拿）：长按＝换成别的值。
      if (hit.hit.expr == null && onLongPressHit(hit.script, hit.hit)) return;
      dragStartFromCanvas(hit.script, hit.hit, _downAt);
      // 拿不起来（这块刚好没了）：退回老的长按。
      if (drag == null) onLongPressHit(hit.script, hit.hit);
    }
    if (drag == null) return;
    _liftMoved = false;
    _touch = _Touch.drag;
  }

  void pointerMove(PointerMoveEvent e) {
    final before = _pointers[e.pointer];
    if (before == null) return;
    final at = viewOf(e.position);
    _pointers[e.pointer] = at;
    switch (_touch) {
      case _Touch.pending:
        if (e.pointer != _primary || (at - _downAt).distance < dragSlop) return;
        // 还没按够就动了：这次是滑着看画布，起点在不在积木上都一样。
        _clearLongPress();
        _touch = _Touch.pan;
        setState(() => setPan(pan + (at - _downAt)));
      case _Touch.pan:
        if (e.pointer == _primary) setState(() => setPan(pan + (at - before)));
      case _Touch.drag:
        if (e.pointer != _primary) return;
        if ((at - _downAt).distance >= dragSlop) _liftMoved = true;
        dragMove(at);
      case _Touch.pinch:
        final ps = _pointers.values.toList();
        if (ps.length < 2) return;
        final focal = (ps[0] + ps[1]) / 2;
        final moved = at - before;
        setState(() {
          setPan(pan + moved / 2);
          setZoom(_pinchZoom * (ps[0] - ps[1]).distance / _pinchDist, focal);
        });
      case _Touch.none || _Touch.held:
        break;
    }
  }

  void pointerUp(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    _clearLongPress();
    final cancelled = e is PointerCancelEvent;
    switch (_touch) {
      case _Touch.pending:
        final hit = _downHit;
        _touch = _Touch.none;
        if (cancelled) return;
        if (_tapBadge(_downAt)) return;
        if (hit == null) {
          select(null);
          _blankTap(e);
        } else {
          onTapHit(hit.script, hit.hit);
        }
      case _Touch.drag:
        if (e.pointer != _primary) return;
        _touch = _Touch.none;
        final hit = _downHit;
        if (cancelled) {
          dragCancel();
        } else if (!_liftMoved && hit != null && onLiftRelease(hit.script, hit.hit)) {
          // ↑ 没挪就松手，这样东西有自己的菜单（参数小块的小卡、语句积木的“包成积木”）：那边已经处理了。
        } else if (!_liftMoved && hit != null && hit.hit.expr != null && onLongPressHit(hit.script, hit.hit, open: false)) {
          // 拿起一个值积木、没挪就松手：放回原处，弹“换成…”。
          dragCancel();
          onLongPressHit(hit.script, hit.hit);
        } else {
          dragEnd();
        }
      case _Touch.pinch:
        // 松开一根：剩下那根接着平移。
        if (_pointers.length == 1) {
          _primary = _pointers.keys.first;
          _touch = _Touch.pan;
        } else if (_pointers.isEmpty) {
          _touch = _Touch.none;
        }
      case _Touch.pan || _Touch.held || _Touch.none:
        if (_pointers.isEmpty) _touch = _Touch.none;
    }
  }

  /// 空白处连点两下（0.3 秒内、同一个地方）：回到 100%、回到起始位置。
  /// 用定时器数时间，不看事件自带的时间戳（有的输入设备不给）。
  void _blankTap(PointerEvent e) {
    final armed = _blankTap1 != null;
    _blankTap1?.cancel();
    _blankTap1 = null;
    if (armed && (_downAt - _blankTapPos).distance < 32) {
      setState(() {
        zoom = 1;
        setPan(Offset.zero);
      });
      return;
    }
    _blankTapPos = _downAt;
    _blankTap1 = Timer(const Duration(milliseconds: 300), () => _blankTap1 = null);
  }

  void disposeCanvas() {
    _clearLongPress();
    _blankTap1?.cancel();
    host.stopIssueTimer();
    flashAnim.dispose();
    roomAnim.dispose();
    pulseAnim.dispose();
  }

  late final Listenable _ticks = Listenable.merge([flashAnim, roomAnim, pulseAnim]);

  /// 画布本体。`shown`＝现在该画的排布（拖动时是预览）。
  Widget buildCanvas(BuildContext context) {
    final d = drag;
    final shown = d?.display ?? previewLayout ?? layout;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: pointerDown,
      onPointerMove: pointerMove,
      onPointerUp: pointerUp,
      onPointerCancel: pointerUp,
      child: AnimatedBuilder(
        animation: _ticks,
        builder: (context, _) {
          final t = roomT;
          final pulse = _pulse;
          return CustomPaint(
            key: const ValueKey('bk-canvas'),
            size: Size.infinite,
            painter: BkWorkspacePainter(
              layout: shown,
              kit: kit,
              pan: pan + viewOrigin,
              zoom: zoom,
              selection: d == null ? selection : null,
              marks: d == null ? issueMarks : const {},
              flash: flashAnim.isAnimating ? 1 - Curves.easeOut.transform(flashAnim.value) : 0,
              ghost: d?.ghost,
              ghostAlpha: t,
              motion: t < 1 && motion.moving ? motion : null,
              motionT: t,
              pulse: pulse != null && pulseAnim.isAnimating ? (scriptId: pulse.scriptId, range: pulse.range, slot: pulse.slot, t: pulseAnim.value) : null,
              hints: d == null || busy || d.kind == BkDragKind.hat ? null : (d.kind == BkDragKind.statement ? BkSnapKind.statement : BkSnapKind.expr),
              hintsIn: d?.palette?.onlyScript,
              slot: d == null || d.kind != BkDragKind.expr || d.target == null
                  ? null
                  : (scriptId: d.target!.scriptId, block: d.target!.snap.parent, arg: d.target!.snap.arg ?? '', path: d.target!.snap.exprPath, warn: d.target!.mismatch),
            ),
          );
        },
      ),
    );
  }
}

class BkWorkspacePainter extends CustomPainter {
  BkWorkspacePainter({
    required this.layout,
    required this.kit,
    required this.pan,
    required this.zoom,
    this.selection,
    this.marks = const {},
    this.flash = 0,
    this.ghost,
    this.ghostAlpha = 1,
    this.motion,
    this.motionT = 1,
    this.pulse,
    this.hints,
    this.hintsIn,
    this.slot,
  });

  final BkCanvasLayout layout;
  final BkKit kit;
  final Offset pan;
  final double zoom;
  final BlockSelection? selection;
  final Map<String, BkIssueMarks> marks;
  final double flash;
  final BkRoom? ghost;
  final double ghostAlpha;

  /// 让位动画：积木此刻的位置从这里查（进度 [motionT]）；null＝都在排版算出来的位置。
  final BkMotion? motion;
  final double motionT;

  /// 刚落下的那一段轻弹一下（`t`＝进度）。
  final ({String scriptId, BkRoom? range, ({LcBlockPath block, String arg, BkExprPath path})? slot, double t})? pulse;

  /// 拖动中：把这一种拼接点都淡淡地标出来（`hintsIn`＝只标这一串的：参数小块只能放进自己那一串）。
  final BkSnapKind? hints;
  final String? hintsIn;
  final ({String scriptId, LcBlockPath block, String arg, BkExprPath path, bool warn})? slot;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = kit.palette;
    // 画布的底色不在这里铺：由外面那一层（block_editor_view 的 bk-canvas-layer）铺，有背景图片且“透出 › 积木画布”开着时它是半透明的。
    _dots(canvas, size, palette);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);
    final visible = Rect.fromLTWH(-pan.dx / zoom, -pan.dy / zoom, size.width / zoom, size.height / zoom).inflate(24);
    final m = motion;
    for (final s in layout.scripts) {
      // 正在滑的时候不按“终点的范围”裁掉整串（它可能正从看得见的地方滑出去）。
      if (m == null && !s.bounds.overlaps(visible)) continue;
      final sel = selection != null && selection!.scriptId == s.id ? selection : null;
      final g = ghost != null && ghost!.scriptId == s.id ? ghost : null;
      final sl = slot != null && slot!.scriptId == s.id ? slot : null;
      final pu = pulse != null && pulse!.scriptId == s.id ? pulse : null;
      final pr = pu?.range;
      final state = BkPaintState(
        selected: sel != null && sel.path.isNotEmpty ? sel.path : null,
        selectedHat: sel != null && sel.path.isEmpty,
        flash: sel == null ? 0 : flash,
        ghostRange: g == null ? null : (parent: g.parent, inElse: g.inElse, arm: g.arm, start: g.start, count: g.count),
        ghostAlpha: ghostAlpha,
        clip: visible.shift(-s.origin),
        pose: m == null ? null : (b) => m.frameOf(b, motionT)?.shift(-s.origin),
        pulse: pu?.t,
        pulseRange: pr == null ? null : (parent: pr.parent, inElse: pr.inElse, arm: pr.arm, start: pr.start, count: pr.count),
        pulseSlot: pu?.slot,
        selectedSlot: sl == null ? null : (block: sl.block, arg: sl.arg, path: sl.path),
        slotColor: sl != null && sl.warn ? palette.warning : null,
        marks: marks[s.id],
      );
      canvas.save();
      canvas.translate(s.origin.dx, s.origin.dy);
      kit.painter.paint(canvas, s.layout, state);
      if (hints != null && (hintsIn == null || hintsIn == s.id)) _hints(canvas, s, visible.shift(-s.origin), g);
      canvas.restore();
    }
    canvas.restore();
  }

  /// 能接的地方：语句＝凸起正中一个小白点；表达式＝槽外面一圈细线。让位滑动的那一小会儿跟着淡入，免得点和积木对不上。
  void _hints(Canvas canvas, BkPlaced s, Rect visible, BkRoom? room) {
    final mt = kit.metrics;
    final a = motion == null ? 1.0 : motionT;
    if (a <= 0) return;
    final dot = Paint()..color = kit.palette.gloss.withValues(alpha: 0.6 * a);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = kit.palette.gloss.withValues(alpha: 0.5 * a);
    for (final snap in s.layout.snaps) {
      if (snap.kind != hints) continue;
      if (room != null) {
        // 落点阴影自己（上下两头）和它里面的位置不标。
        final sameList =
            bkSameBlockPath(snap.parent, room.parent) && (room.parent.isEmpty || lcSameMouth(lcStep(0, inElse: snap.inElse, arm: snap.arm), lcStep(0, inElse: room.inElse, arm: room.arm)));
        if (snap.kind == BkSnapKind.statement && sameList && snap.index >= room.start && snap.index <= room.start + room.count) continue;
        if (snap.parent.isNotEmpty && bkPathBeforeRoom(snap.parent, room) == null) continue;
      }
      if (snap.kind == BkSnapKind.statement) {
        // 一串最前面的那个位置在帽子 / 口的凸起上；别的都在上一块的凸起上。
        final c = snap.anchor + Offset(mt.notchX + mt.notchW / 2, mt.notchD / 2);
        if (visible.contains(c)) canvas.drawCircle(c, 2.2, dot);
      } else if (snap.rect.overlaps(visible)) {
        canvas.drawPath(bkSlotPath(snap.rect.inflate(1.5), mt, hex: snap.hex), ring);
      }
    }
  }

  void _dots(Canvas canvas, Size size, BkPalette palette) {
    final step = 24.0 * zoom;
    if (step < 8) return;
    final paint = Paint()..color = palette.canvasDot;
    final r = math.max(0.8, 1.1 * zoom);
    for (var y = pan.dy % step; y < size.height; y += step) {
      for (var x = pan.dx % step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(BkWorkspacePainter old) => true;
}
