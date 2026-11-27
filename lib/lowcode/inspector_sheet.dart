// 设计约束（低代码 · 合一面板：常用 / 样式 / 事件 · 390×844，浅色 + 深色）
// - 旧的“属性”面板和“样式”面板合成这一张。选中条上的“常用 / 样式 / 逻辑”三个入口打开的是它的三页。
// - 内容主次：① 组件名（一行，告诉她在改谁）→ ② 三页的切换（等宽三段，不横滑）→ ③ 这一页的内容（主角）。
//   “样式”页多一行九个分组的标签（可横滑，改过的带小圆点）；标题右边多“CSS”“重置”两个次要操作。
// - 唯一主操作：没有。改了就生效，画布跟着变，靠撤销反悔；所以没有“保存”按钮。
// - 在搭建页里它是**不挡画布的**（贴在底部、默认约 60% 高、可拖到 92%；往下拖到底或点“×”收起）：
//   上面露着的画布照样能点——点另一个组件，面板跟着换成它，不用关了再开（“选中 → 点档”两步改完）。
//   单独弹出来用（showStyleEditor）时是普通的底部弹层。
// - 撤销记录的合并：打字、点加减、拖滑块算连续操作，停 400ms（或换了组件 / 关面板 / 做了别的操作）才提交一次；
//   点档、按钮组、开关、取色、应用 CSS、重置是一下一条。
// - 取用的 tokens：Space.x1–x4、Radii.lg（面板上沿圆角）、Radii.sm（分段）、accentSoft / accent（选中的那一段）、
//   surfaceMuted（分段的底）、textMuted（次要操作）、border（分隔线）。
import 'dart:async';
import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_editing.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/inspector_bp_widgets.dart';
import 'package:lopicode/lowcode/inspector_bp_write.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_events_widgets.dart';
import 'package:lopicode/lowcode/inspector_header_widgets.dart';
import 'package:lopicode/lowcode/inspector_state_widgets.dart';
import 'package:lopicode/lowcode/inspector_style_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/states_bp.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_css_sheet.dart';
import 'package:lopicode/lowcode/style_groups_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/inspector_header_widgets.dart' show InspectorPage;

/// 连续操作（打字、加减、拖动）停多久算“告一段落”、提交成一条撤销记录。
const Duration kStyleCommitDelay = Duration(milliseconds: 400);

/// 合一面板的三页。
/// 面板刚打开时占多高（占它能用的高度的几成）。
const double kInspectorInitialSize = 0.5;

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    super.key,
    required this.doc,
    required this.nodeId,
    required this.onEdit,
    this.initialPage = InspectorPage.common,
    this.modal = false,
    this.onClose,
    this.pickImage,
    this.onOpenLogic,
    this.onAddLogic,
    this.onState,
    this.bp,
  });
  final LcDocument doc;
  final String nodeId;
  final LcEdit onEdit;
  final InspectorPage initialPage;

  /// true＝在底部弹层里（自己垫键盘的高度）；false＝贴在搭建台底部、不挡画布。
  final bool modal;

  /// 收起（不挡画布时用：点“×”或往下拖到底）。
  final VoidCallback? onClose;
  final Future<String?> Function(String from)? pickImage;

  /// 去积木编辑器看这个组件的逻辑；不给＝没有“事件”页（自定义组件里的控件不支持逻辑）。
  final void Function(String nodeId)? onOpenLogic;

  /// 给这个组件的某个事件加逻辑（建好帽子再跳过去）。
  final void Function(String nodeId, String event)? onAddLogic;

  /// “样式”页顶上选了哪个状态（null＝平时）：搭建台拿它让画布照这个状态画选中的组件。
  final ValueChanged<String?>? onState;

  /// 画布现在看的是哪一档屏宽（null＝手机）：不是手机时，“样式”页改的只记成那一档的差别。
  final String? bp;

  @override
  State<InspectorPanel> createState() => InspectorPanelState();
}

