/// 底部导航栏跨页**真共用**（第四轮 B1；设计见 docs/blocks-v5-parts/E-editor-components.md §10.9）。
///
/// 规矩：
/// - 页面文件最外层的 `shared.bottomNav` 是**唯一的一份**（导航项、样子、样式、按下时的样式、各屏宽的差别、绑定）。
/// - 哪一页要显示它，就在那一页的树里放一个带 `shared: true` 的底部导航栏节点。文件里这个节点**只有 id / 名字这些自己的记号**，
///   不写 props / style——内容都在最外层那一份里。没放这个节点的页＝“这一页不显示底部导航”。
/// - “当前项”不存：哪一项的“点了去”指着这一页，这一页上就亮哪一项（没有哪一项指着它就亮第一项）。
/// - 内存里每一页的这个节点照常带着全部内容（读文件时填上），所以画布、面板、四种导出都把它当普通导航栏，不用另学一套。
///   每次写文件 / 记撤销之前（[LcDocument.toJson] 里）调 [lcSettleSharedNav]：把“刚被改过的那一条”抄给别的页。
///   “刚被改过的”＝当前页上那一条；当前页没有就取第一页有的那一条（这时各页的本来就一样）。
/// - 没用共用导航的文件：没有 `shared`、节点上没有 `shared`，存出来和以前逐字节一样。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_sync.dart';

/// 节点上除了 props / style 以外，跟着共用的那一份走的字段。别的（名字、锁定、隐藏、放在哪个插槽、看不懂的字段）各页留各页的。
const List<String> kLcSharedNavMoreKeys = ['states', 'responsive', 'data', 'showIf', 'renderIf', 'classIf', 'styles'];

/// 这个节点用的是不是共用的那一条底部导航。
bool lcIsSharedNav(LcNode n) => n.type == 'bottomNav' && n.more['shared'] == true;

Map<String, dynamic> _copy(Map<String, dynamic> m) => m.isEmpty ? <String, dynamic>{} : jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 这一页里用着共用导航的节点（一般就一个）。
List<LcNode> lcSharedNavsIn(LcNode root) {
  final out = <LcNode>[];
  _walk(root, (n) {
    if (lcIsSharedNav(n)) out.add(n);
  });
  return out;
}

/// 这一页里的底部导航栏（不管共不共用），按树里的先后。
List<LcNode> lcNavsIn(LcNode root) {
  final out = <LcNode>[];
  _walk(root, (n) {
    if (n.type == 'bottomNav') out.add(n);
  });
  return out;
}

/// 共用的那一份长什么样（不带“当前项”）。两条导航栏这个值一样＝内容一样。
Map<String, dynamic> lcNavContent(LcNode n) => {
  'props': {
    for (final e in {...n.keptProps, ...n.props}.entries)
      if (e.key != 'current') e.key: e.value,
  },
  if (n.style.isNotEmpty) 'style': Map<String, dynamic>.of(n.style),
  for (final k in kLcSharedNavMoreKeys)
    if (n.more[k] != null) k: n.more[k],
};

/// [pageId] 这一页上该亮第几项。
int lcNavCurrentFor(LcNode nav, String pageId) {
  final i = lcObjects(nav, 'items').indexWhere((m) => lcNavItemPage(m) == pageId);
  return i < 0 ? 0 : i;
}

/// 把共用的内容 [content] 填进节点 [n]（它在 [pageId] 这一页上）。
void lcFillSharedNav(LcNode n, Map<String, dynamic> content, String pageId) {
  final node = LcNode.fromJson({'id': n.id, 'type': 'bottomNav', 'props': content['props'] ?? const <String, dynamic>{}, 'style': content['style']}, 0);
  n.props
    ..clear()
    ..addAll(node.props);
  n.keptProps
    ..clear()
    ..addAll(node.keptProps);
  n.style
    ..clear()
    ..addAll(node.style);
  for (final k in kLcSharedNavMoreKeys) {
    final v = content[k];
    if (v == null) {
      n.more.remove(k);
    } else {
      n.more[k] = v is Map<String, dynamic> ? _copy(v) : jsonDecode(jsonEncode(v));
    }
  }
  n.props['current'] = lcNavCurrentFor(n, pageId);
}

