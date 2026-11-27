/// 顶部导航栏跨页共用（第四轮 B3；设计见 docs/blocks-v5-parts/E-editor-components.md §10.11）。办法照底部导航那一套（nav_shared.dart）。
///
/// 规矩：
/// - 页面文件最外层的 `shared.topBar` 是**唯一的一份**：样子（居左 / 居中、固定顶部、背景、文字颜色）、样式、各屏宽的差别、绑定，
///   外加“默认的”标题、返回箭头、左右两边放的控件（`children`）。
/// - 哪一页要显示它，就在那一页的树里放一个带 `shared: true` 的顶部导航栏节点。
/// - 每一页可以有三样自己的东西：标题、返回箭头、左右按钮。哪几样是这一页自己的，记在节点的 `own` 里
///   （`["title", "back", "slots"]` 的子集）。文件里这个节点只写 id / 名字这些记号、`own`，和 `own` 里那几样的值
///   （`props.title` / `props.back` / `children`）；别的都在最外层那一份里。
/// - 内存里每一页的这个节点照常带着全部内容（读文件时填上），画布、面板、四种导出都把它当普通的顶部导航栏。
///   每次写文件 / 记撤销之前调 [lcSettleSharedTop]：把“刚被改过的那一条”里**不是这一页自己的**部分抄给别的页；
///   别的页自己的那几样不动。同步点只有这一个。
/// - 共用的左右控件抄到各页时 id 不变（一页之内撞了才换新的）：所以各页给它接的逻辑不会因为同步丢掉。
/// - 没用共用顶栏的文件：没有 `shared.topBar`、节点上没有 `shared`，存出来和以前逐字节一样。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';

/// 一页可以自己说了算的三样。
const List<String> kLcTopOwnKeys = ['title', 'back', 'slots'];
const Map<String, String> kLcTopOwnLabels = {'title': '标题', 'back': '返回箭头', 'slots': '左右按钮'};

bool lcIsSharedTop(LcNode n) => n.type == 'appBar' && n.more['shared'] == true;

/// 这一页自己说了算的是哪几样。
Set<String> lcTopOwn(LcNode n) {
  final raw = n.more['own'];
  return {
    if (raw is List)
      for (final k in raw)
        if (kLcTopOwnKeys.contains(k)) k as String,
  };
}

void _setOwn(LcNode n, Set<String> own) {
  if (own.isEmpty) {
    n.more.remove('own');
  } else {
    n.more['own'] = [
      for (final k in kLcTopOwnKeys)
        if (own.contains(k)) k,
    ];
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> m) => m.isEmpty ? <String, dynamic>{} : jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 这一页里用着共用顶栏的节点（一般就一个）。
List<LcNode> lcSharedTopsIn(LcNode root) {
  final out = <LcNode>[];
  _walk(root, (n) {
    if (lcIsSharedTop(n)) out.add(n);
  });
  return out;
}

/// 这一页里的顶部导航栏（不管共不共用），按树里的先后。
List<LcNode> lcTopsIn(LcNode root) {
  final out = <LcNode>[];
  _walk(root, (n) {
    if (n.type == 'appBar') out.add(n);
  });
  return out;
}

List<Object?> _kidsJson(LcNode n) => [for (final c in n.children) jsonDecode(jsonEncode(c.toJson()))];

/// 去掉 id 再比：两页的左右按钮“长得一样”就算一样。
Object? _noIds(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (e.key != 'id') e.key: _noIds(e.value),
    };
  }
  return v is List ? [for (final x in v) _noIds(x)] : v;
}

/// 整条的内容（共用的那一份长这样）。
Map<String, dynamic> lcTopContent(LcNode n) => {
  'props': {...n.keptProps, ...n.props},
  if (n.style.isNotEmpty) 'style': Map<String, dynamic>.of(n.style),
  for (final k in kLcSharedNavMoreKeys)
    if (n.more[k] != null) k: n.more[k],
  if (n.children.isNotEmpty) 'children': _kidsJson(n),
};

/// 两条顶栏在 [key] 这一样上是不是一样。
bool lcTopSame(Map<String, dynamic> a, Map<String, dynamic> b, String key) => switch (key) {
  'slots' => jsonEncode(_noIds(a['children'] ?? const [])) == jsonEncode(_noIds(b['children'] ?? const [])),
  _ => jsonEncode((a['props'] as Map?)?[key]) == jsonEncode((b['props'] as Map?)?[key]),
};

