/// 多页面导出的公共部分（第 4 期；设计见 docs/blocks-v5-parts/E-editor-components.md §10.6）。
///
/// 各导出器（网页 / Vue / React / Flutter）一次只认“当前页”。多页面时这里给每一页做一份“只看这一页”的副本
/// （[lcPageView]）交给它们，再补上“页面之间怎么跳”：
/// - 普通网页：每页一个 .html（首页 `index.html`，别的页 `page-<id>.html`），跳页就是换地址。
/// - Vue 3 / React：不引路由库。多一个外壳文件（[kLcShellName]），它看地址栏里 `#/` 后面那段决定显示哪一页；
///   跳页就是改那一段（`location.hash`），浏览器的后退也跟着管用。
/// - Flutter：所有页面的类写在同一个文件里，用 Navigator 跳。
///
/// 只有一页的项目完全不走这里：导出的文件和以前逐字节一样。
library;

import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/model.dart';

/// Vue / React 多页面导出的外壳的名字（文件是 `LcApp.vue` / `LcApp.jsx`）。`Lc` 开头是我们自己的地盘。
const String kLcShellName = 'LcApp';

const String kNotePages = '这个项目有多页：导出里多了一个外壳 $kLcShellName，在你的工程里挂它（不是某一页）。它看地址栏里 #/ 后面那段决定显示哪一页，没有用路由库；想换成正式的路由，把“去页面”那几句 location.hash 换掉就行。';

/// 一页在导出里的安排。
class LcPagePlan {
  LcPagePlan(this.view, this.name);

  /// 只看这一页的文档副本。
  final LcDocument view;

  /// Vue / React 里的组件名（也是文件名），全项目不重复。
  final String name;
  LcPage get page => view.page;
}

/// 整个项目在 Vue / React 导出里的安排：每页叫什么、每个自定义组件叫什么（各页说法一致）。
class LcSitePlan {
  LcSitePlan(LcDocument doc) {
    final used = <String>{kLcShellName};
    for (var i = 0; i < doc.pages.length; i++) {
      final view = lcPageView(doc, i);
      final base = lcPageName(view);
      var name = base;
      for (var k = 2; !used.add(name); k++) {
        name = '$base$k';
      }
      pages.add(LcPagePlan(view, name));
    }
    for (final c in doc.components) {
      final base = lcPascalName(c.name, fallback: 'LcComponent');
      var name = base;
      for (var k = 2; !used.add(name); k++) {
        name = '$base$k';
      }
      componentNames[c.id] = name;
    }
  }

  final List<LcPagePlan> pages = [];
  final Map<String, String> componentNames = {};
}

/// “点一下去这一页”的 JS 表达式（给底部导航项用；里面不带双引号，事件对象用 [kLcEv] 占位）。
/// 页面不存在、或者就是当前这页（[allowSelf] 为 false 时）返回 null＝点了没反应。
String? Function(String pageId) lcPageJumper(LcDocument doc, {required bool hash, bool allowSelf = false}) => (pageId) {
  final p = doc.pageById(pageId);
  if (p == null || (!allowSelf && identical(p, doc.page))) return null;
  return hash ? "$kLcEv.view.location.hash = '#/${p.id}'" : "$kLcEv.view.location.href = '${lcPageFileBase(doc, p.id)}.html'";
};

