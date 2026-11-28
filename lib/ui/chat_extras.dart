// 设计约束（聊天里的三种安静提示 · 390×844）— 2026-11-24
// - 思考过程：一行。还在想＝转圈 +“正在思考…”+ 已用秒数；想完＝“思考了 N 秒”，点开才看全文（淡色小字，限高可滚）。
//   它是“过程”，和步骤同级：无底无框、灰字，不和正式回复抢眼；在步骤组里就是清单里的一行。
// - 已压缩较早的对话：一行灰字居中分隔线的样子，点开看摘要。不用色块——这不是需要处理的事。
// - 上一轮没正常结束：这是要用户拿主意的事，用一张卡（中性底）：标题一句话说停在哪，下面逐条细节，
//   最下面一行两个按钮：“不用了”（描边）+“继续”（唯一的实心主按钮）。有“可能只执行了一半”的步骤时，只有那个小图标带警告色。
// - 一行只做一件事；颜色只用在状态上。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/message_text.dart';
import 'package:material_ui/material_ui.dart';

/// 聊天行里要用到、但行自己拿不到的几个动作。由聊天页在列表外面套一层提供；没套（比如只读的子对话页）就不出现对应按钮。
class ChatRowActions extends InheritedWidget {
  const ChatRowActions({super.key, required super.child, this.readOutput, this.onResume, this.onDismissInterrupted});

  /// 读一份转存的命令输出（工作区内相对路径）；被清理掉了返回 null。
  final Future<String?> Function(String rel)? readOutput;

  /// “上一轮没正常结束”那张卡的两个按钮。
  final VoidCallback? onResume;
  final VoidCallback? onDismissInterrupted;

  static ChatRowActions? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChatRowActions>();

  @override
  bool updateShouldNotify(ChatRowActions oldWidget) => oldWidget.readOutput != readOutput || oldWidget.onResume != onResume || oldWidget.onDismissInterrupted != onDismissInterrupted;
}

/// “想了多久”的写法：不到 1 秒说“不到 1 秒”，一分钟以上说“1 分 5 秒”。
String formatThinkingSpan(int ms) {
  final s = (ms / 1000).round();
  if (ms < 1000) return '不到 1 秒';
  return s < 60 ? '$s 秒' : '${s ~/ 60} 分 ${s % 60} 秒';
}

/// 思考那一行写什么：还在想＝“正在思考… N 秒”，想完＝“思考了 N 秒”（旧记录没存用时就只写“思考过程”）。
String thinkingLineOf(ThinkingItem item) {
  if (item.streaming) {
    final from = item.startedAt;
    final secs = from == null ? 0 : DateTime.now().difference(from).inSeconds;
    return secs < 1 ? '正在思考…' : '正在思考… $secs 秒';
  }
  return item.ms == null ? '思考过程' : (item.ms! < 1000 ? '思考了不到 1 秒' : '思考了 ${formatThinkingSpan(item.ms!)}');
}

/// 每秒重画一次里面的东西（给“已经想了几秒”这种自己会变的字用）。
class SecondTick extends StatefulWidget {
  const SecondTick({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<SecondTick> createState() => _SecondTickState();
}

class _SecondTickState extends State<SecondTick> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// 一段思考：一行，点开看全文。
class ThinkingRow extends StatefulWidget {
  const ThinkingRow({super.key, required this.item});
  final ThinkingItem item;

  @override
  State<ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<ThinkingRow> {
  bool _open = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ThinkingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// 还在想的时候每秒刷新一次用时；想完就停表。
  void _sync() {
    if (widget.item.streaming) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final item = widget.item;
    final label = thinkingLineOf(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: _open ? '收起思考过程' : '展开思考过程',
          child: InkWell(
            key: const ValueKey('thinking-row'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: item.streaming
                          ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textFaint))
                          : Icon(Icons.psychology_alt_outlined, size: 16, color: c.textFaint),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      label,
                      style: t.bodyMedium?.copyWith(color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.x1),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: c.textFaint),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Container(
            key: const ValueKey('thinking-text'),
            margin: const EdgeInsets.only(left: Space.x8, bottom: Space.x2),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: BackdropScope.surface(context, c.codeBg, seeThrough: BackdropArea.code),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: SingleChildScrollView(
              // 还在想：贴着底看最新的
              reverse: item.streaming,
              padding: const EdgeInsets.all(Space.x3),
              // 和正文同一套 Markdown 排版，只是小字、灰色
              child: MessageText(item.text.trim(), muted: true, streaming: false),
            ),
          ),
      ],
    );
  }
}

/// “已压缩较早的对话”：一行，点开看摘要。
class CompactionRow extends StatefulWidget {
  const CompactionRow({super.key, required this.item});
  final CompactionItem item;