/// 除了三样“每页可以自己定”的以外，两条是不是一样。
bool _sameRest(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, dynamic> rest(Map<String, dynamic> m) => {
    for (final e in m.entries)
      if (e.key == 'props')
        'props': {
          for (final p in (e.value as Map).entries)
            if (p.key != 'title' && p.key != 'back') p.key: p.value,
        }
      else if (e.key != 'children')
        e.key: e.value,
  };
  return jsonEncode(rest(a)) == jsonEncode(rest(b));
}

List<LcNode> _kidsFrom(Object? raw, LcNode page, LcNode host) {
  final taken = <String>{};
  _walk(page, (n) => taken.add(n.id));
  _walk(host, (n) {
    if (!identical(n, host)) taken.remove(n.id);
  });
  final out = <LcNode>[];
  for (final c in raw is List ? raw : const <Object?>[]) {
    if (c is! Map<String, dynamic>) continue;
    try {
      out.add(LcNode.fromJson(_copy(c), 1));
    } on FormatException {
      continue; // 读不出来的一个：跳过，不让整条顶栏坏掉
    }
  }
  var extra = 0;
  for (final k in out) {
    _walk(k, (n) {
      if (n.id.isEmpty || !taken.add(n.id)) {
        while (!taken.add('${host.id}_t$extra')) {
          extra++;
        }
        n.id = '${host.id}_t$extra';
      }
    });
  }
  return out;
}

/// 把共用的内容 [content] 填进节点 [n]（它在 [page] 这一页的树里）。这一页自己的那几样不动。
void lcFillSharedTop(LcNode n, Map<String, dynamic> content, LcNode page) {
  final own = lcTopOwn(n);
  final mine = {
    for (final k in const ['title', 'back'])
      if (own.contains(k) && n.props.containsKey(k)) k: n.props[k],
  };
  final node = LcNode.fromJson({'id': n.id, 'type': 'appBar', 'props': content['props'] ?? const <String, dynamic>{}, 'style': content['style']}, 0);
  n.props
    ..clear()
    ..addAll(node.props);
  n.keptProps
    ..clear()
    ..addAll(node.keptProps);
  for (final k in const ['title', 'back']) {
    if (!own.contains(k)) continue;
    mine.containsKey(k) ? n.props[k] = mine[k] : n.props.remove(k);
  }
  n.style
    ..clear()
    ..addAll(node.style);
  for (final k in kLcSharedNavMoreKeys) {
    final v = content[k];
    if (v == null) {
      n.more.remove(k);
    } else {
      n.more[k] = jsonDecode(jsonEncode(v));
    }
  }
  if (!own.contains('slots')) {
    final kids = _kidsFrom(content['children'], page, n);
    n.children
      ..clear()
      ..addAll(kids);
  }
}

Map<String, dynamic> _defaultContent() => {'props': jsonDecode(jsonEncode(lcSpecs['appBar']!.defaults)) as Map<String, dynamic>};

/// 读文件之后调一次：把最外层那一份填进各页带 `shared: true` 的顶栏节点。
/// 容错：有节点带记号却没有最外层那一份——取第一个自己带着 props 的当那一份，都没有就用默认的。
void lcMaterializeSharedTop(LcDocument doc) {
  final raw = doc.sharedTop;
  Map<String, dynamic>? content = raw == null ? null : _copy(raw);
  final users = <(LcNode, LcPage)>[
    for (final p in doc.pages)
      for (final n in lcSharedTopsIn(p.root)) (n, p),
  ];
  if (users.isEmpty) return;
  if (content == null) {
    final full = users.where((u) => u.$1.props.length > lcTopOwn(u.$1).length).firstOrNull;
    content = full == null ? _defaultContent() : lcTopContent(full.$1);
    doc.sharedTop = content;
  }
  for (final (n, p) in users) {
    lcFillSharedTop(n, content, p.root);
  }
}