/// Vue / React 里“去页面”积木翻成的那一句。
List<String> lcHashGoPage(LcPage page) => ['location.hash = ${jsString('#/${page.id}')};'];

List<String> _pageTable(LcSitePlan site) => [
  '// 页面清单：地址栏里 #/ 后面那段 → 页面。第一个是首页。',
  'const lcPages = {',
  for (final p in site.pages) '  ${p.page.id}: ${p.name}, // ${jsComment(p.page.title, 40)}',
  '};',
  'const lcHome = ${jsString(site.pages.first.page.id)};',
  '',
  '// 现在该显示哪一页：地址栏里写的那页；没写、或者没有这一页，就是首页。',
  'function lcPageFromHash() {',
  '  if (typeof location === "undefined") return lcHome; // 服务端渲染时没有地址栏',
  '  const id = location.hash.replace(/^#\\/?/, "");',
  '  return Object.prototype.hasOwnProperty.call(lcPages, id) ? id : lcHome;',
  '}',
];

/// Vue 3 的外壳（单文件组件）。
/// [themeCss]：主题变量那一段（所有页面共用，所以放外壳里；没用到是空串）。
String lcVueShell(LcSitePlan site, {String themeCss = ''}) => [
  '<script setup>',
  '// $kExportHeader',
  '// 多页面的外壳：看地址栏里 #/ 后面那段决定显示哪一页。在你的工程里挂这个组件。',
  'import { onBeforeUnmount, onMounted, shallowRef } from "vue";',
  for (final p in site.pages) 'import ${p.name} from ${jsString('./${p.name}.vue')};',
  '',
  ..._pageTable(site),
  '',
  'const lcCurrent = shallowRef(lcPageFromHash());',
  'function lcOnHash() {',
  '  lcCurrent.value = lcPageFromHash();',
  '  window.scrollTo(0, 0);',
  '}',
  'onMounted(() => window.addEventListener("hashchange", lcOnHash));',
  'onBeforeUnmount(() => window.removeEventListener("hashchange", lcOnHash));',
  '</script>',
  '',
  '<template>',
  '  <component :is="lcPages[lcCurrent]" :key="lcCurrent" />',
  '</template>',
  '',
  if (themeCss.isNotEmpty) ...['<style>', themeCss.trimRight(), '</style>', ''],
].join('\n');

/// React 的外壳。
String lcReactShell(LcSitePlan site) => [
  '// $kExportHeader',
  '// 多页面的外壳：看地址栏里 #/ 后面那段决定显示哪一页。在你的工程里挂这个组件。',
  'import React, { useEffect, useState } from "react";',
  for (final p in site.pages) 'import ${p.name} from ${jsString('./${p.name}.jsx')};',
  '',
  ..._pageTable(site),
  '',
  'export default function $kLcShellName() {',
  '  const [lcCurrent, lcSetCurrent] = useState(lcPageFromHash);',
  '  useEffect(() => {',
  '    function lcOnHash() {',
  '      lcSetCurrent(lcPageFromHash());',
  '      window.scrollTo(0, 0);',
  '    }',
  '    window.addEventListener("hashchange", lcOnHash);',
  '    return () => window.removeEventListener("hashchange", lcOnHash);',
  '  }, []);',
  '  const LcCurrentPage = lcPages[lcCurrent];',
  '  return <LcCurrentPage key={lcCurrent} />;',
  '}',
  '',
].join('\n');

/// 普通网页导出里的一页：三个文件叫什么、内容是什么。
class LcHtmlPageFiles {
  LcHtmlPageFiles(this.pageId, this.base, this.files, this.logicErrors);
  final String pageId;

  /// 文件名不带后缀的那段：首页 `index`，别的页 `page-<id>`。
  final String base;
  final LcHtmlExport files;

  /// 这一页积木逻辑里“错误”级的问题数：大于 0 时不更新它的脚本文件（规矩见 logic_gate.dart）。
  final int logicErrors;

  String get htmlName => '$base.html';
  String get cssName => base == 'index' ? 'style.css' : '$base.css';
  String get jsName => base == 'index' ? kLowcodeLogicFile : '$base.js';
}

/// 把每一页导出成普通网页。首页的三个文件名和单页面时一样（index.html / style.css / logic.js）。
/// 过程中会临时把 [doc] 换到各页上，结束时换回原来那页（同步做完，中间没有别人插得进来）。
List<LcHtmlPageFiles> exportHtmlPages(LcDocument doc, {LcHtmlExport Function(LcHtmlExport e)? tidy}) {
  final keep = doc.pageIndex;
  final out = <LcHtmlPageFiles>[];
  try {
    for (var i = 0; i < doc.pages.length; i++) {
      doc.openPageAt(i);
      final base = lcPageFileBase(doc, doc.page.id);
      final raw = base == 'index' ? exportHtml(doc) : exportHtml(doc, cssFile: '$base.css', jsFile: '$base.js');
      var files = tidy == null ? raw : tidy(raw);
      // 多页时首页的脚本多带一行“这是哪一页的”：换了首页以后，logic.js 可能还是上一个首页留下的（见 lcStaleHomeScript）。
      if (doc.isMultiPage && base == 'index' && files.js.isNotEmpty) {
        final cut = files.js.indexOf('\n') + 1;
        files = LcHtmlExport(files.html, files.css, '${files.js.substring(0, cut)}${lcPageScriptTag(doc.page.id)}\n${files.js.substring(cut)}');
      }
      out.add(LcHtmlPageFiles(doc.page.id, base, files, lcLogicErrorCount(doc)));
    }
  } finally {
    doc.openPageAt(keep);
  }
  return out;
}

/// 首页脚本里“这是哪一页的”那一行。
String lcPageScriptTag(String pageId) => '// 页面：$pageId';

final RegExp _scriptTag = RegExp(r'^// 页面：(\S+)\s*$', multiLine: true);

/// 手上这份 logic.js（只看开头 [head]）是不是“别的页”当首页时留下的。
/// 首页的逻辑有错误时我们不更新脚本、留着上一次的；可要是上一次的其实是另一页的，留着就是让这一页跑别人的逻辑，得删。
/// 没有那一行的（单页面时导出的）一律当成是这一页的。
bool lcStaleHomeScript(String head, String homeId) {
  final m = _scriptTag.firstMatch(head);
  return m != null && m[1] != homeId;
}

final RegExp _pageFile = RegExp(r'^page-[A-Za-z0-9_]{1,24}\.(html|css|js)$');

/// 项目根目录下的这个文件名是不是“别的页”的导出文件的样子（`page-<id>.html/.css/.js`）。
bool lcLooksLikePageFile(String name) => _pageFile.hasMatch(name);
