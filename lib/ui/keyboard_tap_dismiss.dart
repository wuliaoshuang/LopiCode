// 设计约束（点输入框外面 → 收键盘 · 全应用一处）
// - 安卓上系统输入框默认“手指点到外面不失焦”（只有鼠标才失焦），所以键盘只能靠键盘上的收起键关。
//   这里在应用最外层把这条默认行为换掉，全应用所有系统输入框（TextField / TextFormField，含对话框、底部面板里的）一起生效，
//   各页面不用各写一遍。判断规则在 tap_outside.dart。
// - 规则：
//   · 在输入框外面**轻点**一下 → 失焦、收键盘。抬手时才收，不是按下就收：拖动、长按、双指捏合都不收。
//   · 点到按钮、列表项、链接：它照常响应，同时收键盘（表单页的“保存”、开关、列表行都是这样）。
//   · 点另一个输入框、输入框自己的清除 / 显示密码小图标、选择手柄、复制粘贴条：不收（它们本来就和输入框算一组）。
//   · “输入区”里的东西点了不收：聊天页 [KeyboardDock] 那条线以下的全部（排队条、附件条、候选列表、工具栏、发送）；
//     别的页面里要留住键盘的控件用 [KeyboardKeep] 包起来。
//   · 有 [KeyboardDock] 的页面（聊天）：手指拖动那条线以上的内容滚动时也收键盘；程序自己滚（流式输出滚到底）不收。
//     普通表单页拖动不收——要一边看着键盘一边翻下面的输入框。
// - 不归这里管的：终端（lib/terminal/terminal_input.dart 自己接键盘，点终端就是为了叫出键盘）、代码编辑器（re_editor 自己接键盘，
//   点编辑区是放光标）。它们不是系统输入框，这里的规则碰不到它们。
// - 鼠标、触控板按下就失焦（和系统原来的行为一样）。
// - 和 keyboard_dismiss.dart 不打架：这里只摘焦点；那边在失焦之后什么都不看，所以随后的键盘下降不会被再处理一遍。
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:lopicode/ui/tap_outside.dart';

/// 包在应用最外层（Navigator 外面）：点输入框外面的空白收键盘。全应用只放这一个。
class KeyboardTapDismiss extends StatefulWidget {
  const KeyboardTapDismiss({super.key, required this.child});
  final Widget child;

  @override
  State<KeyboardTapDismiss> createState() => _KeyboardTapDismissState();
}

class _KeyboardTapDismissState extends State<KeyboardTapDismiss> {
  final TapOutsideJudge _judge = TapOutsideJudge();
  final Set<_KeyboardDockState> _docks = {};

  /// 按下时拿着焦点的那个输入框：抬手时要摘的就是它。
  FocusNode? _node;

  late final Map<Type, Action<Intent>> _actions = {EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(onInvoke: _down)};

  @override
  void initState() {
    super.initState();
    // 抬起 / 取消自己从全局指针事件里看：输入框只会把“第一根抬起的手指”告诉我们，多指手势时会漏掉另一根。
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  /// 这个焦点所在的输入区上沿（屏幕坐标）；它不在任何输入区里就是 null。
  double? _dockLine(FocusNode node) {
    for (final dock in _docks) {
      final line = dock.lineFor(node);
      if (line != null) return line;
    }
    return null;
  }

  Object? _down(EditableTextTapOutsideIntent intent) {
    final event = intent.pointerDownEvent;
    switch (event.kind) {
      case PointerDeviceKind.touch:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        final line = _dockLine(intent.focusNode);
        _node = intent.focusNode;
        _judge.down(pointer: event.pointer, position: event.position, time: event.timeStamp, keep: line != null && event.position.dy >= line);
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
        intent.focusNode.unfocus();
    }
    return null;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerCancelEvent) {
      _judge.cancel(event.pointer);
    } else if (event is PointerUpEvent) {
      final node = _node;
      if (!_judge.up(pointer: event.pointer, position: event.position, time: event.timeStamp) || node == null) return;
      _node = null;
      // 按下之后焦点已经被别的事情挪走（比如这一下点开了一个面板）：不再管。
      if (node.hasPrimaryFocus) node.unfocus();
    }
  }

  /// 手指拖着聊天内容滚：收键盘。程序自己滚的（没有 dragDetails）不管。
  bool _onScroll(ScrollNotification n) {
    final drag = switch (n) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      OverscrollNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (drag == null) return false;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !node.hasPrimaryFocus) return false;
    final line = _dockLine(node);
    if (line == null) return false;
    // 滚的是输入区里面的东西（输入框自己的多行滚动、候选列表、附件条）：不收。
    final box = n.context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    if (box.localToGlobal(Offset.zero).dy >= line - 0.5) return false;
    node.unfocus();
    return false;
  }

  @override
  Widget build(BuildContext context) => _KeyboardTapScope(
    state: this,
    child: Actions(
      actions: _actions,
      child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
    ),
  );
}

class _KeyboardTapScope extends InheritedWidget {
  const _KeyboardTapScope({required this.state, required super.child});
  final _KeyboardTapDismissState state;

  @override
  bool updateShouldNotify(_KeyboardTapScope old) => !identical(old.state, state);
}

/// “输入区从这里开始”的一条线：放在一列（Column）里，夹在内容和贴底输入区之间。它自己不占地方、不画东西。
///
/// 输入框在这条线以下、并且和它在同一列里时：
/// - 点这条线以下的任何东西都不收键盘（工具栏、发送、附件条、排队条、候选列表）；
/// - 手指拖动这条线以上的内容滚动时收键盘。
class KeyboardDock extends StatefulWidget {
  const KeyboardDock({super.key});

  @override
  State<KeyboardDock> createState() => _KeyboardDockState();
}

class _KeyboardDockState extends State<KeyboardDock> {
  _KeyboardTapDismissState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context.dependOnInheritedWidgetOfExactType<_KeyboardTapScope>()?.state;
    if (identical(host, _host)) return;
    _host?._docks.remove(this);
    _host = host;
    host?._docks.add(this);
  }

  @override
  void dispose() {
    _host?._docks.remove(this);
    super.dispose();
  }

  /// [node] 是这条线管着的输入框（同一列里、在线以下）就返回线的位置（屏幕坐标），否则 null。
  double? lineFor(FocusNode node) {
    if (!mounted) return null;
    final box = context.findRenderObject();
    final field = node.context;
    if (box is! RenderBox || !box.attached || !box.hasSize || field == null) return null;
    Element? column;
    context.visitAncestorElements((e) {
      column = e;
      return false;
    });
    var sameColumn = false;
    field.visitAncestorElements((e) {
      sameColumn = identical(e, column);
      return !sameColumn;
    });
    if (!sameColumn) return null;
    final fieldBox = field.findRenderObject();
    if (fieldBox is! RenderBox || !fieldBox.attached || !fieldBox.hasSize) return null;
    final line = box.localToGlobal(Offset.zero).dy;
    return fieldBox.localToGlobal(Offset.zero).dy >= line - 0.5 ? line : null;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 把“点了也要留住键盘”的控件包起来（输入框旁边帮着输入的按钮：插入符号、格式工具条之类）。
/// 包住的范围和输入框算一组，点它不收键盘。
class KeyboardKeep extends StatelessWidget {
  const KeyboardKeep({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(child: child);
}