/// 写文件 / 记撤销之前调：以“刚被改过的那一条”（当前页上的；当前页没有就取第一页有的）为准，
/// 它身上不是自己的那几样连同样子、样式定成共用的那一份，抄给别的页。
void lcSettleSharedTop(LcDocument doc) {
  final old = doc.sharedTop;
  if (old == null) {
    for (final p in doc.pages) {
      for (final n in lcSharedTopsIn(p.root)) {
        n.more
          ..remove('shared')
          ..remove('own');
      }
    }
    return;
  }
  LcNode? source = lcSharedTopsIn(doc.page.root).firstOrNull;
  if (source == null) {
    for (final p in doc.pages) {
      source = lcSharedTopsIn(p.root).firstOrNull;
      if (source != null) break;
    }
  }
  if (source == null) return;
  final own = lcTopOwn(source);
  final content = _copy(lcTopContent(source));
  final props = content['props'] as Map<String, dynamic>, oldProps = old['props'];
  for (final k in const ['title', 'back']) {
    if (!own.contains(k)) continue;
    final was = oldProps is Map ? oldProps[k] : null;
    was == null ? props.remove(k) : props[k] = was;
  }
  if (own.contains('slots')) {
    old['children'] == null ? content.remove('children') : content['children'] = jsonDecode(jsonEncode(old['children']));
  }
  doc.sharedTop = content;
  for (final p in doc.pages) {
    for (final n in lcSharedTopsIn(p.root)) {
      if (!identical(n, source)) lcFillSharedTop(n, content, p.root);
    }
  }
}

/// 存盘用：把一页的 JSON 里带 `shared: true` 的顶栏节点削成只剩自己的记号和自己的那几样。
void lcStripSharedTopJson(Map<String, dynamic> node) {
  if (node['type'] == 'appBar' && node['shared'] == true) {
    final rawOwn = node['own'];
    final own = {if (rawOwn is List) ...rawOwn};
    final props = node['props'];
    final mine = {
      for (final k in const ['title', 'back'])
        if (own.contains(k) && props is Map && props.containsKey(k)) k: props[k],
    };
    mine.isEmpty ? node.remove('props') : node['props'] = mine;
    node.remove('style');
    for (final k in kLcSharedNavMoreKeys) {
      node.remove(k);
    }
    if (!own.contains('slots')) node.remove('children');
    return;
  }
  final kids = node['children'];
  if (kids is List) {
    for (final k in kids) {
      if (k is Map<String, dynamic>) lcStripSharedTopJson(k);
    }
  }
}

int lcSharedTopPageCount(LcDocument doc) => doc.pages.where((p) => lcSharedTopsIn(p.root).isNotEmpty).length;

bool lcPageShowsSharedTop(LcPage page) => lcSharedTopsIn(page.root).isNotEmpty;

LcNode _newShared(LcDocument doc, LcPage page, Map<String, dynamic> content) {
  // 新加到一页上的：标题先用这一页的名字（算这一页自己的），别的跟共用的走。
  final n = doc.newNode('appBar')
    ..more['shared'] = true
    ..more['own'] = ['title'];
  lcFillSharedTop(n, content, page.root);
  n.props['title'] = page.title;
  return n;
}

/// 让 [pageId] 这一页显示 / 不显示共用的那一条。显示＝放在页面最前面；不显示＝把这一页用着它的节点拿掉（连带清掉逻辑里对它和它里面控件的引用）。
bool lcSetPageShowsSharedTop(LcDocument doc, String pageId, bool show) {
  final page = doc.pageById(pageId);
  final content = doc.sharedTop;
  if (page == null || content == null) return false;
  final there = lcSharedTopsIn(page.root);
  if (show == there.isNotEmpty) return false;
  if (show) {
    page.root.children.insert(0, _newShared(doc, page, _copy(content)));
    return true;
  }
  void drop(LcNode parent) {
    parent.children.removeWhere((c) {
      if (!lcIsSharedTop(c)) return false;
      _walk(c, (n) => page.logic.removeNodeRefs(n.id));
      return true;
    });
    parent.children.forEach(drop);
  }

  drop(page.root);
  return true;
}

/// 这一页的 [key]（标题 / 返回箭头 / 左右按钮）用自己的还是跟共用的走。改成跟共用的走时，这一页自己的那份换成共用的。
bool lcSetTopOwn(LcDocument doc, LcNode n, String key, bool mine) {
  final content = doc.sharedTop;
  if (!lcIsSharedTop(n) || content == null || !kLcTopOwnKeys.contains(key)) return false;
  final own = lcTopOwn(n);
  if (own.contains(key) == mine) return false;
  if (mine) {
    _setOwn(n, {...own, key});
    return true;
  }
  if (key == 'slots') {
    final page = doc.pages.where((p) => lcSharedTopsIn(p.root).any((x) => identical(x, n))).firstOrNull;
    if (page != null) _walk(n, (c) => identical(c, n) ? null : page.logic.removeNodeRefs(c.id));
  }
  _setOwn(n, {...own}..remove(key));
  // 先把共用的那一份填回来，再让同步点看到的“刚改过的那一条”就是共用的样子。
  final page = doc.pages.where((p) => lcSharedTopsIn(p.root).any((x) => identical(x, n))).firstOrNull;
  lcFillSharedTop(n, _copy(content), page?.root ?? doc.root);
  return true;
}

