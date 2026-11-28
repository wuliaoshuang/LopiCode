import 'dart:convert';

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model_pages.dart';
import 'package:lopicode/lowcode/model_props.dart';
import 'package:lopicode/lowcode/model_specs.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/top_shared.dart';

export 'package:lopicode/lowcode/model_history.dart';
export 'package:lopicode/lowcode/model_pages.dart';
export 'package:lopicode/lowcode/model_specs.dart';

part 'model_node.dart';

class LcDocument {
  LcDocument({
    required String title,
    required LcNode root,
    LcLogic? logic,
    List<LcComponentDef>? components,
    this.fileVersion = currentVersion,
    Map<String, dynamic>? more,
    List<Object?>? keptComponents,
    String? pageId,
    List<LcPage>? pages,
    List<Object?>? keptPages,
    this.sharedNav,
    this.sharedTop,
  }) : pages = [LcPage(id: pageId ?? kLcFirstPageId, title: title, root: root, logic: logic), ...?pages],
       components = components ?? [],
       more = more ?? {},
       keptComponents = keptComponents ?? [],
       keptPages = keptPages ?? [] {
    lcNormalizePageIds(this.pages);
    _normalizeIds();
    _normalizeComponents();
    lcLinkInstances(this);
    lcMaterializeSharedNav(this);
    lcMaterializeSharedTop(this);
  }

  /// 跨页共用的那一条底部导航栏的内容（文件最外层的 `shared.bottomNav`；没有共用是 null）。规矩见 nav_shared.dart。
  Map<String, dynamic>? sharedNav;

  /// 跨页共用的那一条顶部导航栏的内容（文件最外层的 `shared.topBar`；没有共用是 null）。规矩见 top_shared.dart。
  Map<String, dynamic>? sharedTop;

  /// 1＝只有组件树；2＝加了 style / logic / components（都可省略，所以第 1 版的文件照样能读）。
  /// 3＝节点多了名字 / 锁定 / 编辑器内隐藏和一批新属性，并且给后面几期留好了字段；看不懂的东西一律原样留着。
  /// 整份说明见 docs/lowcode-page-format-v3.md。
  static const int currentVersion = 3;

  /// 最外层这一版会读的字段；别的（给后面几期留的 theme，以及任何不认识的）都进 [more]。
  static const Set<String> knownKeys = {'version', 'id', 'title', 'root', 'logic', 'components', 'pages'};

  /// 打开的那个文件写的是第几版（没写＝1）。只用来判断“是不是比这一版新”，以及存盘时版本号不往回写。
  final int fileVersion;

  /// 这个页面是比这一版应用更新的版本做的：有些东西这里显示不了、改不了，但存盘时会原样留着。
  bool get isFromNewer => fileVersion > currentVersion;

  /// 最外层别的字段：不解释，原样留着。
  final Map<String, dynamic> more;

  /// 读不出来的组件定义：不解释，原样留着（排在读得出来的后面）。
  final List<Object?> keptComponents;

  /// 全部页面，第一个是首页（多页面见 model_pages.dart）。至少有一页。
  final List<LcPage> pages;

  /// `pages` 里读不出来的项：不解释，原样留着（排在读得出来的后面）。
  final List<Object?> keptPages;
  int _at = 0;

  /// 当前在编辑的那一页。下面的 [title] / [root] / [logic] 和查找、插入、移动都是对它说的。
  LcPage get page => pages[_at];
  int get pageIndex => _at;

  /// 换一页来编辑（不算一次修改，不写文件）。
  void openPageAt(int index) => _at = index.clamp(0, pages.length - 1);
  bool openPage(String id) {
    final i = pages.indexWhere((p) => p.id == id);
    if (i >= 0) _at = i;
    return i >= 0;
  }

  String get title => page.title;
  set title(String v) => page.title = v;
  LcNode get root => page.root;
  set root(LcNode v) => page.root = v;

  /// 当前页的逻辑：变量和事件处理。
  LcLogic get logic => page.logic;

  /// 自定义组件的定义（项目级：所有页面共用）。
  final List<LcComponentDef> components;
  int _nextId = 1;

  factory LcDocument.starter(String title) => LcDocument(
    title: title,
    root: LcNode(
      id: 'root',
      type: 'page',
      props: Map.of(lcSpecs['page']!.defaults),
      children: [
        LcNode(id: '', type: 'text', props: {'text': title, 'fontSize': 24, 'bold': true, 'color': '#222435'}),
        LcNode(id: '', type: 'text', props: {'text': '点左下角的“添加”选一个组件放进来；长按组件可以拖动。', 'fontSize': 16, 'color': '#5C6479'}),
        LcNode(
          id: '',
          type: 'card',
          props: Map.of(lcSpecs['card']!.defaults),
          children: [
            LcNode(id: '', type: 'input', props: Map.of(lcSpecs['input']!.defaults)),
            LcNode(id: '', type: 'button', props: {...lcSpecs['button']!.defaults, 'text': '提交'}),
          ],
        ),
      ],
    ),
  );

