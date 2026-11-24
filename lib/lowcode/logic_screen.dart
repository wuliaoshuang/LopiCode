// 设计约束（积木逻辑页 · 390×844，浅色 + 深色）— 2026-11-24 改成积木画布
// - 这一页只是薄壳：界面全在通用的积木编辑器 BlockEditorView（lib/blocks/block_editor_view.dart）里，
//   这里只负责三件事：把文档包成 LogicBlockHost、把改动 / 撤销交还给搭建页（落盘在那边）、顶栏多放一个“变量”入口。
// - 顶栏：返回、标题“积木逻辑”，右边胶囊里是 变量（带数量）、问题（带数量）、看代码。
//   积木有错误时标题下面多一行“N 个错误，没更新”（logic.js 留着上一次的）；修好就消失。只有警告时没有这一行。
//   顶栏是沉浸式的（lib/ui/immersive_bar.dart，由 BlockEditorView 摆）：没有底色，浮在画布上，三样都是悬浮的小块。
// - 主体是积木画布，底下是积木盒；没有“添加事件”按钮了——事件是积木盒第一页里的帽子积木，拖出来或点一下就是一串新的。
// - 从某个控件点进来（initialNodeId）：画布移到它的第一串事件并选中帽子；它还没有事件就提示一句，不再有“只看：…”的筛选标签。
// - 所有改动都走 onEdit（每次一条撤销记录）；提交后从最近见到的文档重新读，不留着旧对象。
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 整页的积木逻辑编辑器。[doc] 是搭建页手里那份活的文档；[initialNodeId] 不为空时先看这个组件的事件。
/// [history] + [onRestore] 给了才有撤销 / 重做（搭建页把自己的历史交过来，两边是同一条撤销线）。
class LogicScreen extends StatefulWidget {
  const LogicScreen({super.key, required this.doc, required this.onEdit, this.initialNodeId, this.history, this.onRestore});
  final LcDocument doc;
  final LcEdit onEdit;
  final String? initialNodeId;
  final LcHistory? history;

  /// 撤销 / 重做拿到的那份文档交回搭建页（它换掉手里的文档并落盘）。
  final void Function(LcDocument? doc)? onRestore;

  @override
  State<LogicScreen> createState() => _LogicScreenState();
}

class _LogicScreenState extends State<LogicScreen> {
  late final LogicBlockHost _host = LogicBlockHost(
    doc: widget.doc,
    onEdit: widget.onEdit,
    canUndoOf: () => widget.onRestore != null && (widget.history?.canUndo ?? false),
    canRedoOf: () => widget.onRestore != null && (widget.history?.canRedo ?? false),
    onUndo: () => _restore(widget.history?.undo()),
    onRedo: () => _restore(widget.history?.redo()),
    preferTarget: widget.initialNodeId,
  );

  /// 进来时要看的那一串：这个控件的第一个事件。
  late final String? _focus = () {
    final id = widget.initialNodeId;
    if (id == null) return null;
    for (final h in widget.doc.logic.handlers) {
      if (h.target == id) return h.id;
    }
    return null;
  }();

  LcDocument? _restore(LcDocument? doc) {
    if (doc != null) widget.onRestore?.call(doc);
    return doc;
  }

  @override
  void initState() {
    super.initState();
    final id = widget.initialNodeId;
    if (id == null || _focus != null) return;
    // 这个控件还没有事件：说一句怎么加（等第一帧画完再说，搭界面的过程中不能弹提示）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSnack(context, '${describeNode(widget.doc, id)}还没有事件：从下面“事件”里拖一块出来。');
    });
  }

  @override
  void didUpdateWidget(LogicScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.doc, widget.doc)) _host.replaceDoc(widget.doc);
  }

  Future<void> _openVars() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LcVarsSheet(read: () => _host.doc, edit: (change) => _host.edit(() => change(_host.doc))),
    );
    if (mounted) setState(() {});
  }

  /// 变量下拉菜单最后一项“新建变量…”：建变量和选中它是同一次改动（一条撤销记录）。
  BlockMenuExtra? _menuExtra(LcArgSpec arg) {
    if (arg.kind != LcArgKind.variable) return null;
    return (
      label: '新建变量…',
      run: (context) async {
        final draft = await showLcVariableDialog(context, taken: {for (final v in _host.doc.logic.variables) v.name});
        if (draft == null || draft.delete) return null;
        return (value: draft.name, apply: () => lcApplyVarDraft(_host.doc.logic, draft));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vars = _host.doc.logic.variables.length;
    final errors = _host.errorCount;
    return BlockEditorView(
      host: _host,
      title: '积木逻辑',
      dockMemoryKey: 'logic',
      subtitle: errors > 0 ? blockErrorsBrief(errors) : null,
      focusScriptId: _focus,
      menuExtra: _menuExtra,
      onHostChanged: () => setState(() {}),
      extraActions: [
        IconButton(
          key: const ValueKey('lc-top-vars'),
          tooltip: '变量',
          onPressed: _openVars,
          icon: Badge(isLabelVisible: vars > 0, label: Text('$vars'), backgroundColor: c.accentFill, textColor: c.onAccent, child: const Icon(Icons.data_object_rounded)),
        ),
      ],
    );
  }
}
