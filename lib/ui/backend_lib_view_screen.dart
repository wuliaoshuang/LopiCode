// 设计约束（自带库在画布上看 · 只读，390×844，浅色 + 深色）— 2026-11-28 第四轮 A3b
// - 一整页：顶栏是库的名字和“只读”，右边一个“函数”按钮（列出所有函数，点哪个画布就挪到哪个）。
// - 顶栏下面一条说明：这是从文字写法翻过来的；多少个函数、多少句、几处没翻成积木。点这一条看明细（哪几处、换了哪些说法）。
// - 下面整块是只读画布：能平移、双指缩放、点选，不能拖不能改，也没有积木盒。画布上不标问题（这是应用自带的库，
//   里面直接调宿主接口是正常的，不该照“自己的库”的规矩标红）。
// - 翻不出来（模块读不了）时正中一句原因。
// - 颜色全取主题值，代码用应用统一的代码字号。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_from_text.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 只读画布用的宿主：和平常的一样，只是不报问题。
class BeViewHost extends BeBlockHost {
  BeViewHost({required super.doc});

  @override
  List<BlockIssue> get issues => const [];

  @override
  List<BlockIssue> get liveIssues => const [];
}

/// 打开“在画布上看”。[moduleText]＝这个库的模块（文字写法）。
Future<void> showBeLibView(BuildContext context, {required String title, required String moduleText, required LibSide side}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => BeLibViewScreen(title: title, moduleText: moduleText, side: side),
  ),
);

class BeLibViewScreen extends ConsumerStatefulWidget {
  const BeLibViewScreen({super.key, required this.title, required this.moduleText, required this.side});
  final String title;
  final String moduleText;
  final LibSide side;

  @override
  ConsumerState<BeLibViewScreen> createState() => _BeLibViewScreenState();
}

class _BeLibViewScreenState extends ConsumerState<BeLibViewScreen> {
  // 标识只是给这份只读文档一个合规矩的名字，不会存下来、也不会拿去用。
  late final BeFromTextResult _got = beFromText(widget.moduleText, id: 'view/${widget.side == LibSide.frontend ? 'page' : 'service'}', name: widget.title, side: widget.side);
  late final BeViewHost? _host = _got.doc == null ? null : BeViewHost(doc: _got.doc!);
  final GlobalKey<BlockCanvasViewState> _canvas = GlobalKey();
  final TransformationController _move = TransformationController();

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  String get _summary {
    final r = _got;
    final rest = r.rawSpots == 0 ? '全部翻成了积木' : '${r.rawSpots} 处没有对应的积木，照文字原样放着';
    return '从文字写法翻过来的，只能看。${r.fns.length} 个函数、${r.stmts} 句，$rest。点这里看明细';
  }

  void _goto(String fnName) {
    final host = _host;
    final state = _canvas.currentState;
    if (host == null || state == null) return;
    final f = host.doc.functions.where((f) => f.name == fnName).firstOrNull;
    final placed = f == null ? null : state.layout.placed(f.id);
    if (placed == null) return;
    _move.value = Matrix4.translationValues(16 - placed.origin.dx, 16 - placed.origin.dy, 0);
    state.select(BlockSelection(f!.id, const []));
  }

  Future<void> _pick() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => BeSheetFrame(
        key: const ValueKey('be-lib-view-fns'),
        title: '函数（${_got.fns.length} 个）',
        hint: '点哪个，画布就挪到哪个。后面写着它有几句、其中几处是文字原样。',
        children: [
          for (final f in _got.fns)
            BeSheetRow(
              key: ValueKey('be-lib-view-fn-${f.name}'),
              label: f.name,
              value: f.raws.isEmpty ? '${f.stmts} 句' : '${f.stmts} 句 · 原样 ${f.raws.length} 处',
              onTap: () => Navigator.pop(sheet, f.name),
            ),
        ],
      ),
    );
    if (name != null && mounted) _goto(name);
  }

  Future<void> _detail() {
    final r = _got;
    final c = context.colors;
    final code = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.read(compactCodeFontProvider), color: c.text, height: 1.4);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => BeSheetFrame(
        key: const ValueKey('be-lib-view-detail'),
        title: '翻成积木的明细',
        hint:
            '这个库本来是用语言基础的文字写法写的。这里把它翻成了积木；翻完又照平常的路翻回去，和原来的逐句对过，一句不差。\n'
            '一共 ${r.stmts} 句，其中整句照文字原样放着的 ${r.rawStmts} 句；连一句里某个值算上，没有对应积木的地方一共 ${r.rawSpots} 处。',
        children: [
          const BeSheetSection('和原来的写法不一样、意思一样的地方'),
          BeSheetRow(label: '局部变量换了名字', value: '${r.renamed} 个', muted: true),
          const BeSheetRow(label: '积木里的变量名只能用英文字母、数字、下划线，原来用汉字起的换成了 v1、v2…', muted: true, indent: true),
          for (final a in r.aliases.entries) BeSheetRow(label: '别名「${a.key}」直接写成了', value: a.value, muted: true),
          const BeSheetRow(label: '宿主接口的声明不用写，用到哪个自动补哪个', muted: true),
          for (final s in r.skipped) BeSheetRow(label: '没带过来：$s', muted: true),
          BeSheetSection('没有对应积木的地方（${r.rawSpots} 处）'),
          if (r.rawSpots == 0) const BeSheetRow(label: '没有，全部翻成了积木', muted: true),
          for (final f in r.fns)
            if (f.raws.isNotEmpty) ...[
              BeSheetRow(key: ValueKey('be-lib-view-raw-${f.name}'), label: f.name, value: f.whole ? '整个函数' : '${f.raws.length} 处'),
              for (final x in f.raws)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x4, Space.x2),
                  child: Text(x.replaceAll(RegExp(r'\s+'), ' '), style: code),
                ),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final host = _host;
    return Scaffold(
      key: const ValueKey('be-lib-view'),
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(
        background: c.canvas,
        titleText: '${widget.title} · 只读',
        actions: [if (host != null) TextButton(key: const ValueKey('be-lib-view-pick'), onPressed: _pick, child: const Text('函数'))],
      ),
      body: BelowBar(
        child: host == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Text(
                    key: const ValueKey('be-lib-view-bad'),
                    '这个库的模块读不出来，没法放到画布上：${_got.problems.firstOrNull ?? ''}',
                    style: t.bodyMedium?.copyWith(color: c.danger),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: c.surfaceMuted,
                    child: InkWell(
                      key: const ValueKey('be-lib-view-summary'),
                      onTap: _detail,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
                        child: Text(_summary, style: t.bodySmall?.copyWith(color: c.textMuted)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: BlockCanvasView(key: _canvas, host: host, transformation: _move),
                  ),
                ],
              ),
      ),
    );
  }
}