  factory LcDocument.fromJson(Map<String, dynamic> json) {
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) {
      throw const FormatException('缺少 root');
    }
    final v = json['version'];
    final version = v is int && v >= 1 ? v : 1;
    final root = LcNode.fromJson(rootJson, 0, version: version);
    if (root.type != 'page') {
      throw const FormatException('根组件必须是 page');
    }
    final rawComponents = json['components'];
    // 共用的底部导航：`shared.bottomNav` 是个带 props 对象的对象才认；`shared` 里别的键原样留着。
    final rawShared = json['shared'];
    final rawNav = rawShared is Map<String, dynamic> ? rawShared['bottomNav'] : null;
    final sharedNav = rawNav is Map<String, dynamic> && (rawNav['props'] == null || rawNav['props'] is Map) ? rawNav : null;
    final rawTop = rawShared is Map<String, dynamic> ? rawShared['topBar'] : null;
    final sharedTop = rawTop is Map<String, dynamic> && (rawTop['props'] == null || rawTop['props'] is Map) ? rawTop : null;
    final rawPages = json['pages'];
    final pages = <LcPage>[], keptPages = <Object?>[];
    for (final p in rawPages is List ? rawPages : const <Object?>[]) {
      final page = pages.length < kLcMaxPages - 1 ? LcPage.tryParse(p, version: version) : null;
      page == null ? keptPages.add(p) : pages.add(page);
    }
    return LcDocument(
      title: json['title'] is String ? json['title'] as String : '未命名页面',
      root: root,
      logic: LcLogic.fromJson(json['logic']),
      fileVersion: version,
      pageId: json['id'] is String ? json['id'] as String : null,
      pages: pages,
      keptPages: keptPages,
      sharedNav: sharedNav == null ? null : jsonDecode(jsonEncode(sharedNav)) as Map<String, dynamic>,
      sharedTop: sharedTop == null ? null : jsonDecode(jsonEncode(sharedTop)) as Map<String, dynamic>,
      components: [
        if (rawComponents is List)
          for (final c in rawComponents) ?LcComponentDef.tryParse(c, version: version),
      ],
      keptComponents: [
        if (rawComponents is List)
          for (final c in rawComponents)
            if (LcComponentDef.tryParse(c, version: version) == null) c,
      ],
      more: {
        for (final e in json.entries)
          if (!knownKeys.contains(e.key) && e.value != null)
            if (e.key != 'shared' || (sharedNav == null && sharedTop == null))
              e.key: e.value
            else if ((e.value as Map<String, dynamic>).keys.any((k) => !((k == 'bottomNav' && sharedNav != null) || (k == 'topBar' && sharedTop != null))))
              e.key: {
                for (final s in (e.value as Map<String, dynamic>).entries)
                  if (!((s.key == 'bottomNav' && sharedNav != null) || (s.key == 'topBar' && sharedTop != null))) s.key: s.value,
              },
      },
    );
  }

  static LcDocument parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('页面文件不是合法 JSON：${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('页面文件必须是一个 JSON 对象');
    }
    return LcDocument.fromJson(decoded);
  }

  /// 首页写在最外层，别的页写在 `pages` 里。只有一页、首页的 id 又是默认的那个时不写 `id` 和 `pages`——和以前逐字节一样。
  /// 用了共用底部导航 / 顶部导航的：最外层多一个 `shared`，各页里用它的节点只写自己的记号（见 nav_shared.dart、top_shared.dart）。
  Map<String, dynamic> toJson() {
    lcSettleSharedNav(this);
    lcSettleSharedTop(this);
    final home = pages.first, rest = pages.skip(1);
    final nav = sharedNav, top = sharedTop, keptShared = more['shared'];
    final any = nav != null || top != null;
    Map<String, dynamic> tree(Map<String, dynamic> json) {
      if (nav != null) lcStripSharedNavJson(json['root'] as Map<String, dynamic>);
      if (top != null) lcStripSharedTopJson(json['root'] as Map<String, dynamic>);
      return json;
    }

    return tree({
      'version': fileVersion > currentVersion ? fileVersion : currentVersion,
      if (rest.isNotEmpty || home.id != kLcFirstPageId) 'id': home.id,
      'title': home.title,
      'root': home.root.toJson(),
      if (!home.logic.isEmpty) 'logic': home.logic.toJson(),
      if (components.isNotEmpty || keptComponents.isNotEmpty) 'components': [for (final c in components) c.toJson(), ...keptComponents],
      if (rest.isNotEmpty || keptPages.isNotEmpty) 'pages': [for (final p in rest) any ? tree(p.toJson()) : p.toJson(), ...keptPages],
      if (any) 'shared': {'bottomNav': ?nav, 'topBar': ?top, if (keptShared is Map<String, dynamic>) ...keptShared},
      ...home.more,
      for (final e in more.entries)
        if (e.key != 'shared' || !any) e.key: e.value,
    });
  }

  LcComponentDef? component(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 组件定义：id 缺了 / 重了补成 `c数字`；定义内部的节点 id 各自保证唯一（和页面的节点 id 互不相干）。
  void _normalizeComponents() {
    final ids = <String>{};
    var next = 1;
    for (final c in components) {
      if (c.id.isEmpty || !ids.add(c.id)) {
        while (ids.contains('c$next')) {
          next++;
        }
        c.id = 'c$next';
        ids.add(c.id);
      }
      final seen = <String>{};
      var n = 1;
      void fix(LcNode node) {
        if (node.id.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(node.id) || !seen.add(node.id)) {
          while (seen.contains('k$n')) {
            n++;
          }
          node.id = 'k$n';
          seen.add(node.id);
        }
        node.children.forEach(fix);
      }

      fix(c.root);
    }
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 保证每个节点都有唯一 id（外部 JSON、Agent 写入的可能缺或重复）。每页各算各的；新 id 的数字全项目往上接。
  void _normalizeIds() {
    var maxN = 0;
    void scan(LcNode n) {
      final m = RegExp(r'^n(\d+)$').firstMatch(n.id);
      if (m != null) maxN = maxN < int.parse(m[1]!) ? int.parse(m[1]!) : maxN;
      n.children.forEach(scan);
    }

    for (final p in pages) {
      scan(p.root);
    }
    _nextId = maxN + 1;
    for (final p in pages) {
      final seen = <String>{};
      void fix(LcNode n) {
        if (n.id.isEmpty || !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(n.id) || !seen.add(n.id)) {
          n.id = 'n${_nextId++}';
          seen.add(n.id);
        }
        n.children.forEach(fix);
      }

      fix(p.root);
    }
  }

  LcNode newNode(String type) => type == kLcToastPaletteType
      ? LcNode(id: 'n${_nextId++}', type: 'dialog', props: {...kLcToastDefaults})
      : LcNode(id: 'n${_nextId++}', type: type, props: jsonDecode(jsonEncode(lcSpecs[type]!.defaults)) as Map<String, dynamic>);

  LcNode? find(String id) {
    LcNode? walk(LcNode n) {
      if (n.id == id) return n;
      for (final c in n.children) {
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(root);
  }

  LcNode? parentOf(String id) {
    LcNode? walk(LcNode n) {
      for (final c in n.children) {
        if (c.id == id) return n;
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(root);
  }

  bool _contains(LcNode ancestor, String id) => ancestor.id == id || ancestor.children.any((c) => _contains(c, id));

  /// 把节点插到某个容器的指定位置；返回是否成功。
  bool insert(String parentId, LcNode node, [int? index]) {
    final parent = find(parentId);
    lcLinkInstances(this, extra: node);
    if (parent == null || !parent.isContainer || node.type == 'page') return false;
    final i = (index ?? parent.children.length).clamp(0, parent.children.length);
    parent.children.insert(i, node);
    lcSettleSlot(parent, node, i);
    _normalizeIds();
    return true;
  }

  bool remove(String id) {
    final parent = parentOf(id);
    if (parent == null) return false; // 根不能删
    parent.children.removeWhere((c) => c.id == id);
    return true;
  }

  /// 移动 / 重排。不能移进自己或自己的后代里。
  bool move(String id, String newParentId, int index) {
    final node = find(id);
    final oldParent = parentOf(id);
    final newParent = find(newParentId);
    if (node == null || oldParent == null || newParent == null) return false;
    lcLinkInstances(this);
    if (!newParent.isContainer || _contains(node, newParentId)) return false;
    final oldIndex = oldParent.children.indexOf(node);
    oldParent.children.removeAt(oldIndex);
    var i = index;
    if (identical(oldParent, newParent) && oldIndex < index) i -= 1;
    final at = i.clamp(0, newParent.children.length);
    newParent.children.insert(at, node);
    lcSettleSlot(newParent, node, at);
    return true;
  }

  /// 在同级里上移 / 下移一位。
  bool shift(String id, int delta) {
    final parent = parentOf(id);
    if (parent == null) return false;
    final i = parent.children.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (j < 0 || j >= parent.children.length) return false;
    final node = parent.children.removeAt(i);
    parent.children.insert(j, node);
    return true;
  }

  String? duplicate(String id) {
    final parent = parentOf(id);
    final node = find(id);
    if (parent == null || node == null) return null;
    final copy = node.clone();
    void clear(LcNode n) {
      n.id = '';
      n.children.forEach(clear);
    }

    clear(copy);
    parent.children.insert(parent.children.indexOf(node) + 1, copy);
    _normalizeIds();
    lcLinkInstances(this);
    return copy.id;
  }
}
