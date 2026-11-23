import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

/// 软键盘的两种输入方式。
enum TerminalImeMode {
  /// 直接输入：每按一个键立刻进终端（敲命令用）。键盘类型用“可见密码”，
  /// 绝大多数输入法在这种输入框里不做联想、不攒字。
  direct,

  /// 中文输入：允许输入法先攒拼音、选好字再上屏。
  chinese,
}

/// 把输入法送来的“编辑框内容”翻译成终端要的按键。纯逻辑，方便单测。
///
/// 背景：xterm 自带的输入处理在输入法“攒字”（预编辑）期间什么都不往终端里写，只把攒着的字
/// 画在光标格子上、再把实心光标盖在第一个字上面——看起来就是“字被光标挡住、光标不动、
/// 回车也没反应”。很多国产输入法连英文字母都会先攒着，于是命令根本没进终端。
///
/// 这里的做法：
/// - 直接输入模式下，攒着的内容如果全是普通英文字符，就边攒边写进终端（之后输入法改了主意，
///   用退格把差的部分改回来）；
/// - 其余情况（中文拼音选字）攒着的字不写进终端，由界面画在光标后面，选定了再一次写入；
/// - 输入法“提交”的文字立刻写进终端；回车统一发 \r。
class ImeTranslator {
  ImeTranslator({required this.onText, required this.onBackspace, required this.onEnter});

  final void Function(String text) onText;
  final void Function() onBackspace;
  final void Function() onEnter;

  TerminalImeMode mode = TerminalImeMode.direct;

  /// 编辑框里垫两个空格：输入法按退格时内容变短，才知道用户按了退格。
  static const String sentinel = '  ';
  static const TextEditingValue idle = TextEditingValue(text: sentinel, selection: TextSelection.collapsed(offset: 2));

  /// 已经提前写进终端、但输入法还没“提交”的那段字。
  String _eager = '';

  /// 攒着、还没写进终端的字（界面画在光标后面）；没有就是空串。
  String pending = '';

  static bool _plainAscii(String text) => text.isNotEmpty && text.codeUnits.every((c) => c >= 0x20 && c < 0x7f);

  /// 把终端里已经有的 [_eager] 改成 [target]：退掉不一样的尾巴，补上新的。
  void _syncEager(String target) {
    var common = 0;
    while (common < _eager.length && common < target.length && _eager.codeUnitAt(common) == target.codeUnitAt(common)) {
      common++;
    }
    for (var i = _eager.runes.length - _eager.substring(0, common).runes.length; i > 0; i--) {
      onBackspace();
    }
    final rest = target.substring(common);
    if (rest.isNotEmpty) _emit(rest);
  }

  void _emit(String text) {
    // 输入法可能把回车当成普通字符塞进来。
    final parts = text.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) onText(parts[i]);
      if (i < parts.length - 1) onEnter();
    }
  }

  /// 输入法每次改动编辑框都会调到这里。返回 true 表示编辑框该重置回 [idle]。
  bool update(TextEditingValue value) {
    final text = value.text;
    if (!value.composing.isCollapsed && value.composing.isValid && value.composing.end <= text.length) {
      final composing = value.composing.textInside(text);
      if (mode == TerminalImeMode.direct && _plainAscii(composing)) {
        _syncEager(composing);
        _eager = composing;
        pending = '';
      } else {
        // 之前提前写进去的英文，输入法现在要换成别的（比如切成了中文）：先退掉。
        if (_eager.isNotEmpty) {
          _syncEager('');
          _eager = '';
        }
        pending = composing;
      }
      return false;
    }
    pending = '';
    if (text.length < sentinel.length) {
      // 垫的空格被删了：用户按了退格。
      if (_eager.isNotEmpty) {
        _syncEager('');
        _eager = '';
      }
      for (var i = sentinel.length - text.length; i > 0; i--) {
        onBackspace();
      }
      return true;
    }
    final committed = text.startsWith(sentinel) ? text.substring(sentinel.length) : text.trimLeft();
    if (_eager.isNotEmpty) {
      _syncEager(committed);
      _eager = '';
    } else if (committed.isNotEmpty) {
      _emit(committed);
    }
    return text != sentinel;
  }

  /// 输入法的“完成 / 换行 / 发送”键。
  void action() {
    _eager = '';
    pending = '';
    onEnter();
  }

  /// 输入连接断开（收起键盘、切走）：攒着的东西作废。
  void reset() {
    _eager = '';
    pending = '';
  }
}

