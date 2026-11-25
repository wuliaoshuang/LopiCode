// 设计约束（聊天输入栏 · 390×844）
// - 输入区常驻底部。没点进去且没有字：收成一行胶囊（附件、提示、用量小环、发送）。
//   胶囊连边框高 48（字体特别大时跟着长高）；发送圆钮看着是 36，但 ＋、用量小环、发送每个可点区域都不小于 44×44。
// - 点进去或有草稿：展开成两行，上方多行输入，下方工具栏放附件、权限、模型、用量小环和发送。
// - 语音输入暂时隐藏（2026-11-25 霜霜定）：开关是 kChatVoiceEnabled，默认关，设置页里没有入口。关着的时候两种排法里都没有麦克风，
//   位置由旁边的控件自然补上；不创建语音识别、不申请麦克风权限。代码留着，打开开关就回到原样（麦克风排在发送左边）。
// - 在输入框里打 @：输入栏正上方出现工作区文件候选（界面在 file_mention.dart，规则在 session/file_mentions.dart）。
// - 软键盘被用户收起（系统手势 / 返回键）时输入框跟着失焦：键盘一开始往下走就摘，不等它降完。没草稿收回胶囊，有草稿保持展开。
//   判断规则在 keyboard_dismiss.dart；只看这块屏幕自己的键盘高度，不依赖输入栏外面怎么摆。语音输入不会因此被打断。
// - 长按发送仍可选排队、插话或中断。
// - （开关打开时）语音识别把实时结果接进草稿，不覆盖已有文字；不可用时给出明确原因。
import 'dart:async';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_mention.dart';
import 'package:lopicode/ui/keyboard_dismiss.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音输入的入口要不要露出来。暂时隐藏（2026-11-25）；这是内部开关，设置页里没有。
const bool kChatVoiceEnabled = false;

abstract interface class ChatVoiceInput {
  bool get isListening;
  Future<bool> initialize();
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError});
  Future<void> stop();
  void dispose();
}

final _deviceVoiceInput = _DeviceVoiceInput();