class InspectorPanelState extends State<InspectorPanel> {
  /// 最近一次见到的文档：打开时是传进来的那份，之后每次提交换成搭建页在回调里给的那份
  /// （撤销 / 重做之后搭建页手里的文档对象可能已经换了）。
  late LcDocument _doc = widget.doc;

  /// 面板显示用的：组件自己的属性和 style，加上还没提交的改动。
  Map<String, dynamic> _props = {};
  Map<String, String> _style = {};

  /// 节点上别的字段（状态样式在这里面）的显示用副本。
  Map<String, dynamic> _more = {};

  /// “样式”页现在改的是哪个状态的样子；null＝平时。
  String? _state;

  /// 还没提交的改动。提交时在搭建页给的节点上按顺序重放一遍，而不是拿显示用的那份整个盖过去——
  /// 这样即使节点在别处变过，也只动用户碰过的那几项。
  final List<void Function(LcNode n, LcNode? parent)> _pending = [];
  Timer? _timer;
  final DraggableScrollableController _sheet = DraggableScrollableController();
  bool _keyboardUp = false;
  ScrollController? _scroll;
  late InspectorPage _page = widget.initialPage;
  StyleTab _tab = StyleTab.size;

  /// 上次“应用 CSS”时没收下的条目。
  List<String> _dropped = const [];

  static const double _maxSize = 0.92;
  static const double _minSize = 0.22;

  LcNode? get _node => _doc.find(widget.nodeId);
  bool get _hasEvents => widget.onOpenLogic != null;

  /// 页面上能绑；“编辑组件”页里也能（第四轮 B2：挑的是组件的属性和组件自己的状态）。
  bool get _canBind => _hasEvents || _doc.root.id == kComponentEditRootId;

  /// 换到某一页（选中条上的三个入口用）。
  void showPage(InspectorPage page) {
    if (page == InspectorPage.events && !_hasEvents) return;
    _jumpTop();
    setState(() => _page = page);
  }

  InspectorPage get page => _page;

  @override
  void initState() {
    super.initState();
    if (_page == InspectorPage.events && !_hasEvents) _page = InspectorPage.common;
    _reload();
  }

