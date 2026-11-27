// 设计约束（低代码 · 页面面板 · 390×844；第 4 期·多页面，设计见 docs/blocks-v5-parts/E-editor-components.md §10.6）
// - 从哪进：搭建页顶栏右边的“页面”按钮（⋮ 左边；有几页写几页），或 ⋮ 菜单第一项“页面”。底部面板。
// - 这个面板的主要用途是**换一页去编辑**：点一行＝换到那一页并关掉面板。所以行本身是主角，没有另外的主按钮。
// - 从上到下：
//     标题行：左“页面 · 3 个”。下面一句灰色小字：第一页是首页，导出的应用 / 网站从它开始。
//     一页一行（行高 56）：[图标：首页是小房子，别的是纸] [页名（主，titleSmall）／下面一行灰色小字“首页 · 5 个组件 · 2 串逻辑”] [⋮]
//       正在编辑的那一行整行浅强调色，小字最前面多“正在编辑”。
//       行尾 ⋮ 一个菜单装下这一页能做的所有事（一行只做“去这一页”一件事，别的都收进去）：
//         改名 / 复制一页 / 设为首页（首页没有这项）/ 上移 / 下移 / 删除（红字；只剩一页时变灰）。
//       上移 / 下移只在“不是首页的那几页”之间排——换首页只能点“设为首页”，免得排个序不小心把首页换了。
//     最下面一个整宽的描边按钮“＋ 新建页面”（次要操作：描边不实心）。满 30 页变灰并写明“最多 30 页”。
// - 新建：先问名字（预填“页面 N”），建好就换过去、关面板。改名：弹输入框。复制：紧跟在原页后面，名字加“ 副本”，不换页。
// - 删除一定先问：说清楚里面有几个组件、几串逻辑会一起删；别的页还有几处（“去页面”积木、底部导航项）指着它时再多说一句
//   “那些地方会标成错误，要自己改”。删了能撤销。
// - 每个操作一条撤销。换页本身不算修改、不存盘。
// - 取用的 tokens：Space.x1/x2/x3/x4/x6、accentSoft（正在编辑的行）、textMuted / textFaint（图标、小字）、danger（删除）。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 页面面板一行多高。
const double kPageRowHeight = 56;

class PagesSheet extends StatefulWidget {
  const PagesSheet({super.key, required this.doc, required this.onEdit, required this.onOpen});

  /// 取现在的文档（面板开着的时候文档会被改）。
  final LcDocument Function() doc;
  final LcEdit onEdit;

  /// 换到这一页去编辑（页面那边负责清选中、重画）。
  final void Function(String pageId) onOpen;

  @override
  State<PagesSheet> createState() => _PagesSheetState();
}

int _nodeCount(LcNode n) => n.children.fold(0, (sum, c) => sum + 1 + _nodeCount(c));

class _PagesSheetState extends State<PagesSheet> {
  LcDocument get _doc => widget.doc();

  void _edit(void Function(LcDocument d) change) {
    widget.onEdit(change);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final name = await promptDialog(context, title: '新建页面', initial: _doc.freshPageTitle(), hint: '页面的名字', confirmLabel: '新建');
    if (name == null || !mounted) return;
    String? id;
    widget.onEdit((d) {
      id = d.addPage(name);
      // 建好就换过去：放在同一次修改里，撤销“新建页面”时人也跟着回到原来那页。
      if (id != null) d.openPage(id!);
    });
    if (id == null || !mounted) return;
    widget.onOpen(id!);
    Navigator.pop(context);
  }

  Future<void> _rename(LcPage page) async {
    final name = await promptDialog(context, title: '页面的名字', initial: page.title, confirmLabel: '保存');
    if (name == null || !mounted) return;
    _edit((d) => d.renamePage(page.id, name));
  }