/// “改成共用”会动哪些页。
class LcShareTopPlan {
  const LcShareTopPlan({required this.replaced, required this.keeps, required this.differs});

  /// 已经有顶部导航栏、会被换成共用那一条的页（不含作准的那一页）。
  final List<LcPage> replaced;

  /// 被换掉的页里，各自会留下哪几样自己的（页 id → 标题 / 返回箭头 / 左右按钮）。
  final Map<String, Set<String>> keeps;

  /// 被换掉的页里，有没有样子（背景、颜色、居左居中、样式…）和作准的那一条不一样的——这些会被换掉。
  final bool differs;
}

/// 各页的第一条顶部导航栏：（页，节点）。
List<(LcPage, LcNode)> lcTopCandidates(LcDocument doc) => [
  for (final p in doc.pages)
    if (lcTopsIn(p.root).firstOrNull case final n?) (p, n),
];

LcShareTopPlan? lcShareTopPlan(LcDocument doc, String basePageId) {
  final base = lcTopCandidates(doc).where((c) => c.$1.id == basePageId).firstOrNull;
  if (base == null) return null;
  final baseContent = lcTopContent(base.$2);
  final replaced = <LcPage>[];
  final keeps = <String, Set<String>>{};
  var differs = false;
  for (final (p, n) in lcTopCandidates(doc)) {
    if (p.id == basePageId) continue;
    replaced.add(p);
    final c = lcTopContent(n);
    keeps[p.id] = {
      for (final k in kLcTopOwnKeys)
        if (!lcTopSame(c, baseContent, k)) k,
    };
    if (!_sameRest(c, baseContent)) differs = true;
  }
  return LcShareTopPlan(replaced: replaced, keeps: keeps, differs: differs);
}

/// 各页顶栏的样子（除了标题、返回箭头、左右按钮）是不是都一样。
bool lcTopsAllSame(LcDocument doc) {
  final all = [for (final (_, n) in lcTopCandidates(doc)) lcTopContent(n)];
  return all.every((c) => _sameRest(c, all.first));
}

/// 改成共用：以 [basePageId] 那一页的第一条顶栏为准。别的页已有的第一条换成共用的——它的标题、返回箭头、左右按钮和作准的不一样的，留成那一页自己的。
/// 没有顶栏的页不加（要显示：右上角“页面”› 那一页的 ⋮）。返回用上它的页数（0＝没做成）。
int lcShareTop(LcDocument doc, String basePageId) {
  final plan = lcShareTopPlan(doc, basePageId);
  if (plan == null) return 0;
  final base = lcTopCandidates(doc).firstWhere((c) => c.$1.id == basePageId).$2;
  final content = _copy(lcTopContent(base));
  doc.sharedTop = content;
  for (final (p, n) in lcTopCandidates(doc)) {
    n.more['shared'] = true;
    _setOwn(n, plan.keeps[p.id] ?? const {});
    if (!identical(n, base)) lcFillSharedTop(n, content, p.root);
  }
  return 1 + plan.replaced.length;
}

/// 取消共用：每一页留着现在的样子，变回各页自己的一条。返回动了几页。
int lcUnshareTop(LcDocument doc) {
  var pages = 0;
  for (final p in doc.pages) {
    final tops = lcSharedTopsIn(p.root);
    if (tops.isNotEmpty) pages++;
    for (final n in tops) {
      n.more
        ..remove('shared')
        ..remove('own');
    }
  }
  doc.sharedTop = null;
  return pages;
}

/// 新放进当前页的一条顶栏 [node]：项目里已经有共用的那一条、这一页又还没显示它——那它就是共用的那一条（标题先用这一页的名字）。
/// 在把 [node] 插进树**之前**调。
void lcAdoptNewTop(LcDocument doc, LcNode node) {
  if (node.type != 'appBar' || lcIsSharedTop(node)) return;
  final content = doc.sharedTop;
  if (content == null || lcPageShowsSharedTop(doc.page)) return;
  node.more['shared'] = true;
  node.more['own'] = ['title'];
  lcFillSharedTop(node, _copy(content), doc.page.root);
  node.props['title'] = doc.page.title;
}