  @override
  void didUpdateWidget(InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      // 换了组件：没提交的先交给原来那个（现在正在搭界面，不能马上去动搭建页，等这一帧画完）。
      _timer?.cancel();
      _timer = null;
      if (_pending.isNotEmpty) {
        final ops = List.of(_pending);
        _pending.clear();
        final id = oldWidget.nodeId;
        WidgetsBinding.instance.addPostFrameCallback((_) => _commit(id, ops));
      }
      _dropped = const [];
      _pickState(null, later: true);
    }
    _doc = widget.doc;
    if (_pending.isEmpty) _reload();
  }

  List<bool Function()>? _claims;
  bool _claimBack() => mounted;

  @override
  void dispose() {
    _claims?.remove(_claimBack);
    // 正常关闭走 flush()（弹层的 PopScope / 搭建页收起之前），这里只收定时器（销毁过程中不能再去动搭建页）。
    _timer?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在外壳里：告诉外壳“返回键这一下我接了”（收面板），别同时把人带回聊天页。
    final claims = widget.modal ? null : ShellScope.maybeOf(context)?.backClaims;
    if (!identical(claims, _claims)) {
      _claims?.remove(_claimBack);
      _claims = claims?..add(_claimBack);
    }
    // 键盘一弹出就把面板拉到最高：默认 60% 高时键盘会盖掉大半，剩下的地方连被编辑的那一行都放不下。
    final up = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (up && !_keyboardUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 不等：只是把面板拉高的动画，做不做完都不影响编辑。
        if (mounted && _sheet.isAttached && _sheet.size < _maxSize) unawaited(_sheet.animateTo(_maxSize, duration: const Duration(milliseconds: 180), curve: Curves.easeOut));
      });
    }
    _keyboardUp = up;
  }

  void _reload() {
    final n = _node;
    _props = n == null ? {} : (jsonDecode(jsonEncode(n.props)) as Map).cast<String, dynamic>();
    _style = n == null ? {} : Map.of(n.style);
    _more = n == null ? {} : (jsonDecode(jsonEncode(n.more)) as Map).cast<String, dynamic>();
  }

  LcNode _preview(LcNode node) => LcNode(id: node.id, type: node.type, props: _props, style: _style, more: _more);

  /// 换一个状态来改（null＝平时）。[later]＝现在正在搭界面，等这一帧画完再告诉搭建台。
  void _pickState(String? state, {bool later = false}) {
    if (_state == state) return;
    _state = state;
    final tell = widget.onState;
    if (tell == null) return;
    if (later) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tell(state));
    } else {
      tell(state);
    }
  }

  /// 改某个状态下的样式：改完的那份整个写回 `states[状态]`（只有和平时不一样的那几条）。
  void _applyState(String state, void Function(LcStyle s) change, {bool merge = false}) => _apply((n, _) {
    final decl = Map<String, String>.of(lcStateStyle(n, state));
    change(LcStyle(decl));
    lcReplaceState(n, state, decl);
  }, merge: merge);

  void _apply(void Function(LcNode n, LcNode? parent) change, {bool merge = false}) {
    final node = _node;
    if (node == null) {
      // 组件已经不在了（被删 / 被撤销）：不改，重画成“不在了”。
      setState(() {});
      return;
    }
    setState(() {
      change(_preview(node), _doc.parentOf(node.id));
      _pending.add(change);
    });
    _timer?.cancel();
    if (merge) {
      _timer = Timer(kStyleCommitDelay, flush);
    } else {
      flush();
    }
  }

  void _applyStyle(void Function(LcStyle s) change, {bool merge = false}) => _apply((n, _) => change(LcStyle(n.style)), merge: merge);

  void _commit(String id, List<void Function(LcNode n, LcNode? parent)> ops) => widget.onEdit((d) {
    _doc = d;
    final n = d.find(id);
    if (n == null) return;
    final parent = d.parentOf(id);
    for (final op in ops) {
      op(n, parent);
    }
  });

  /// 把攒着的改动一次交给搭建页（一条撤销记录），然后按搭建页手里的文档重新读显示值。
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final ops = List.of(_pending);
    _pending.clear();
    _commit(widget.nodeId, ops);
    if (mounted) setState(_reload);
  }

  Future<void> _openCss(LcNode node) async {
    flush();
    final css = await showStyleCssEditor(context, initialCss: LcStyle(_style).toCss(), legacy: legacyStyle(node, _doc.parentOf(node.id)));
    if (css == null || !mounted) return;
    final parsed = parseCss(css);
    _applyStyle(
      (s) => s.map
        ..clear()
        ..addAll(parsed.declarations),
    );
    setState(() => _dropped = parsed.dropped);
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(context, title: '重置样式？', message: '会清掉这个组件在“样式”页里设的全部内容（包括自定义 CSS）。“常用”页里设的不受影响。清掉之后可以撤销。', confirmLabel: '重置', danger: true);
    if (!ok || !mounted) return;
    _applyStyle((s) => s.map.clear());
    setState(() => _dropped = const []);
  }

  void _jumpTop() {
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients && scroll.offset > 0) scroll.jumpTo(0);
  }

  /// 改整份文档（快捷操作、同步导航栏）：先把面板里还没提交的改动交掉，改完重新读这个组件。
  void _editDoc(void Function(LcDocument d) change) {
    flush();
    widget.onEdit((d) => change(_doc = d));
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    final sheet = DraggableScrollableSheet(
      controller: _sheet,
      expand: false,
      initialChildSize: widget.modal ? 0.6 : kInspectorInitialSize,
      minChildSize: widget.modal ? 0.35 : _minSize,
      maxChildSize: _maxSize,
      builder: (context, scroll) => node == null ? _gone(context, scroll) : _body(context, scroll, node),
    );
    if (widget.modal) {
      return PopScope(
        // 面板怎么关的都算（下滑、点外面、返回键）：关之前把没提交的交出去。
        onPopInvokedWithResult: (_, _) => flush(),
        // 键盘的高度垫在面板外面：滚动区到键盘上沿为止，被编辑的那一行才会被滚到看得见的地方。
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: sheet,
        ),
      );
    }
    final c = context.colors;
    return PopScope(
      // 返回键先收面板，不直接退出搭建页。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          // 往下拖到底＝收起。
          if (n.extent <= _minSize + 0.01) WidgetsBinding.instance.addPostFrameCallback((_) => _close());
          return false;
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            key: const Key('lc-inspector'),
            color: c.surface,
            elevation: 12,
            shadowColor: c.shadowOf(0x61 / 255),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg))),
            clipBehavior: Clip.antiAlias,
            child: sheet,
          ),
        ),
      ),
    );
  }

  void _close() {
    if (!mounted) return;
    flush();
    widget.onClose?.call();
  }

  Widget _gone(BuildContext context, ScrollController scroll) => SingleChildScrollView(
    controller: scroll,
    child: SizedBox(
      height: 280,
      child: EmptyState(
        icon: Icons.layers_clear_outlined,
        title: '这个组件已经不在了',
        message: '它被删掉或者被撤销掉了，没有可以改的东西。',
        action: FilledButton(key: const Key('lc-style-close'), onPressed: () => widget.modal ? Navigator.pop(context) : _close(), child: const Text('关闭')),
      ),
    ),
  );

  Widget _body(BuildContext context, ScrollController scroll, LcNode node) {
    // 用“节点 + 预览中的属性和 style”算最终样式：面板显示的和提交后画布上的是同一套规矩。
    final preview = _preview(node);
    final parent = _doc.parentOf(node.id);
    _scroll = scroll;
    final state = _state;
    final parentStyle = parent == null ? null : resolvedStyle(lcViewNode(parent, LcViewEnv.of(_doc, widget.bp)), _doc.parentOf(parent.id));
    final parentColumns = parentStyle != null && lcIsGrid(parentStyle) ? lcGridColumns(parentStyle) : null;
    final bp = widget.bp;
    // 三种状态的样子能分屏宽设（states_bp.dart）：在平板 / 桌面档上改的只记成这一档的差别。
    final stateBp = lcStateSplitsByBp(state) ? bp : null;
    final stateOwn = state == null ? const <String, String>{} : (stateBp == null ? lcStateStyle(preview, state) : canonicalDeclarations(lcBpStateStyle(preview, stateBp, state)));
    // 这一档看到的样子（手机的 + 更窄各档的 + 这一档的差别）；变量不换成值，控件上才看得出“这是变量”。
    final seen = bp == null ? preview : lcViewNode(preview, LcViewEnv(bp: bp));
    final bpOwn = bp == null ? const <String, String>{} : canonicalDeclarations(lcBpStyle(preview, bp));
    final bpNote = bp == null
        ? null
        : LcBpNote(
            bp: bp,
            onStylePage: _page == InspectorPage.style,
            filled: bpOwn.isNotEmpty,
            stateLabel: state == null ? null : lcStateLabel(state),
            stateSplit: stateBp != null,
            stateFilled: state != null && lcStateStyleAt(preview, state, bp).isNotEmpty,
            onClearState: () => _apply((n, _) => stateBp == null ? lcReplaceState(n, state!, const {}) : lcReplaceBpState(n, stateBp, state!, const {})),
            onClear: () => _apply((n, _) => lcReplaceBp(n, bp, const {})),
          );
    final Widget content = switch (_page) {
      InspectorPage.common => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?bpNote,
          LcBpRowScope(
            bp: bp,
            child: InspectorCommonPage(
              key: ValueKey('common-${node.id}'),
              // 平板 / 桌面档：看到的是这一档的样子，样子类的改动只记这一档（inspector_bp_write.dart）。
              ed: bp == null
                  ? InspectorEdit(doc: _doc, node: preview, parent: parent, apply: _apply, pickImage: widget.pickImage, editDoc: _editDoc, canBind: _canBind)
                  : InspectorEdit(
                      doc: _doc,
                      node: seen,
                      parent: parent,
                      apply: (change, {merge = false}) => _apply((n, p) => lcApplyCommonAtBp(n, p, bp, change), merge: merge),
                      pickImage: widget.pickImage,
                      editDoc: _editDoc,
                      canBind: _canBind,
                      bp: bp,
                    ),
            ),
          ),
        ],
      ),
      InspectorPage.style => InspectorStylePage(
        key: ValueKey('style-${node.id}'),
        ed: state != null
            ? StyleEdit(
                node: node,
                own: stateOwn,
                resolved: {...resolvedStyle(seen, parent), ...lcStateStyleAt(preview, state, stateBp)},
                apply: (change, {merge = false}) =>
                    stateBp == null ? _applyState(state, change, merge: merge) : _apply((n, _) => lcEditStateAtBp(n, stateBp, state, (m) => change(LcStyle(m))), merge: merge),
                inheritedHint: stateBp == null ? null : '跟手机一样',
                parentColumns: parentColumns,
              )
            : bp != null
            ? StyleEdit(
                node: node,
                own: bpOwn,
                resolved: resolvedStyle(seen, parent),
                apply: (change, {merge = false}) => _apply((n, _) => lcEditAtBp(n, bp, (m) => change(LcStyle(m))), merge: merge),
                parentColumns: parentColumns,
                inheritedHint: '跟手机一样',
              )
            : StyleEdit(node: node, own: _style, resolved: resolvedStyle(preview, parent), apply: _applyStyle, parentColumns: parentColumns),
        tab: _tab,
        dropped: _dropped,
        onDismissDropped: () => setState(() => _dropped = const []),
        top: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选了状态：屏宽、状态并成一条，放到状态那一行下面（LcStateBar 的 note）
            if (state == null) ?bpNote,
            LcStateBar(
              note: state == null ? null : bpNote,
              state: state,
              filled: {
                for (final s in [...kLcStateNames, for (final k in lcClassIfOf(preview)) lcClassState(k.name)])
                  if (lcStateStyleAt(preview, s, bp).isNotEmpty) s,
              },
              classes: [for (final k in lcClassIfOf(preview)) k.name],
              onPick: (s) => setState(() => _pickState(s)),
              onClear: () => _apply((n, _) => stateBp == null ? lcReplaceState(n, state!, const {}) : lcReplaceBpState(n, stateBp, state!, const {})),
              caveat: lcStateCaveat(preview.type, state),
            ),
          ],
        ),
      ),
      InspectorPage.events => InspectorEventsPage(
        key: ValueKey('events-${node.id}'),
        doc: _doc,
        node: node,
        onEdit: _editDoc,
        onOpen: () {
          flush();
          widget.onOpenLogic?.call(node.id);
        },
        onAdd: (event) {
          flush();
          widget.onAddLogic?.call(node.id, event);
        },
      ),
    };
    return LcThemeScope(
      theme: lcThemeOf(_doc),
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          PinnedHeaderSliver(child: _header(context, node)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x6),
            // 不用懒加载的列表：内容就这么几行，一次排好，滚动位置和“滚到被编辑的那一行”都更稳。
            sliver: SliverToBoxAdapter(child: content),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, LcNode node) => InspectorHeader(
    title: '${node.type == 'component' ? componentLabel(_doc, node) : node.spec.label}${widget.modal ? ' 样式' : ''}',
    modal: widget.modal,
    page: _page,
    pages: [
      for (final p in InspectorPage.values)
        if (p != InspectorPage.events || _hasEvents) p,
    ],
    onPage: showPage,
    // “CSS”“重置”改的是手机（默认）那份：画布切到别的屏宽时收起来，免得以为改的是这一档。
    onCss: _page == InspectorPage.style && widget.bp == null ? () => _openCss(node) : null,
    onReset: _style.isEmpty ? null : _reset,
    onClose: _close,
    strip: _page != InspectorPage.style
        ? null
        : StyleTabStrip(
            tab: _tab,
            own: widget.bp == null ? _style : canonicalDeclarations(lcBpStyle(_preview(node), widget.bp!)),
            onSelect: (tab) {
              _jumpTop();
              setState(() => _tab = tab);
            },
          ),
  );
}