/// 默认的一份（文件里有 `shared: true` 的节点、却没有最外层那一份时用）。
Map<String, dynamic> _defaultContent() => {
  'props': {
    for (final e in (jsonDecode(jsonEncode(lcSpecs['bottomNav']!.defaults)) as Map<String, dynamic>).entries)
      if (e.key != 'current') e.key: e.value,
  },
};

/// 读文件之后调一次：把最外层那一份填进各页带 `shared: true` 的节点。
///
/// 容错：有节点带 `shared: true` 却没有最外层那一份（手写的、Agent 写的）——取第一个自己带着 props 的这种节点当那一份，都没有就用默认的。
void lcMaterializeSharedNav(LcDocument doc) {
  final raw = doc.sharedNav;
  Map<String, dynamic>? content = raw == null ? null : _copy(raw);
  final users = <(LcNode, String)>[
    for (final p in doc.pages)
      for (final n in lcSharedNavsIn(p.root)) (n, p.id),
  ];
  if (users.isEmpty) return;
  if (content == null) {
    final own = users.where((u) => u.$1.props.isNotEmpty).firstOrNull;
    content = own == null ? _defaultContent() : lcNavContent(own.$1);
    doc.sharedNav = content;
  }
  for (final (n, pageId) in users) {
    lcFillSharedNav(n, content, pageId);
  }
}

/// 写文件 / 记撤销之前调：把“刚被改过的那一条”定成共用的那一份，抄给每一页用着它的节点，各页的“当前项”重新算。
/// 没有哪一页在用时，最外层那一份原样留着（“每页都不显示”不等于“不要了”）。
void lcSettleSharedNav(LcDocument doc) {
  if (doc.sharedNav == null) {
    // 没有共用的那一份：节点上的记号不算数（比如把共用的那条粘贴进了另一个项目）。
    for (final p in doc.pages) {
      for (final n in lcSharedNavsIn(p.root)) {
        n.more.remove('shared');
      }
    }
    return;
  }
  LcNode? source = lcSharedNavsIn(doc.page.root).firstOrNull;
  if (source == null) {
    for (final p in doc.pages) {
      source = lcSharedNavsIn(p.root).firstOrNull;
      if (source != null) break;
    }
  }
  if (source == null) return;
  final content = _copy(lcNavContent(source));
  doc.sharedNav = content;
  for (final p in doc.pages) {
    for (final n in lcSharedNavsIn(p.root)) {
      lcFillSharedNav(n, content, p.id);
    }
  }
}

/// 存盘用：把一页的 JSON 里带 `shared: true` 的导航栏节点削成只剩自己的记号。
void lcStripSharedNavJson(Map<String, dynamic> node) {
  if (node['type'] == 'bottomNav' && node['shared'] == true) {
    node.remove('props');
    node.remove('style');
    for (final k in kLcSharedNavMoreKeys) {
      node.remove(k);
    }
  }
  final kids = node['children'];
  if (kids is List) {
    for (final k in kids) {
      if (k is Map<String, dynamic>) lcStripSharedNavJson(k);
    }
  }
}

/// 有几页在用共用的那一条。
int lcSharedNavPageCount(LcDocument doc) => doc.pages.where((p) => lcSharedNavsIn(p.root).isNotEmpty).length;

/// 这一页显不显示共用的那一条。
bool lcPageShowsSharedNav(LcPage page) => lcSharedNavsIn(page.root).isNotEmpty;

/// 让 [pageId] 这一页显示 / 不显示共用的那一条。显示＝在页面最后放一个；不显示＝把这一页用着它的节点拿掉（连带清掉这一页逻辑里对它的引用）。
/// 返回有没有改动。
bool lcSetPageShowsSharedNav(LcDocument doc, String pageId, bool show) {
  final page = doc.pageById(pageId);
  final content = doc.sharedNav;
  if (page == null || content == null) return false;
  final there = lcSharedNavsIn(page.root);
  if (show == there.isNotEmpty) return false;
  if (show) {
    final n = doc.newNode('bottomNav')..more['shared'] = true;
    lcFillSharedNav(n, _copy(content), page.id);
    page.root.children.add(n);
    return true;
  }
  void drop(LcNode parent) {
    parent.children.removeWhere((c) {
      if (!lcIsSharedNav(c)) return false;
      page.logic.removeNodeRefs(c.id);
      return true;
    });
    parent.children.forEach(drop);
  }

  drop(page.root);
  return true;
}

/// “改成共用”会动哪些页。
class LcShareNavPlan {
  const LcShareNavPlan({required this.replaced, required this.added, required this.differs});

