/// 多页面（第 4 期）：一个项目有几页、哪页是首页、当前在编辑哪页，以及新建 / 复制 / 删除 / 排序 / 设为首页。
/// 设计见 docs/blocks-v5-parts/E-editor-components.md §10.6；文件里怎么写见 docs/lowcode-page-format-v3.md。
///
/// 要点：
/// - 所有页面都在同一个 `page.lc.json` 里。**首页永远是最外层的 title / root / logic**，别的页在最外层的 `pages` 里；
///   所以只有一页的文件和以前逐字节一样，老版本应用也至少能打开首页。
/// - 内存里 [LcDocument.pages] 是全部页面（第一个是首页）；[LcDocument.root] / `title` / `logic` 指的是“当前在编辑的那页”，
///   编辑器别的地方不用知道有多页面。
/// - 节点 id 只要求**每页之内**唯一；页面 id（`p1`、`p2`…）整份文件唯一，“去页面”积木和底部导航项存的就是它。
/// - 自定义组件是**项目级**的（[LcDocument.components] 所有页面共用）。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 一个项目最多这么多页（页面清单是一屏内能翻完的长度；导出的文件数也有个头）。
const int kLcMaxPages = 30;

/// 首页没写 id 时就是它（只有一页的旧文件都没写）。
const String kLcFirstPageId = 'p1';

final RegExp _pageId = RegExp(r'^[A-Za-z0-9_]{1,24}$');

/// 一页：名字、组件树、这一页自己的逻辑。
class LcPage {
  LcPage({required this.id, required this.title, required this.root, LcLogic? logic, Map<String, dynamic>? more}) : logic = logic ?? LcLogic(), more = more ?? {};

  /// 这一版会读的字段；别的原样留在 [more] 里。
  static const Set<String> knownKeys = {'id', 'title', 'root', 'logic'};

  String id;
  String title;
  LcNode root;
  final LcLogic logic;

  /// 页面对象上这一版看不懂的字段：不解释，原样留着。
  final Map<String, dynamic> more;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'root': root.toJson(), if (!logic.isEmpty) 'logic': logic.toJson(), ...more};

  /// 读不出来（不是对象、没有 root、root 不是 page）返回 null：这一项原样留着，不让整份文件打不开。
  static LcPage? tryParse(Object? json, {required int version}) {
    if (json is! Map<String, dynamic>) return null;
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) return null;
    final LcNode root;
    try {
      root = LcNode.fromJson(rootJson, 0, version: version);
    } on FormatException {
      return null;
    }
    if (root.type != 'page') return null;
    final id = json['id'], title = json['title'];
    return LcPage(
      id: id is String ? id : '',
      title: title is String ? title : '未命名页面',
      root: root,
      logic: LcLogic.fromJson(json['logic']),
      more: {
        for (final e in json.entries)
          if (!knownKeys.contains(e.key) && e.value != null) e.key: e.value,
      },
    );
  }

  /// 深拷贝一份（id 由调用的人另给）。
  LcPage copyAs(String id, String title) => LcPage(
    id: id,
    title: title,
    root: root.clone(),
    logic: LcLogic.fromJson(jsonDecode(jsonEncode(logic.toJson())))..loaded = logic.loaded,
    more: jsonDecode(jsonEncode(more)) as Map<String, dynamic>,
  );
}

/// 页面 id 缺了 / 写法不对 / 重了，补成 `p数字`（文档每次建好时调）。
void lcNormalizePageIds(List<LcPage> pages) {
  final seen = <String>{};
  // 先让写得对的占住自己的 id，再给不对的发新的：免得坏的那个抢了后面好的那个的 id。
  for (final p in pages) {
    if (_pageId.hasMatch(p.id) && !seen.contains(p.id)) {
      seen.add(p.id);
    } else {
      p.id = '';
    }
  }
  for (final p in pages) {
    if (p.id.isEmpty) p.id = lcFreshPageId(seen);
  }
}

/// 一个没人用的 `p数字`（顺手登记进 [taken]）。
String lcFreshPageId(Set<String> taken) {
  var n = 1;
  while (taken.contains('p$n')) {
    n++;
  }
  taken.add('p$n');
  return 'p$n';
}

String _cleanTitle(String title) {
  final t = title.replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ').trim();
  final runes = t.runes.toList();
  return runes.isEmpty ? '未命名页面' : String.fromCharCodes(runes.take(kLcMaxPageTitle));
}

/// 页面名字最多这么多个字（清单里一行放得下、导出时当网页标题也不离谱）。
const int kLcMaxPageTitle = 30;

/// 页面清单上的操作。都不动“当前在编辑哪页”以外的东西；做不了返回 false / null。
extension LcDocumentPages on LcDocument {
  bool get isMultiPage => pages.length > 1;

