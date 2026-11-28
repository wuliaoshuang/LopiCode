/// 导出里“各页共用的底部导航”抽成一个公共部件（第四轮 B3；设计见 docs/blocks-v5-parts/E-editor-components.md §10.11）。
///
/// 只管 Vue 3 / React 的多页面导出：多出一个文件 `components/LcBottomNav.vue`（`.jsx`），各页不再各写一遍那条导航，
/// 而是引用它，把“这一页亮第几项”传进去（`current`，从 0 数）。页面自己的那条样式规则（`.n-<id>`）还留在页面里，
/// 经 class 落到部件最外面那个元素上。
///
/// 什么时候不抽、还是每页写一份：
/// - 这条导航不是共用的（各页各管各的）；
/// - 这一页上它被逻辑改着（改控件 / 显示条件 / 绑定 / 挂了事件）——那是这一页自己的事，部件里放不下。
/// 纯网页导出每页是一个独立的 .html，没有“引用另一个文件里的一段”这回事（除非运行时用脚本拼）；
/// Flutter 导出所有页面的类在同一个文件里，那条导航已经是每页调用同一套写法。这两种保持每页一份。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/export_web_v3_css.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/top_shared.dart';

/// 这一页（按页面根节点记）的共用导航要引用的部件名；没记＝不抽。
final Expando<String> lcNavPartOf = Expando<String>('lcNavPart');

/// 页面里的 [n] 是不是该写成“引用公共部件”：返回部件名，不该是 null。
/// [attrs] 是导出器给这个节点算出来的属性串，[plain] 是“什么额外的都没有”时的样子——两样一样才抽。
/// [scoped]：样式只在本文件里生效的写法（Vue）——抽出去以后，页面里那份这种组件的通用样式就用不上了，记一笔好去掉。
String? lcNavPartFor(LcNode? pageRoot, LcNode n, {required String attrs, required String plain, bool scoped = false}) {
  if (pageRoot == null || !lcIsSharedNav(n) || lcHasBindings(n) || attrs != plain) return null;
  final part = lcNavPartOf[pageRoot];
  if (part != null && scoped) lcPartExtracted[n] = true;
  return part;
}

/// 顶部导航栏同理：这一页的共用顶栏要引用的部件名。
final Expando<String> lcTopPartOf = Expando<String>('lcTopPart');

/// 页面里的 [n] 是不是该写成“引用顶栏公共部件”。和底部导航一个规矩：共用的、没绑定、没被这一页的逻辑改着才抽。
String? lcTopPartFor(LcNode? pageRoot, LcNode n, {required String attrs, required String plain, bool scoped = false}) {
  if (pageRoot == null || !lcIsSharedTop(n) || lcHasBindings(n) || attrs != plain) return null;
  final part = lcTopPartOf[pageRoot];
  if (part != null && scoped) lcPartExtracted[n] = true;
  return part;
}

/// 这一页传给顶栏部件的两样：标题、有没有返回箭头。
String lcTopPartTitle(LcNode n) => n.strProp('title') ?? '';
bool lcTopPartBack(LcNode n) => n.props['back'] == true;

/// 这一页放在顶栏左边 / 右边的控件。
List<LcNode> lcTopPartSlot(LcNode n, String name) => lcSlotChildren(n, name);

/// 这一页亮第几项。
int lcNavPartCurrent(LcNode n) => n.props['current'] is int ? n.props['current'] as int : 0;

LcNode? _firstSharedNav(LcSitePlan site) {
  for (final p in site.pages) {
    final navs = lcSharedNavsIn(p.view.root);
    if (navs.isNotEmpty) return navs.first;
  }
  return null;
}