class _DeviceVoiceInput implements ChatVoiceInput {
  final _speech = SpeechToText();
  void Function(String)? _onResult;
  void Function(bool)? _onListeningChanged;
  void Function(String)? _onError;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() => _speech.initialize(
    onStatus: (status) {
      if (status == SpeechToText.listeningStatus) _onListeningChanged?.call(true);
      if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) _onListeningChanged?.call(false);
    },
    onError: (error) => _onError?.call(_messageFor(error)),
  );

  @override
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError}) async {
    _onResult = onResult;
    _onListeningChanged = onListeningChanged;
    _onError = onError;
    await _speech.listen(
      onResult: (result) => _onResult?.call(result.recognizedWords),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation, listenFor: const Duration(seconds: 60)),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  void dispose() {
    _onResult = null;
    _onListeningChanged = null;
    _onError = null;
    unawaited(_speech.cancel());
  }

  String _messageFor(SpeechRecognitionError error) {
    final code = error.errorMsg;
    if (code.contains('permission')) return '没有麦克风或语音识别权限，请到系统设置里开启。';
    if (code.contains('network') || code.contains('unavailable')) return '语音服务暂时不可用，请稍后重试或改用键盘输入。';
    if (code.contains('audio') || code.contains('busy')) return '麦克风正被占用，请先关闭其他录音功能。';
    if (code.contains('no_match')) return '没听清，请再说一次。';
    return '语音识别失败，请重试或改用键盘输入。';
  }
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.canSend,
    required this.modelName,
    required this.permission,
    required this.onPlus,
    required this.onModel,
    required this.onPermission,
    required this.onSend,
    required this.onLongSend,
    required this.onStop,
    this.context_,
    this.onContext,
    this.voiceInput,
    this.showVoice = kChatVoiceEnabled,
    this.mentionGuard,
    this.mentionScanner,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool canSend;
  final String modelName;
  final PermissionLevel permission;
  final VoidCallback onPlus;
  final VoidCallback onModel;
  final VoidCallback onPermission;
  final VoidCallback onSend;
  final VoidCallback onLongSend;
  final VoidCallback onStop;
  final ContextUsage? context_;
  final VoidCallback? onContext;
  final ChatVoiceInput? voiceInput;

  /// 要不要显示麦克风。不显示时不创建语音识别，也就不会申请麦克风权限。
  final bool showVoice;

  /// 工作区的路径守卫：给了才有“打 @ 选文件”。
  final PathGuard? mentionGuard;
  final MentionScanner? mentionScanner;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

/// 收起态胶囊里一行的高度，也是每个可点目标的最小边长。连上下各 1 的内边距和边框，胶囊总高 48。
const double _kTarget = 44;

/// 发送圆钮看得见的直径（可点区域仍是 [_kTarget]）。
const double _kSendVisible = 36;

class _ChatComposerState extends State<ChatComposer> with WidgetsBindingObserver {
  late final ChatVoiceInput _voice = widget.voiceInput ?? _deviceVoiceInput;
  String _dictationBase = '';
  bool _startingVoice = false;
  bool _listening = false;
  bool _acceptingDictation = false;

  /// 收起和展开是两种排法，输入框靠这把钥匙在两边搬来搬去，焦点和光标不丢。
  final GlobalKey _fieldKey = GlobalKey();
  bool _wasCollapsed = true;

  /// 键盘被用户收起后把焦点摘掉（规则见 keyboard_dismiss.dart）。
  final KeyboardDismissTracker _keyboard = KeyboardDismissTracker();
  Timer? _keyboardCheck;

  @override
  void initState() {
    super.initState();
    _wasCollapsed = _collapsed;
    WidgetsBinding.instance.addObserver(this);
    widget.focusNode.addListener(_onInputChanged);
    widget.controller.addListener(_onInputChanged);
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onInputChanged);
      widget.focusNode.addListener(_onInputChanged);
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onInputChanged);
      widget.controller.addListener(_onInputChanged);
    }
  }

  /// 这块屏幕上软键盘的高度（逻辑像素）。
  /// 不读 MediaQuery：外面的 Scaffold 给键盘让位时会把它清零。
  double get _keyboardInset {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    _afterVerdict(_keyboard.onMetrics(inset: _keyboardInset, width: View.of(context).physicalSize.width, now: keyboardNow()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    _afterVerdict(_keyboard.onLifecycle(resumed: state == AppLifecycleState.resumed, now: keyboardNow()));
  }

  void _afterVerdict(KeyboardVerdict verdict) {
    if (verdict == KeyboardVerdict.none) return;
    _keyboardCheck?.cancel();
    // 只摘焦点，不碰语音输入；有草稿时展开状态由 _collapsed 自己决定。
    // 摘掉之后 _onInputChanged 会告诉 _keyboard“没焦点了”，键盘剩下的下降过程不会再被处理。
    if (verdict == KeyboardVerdict.dismissNow) {
      if (widget.focusNode.hasFocus) widget.focusNode.unfocus();
      return;
    }
    _keyboardCheck = Timer(verdict == KeyboardVerdict.checkSoon ? kKeyboardSettle : kKeyboardSettleSlow, () {
      if (!mounted) return;
      if (_keyboard.confirm(inset: _keyboardInset) && widget.focusNode.hasFocus) widget.focusNode.unfocus();
    });
  }

  /// 只在“收起 / 展开”真的变了的时候重画，打字时不跟着每个字重画。
  void _onInputChanged() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (!focused) _keyboardCheck?.cancel();
    _keyboard.onFocus(focused: focused, inset: _keyboardInset, now: keyboardNow());
    final now = _collapsed;
    if (now == _wasCollapsed) return;
    _wasCollapsed = now;
    setState(() {});
  }

  @override
  void dispose() {
    _keyboardCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_onInputChanged);
    widget.controller.removeListener(_onInputChanged);
    // 麦克风藏着的时候从没碰过语音识别：这里也不碰，免得为了“释放”反而把它建出来。
    if (widget.showVoice) _voice.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopVoice();
      return;
    }
    if (_startingVoice) return;
    widget.focusNode.unfocus();
    setState(() => _startingVoice = true);
    try {
      final available = await _voice.initialize();
      if (!mounted) return;
      if (!available) {
        setState(() => _startingVoice = false);
        showSnack(context, '这台设备暂时不能语音输入，请检查权限或改用键盘输入。');
        return;
      }
      _dictationBase = widget.controller.text;
      _acceptingDictation = true;
      await _voice.listen(
        onResult: _onVoiceWords,
        onListeningChanged: (active) {
          if (mounted) setState(() => _listening = active);
        },
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _startingVoice = false;
            _listening = false;
            _acceptingDictation = false;
          });
          showSnack(context, message);
        },
      );
      if (mounted && _voice.isListening) {
        setState(() {
          _startingVoice = false;
          _listening = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startingVoice = false;
        _acceptingDictation = false;
      });
      showSnack(context, '语音输入没能启动，请检查麦克风权限或改用键盘输入。');
    }
  }

  void _onVoiceWords(String words) {
    if (!mounted || !_acceptingDictation || words.isEmpty) return;
    final separator = _dictationBase.isEmpty || _dictationBase.endsWith(' ') || _dictationBase.endsWith('\n') ? '' : ' ';
    final text = '$_dictationBase$separator$words';
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _stopVoice() async {
    if (!_listening && !_startingVoice) return;
    setState(() {
      _listening = false;
      _startingVoice = false;
      _acceptingDictation = false;
    });
    await _voice.stop();
  }

  void _send() {
    if (_listening || _startingVoice) {
      unawaited(_stopVoice());
    }
    widget.onSend();
  }

  void _longSend() {
    if (_listening || _startingVoice) {
      unawaited(_stopVoice());
    }
    widget.onLongSend();
  }

  /// 收起＝没在输入、没有字、没在听写：只留一行胶囊（＋、提示、麦克风、发送）。
  /// 点进去或有内容时展开成两行，第二行放权限、模型。
  /// 用量小环两种状态都在：它是打开用量弹层的唯一入口，收起时藏掉就得先弹键盘才看得到。
  bool get _collapsed => !widget.focusNode.hasFocus && widget.controller.text.isEmpty && !_listening && !_startingVoice;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    const noBorder = OutlineInputBorder(borderSide: BorderSide.none);
    final collapsed = _collapsed;
    _wasCollapsed = collapsed;
    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      minLines: 1,
      maxLines: 5,
      style: t.bodyLarge,
      cursorColor: c.text,
      textInputAction: TextInputAction.newline,
      scrollPadding: const EdgeInsets.only(bottom: Space.x12),
      decoration: InputDecoration(
        hintText: widget.busy ? '接着说，或长按发送选择方式' : '描述你的任务…',
        hintStyle: t.bodyLarge?.copyWith(color: c.textFaint),
        hintMaxLines: 1,
        filled: false,
        isDense: true,
        // 收起时上下不留白：一行的高度由 44 的按钮撑着，字居中；字体行高再大胶囊也不跟着变高。
        contentPadding: EdgeInsets.symmetric(horizontal: Space.x1, vertical: collapsed ? 0 : Space.x2),
        border: noBorder,
        enabledBorder: noBorder,
        focusedBorder: noBorder,
      ),
    );
    final plus = _PlainAction(key: const ValueKey('plus-button'), tooltip: '附件与对话设置', icon: Icons.add, color: c.text, onPressed: widget.onPlus);
    final voice = _PlainAction(
      key: const ValueKey('voice-button'),
      tooltip: _listening ? '停止语音输入' : '语音输入',
      icon: _listening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
      color: _listening ? c.accent : c.text,
      onPressed: _startingVoice ? null : _toggleVoice,
      child: _startingVoice ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
    );
    final send = _SendAction(busy: widget.busy, canSend: widget.canSend, onSend: _send, onLongSend: _longSend, onStop: widget.onStop);
    // 小环自己高 44；宽度跟着百分比文字走，字很短时这里兜住不小于 44。
    final ring = widget.context_ != null && widget.onContext != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _kTarget),
            child: ContextRing(usage: widget.context_!, onTap: widget.onContext!),
          )
        : null;

    final Widget body;
    if (collapsed) {
      body = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kTarget),
        child: Row(
          children: [
            plus,
            Expanded(child: field),
            ?ring,
            if (widget.showVoice) voice,
            send,
          ],
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1, Space.x2, 0), child: field),
          const SizedBox(height: Space.x1),
          Row(
            children: [
              plus,
              _PlainAction(
                key: const ValueKey('permission-button'),
                tooltip: '权限：${widget.permission.label}',
                icon: widget.permission == PermissionLevel.full ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                color: widget.permission == PermissionLevel.full ? c.warning : c.textMuted,
                onPressed: widget.onPermission,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: TextButton(
                      key: const ValueKey('model-button'),
                      onPressed: widget.onModel,
                      style: TextButton.styleFrom(
                        foregroundColor: c.text,
                        minimumSize: const Size(0, _kTarget),
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                      ),
                      child: Text(
                        widget.modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(color: c.text),
                      ),
                    ),
                  ),
                ),
              ),
              ?ring,
              if (widget.showVoice) voice,
              send,
            ],
          ),
        ],
      );
    }

    final guard = widget.mentionGuard;
    final input = Container(
      key: const ValueKey('chat-input'),
      margin: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
      padding: collapsed ? const EdgeInsets.symmetric(horizontal: 2, vertical: 1) : const EdgeInsets.fromLTRB(Space.x1, Space.x2, Space.x1, Space.x1),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(collapsed ? 24 : 28),
        border: Border.all(color: c.border),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 140), curve: Curves.easeOut, alignment: Alignment.bottomCenter, child: body),
    );
    if (guard == null) return input;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FileMentionLayer(controller: widget.controller, focusNode: widget.focusNode, guard: guard, scanner: widget.mentionScanner),
        input,
      ],
    );
  }
}

