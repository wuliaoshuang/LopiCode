// 设计约束（全局兜底 · 390×844）
// - 没被接住的异常不许白屏、不许悄悄闪退：统一记进错误日志（lib/core/crash_log.dart），界面上给一条能点开的提示。
// - 提示是屏幕顶上的一条窄条：“出了点问题” + “查看” + 关闭。一行只做一件事；同一时间只有一条，新的盖旧的。
// - 某一块界面画不出来时，那一块换成一张小卡片（说明 + “查看”），别的地方照常能用。
// - “查看”打开错误详情页：最近的错误全文、“复制”和“清空”。内容已经抹掉了像 Key 的东西。
// - 启动就失败（连设置都读不出来）：显示一整页说明 + 可复制的错误 + “重试”。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 装上三道兜底：界面框架抛的、平台层抛的。（第三道 runZonedGuarded 在 main.dart 里包住整个启动。）
/// 返回一个函数，调用它可以恢复原来的处理器（测试用）。
///
/// [forward]：记完以后要不要再交给原来的处理器（调试时照常打到控制台）。
VoidCallback installErrorHandlers({bool forward = kDebugMode}) {
  final oldFlutter = FlutterError.onError;
  final oldPlatform = PlatformDispatcher.instance.onError;
  final oldBuilder = ErrorWidget.builder;

  FlutterError.onError = (details) {
    final where = details.context?.toDescription();
    CrashLog.instance.record(details.exception, details.stack, source: where == null ? '界面' : '界面（$where）');
    if (forward) oldFlutter?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.instance.record(error, stack, source: '后台任务');
    return true; // 已处理：不让它把应用带崩
  };
  ErrorWidget.builder = (details) => BrokenBlock(message: '${details.exception}');

  return () {
    FlutterError.onError = oldFlutter;
    PlatformDispatcher.instance.onError = oldPlatform;
    ErrorWidget.builder = oldBuilder;
  };
}

/// runZonedGuarded 的错误回调。
void recordZoneError(Object error, StackTrace stack) => CrashLog.instance.record(error, stack, source: '后台任务');

/// 某一块界面画不出来时顶替它的小卡片。
class BrokenBlock extends StatelessWidget {
  const BrokenBlock({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    // 这里不能假设外面有主题 / 方向信息（出错的地方可能很靠外）。
    // 在应用里（有主题）跟应用的深浅色；更靠外的地方 Theme.of 会给默认的浅色主题。
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF3A1D22) : const Color(0xFFFFEBF3);
    final fg = dark ? const Color(0xFFFFB3C7) : const Color(0xFFAB131E);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        key: const Key('broken-block'),
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(
          '这一块显示不出来。别的地方可以照常用；详情在“设置 › 关于 › 错误日志”。\n${redactSecrets(message)}',
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: fg, fontSize: 13, height: 1.5, decoration: TextDecoration.none, fontWeight: FontWeight.w400),
        ),
      ),
    );
  }
}

/// 包在整个应用外面：有新的错误时在顶上出一条提示。
class ErrorNotice extends StatefulWidget {
  const ErrorNotice({super.key, required this.child, required this.navigatorKey});
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// [stormWindow] 时间内报错超过 [stormLimit] 次，就不再更新提示。
  static const Duration stormWindow = Duration(seconds: 10);
  static const int stormLimit = 5;

  @override
  State<ErrorNotice> createState() => _ErrorNoticeState();
}

class _ErrorNoticeState extends State<ErrorNotice> {
  StreamSubscription<CrashEntry>? _sub;
  CrashEntry? _latest;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _sub = CrashLog.instance.changes.listen(_onEntry);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 最近几次报错的时间：短时间里连着报（比如每一帧都在出同一个错）就不再反复弹，免得提示自己把界面拖垮。
  final List<DateTime> _recent = [];