List<String> _lines(LcDocument doc, LcNode nav, LcWebDialect d, {required String hostAttrs, required String Function(String s) text, required String Function(String name, String value) attr}) {
  // 哪一项都不亮地画一遍（亮哪项由 current 说了算）；每一项都能点（点到当前页那项地址不变，等于没点）。
  final plain = LcNode(id: nav.id, type: nav.type, props: {...nav.props, 'current': -1}, style: nav.style, more: nav.more);
  final ctx = LcWebCtx(uniqueIds: true, fieldClass: (_) => '', closeExpr: (_) => null, pageRoot: null, pageJump: lcPageJumper(doc, hash: true, allowSelf: true));
  final el = lcWebElement(plain, ctx);
  if (el == null) return const [];
  return [
    for (final p in lcRenderEl(el, d, hostAttrs: hostAttrs, text: text, attr: attr))
      if (p.line != null) '${'  ' * p.indent}${p.line}',
  ];
}

/// 第 k 个导航项的开头那一行里，把 [mark] 换成带“亮不亮”的写法。
List<String> _withCurrent(List<String> lines, String mark, String Function(int k) add) {
  var k = 0;
  return [
    for (final l in lines)
      if (l.contains(mark)) l.replaceFirst(mark, '$mark${add(k++)}') else l,
  ];
}

/// Vue 的公共部件文件内容；项目里没有共用导航返回 null。
String? lcVueNavPart(LcDocument doc, LcSitePlan site, {required String Function(String s) text, required String Function(String name, String value) attr}) {
  final nav = _firstSharedNav(site);
  if (nav == null) return null;
  final lines = _withCurrent(_lines(doc, nav, LcWebDialect.vue, hostAttrs: '', text: text, attr: attr), 'class="lc-nav-item"', (k) => " :aria-current=\"current === $k ? 'page' : undefined\"");
  final css = lcV3ComponentsCss(nav).trimRight();
  return [
    '<script setup>',
    '// $kExportHeader',
    '// 各页共用的底部导航：每一页引用它，把“这一页亮第几项”传进来（current，从 0 数）。',
    '// 这条导航自己的样式（颜色、高度…）写在各页的样式里，经 class 落到下面最外面这个元素上。',
    'defineProps({',
    '  current: { type: Number, default: -1 },',
    '});',
    '</script>',
    '',
    '<template>',
    for (final l in lines) '  $l',
    '</template>',
    '',
    '<style scoped>',
    css,
    '</style>',
    '',
  ].join('\n');
}

/// React 的公共部件文件内容；项目里没有共用导航返回 null。样式跟着各页的 .css 走（React 的样式不分文件生效）。
String? lcReactNavPart(LcDocument doc, LcSitePlan site, String name, {required String Function(String s) text, required String Function(String name, String value) attr}) {
  final nav = _firstSharedNav(site);
  if (nav == null) return null;
  final lines = _withCurrent(
    _lines(doc, nav, LcWebDialect.react, hostAttrs: ' {...lcRest}', text: text, attr: attr),
    'className={"lc-nav-item"}',
    (k) => ' aria-current={current === $k ? "page" : undefined}',
  );
  return [
    '// $kExportHeader',
    '// 各页共用的底部导航：每一页引用它，把“这一页亮第几项”传进来（current，从 0 数）。',
    '// 它的样式写在各页的 .css 里（class 由页面传进来）。',
    'import React from "react";',
    '',
    'export default function $name({ current = -1, ...lcRest }) {',
    '  return (',
    for (final l in lines) '    $l',
    '  );',
    '}',
    '',
  ].join('\n');
}

// ───────────── 顶部导航栏（第四轮 B5） ─────────────

const String _titleMark = 'LCTOPTITLEMARK';

LcNode? _firstSharedTop(LcSitePlan site) {
  for (final p in site.pages) {
    final tops = lcSharedTopsIn(p.view.root);
    if (tops.isNotEmpty) return tops.first;
  }
  return null;
}

/// 顶栏“壳子”：各页一样的那部分（居左 / 居中、固定顶部）照着画，返回箭头先画上、标题放一个记号，左右不放东西。
LcNode _topShell(LcNode top) => LcNode(id: top.id, type: top.type, props: {...top.props, 'back': true, 'title': _titleMark}, style: top.style, more: top.more);

