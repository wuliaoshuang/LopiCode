// 设计约束（搭建页外壳 · 390×844，浅色 + 深色）— 2026-11-24
// - 底部导航“搭建”这一页现在有两种东西可以搭：页面（低代码画布，BuilderScreen）和后端（积木，BackendScreen）。这个外壳只负责“显示哪一个”：
//   · 只有页面（page.lc.json）→ 直接是页面搭建，和以前一样；
//   · 只有后端（backend.lc.json，在根目录或 server/ 等）→ 直接是后端积木；
//   · 两个都有（全栈项目）→ 最上面一条分段按钮“页面 | 后端”，下面是对应的那一页；切走的那一页留着不销毁。
//   · 都没有 → 一个空状态，两个出路各占一行：主按钮“新建页面”，次按钮“新建后端积木”。
// - 分段按钮单独占一行（一行只做一件事），不往两个页面各自的顶栏里塞。
//   它是浮着的：没有整条底色，下面的画布一直铺到屏幕最顶。它排在两个页面各自的悬浮顶栏**下面**一行（顶栏位置全应用一致），
//   占的高度经 BarExtra 告诉里面的页面。
// - 上次选的是页面还是后端，按工作区记着（只记在内存里），从别的页签回来还是它。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 每个工作区上次看的是哪一边（'page' / 'backend'）。
final Expando<String> _lastSide = Expando('builderHubSide');

class BuilderHubScreen extends ConsumerStatefulWidget {
  const BuilderHubScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<BuilderHubScreen> createState() => _BuilderHubScreenState();
}

class _BuilderHubScreenState extends ConsumerState<BuilderHubScreen> {
  bool _probed = false;
  bool _hasPage = false;

  /// 后端积木文件在工作区里的相对路径；没有是 null。
  String? _backendFile;
  bool _busy = false;
  final Set<String> _built = {};

  ProjectSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _probe();
    // 文件变了（Agent 新建了页面 / 后端、文件页里删了）：重新看一眼有哪些。
    ref.listenManual(filesRevProvider(_s), (_, _) => _probe());
  }

  Future<bool> _exists(String rel) async {
    try {
      return await File(_s.guard.resolve(rel)).exists();
    } on PathGuardException {
      return false; // 指到工作区外面去的链接：当没有
    } on FileSystemException {
      return false; // 看不了（权限）：当没有
    }
  }

  Future<void> _probe() async {
    final page = await _exists(kLowcodePageFile);
    String? backend;
    for (final dir in kBackendDirs) {
      final rel = dir.isEmpty ? kBackendFileName : '$dir/$kBackendFileName';
      if (await _exists(rel)) {
        backend = rel;
        break;
      }
    }
    if (!mounted || (_probed && page == _hasPage && backend == _backendFile)) return;
    setState(() {
      _probed = true;
      _hasPage = page;
      _backendFile = backend;
    });
  }

  Future<void> _create(Future<void> Function() make) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await make();
    } on FileSystemException catch (e) {
      if (mounted) showSnack(context, '没建成：${e.osError?.message ?? e.message}');
    } on PathGuardException catch (e) {
      if (mounted) showSnack(context, '没建成：${e.message}');
    }
    await _probe();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _newPage() => _create(() async {
    await saveLowcodePage(_s.guard, LcDocument.starter(_s.project.name));
    _lastSide[_s] = 'page';
    _s.filesChanged();
  });

  Future<void> _newBackend() => _create(() async {
    final result = await createBackendStarter(_s);
    _lastSide[_s] = 'backend';
    if (mounted && result.conflicts.isNotEmpty) showSnack(context, '项目里已经有同名的文件，没有覆盖：${[for (final c in result.conflicts) c.path].join('、')}');
  });

  @override
  Widget build(BuildContext context) => AppBackdrop(area: BackdropArea.pages, builder: _page);

  /// [on]＝这一页现在画着背景图片：各层的页面底色让开。
  Widget _page(BuildContext context, bool on) {
    final c = context.colors;
    final backend = _backendFile;
    if (!_probed) {
      return Scaffold(
        backgroundColor: on ? Colors.transparent : null,
        extendBodyBehindAppBar: true,
        appBar: const ShellAppBar(title: '搭建'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasPage && backend == null) {
      return Scaffold(
        backgroundColor: on ? Colors.transparent : null,
        extendBodyBehindAppBar: true,
        appBar: const ShellAppBar(title: '搭建'),
        body: BelowBar(
          child: EmptyState(
            key: const ValueKey('hub-empty'),
            icon: Icons.dashboard_customize_outlined,
            title: '这个项目还没有可以搭的东西',
            message: '页面：拖组件搭网页，生成 $kLowcodePageFile，并自动导出 index.html 和 style.css。\n后端：用积木搭接口，生成 $kBackendFileName 和能直接启动的代码。',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(key: const ValueKey('hub-new-page'), onPressed: _busy ? null : _newPage, child: const Text('新建页面')),
                const SizedBox(height: Space.x2),
                OutlinedButton(key: const ValueKey('hub-new-backend'), onPressed: _busy ? null : _newBackend, child: const Text('新建后端积木')),
              ],
            ),
          ),
        ),
      );
    }
    Widget page() => BuilderScreen(session: _s);
    Widget back() => BackendScreen(key: ValueKey('be-$backend'), session: _s, file: backend);
    if (backend == null) return page();
    if (!_hasPage) return back();

    final side = _lastSide[_s] == 'backend' ? 'backend' : 'page';
    _built.add(side);
    // 切换条浮在画布上面、排在悬浮顶栏的下面（顶栏在全应用同一个位置，不因为多了切换条往下挪）；
    // 它占的高度经 BarExtra 告诉里面的页面：画布多让出这一段，顶栏的渐隐遮罩也盖到它下面。
    final mq = MediaQuery.of(context);
    const lift = kHubSwitchHeight + Space.x2;
    return ColoredBox(
      color: on ? Colors.transparent : c.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BarExtra(
            extra: lift,
            child: IndexedStack(index: side == 'page' ? 0 : 1, children: [_built.contains('page') ? page() : const SizedBox.shrink(), _built.contains('backend') ? back() : const SizedBox.shrink()]),
          ),
          Positioned(
            left: Space.x4,
            right: Space.x4,
            top: mq.viewPadding.top + PageBar.kHeight,
            height: kHubSwitchHeight,
            child: DecoratedBox(
              // 自己带一块卡片色的底：下面有积木 / 控件滑过时字还看得清。
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(kHubSwitchHeight / 2)),
              child: SegmentedButton<String>(
                key: const ValueKey('hub-switch'),
                showSelectedIcon: false,
                // 和外面那块底一样高，选中的那一半才填得满。
                style: const ButtonStyle(visualDensity: VisualDensity.standard, tapTargetSize: MaterialTapTargetSize.shrinkWrap, minimumSize: WidgetStatePropertyAll(Size(0, kHubSwitchHeight))),
                segments: const [
                  ButtonSegment(value: 'page', label: Text('页面'), icon: Icon(Icons.dashboard_customize_outlined, size: 18)),
                  ButtonSegment(value: 'backend', label: Text('后端'), icon: Icon(Icons.dns_outlined, size: 18)),
                ],
                selected: {side},
                onSelectionChanged: (v) => setState(() => _lastSide[_s] = v.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// “页面 / 后端”切换条多高。
const double kHubSwitchHeight = 40;