  void _onEntry(CrashEntry entry) {
    if (!entry.fatal || !mounted) return;
    final now = DateTime.now();
    _recent
      ..removeWhere((t) => now.difference(t) > ErrorNotice.stormWindow)
      ..add(now);
    if (_recent.length > ErrorNotice.stormLimit) return; // 都在日志里，只是不再打扰
    _latest = entry;
    // 错误可能正好在画界面的过程中报出来：那就等这一帧画完再刷新，免得在 build 里 setState。
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _open() {
    setState(() => _latest = null);
    widget.navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => const ErrorLogScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final entry = _latest;
    return Stack(
      children: [
        widget.child,
        if (entry != null)
          Positioned(
            left: Space.x3,
            right: Space.x3,
            top: MediaQuery.paddingOf(context).top + Space.x2,
            child: _NoticeBar(onOpen: _open, onClose: () => setState(() => _latest = null)),
          ),
      ],
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.onOpen, required this.onClose});
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Material(
      key: const Key('error-notice'),
      color: c.dangerSoft,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.x3),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: c.danger),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text('出了点问题，刚才的操作可能没完成', style: t.bodySmall?.copyWith(color: c.danger), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            TextButton(
              key: const Key('error-notice-open'),
              onPressed: onOpen,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: const Text('查看'),
            ),
            // 注意：这条提示在 Navigator 外面（没有 Overlay），不能用带 tooltip 的控件。
            Semantics(
              button: true,
              label: '关闭提示',
              child: InkResponse(
                key: const Key('error-notice-close'),
                onTap: onClose,
                radius: 22,
                child: Padding(
                  padding: const EdgeInsets.all(Space.x3),
                  child: Icon(Icons.close, size: 18, color: c.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误日志页：最近的错误全文，可复制、可清空。
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  String? _text;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await CrashLog.instance.readAll();
    if (mounted) setState(() => _text = text);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text ?? ''));
    if (mounted) showSnack(context, '已复制');
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(context, title: '清空错误日志？', message: '只删除这份日志，不影响项目和设置。', confirmLabel: '清空', danger: true);
    if (!ok) return;
    await CrashLog.instance.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final text = _text;
    final empty = text != null && text.trim().isEmpty;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(background: c.canvas, title: const Text('错误日志')),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : empty
          ? const EmptyState(icon: Icons.check_circle_outline, title: '没有记录到错误', message: '应用出错时会记在这里，\n可以复制出来发给开发者。')
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
                  child: Text('只存在这台手机上，不会上传。里面像 Key 的内容已经抹掉。', style: t.bodySmall?.copyWith(color: c.textFaint)),
                ),
                FilledButton.icon(key: const Key('error-log-copy'), onPressed: _copy, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('复制全部')),
                const SizedBox(height: Space.x3),
                GroupCard(
                  padding: const EdgeInsets.all(Space.x4),
                  children: [
                    SelectableText(
                      text,
                      key: const Key('error-log-text'),
                      style: t.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                ),
                TextButton(
                  key: const Key('error-log-clear'),
                  onPressed: _clear,
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  child: const Text('清空错误日志'),
                ),
              ],
            ),
    );
  }
}

/// 启动失败时的整页说明（这时候连设置都没读出来，所以自带一个最小的应用外壳）。
class BootFailureApp extends StatelessWidget {
  const BootFailureApp({super.key, required this.error, required this.onRetry, this.fontFamily});
  final String error;
  final VoidCallback onRetry;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LopiCode',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light, fontFamily: fontFamily),
      darkTheme: buildAppTheme(Brightness.dark, fontFamily: fontFamily),
      home: Builder(
        builder: (context) {
          final c = context.colors;
          final t = Theme.of(context).textTheme;
          return Scaffold(
            backgroundColor: c.canvas,
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Space.x6),
                children: [
                  const SizedBox(height: Space.x8),
                  Icon(Icons.error_outline, size: 40, color: c.danger),
                  const SizedBox(height: Space.x4),
                  Text('LopiCode 没能启动', style: t.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: Space.x2),
                  Text('你的项目文件没有被动过。可以先点“重试”；还不行的话，把下面的内容复制出来发给开发者。', style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.6), textAlign: TextAlign.center),
                  const SizedBox(height: Space.x6),
                  FilledButton(key: const Key('boot-retry'), onPressed: onRetry, child: const Text('重试')),
                  const SizedBox(height: Space.x3),
                  OutlinedButton.icon(
                    key: const Key('boot-copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: error));
                      if (context.mounted) showSnack(context, '已复制');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制错误信息'),
                  ),
                  const SizedBox(height: Space.x4),
                  GroupCard(
                    padding: const EdgeInsets.all(Space.x4),
                    children: [
                      SelectableText(error, style: t.bodySmall?.copyWith(height: 1.5)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