  Future<void> _remove(LcPage page) async {
    final nodes = _nodeCount(page.root), chains = page.logic.handlers.length, refs = _doc.pageRefCount(page.id);
    final inside = nodes == 0 && chains == 0 ? '这一页是空的。' : '里面的 $nodes 个组件${chains > 0 ? '、$chains 串逻辑' : ''}会一起删掉。';
    final outside = refs > 0 ? '\n别的页面还有 $refs 处（“去页面”积木、底部导航项）指着它：删了以后那些地方会标成错误，要自己改。' : '';
    final ok = await confirmDialog(context, title: '删除「${page.title}」', message: '$inside$outside\n删错了可以撤销。', confirmLabel: '删除', danger: true);
    if (!ok || !mounted) return;
    final wasCurrent = _doc.page.id == page.id;
    _edit((d) => d.removePage(page.id));
    if (wasCurrent) widget.onOpen(_doc.page.id);
  }

  void _menu(String v, LcPage page) {
    final doc = _doc, at = doc.pages.indexOf(page);
    switch (v) {
      case 'rename':
        _rename(page);
      case 'dup':
        _edit((d) => d.duplicatePage(page.id));
      case 'home':
        _edit((d) => d.setHomePage(page.id));
      case 'up':
        _edit((d) => d.movePage(page.id, at - 1));
      case 'down':
        _edit((d) => d.movePage(page.id, at + 1));
      case 'delete':
        _remove(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final doc = _doc;
    final pages = doc.pages;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        child: Column(
          key: const Key('lc-pages-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('页面 · ${pages.length} 个', style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('点一页去编辑它。第一页是首页：导出的应用和网站从它开始。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            ),
            for (final (i, page) in pages.indexed) _row(page, i, doc, c, t),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
              child: OutlinedButton.icon(
                key: const Key('lc-page-add'),
                onPressed: doc.canAddPage ? _add : null,
                icon: const Icon(Icons.add, size: 18),
                label: Text(doc.canAddPage ? '新建页面' : '最多 $kLcMaxPages 页'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(LcPage page, int i, LcDocument doc, AppColors c, TextTheme t) {
    final current = doc.page.id == page.id, home = i == 0;
    final nodes = _nodeCount(page.root), chains = page.logic.handlers.length;
    final facts = [if (current) '正在编辑', if (home) '首页', '$nodes 个组件', if (chains > 0) '$chains 串逻辑'].join(' · ');
    return Material(
      color: current ? c.accentSoft : Colors.transparent,
      child: InkWell(
        key: Key('lc-page-row-${page.id}'),
        onTap: () {
          widget.onOpen(page.id);
          Navigator.pop(context);
        },
        child: SizedBox(
          height: kPageRowHeight,
          child: Row(
            children: [
              const SizedBox(width: Space.x4),
              Icon(home ? Icons.home_outlined : Icons.description_outlined, size: 20, color: current ? c.accent : c.textMuted),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                    Text(
                      facts,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: current ? c.textMuted : c.textFaint),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('lc-page-menu-${page.id}'),
                tooltip: '这一页的操作',
                icon: Icon(Icons.more_vert, color: c.textMuted),
                onSelected: (v) => _menu(v, page),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('改名')),
                  PopupMenuItem(value: 'dup', enabled: doc.canAddPage, child: const Text('复制一页')),
                  if (!home) const PopupMenuItem(value: 'home', child: Text('设为首页')),
                  // 排序只在“不是首页的那几页”之间：第 2 页不能再上移（那等于换首页）。
                  PopupMenuItem(value: 'up', enabled: i > 1, child: const Text('上移')),
                  PopupMenuItem(value: 'down', enabled: !home && i < doc.pages.length - 1, child: const Text('下移')),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: doc.pages.length > 1,
                    child: Text('删除', style: TextStyle(color: doc.pages.length > 1 ? c.danger : null)),
                  ),
                ],
              ),
              const SizedBox(width: Space.x1),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开页面面板。面板关掉时这个 Future 完成。
Future<void> showPagesSheet(BuildContext context, {required LcDocument Function() doc, required LcEdit onEdit, required void Function(String pageId) onOpen}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => PagesSheet(doc: doc, onEdit: onEdit, onOpen: onOpen),
);
