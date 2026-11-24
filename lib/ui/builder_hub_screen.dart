// 设计约束（搭建页外壳 · 390×844，浅色 + 深色）— 2026-11-24
// - 底部导航“搭建”这一页现在有两种东西可以搭：页面（低代码画布，BuilderScreen）和后端（积木，BackendScreen）。这个外壳只负责“显示哪一个”：
//   · 只有页面（page.lc.json）→ 直接是页面搭建，和以前一样；
//   · 只有后端（backend.lc.json，在根目录或 server/ 等）→ 直接是后端积木；
//   · 两个都有（全栈项目）→ 最上面一条分段按钮“页面 | 后端”，下面是对应的那一页；切走的那一页留着不销毁。
//   · 都没有 → 一个空状态，两个出路各占一行：主按钮“新建页面”，次按钮“新建后端积木”。
// - 分段按钮单独占一行（一行只做一件事），不往两个页面各自的顶栏里塞。
// - 上次选的是页面还是后端，按工作区记着（只记在内存里），从别的页签回来还是它。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/shell.dart';
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
  Widget build(BuildContext context) {
    final c = context.colors;
    final backend = _backendFile;
    if (!_probed) {
      return const Scaffold(
        appBar: ShellAppBar(title: '搭建'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_hasPage && backend == null) {
      return Scaffold(
        appBar: const ShellAppBar(title: '搭建'),
        body: EmptyState(
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
      );
    }
    Widget page() => BuilderScreen(session: _s);
    Widget back() => BackendScreen(key: ValueKey('be-$backend'), session: _s, file: backend);
    if (backend == null) return page();
    if (!_hasPage) return back();

    final side = _lastSide[_s] == 'backend' ? 'backend' : 'page';
    _built.add(side);
    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  key: const ValueKey('hub-switch'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: const [
                    ButtonSegment(value: 'page', label: Text('页面'), icon: Icon(Icons.dashboard_customize_outlined, size: 18)),
                    ButtonSegment(value: 'backend', label: Text('后端'), icon: Icon(Icons.dns_outlined, size: 18)),
                  ],
                  selected: {side},
                  onSelectionChanged: (v) => setState(() => _lastSide[_s] = v.first),
                ),
              ),
            ),
          ),
          Expanded(
            // 上面那条已经让开了状态栏，里面的页面不用再让一次。
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(index: side == 'page' ? 0 : 1, children: [_built.contains('page') ? page() : const SizedBox.shrink(), _built.contains('backend') ? back() : const SizedBox.shrink()]),
            ),
          ),
        ],
      ),
    );
  }
}
