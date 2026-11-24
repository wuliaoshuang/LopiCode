// 设计约束（聊天输入栏 · 390×844）
// - 输入区常驻底部。没点进去且没有字：收成一行胶囊（附件、提示、用量小环、语音、发送）。
// - 点进去或有草稿：展开成两行，上方多行输入，下方工具栏放附件、权限、模型、用量小环、语音和发送。
// - 键盘弹出时底部导航让位，输入栏贴着键盘；长按发送仍可选排队、插话或中断。
// - 语音识别把实时结果接进草稿，不覆盖已有文字；不可用时给出明确原因。
import 'dart:async';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final ChatVoiceInput _voice = widget.voiceInput ?? _deviceVoiceInput;
  String _dictationBase = '';
  bool _startingVoice = false;
  bool _listening = false;
  bool _acceptingDictation = false;

  /// 收起和展开是两种排法，输入框靠这把钥匙在两边搬来搬去，焦点和光标不丢。
  final GlobalKey _fieldKey = GlobalKey();
  bool _wasCollapsed = true;

  @override
  void initState() {
    super.initState();
    _wasCollapsed = _collapsed;
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

  /// 只在“收起 / 展开”真的变了的时候重画，打字时不跟着每个字重画。
  void _onInputChanged() {
    if (!mounted) return;
    final now = _collapsed;
    if (now == _wasCollapsed) return;
    _wasCollapsed = now;
    setState(() {});
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onInputChanged);
    widget.controller.removeListener(_onInputChanged);
    _voice.dispose();
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
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x2),
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
    final ring = widget.context_ != null && widget.onContext != null ? ContextRing(usage: widget.context_!, onTap: widget.onContext!) : null;

    final Widget body;
    if (collapsed) {
      body = Row(
        children: [
          plus,
          const SizedBox(width: Space.x1),
          Expanded(child: field),
          ?ring,
          voice,
          const SizedBox(width: Space.x1),
          send,
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1, Space.x2, 0), child: field),
          const SizedBox(height: Space.x2),
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
                        minimumSize: const Size(0, 40),
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
              voice,
              const SizedBox(width: Space.x1),
              send,
            ],
          ),
        ],
      );
    }

    return Container(
      key: const ValueKey('chat-input'),
      margin: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
      padding: collapsed ? const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 6) : const EdgeInsets.fromLTRB(Space.x2, Space.x2, Space.x2, Space.x2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(collapsed ? 30 : 28),
        border: Border.all(color: c.border),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 140), curve: Curves.easeOut, alignment: Alignment.bottomCenter, child: body),
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
    width: 40,
    height: 40,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(Space.x2),
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
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
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: Icon(stopping ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 21),
    );
    return longPress ? Semantics(label: '排队发送，长按选择方式', child: button) : button;
  }
}