  /// 已经有底部导航栏、会被换成共用那一条的页（不含作准的那一页）。
  final List<LcPage> replaced;

  /// 本来没有、因为导航项指着它所以会加上的页。
  final List<LcPage> added;

  /// 被换掉的那些页里，有没有和作准的那一条内容不一样的。
  final bool differs;
}

/// 项目里各页的第一条底部导航栏：（页，节点）。“改成共用”时从里面挑一页作准。
List<(LcPage, LcNode)> lcNavCandidates(LcDocument doc) => [
  for (final p in doc.pages)
    if (lcNavsIn(p.root).firstOrNull case final n?) (p, n),
];

/// 以 [basePageId] 那一页的导航栏为准改成共用，会动哪些页。那一页没有导航栏返回 null。
LcShareNavPlan? lcShareNavPlan(LcDocument doc, String basePageId) {
  final base = lcNavCandidates(doc).where((c) => c.$1.id == basePageId).firstOrNull;
  if (base == null) return null;
  final baseContent = jsonEncode(lcNavContent(base.$2));
  final replaced = <LcPage>[], added = <LcPage>[];
  var differs = false;
  for (final (p, n) in lcNavCandidates(doc)) {
    if (p.id == basePageId) continue;
    replaced.add(p);
    if (jsonEncode(lcNavContent(n)) != baseContent) differs = true;
  }
  for (final item in lcObjects(base.$2, 'items')) {
    final p = doc.pageById(lcNavItemPage(item) ?? '');
    if (p != null && p.id != basePageId && !replaced.contains(p) && !added.contains(p)) added.add(p);
  }
  return LcShareNavPlan(replaced: replaced, added: added, differs: differs);
}

/// 各页的导航栏内容是不是都一样（都一样时“改成共用”不用问以哪一页为准）。
bool lcNavsAllSame(LcDocument doc) => {for (final (_, n) in lcNavCandidates(doc)) jsonEncode(lcNavContent(n))}.length <= 1;

/// 改成共用：以 [basePageId] 那一页的第一条导航栏为准。已经有导航栏的页，第一条换成共用的；导航项指着、却没有导航栏的页，在最后加一条。
/// 返回用上它的页数（0＝没做成）。
int lcShareNav(LcDocument doc, String basePageId) {
  final plan = lcShareNavPlan(doc, basePageId);
  if (plan == null) return 0;
  final base = lcNavCandidates(doc).firstWhere((c) => c.$1.id == basePageId).$2;
  final content = _copy(lcNavContent(base));
  doc.sharedNav = content;
  for (final (p, n) in lcNavCandidates(doc)) {
    n.more['shared'] = true;
    lcFillSharedNav(n, content, p.id);
  }
  for (final p in plan.added) {
    final n = doc.newNode('bottomNav')..more['shared'] = true;
    lcFillSharedNav(n, content, p.id);
    p.root.children.add(n);
  }
  return 1 + plan.replaced.length + plan.added.length;
}

/// 取消共用：每一页用着它的节点变回这一页自己的一条（内容留着当时的样子），最外层那一份去掉。返回动了几页。
int lcUnshareNav(LcDocument doc) {
  var pages = 0;
  for (final p in doc.pages) {
    final navs = lcSharedNavsIn(p.root);
    if (navs.isNotEmpty) pages++;
    for (final n in navs) {
      n.more.remove('shared');
    }
  }
  doc.sharedNav = null;
  return pages;
}

/// 新放进当前页的一条导航栏 [node]：项目里已经有共用的那一条、这一页又还没显示它——那它就是共用的那一条；
/// 项目不止一页、哪一页都还没有导航栏——它从一开始就是共用的。别的情况是这一页自己的一条。
/// 在把 [node] 插进树**之前**调。
void lcAdoptNewNav(LcDocument doc, LcNode node) {
  if (node.type != 'bottomNav' || lcIsSharedNav(node)) return;
  final content = doc.sharedNav;
  if (content != null) {
    if (lcPageShowsSharedNav(doc.page)) return;
    node.more['shared'] = true;
    lcFillSharedNav(node, _copy(content), doc.page.id);
  } else if (doc.isMultiPage && lcNavCandidates(doc).isEmpty) {
    node.more['shared'] = true;
    doc.sharedNav = _copy(lcNavContent(node));
  }
}
