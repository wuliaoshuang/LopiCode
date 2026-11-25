// 设计约束（后台命令 · 390×844，浅色 + 深色）
// 按 refactoring-ui 的顺序定：先层级，再排版，最后才上色。
// - 三层，一层只做一件事：
//   1) 输入框上方一条（和待办条同族：中性底 + 细边，行高 40）：只回答“有没有后台命令在跑”——“后台任务 2 个在跑 ›”。
//   2) 点开的面板：每个任务一行，只回答“是哪条命令、什么状态”。第一行命令（等宽、最重），第二行状态和时长（小字、次要色）。
//   3) 点进去的日志页：只看这一条。上面一行状态，中间是日志（等宽、深浅随主题、自动滚到底、可选中），底部一个“停止”。
// - 颜色只用来区分状态：在跑＝强调色小圆点；正常结束＝灰；失败 / 中断＝危险色。其余都是中性色。
// - 字号只用 12 / 14；层级靠字重和颜色深浅拉开。间距只用 4 / 8 / 12 / 16。
// - “停止”是这页唯一的破坏性操作：放在底部、危险色描边，不和“复制”挤在一行（复制在顶栏）。
// - 没有任务时这一条整个不出现；命令都结束、而且 AI 已经知道了，也不再占地方。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/background_tools.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/state/workspace_background.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 面板和日志页里那一行状态：`在跑 · 3 分 12 秒` / `已结束 · 退出码 0 · 5 秒`……
String backgroundRowStatus(BackgroundTask t, DateTime now) {
  final age = backgroundAge(t.age(now));
  return switch (t.status) {
    BackgroundStatus.running => '在跑 · $age',
    BackgroundStatus.exited => '已结束 · 退出码 ${t.exitCode ?? '未知'} · $age',
    BackgroundStatus.stopped => switch (t.stoppedBy) {
      StoppedBy.user => '你停掉的 · $age',
      StoppedBy.agent => 'AI 停掉的 · $age',
      _ => '工作区关闭时停掉的',
    },
    BackgroundStatus.interrupted => '已中断 · 应用被关闭，没有自动重跑',
  };
}

bool _failed(BackgroundTask t) => t.status == BackgroundStatus.interrupted || (t.status == BackgroundStatus.exited && t.exitCode != 0);