List<String> _topLines(
  LcNode top,
  LcWebDialect d, {
  required String hostAttrs,
  required String Function(String s) text,
  required String Function(String name, String value) attr,
  required String backClass,
  required List<String> Function(List<String> button) backIf,
  required String title,
  required List<String> Function(String side) slot,
}) {
  final ctx = LcWebCtx(uniqueIds: true, fieldClass: (_) => '', closeExpr: (_) => null, pageRoot: null);
  final el = lcWebElement(_topShell(top), ctx);
  if (el == null) return const [];
  final raw = [
    for (final p in lcRenderEl(el, d, hostAttrs: hostAttrs, text: text, attr: attr))
      if (p.line != null) '${'  ' * p.indent}${p.line}',
  ];
  final out = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final l = raw[i];
    if (l.contains(backClass)) {
      // 返回箭头那个按钮（连同里面的图标）：有 back 才画
      final button = <String>[l];
      while (!raw[i].trimRight().endsWith('</button>') && i + 1 < raw.length) {
        button.add(raw[++i]);
      }
      out.addAll(backIf(button));
    } else if (l.contains(_titleMark)) {
      out
        ..addAll(slot('left'))
        ..add(l.replaceFirst(RegExp('>[^<]*$_titleMark[^<]*<'), '>$title<'))
        ..addAll(slot('right'));
    } else {
      out.add(l);
    }
  }
  return out;
}

/// Vue 的顶栏公共部件文件内容；项目里没有共用顶栏返回 null。
String? lcVueTopPart(LcDocument doc, LcSitePlan site, {required String Function(String s) text, required String Function(String name, String value) attr}) {
  final top = _firstSharedTop(site);
  if (top == null) return null;
  final lines = _topLines(
    top,
    LcWebDialect.vue,
    hostAttrs: '',
    text: text,
    attr: attr,
    backClass: 'class="lc-bar-back"',
    backIf: (b) => [b.first.replaceFirst('<button', '<button v-if="back"'), ...b.skip(1)],
    title: '{{ title }}',
    slot: (side) => ['  <div v-if="\$slots.$side" class="lc-slot lc-slot-$side">', '    <slot name="$side" />', '  </div>'],
  );
  final css = lcV3ComponentsCss(_topShell(top)).trimRight();
  return [
    '<script setup>',
    '// $kExportHeader',
    '// 各页共用的顶部导航栏：每一页引用它，把这一页的标题（title）、要不要返回箭头（back）传进来；',
    '// 左右两边放的按钮从 left / right 两个插槽传进来（没传就不占地方）。',
    '// 这条顶栏自己的样式（背景、文字颜色…）写在各页的样式里，经 class 落到下面最外面这个元素上。',
    'defineProps({',
    "  title: { type: String, default: '' },",
    '  back: { type: Boolean, default: false },',
    '});',
    '</script>',
    '',
    '<template>',
    for (final l in lines) '  $l',
    '</template>',
    '',
    '<style scoped>',
    css,
    '</style>',
    '',
  ].join('\n');
}

/// React 的顶栏公共部件文件内容；项目里没有共用顶栏返回 null。样式跟着各页的 .css 走。
String? lcReactTopPart(LcDocument doc, LcSitePlan site, String name, {required String Function(String s) text, required String Function(String name, String value) attr}) {
  final top = _firstSharedTop(site);
  if (top == null) return null;
  final lines = _topLines(
    top,
    LcWebDialect.react,
    hostAttrs: ' {...lcRest}',
    text: text,
    attr: attr,
    backClass: 'className={"lc-bar-back"}',
    backIf: (b) => ['  {back ? (', for (final l in b) '  $l', '  ) : null}'],
    title: '{title}',
    slot: (side) => ['  {$side ? <div className="lc-slot lc-slot-$side">{$side}</div> : null}'],
  );
  return [
    '// $kExportHeader',
    '// 各页共用的顶部导航栏：每一页引用它，把这一页的标题（title）、要不要返回箭头（back）、',
    '// 左右两边放的按钮（left / right）传进来。它的样式写在各页的 .css 里（class 由页面传进来）。',
    'import React from "react";',
    '',
    'export default function $name({ title = "", back = false, left = null, right = null, ...lcRest }) {',
    '  return (',
    for (final l in lines) '    $l',
    '  );',
    '}',
    '',
  ].join('\n');
}