/// 终端画面 + 我们自己的软键盘输入处理。
///
/// xterm 的 [TerminalView] 只负责画和处理实体键盘；软键盘 / 输入法这条路由这里接管
/// （原因见 [ImeTranslator]）。
class TerminalInputView extends StatefulWidget {
  const TerminalInputView({
    super.key,
    required this.session,
    required this.focusNode,
    required this.theme,
    required this.textStyle,
    required this.padding,
    this.mode = TerminalImeMode.direct,
  });

  final TerminalSession session;
  final FocusNode focusNode;
  final TerminalTheme theme;
  final TerminalStyle textStyle;
  final EdgeInsets padding;
  final TerminalImeMode mode;

  @override
  State<TerminalInputView> createState() => TerminalInputViewState();
}

class TerminalInputViewState extends State<TerminalInputView> with TextInputClient {
  final _viewKey = GlobalKey<TerminalViewState>();
  TextInputConnection? _connection;
  Offset? _downAt;
  Duration _downTime = Duration.zero;
  TextEditingValue _value = ImeTranslator.idle;
  late final ImeTranslator _ime = ImeTranslator(
    onText: (text) => widget.session.sendText(text),
    onBackspace: () => widget.session.sendKey(TerminalKey.backspace),
    onEnter: () => widget.session.sendKey(TerminalKey.enter),
  )..mode = widget.mode;

  bool get hasInputConnection => _connection?.attached ?? false;

  /// 攒着还没上屏的字（测试用）。
  String get pendingText => _ime.pending;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(TerminalInputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (old.mode != widget.mode) {
      _ime
        ..mode = widget.mode
        ..reset();
      // 键盘类型变了，要重新接一次输入法才生效。
      final wasOpen = hasInputConnection;
      _close();
      if (wasOpen && widget.focusNode.hasFocus) _open();
    }
    if (!identical(old.session, widget.session)) {
      _ime.reset();
      if (hasInputConnection) _connection!.setEditingState(_value = ImeTranslator.idle);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _close();
    super.dispose();
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _open();
    } else {
      _close();
    }
    if (mounted) setState(() {});
  }