/// 每秒重画一次（“已跑多久”要走字）；没有在跑的任务时不走。
mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _timer;

  void tickWhile(bool running) {
    if (running && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.task);
  final BackgroundTask task;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = task.running ? c.accent : (_failed(task) ? c.danger : c.textFaint);
    return SizedBox(
      width: 16,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: task.running ? color : null,
            shape: BoxShape.circle,
            border: task.running ? null : Border.all(color: color, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// 输入框上方那一条。当前对话没有“在跑的”或“结束了 AI 还不知道的”后台命令时不占地方。
class BackgroundBar extends ConsumerWidget {
  const BackgroundBar({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session.disposed) return const SizedBox.shrink();
    final convId = session.activeConversationId;
    final tasks = ref.watch(backgroundTasksProvider(session)).of(convId);
    final running = tasks.where((t) => t.running).length;
    final fresh = tasks.where((t) => !t.running && !t.notified).length;
    if (running == 0 && fresh == 0) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final label = running > 0 ? '后台任务 $running 个在跑' : '后台任务 $fresh 个刚结束';
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('bg-bar'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => BackgroundSheet(session: session, convId: convId),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: running > 0 ? c.accent : c.textMuted),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    label,
                    style: t.bodySmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: c.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 点开的面板：这段对话的后台命令，一条一行。
class BackgroundSheet extends ConsumerStatefulWidget {
  const BackgroundSheet({super.key, required this.session, required this.convId});
  final ProjectSession session;
  final String convId;

  @override
  ConsumerState<BackgroundSheet> createState() => _BackgroundSheetState();
}

class _BackgroundSheetState extends ConsumerState<BackgroundSheet> with _Ticking {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tasks = widget.session.disposed ? const <BackgroundTask>[] : ref.watch(backgroundTasksProvider(widget.session)).of(widget.convId).reversed.toList();
    final running = tasks.where((e) => e.running).length;
    tickWhile(running > 0);
    final now = DateTime.now();
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
            child: Text('后台任务', style: t.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text(tasks.isEmpty ? '这段对话里没有后台命令' : '$running 个在跑，最多同时 $kMaxBackgroundRunning 个。点一条看日志', style: t.bodySmall?.copyWith(color: c.textMuted)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.x2),
              children: [
                for (final task in tasks)
                  InkWell(
                    key: ValueKey('bg-task-${task.id}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BackgroundLogScreen(session: widget.session, taskId: task.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
                      child: Row(
                        children: [
                          _Dot(task),
                          const SizedBox(width: Space.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.command.replaceAll('\n', ' '),
                                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.text, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '#${task.id} · ${backgroundRowStatus(task, now)}',
                                  style: t.bodySmall?.copyWith(color: _failed(task) ? c.danger : c.textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条后台命令的日志页：状态、实时日志、停止。
class BackgroundLogScreen extends ConsumerStatefulWidget {
  const BackgroundLogScreen({super.key, required this.session, required this.taskId});
  final ProjectSession session;
  final int taskId;

  @override
  ConsumerState<BackgroundLogScreen> createState() => _BackgroundLogScreenState();
}

class _BackgroundLogScreenState extends ConsumerState<BackgroundLogScreen> with _Ticking {
  final ScrollController _scroll = ScrollController();
  String _log = '';
  int _bytes = -1;
  bool _stopping = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 输出有变化才重读日志的最后一段；本来就在底部的话，跟着滚到底。
  void _refresh(BackgroundTask task) {
    if (task.bytes == _bytes) return;
    _bytes = task.bytes;
    _log = ref.read(backgroundTasksProvider(widget.session).notifier).logTail(task.id);
    final atBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48;
    if (!atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    await ref.read(backgroundTasksProvider(widget.session).notifier).stop(widget.taskId);
    if (mounted) setState(() => _stopping = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (mounted) showSnack(context, _log.isEmpty ? '还没有输出' : '已复制日志');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final task = widget.session.disposed ? null : ref.watch(backgroundTasksProvider(widget.session)).tasks.where((e) => e.id == widget.taskId).firstOrNull;
    tickWhile(task?.running ?? false);
    if (task != null) _refresh(task);
    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      appBar: PageBar(
        titleText: '后台命令 #${widget.taskId}',
        actions: [IconButton(key: const ValueKey('bg-log-copy'), tooltip: '复制日志', onPressed: task == null ? null : _copy, icon: const Icon(Icons.copy_outlined, size: 20))],
      ),
      body: BelowBar(
        child: task == null
            ? Center(
                child: Text('这条后台命令的记录已经清掉了', style: t.bodyMedium?.copyWith(color: c.textMuted)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
                    child: Text(
                      task.command,
                      style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.text, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                    child: Row(
                      children: [
                        _Dot(task),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text(
                            backgroundRowStatus(task, DateTime.now()),
                            key: const ValueKey('bg-log-status'),
                            style: t.bodySmall?.copyWith(color: _failed(task) ? c.danger : c.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: Space.x4),
                      decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
                      clipBehavior: Clip.antiAlias,
                      child: _log.isEmpty
                          ? Center(
                              child: Text(task.running ? '还没有输出' : '没有输出', style: t.bodySmall?.copyWith(color: c.textFaint)),
                            )
                          : CodeZoom(
                              child: SingleChildScrollView(
                                key: const ValueKey('bg-log-scroll'),
                                controller: _scroll,
                                padding: const EdgeInsets.all(Space.x3),
                                child: SelectableText(
                                  _log,
                                  key: const ValueKey('bg-log-text'),
                                  // 字号跟着“代码字号”走、小一号（默认 12）；双指捏合可调。
                                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), height: 1.45, color: c.text),
                                ),
                              ),
                            ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
                      child: task.running
                          ? OutlinedButton.icon(
                              key: const ValueKey('bg-log-stop'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: c.danger,
                                side: BorderSide(color: c.danger),
                              ),
                              onPressed: _stopping ? null : _stop,
                              icon: const Icon(Icons.stop_rounded, size: 20),
                              label: Text(_stopping ? '正在停止…' : '停止'),
                            )
                          : Text(
                              '完整日志在工作区的 ${task.log}',
                              style: t.bodySmall?.copyWith(color: c.textFaint),
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