  LcPage? pageById(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 页面在界面上叫什么；已经不在了返回 null。
  String? pageTitle(String id) => pageById(id)?.title;

  bool get canAddPage => pages.length < kLcMaxPages;

  /// 一个不和现有页面重名的名字：`页面 2`、`页面 3`…
  String freshPageTitle([String base = '页面']) {
    final used = {for (final p in pages) p.title};
    var n = pages.length + 1;
    while (used.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  /// 新建一张空白页（排在最后），返回它的 id；满了返回 null。
  String? addPage([String? title]) {
    if (!canAddPage) return null;
    final id = lcFreshPageId({for (final p in pages) p.id});
    pages.add(
      LcPage(
        id: id,
        title: _cleanTitle(title ?? freshPageTitle()),
        root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults)),
      ),
    );
    return id;
  }

  /// 复制一页（紧跟在原来那页后面），返回新页的 id。组件树、逻辑照抄；节点 id 不用换（每页各算各的）。
  String? duplicatePage(String id) {
    final i = pages.indexWhere((p) => p.id == id);
    if (i < 0 || !canAddPage) return null;
    final newId = lcFreshPageId({for (final p in pages) p.id});
    final keep = pageIndex;
    pages.insert(i + 1, pages[i].copyAs(newId, _cleanTitle('${pages[i].title} 副本')));
    if (keep > i) openPageAt(keep + 1);
    return newId;
  }

  bool renamePage(String id, String title) {
    final p = pageById(id);
    final t = _cleanTitle(title);
    if (p == null || p.title == t) return false;
    p.title = t;
    return true;
  }

  /// 还有几处指着这一页（别的页里的“去页面”积木 + 各页底部导航的项）。删之前问一句用。
  int pageRefCount(String id) {
    var n = 0;
    for (final p in pages) {
      if (p.id == id) continue;
      for (final h in p.logic.handlers) {
        h.visitBlocks((b, _) {
          if (b.op == kLcGoPageOp && b.args['page'] == id) n++;
        });
      }
      _navItems(p.root, (item) {
        if (item['page'] == id) n++;
      });
    }
    return n;
  }

  /// 删一页。只剩一页时不能删。指着它的“去页面”积木、底部导航项**不跟着删**：留着，校验会标出来“页面已经不在了”，
  /// 导出时那一下不跳（这样撤销 / 改指别的页都方便）。删的是首页时，下一页顶上来当首页。
  bool removePage(String id) {
    final i = pages.indexWhere((p) => p.id == id);
    if (i < 0 || pages.length <= 1) return false;
    final keep = pageIndex;
    pages.removeAt(i);
    openPageAt(keep > i ? keep - 1 : keep.clamp(0, pages.length - 1));
    return true;
  }

  /// 把一页挪到清单的第 [to] 位（0＝首页）。当前在编辑的那页不变。
  bool movePage(String id, int to) {
    final i = pages.indexWhere((p) => p.id == id);
    final j = to.clamp(0, pages.length - 1);
    if (i < 0 || i == j) return false;
    final current = page;
    pages.insert(j, pages.removeAt(i));
    openPageAt(pages.indexOf(current));
    return true;
  }

  /// 设为首页＝挪到第一位。
  bool setHomePage(String id) => movePage(id, 0);

  /// 所有页面的根（给“要扫全项目”的操作用：自定义组件的插槽改名 / 删除、统计用了几处…）。
  Iterable<LcNode> get allRoots => [for (final p in pages) p.root];
}

/// 导出时这一页的文件叫什么（不带后缀）：首页是 `index`，别的页是 `page-<页面 id>`。
/// 页面 id 只有字母、数字、下划线，直接当文件名安全；带 `page-` 前缀所以不会和 index / style / logic 撞。
String lcPageFileBase(LcDocument doc, String pageId) => doc.pages.first.id == pageId ? 'index' : 'page-$pageId';

/// “去页面”积木的名字（参数 `page`＝页面 id）。
const String kLcGoPageOp = 'goPage';

void _navItems(LcNode n, void Function(Map<Object?, Object?> item) visit) {
  if (n.type == 'bottomNav') {
    final items = n.props['items'];
    if (items is List) {
      for (final x in items) {
        if (x is Map) visit(x);
      }
    }
  }
  for (final c in n.children) {
    _navItems(c, visit);
  }
}

/// 只看其中一页的一份副本：导出每一页时用（各导出器只认“当前页”）。和原文档互不影响。
LcDocument lcPageView(LcDocument doc, int index) => lcDocCopy(doc)..openPageAt(index);

/// 整份深拷贝。每一页挂着的积木库（不存盘的那一格 `loaded`）照样带过去：不带的话，导出时用了自己的库的页面会说“项目里找不到它”。
LcDocument lcDocCopy(LcDocument doc) {
  final copy = LcDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
  for (final p in copy.pages) {
    p.logic.loaded = (doc.pageById(p.id) ?? doc.pages.first).logic.loaded;
  }
  return copy;
}