class _PlainAction extends StatelessWidget {
  const _PlainAction({super.key, required this.tooltip, required this.icon, required this.onPressed, this.color, this.child});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _kTarget,
    height: _kTarget,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(Space.x2),
      constraints: const BoxConstraints.tightFor(width: _kTarget, height: _kTarget),
      icon: child ?? Icon(icon, size: 22, color: color),
    ),
  );
}

class _SendAction extends StatelessWidget {
  const _SendAction({required this.busy, required this.canSend, required this.onSend, required this.onLongSend, required this.onStop});

  final bool busy;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onLongSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stopping = busy && !canSend;
    final longPress = busy && canSend;
    final button = IconButton(
      key: const ValueKey('send-button'),
      tooltip: longPress
          ? null
          : stopping
          ? '停止'
          : '发送',
      onPressed: stopping
          ? onStop
          : canSend
          ? onSend
          : null,
      onLongPress: longPress ? onLongSend : null,
      style: IconButton.styleFrom(
        backgroundColor: stopping
            ? c.danger
            : canSend
            ? c.accentFill
            : c.surfaceMuted,
        foregroundColor: stopping || canSend ? c.onAccent : c.textFaint,
        disabledBackgroundColor: c.surfaceMuted,
        disabledForegroundColor: c.textFaint,
        minimumSize: const Size(_kSendVisible, _kSendVisible),
        fixedSize: const Size(_kSendVisible, _kSendVisible),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        // 圆钮看着是 36；padded 会在它外面包一圈 48 的点击区，落在这圈里的点击都算按钮的。
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: Icon(stopping ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 20),
    );
    // 那圈 48 的点击区放进 44 的盒子里（多出来的 2 不占地方也不画东西），所以整格 44×44 都点得到。
    final target = SizedBox(
      width: _kTarget,
      height: _kTarget,
      child: OverflowBox(minWidth: 0, maxWidth: kMinInteractiveDimension, minHeight: 0, maxHeight: kMinInteractiveDimension, child: button),
    );
    return longPress ? Semantics(label: '排队发送，长按选择方式', child: target) : target;
  }
}
