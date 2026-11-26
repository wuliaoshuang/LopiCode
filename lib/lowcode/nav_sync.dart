/// 底部导航栏怎么跨页共用（第 4 期·多页面；设计见 docs/blocks-v5-parts/E-editor-components.md §10.6）。
///
/// 规矩：导航栏在每一页里都是一个普通组件，各存各的——页面文件里没有“共用的导航栏”这种东西，
/// 导出、老版本应用、Agent 看到的都是每页自己那一条。要让几页的导航栏长得一样，在一页上改好以后点
/// “同步到其它页面”：把这一条的导航项、样子、样式抄到**它指向的每一页**（那一页已经有导航栏就改那一条，
/// 没有就在页面最后加一条），并把每一页的“当前项”设成指向它自己的那一项。
/// 不自动联动：改了一页以后别的页不会自己变，要再点一次（这样每页想留点不一样的也可以）。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';

/// 导航项 [item] 点了去哪一页；没设是 null。
String? lcNavItemPage(Map<String, dynamic> item) {
  final p = item['page'];
  return p is String && p.isNotEmpty ? p : null;
}

LcNode? _firstNav(LcNode root) {
  if (root.type == 'bottomNav') return root;
  for (final c in root.children) {
    final r = _firstNav(c);
    if (r != null) return r;
  }
  return null;
}

/// [navId]（当前页里的一条底部导航栏）会同步到哪几页：它的导航项指向的、还在的、不是当前页的那些（不重复，按导航项的先后）。
List<LcPage> lcNavSyncTargets(LcDocument doc, String navId) {
  final nav = doc.find(navId);
  if (nav == null || nav.type != 'bottomNav') return const [];
  final out = <LcPage>[];
  for (final item in lcObjects(nav, 'items')) {
    final page = doc.pageById(lcNavItemPage(item) ?? '');
    if (page != null && page.id != doc.page.id && !out.contains(page)) out.add(page);
  }
  return out;
}

/// 把当前页的导航栏 [navId] 同步到它指向的各页。返回改了几页（0＝没有可同步的页）。
///
/// 顺带把当前页这一条的“当前项”也设成指向当前页的那一项（有的话）。
int lcSyncBottomNav(LcDocument doc, String navId) {
  final nav = doc.find(navId);
  final targets = lcNavSyncTargets(doc, navId);
  if (nav == null || targets.isEmpty) return 0;
  final items = lcObjects(nav, 'items');
  int? indexOf(String pageId) {
    final i = items.indexWhere((m) => lcNavItemPage(m) == pageId);
    return i < 0 ? null : i;
  }

  final mine = indexOf(doc.page.id);
  if (mine != null) nav.props['current'] = mine;
  Map<String, dynamic> copy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
  for (final page in targets) {
    var there = _firstNav(page.root);
    if (there == null) {
      there = doc.newNode('bottomNav');
      page.root.children.add(there);
    }
    there.props
      ..clear()
      ..addAll(copy(nav.props));
    there.style
      ..clear()
      ..addAll(nav.style);
    // “按下时 / 停用时”的样式也一起抄（它们存在节点的 states 里）；名字、隐藏、锁定这些编辑器自己的记号各页留各页的。
    final states = nav.more['states'];
    if (states is Map<String, dynamic>) {
      there.more['states'] = copy(states);
    } else {
      there.more.remove('states');
    }
    there.props['current'] = indexOf(page.id) ?? 0;
  }
  return targets.length;
}