  @override
  State<CompactionRow> createState() => _CompactionRowState();
}

class _CompactionRowState extends State<CompactionRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget rule() => Expanded(child: Divider(height: 1, color: c.border));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: _open ? '收起摘要' : '查看摘要',
          child: InkWell(
            key: const ValueKey('compaction-row'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  rule(),
                  const SizedBox(width: Space.x3),
                  Icon(Icons.compress, size: 14, color: c.textFaint),
                  const SizedBox(width: Space.x1),
                  Text('已压缩较早的对话', style: t.bodySmall?.copyWith(color: c.textMuted)),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: c.textFaint),
                  const SizedBox(width: Space.x3),
                  rule(),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Container(
            key: const ValueKey('compaction-summary'),
            margin: const EdgeInsets.only(bottom: Space.x2),
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
              color: BackdropScope.surface(context, c.codeBg, seeThrough: BackdropArea.code),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('较早的对话已经换成下面这份摘要发给模型（上面的记录还能看，只是不再占上下文）：', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
                  const SizedBox(height: Space.x2),
                  SelectableText(widget.item.summary.trim(), style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 上一轮没正常结束：说清楚停在哪，给“继续 / 不用了”。
class InterruptedCard extends StatelessWidget {
  const InterruptedCard({super.key, required this.item});
  final InterruptedItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final actions = ChatRowActions.maybeOf(context);
    return Container(
      key: const ValueKey('interrupted-card'),
      margin: const EdgeInsets.symmetric(vertical: Space.x2),
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(item.risky ? Icons.warning_amber_rounded : Icons.history, size: 18, color: item.risky ? c.warning : c.textMuted),
              ),
              const SizedBox(width: Space.x2),
              Expanded(child: Text(item.headline, style: t.titleSmall)),
            ],
          ),
          const SizedBox(height: Space.x3),
          for (final line in item.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: Text(line, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
            ),
          if (actions?.onResume != null && actions?.onDismissInterrupted != null) ...[
            const SizedBox(height: Space.x3),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('interrupted-dismiss'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.text,
                      side: BorderSide(color: c.border),
                    ),
                    onPressed: actions!.onDismissInterrupted,
                    child: const Text('不用了'),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: FilledButton(key: const ValueKey('interrupted-resume'), onPressed: actions.onResume, child: const Text('继续')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 整页看一份转存的完整输出（命令输出，或别的工具的超长结果）。字号跟着“代码字号”走、小一号，双指捏合可调。
class CommandOutputPage extends StatelessWidget {
  const CommandOutputPage({super.key, required this.path, required this.load});
  final String path;
  final Future<String?> Function(String rel) load;

  /// 一页最多显示这么多字（再多手机上滚不动）；超了显示开头和结尾。
  static const int maxShown = 200000;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: c.canvas, title: const Text('完整输出')),
      body: ContentWidth(
        child: FutureBuilder<String?>(
          future: load(path),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final text = snap.data;
            if (text == null) {
              return Padding(
                padding: EdgeInsets.fromLTRB(Space.x6, PageBar.insetOf(context) + Space.x6, Space.x6, Space.x6),
                child: Text('这份完整输出已经不在了（转存的输出只留最近 20 份）。需要的话让 Agent 把这一步重新做一次。', style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.6)),
              );
            }
            final shown = text.length <= maxShown
                ? text
                : '${text.substring(0, maxShown ~/ 2)}\n\n…（太长，中间 ${text.length - maxShown} 字没显示；文件在 $path）…\n\n${text.substring(text.length - maxShown ~/ 2)}';
            return CodeZoom(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x4, Space.x4, Space.x4),
                  child: Consumer(
                    builder: (context, ref, _) => SelectableText(
                      shown,
                      key: const ValueKey('output-full-text'),
                      style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), height: 1.5, color: c.text),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