  /// 点屏幕：拿焦点并弹出键盘（已经有焦点但键盘被收起来了，也要再弹出来）。
  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _open();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void _open() {
    if (hasInputConnection) {
      _connection!.show();
      return;
    }
    final direct = widget.mode == TerminalImeMode.direct;
    _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: direct ? TextInputType.visiblePassword : TextInputType.text,
        inputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: !direct,
        enableIMEPersonalizedLearning: false,
        keyboardAppearance: Theme.of(context).brightness,
      ),
    );
    _connection!
      ..show()
      ..setEditingState(_value = ImeTranslator.idle);
    _reportCaret();
  }

  void _close() {
    if (hasInputConnection) _connection!.close();
    _connection = null;
    _ime.reset();
    _value = ImeTranslator.idle;
  }

  /// 光标格子在这个组件里的位置；终端还没排过版时返回 null。
  Rect? _cursorRect() {
    final view = _viewKey.currentState;
    final box = context.findRenderObject();
    if (view == null || box is! RenderBox || !box.hasSize) return null;
    try {
      final global = view.globalCursorRect;
      return box.globalToLocal(global.topLeft) & global.size;
    } catch (_) {
      return null;
    }
  }

  /// 告诉输入法光标在哪，候选字窗口才会跟着光标走。
  void _reportCaret() {
    if (!hasInputConnection) return;
    final box = context.findRenderObject();
    final rect = _cursorRect();
    if (box is! RenderBox || !box.hasSize || rect == null) return;
    _connection!
      ..setEditableSizeAndTransform(box.size, box.getTransformTo(null))
      ..setCaretRect(rect);
  }

  // ── TextInputClient ──────────────────────────────────
  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    final before = _ime.pending;
    final shouldReset = _ime.update(value);
    if (shouldReset && hasInputConnection) {
      _connection!.setEditingState(_value = ImeTranslator.idle);
    }
    if (before != _ime.pending && mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportCaret();
    });
  }

  @override
  void performAction(TextInputAction action) {
    _ime.action();
    if (hasInputConnection) _connection!.setEditingState(_value = ImeTranslator.idle);
    if (mounted) setState(() {});
  }

  @override
  void connectionClosed() {
    _connection = null;
    _ime.reset();
    _value = ImeTranslator.idle;
    if (mounted) setState(() {});
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void insertTextPlaceholder(Size size) {}
  @override
  void removeTextPlaceholder() {}
  @override
  void showToolbar() {}

  @override
  Widget build(BuildContext context) {
    final pending = _ime.pending;
    final rect = pending.isEmpty ? null : _cursorRect();
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            // xterm 4.0.0 的 TerminalView.onTapUp 实际上从不触发（它的手势层只回调 onSingleTapUp），
            // 所以“点一下弹键盘”自己用指针事件判断：按下和抬起几乎在同一点、时间很短，就算一次点按。
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                _downAt = event.position;
                _downTime = event.timeStamp;
              },
              onPointerUp: (event) {
                final at = _downAt;
                _downAt = null;
                if (at == null) return;
                final moved = (event.position - at).distance;
                final held = event.timeStamp - _downTime;
                if (moved <= kTouchSlop && held < kLongPressTimeout) requestKeyboard();
              },
              onPointerCancel: (_) => _downAt = null,
              child: TerminalView(
                widget.session.terminal,
                key: _viewKey,
                focusNode: widget.focusNode,
                theme: widget.theme,
                textStyle: widget.textStyle,
                padding: widget.padding,
                // 软键盘由我们自己接；xterm 只管实体键盘和画面。
                hardwareKeyboardOnly: true,
              ),
            ),
          ),
          if (rect != null)
            Positioned(
              key: const Key('terminal-composing'),
              top: rect.top,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _ComposingLine(
                  text: pending,
                  start: rect.left,
                  cell: rect.size,
                  maxWidth: constraints.maxWidth,
                  style: widget.textStyle.toTextStyle(color: widget.theme.foreground),
                  background: widget.theme.background,
                  cursor: widget.theme.cursor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 攒着的字：从光标格子开始画，带下划线；实心光标画在这段字的后面。
/// 一行放不下时整段往左挪，保证光标始终看得见。
class _ComposingLine extends StatelessWidget {
  const _ComposingLine({
    required this.text,
    required this.start,
    required this.cell,
    required this.maxWidth,
    required this.style,
    required this.background,
    required this.cursor,
  });
  final String text;
  final double start;
  final Size cell;
  final double maxWidth;
  final TextStyle style;
  final Color background;
  final Color cursor;

  @override
  Widget build(BuildContext context) {
    final textStyle = style.copyWith(decoration: TextDecoration.underline, height: null);
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final needed = painter.width + cell.width;
    painter.dispose();
    final left = (start + needed > maxWidth ? maxWidth - needed : start).clamp(0.0, double.infinity);
    return Padding(
      padding: EdgeInsets.only(left: left),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ColoredBox(
              color: background,
              child: SizedBox(
                height: cell.height,
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(text, key: const Key('terminal-composing-text'), maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: textStyle),
                ),
              ),
            ),
          ),
          Container(key: const Key('terminal-composing-cursor'), width: cell.width, height: cell.height, color: cursor),
        ],
      ),
    );
  }
}
