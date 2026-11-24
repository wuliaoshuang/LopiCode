import 'dart:convert';

import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';

/// 新建项目时模板的分组，按界面上的顺序。
enum TemplateGroup {
  blank('空白'),
  frontend('前端'),
  backendBlocks('后端 · 积木'),
  backendCode('后端 · 代码'),
  fullstack('全栈');

  const TemplateGroup(this.label);
  final String label;
}

/// 这个模板创建时要不要再选一种语言、从哪张表里选。表本身不在 core（见 lib/templates/project_templates.dart）。
enum TemplateLanguageSource {
  /// 不用选。
  none,

  /// 后端积木现有的生成器（lib/backend 的 `backendTargets`）。
  blockTargets,

  /// 纯代码起步工程（lib/templates/code_starters.dart）。
  codeStarters,
}

/// 模板目录。`id` 存在项目的 project.json 里：**已有的 id 不许改**；读到不认识的 id 回退成空项目（[byId]）。
///
/// 这里只有“目录”（名字、说明、分组、图标）。empty / web / lowcode 的文件在本文件生成；
/// 其余模板的文件要用到 lib/backend，不能放在 core——由 lib/templates/project_templates.dart 生成后交给 `ProjectStore.create`。
enum ProjectTemplate {
  empty('empty', '空项目', '只有一个 README，从零开始', TemplateGroup.blank, 'readme'),
  web('web', '前端网页', 'HTML + CSS + JS，可直接预览', TemplateGroup.frontend, 'html'),
  lowcode('lowcode', '低代码页面', '拖拽搭建页面，导出网页或 Flutter 代码', TemplateGroup.frontend, 'template'),
  backendBlocks('backend-blocks', '后端服务（积木）', '用积木搭接口，自动生成所选语言的代码', TemplateGroup.backendBlocks, 'openapi', languages: TemplateLanguageSource.blockTargets),
  backendCode('backend-code', '后端服务（代码）', '所选语言的最小 HTTP 服务，从代码写起', TemplateGroup.backendCode, 'console', languages: TemplateLanguageSource.codeStarters),
  fullstack('fullstack', '前端 + 后端', '一个网页加一个积木后端，网页调后端的接口', TemplateGroup.fullstack, 'http', languages: TemplateLanguageSource.blockTargets);

  const ProjectTemplate(this.id, this.label, this.description, this.group, this.icon, {this.languages = TemplateLanguageSource.none});
  final String id;
  final String label;
  final String description;
  final TemplateGroup group;

  /// 图标（给界面的 `FileIcon.language`）：语言 id 或图标名。
  final String icon;

  /// 创建时要不要选语言。
  final TemplateLanguageSource languages;

  bool get needsLanguage => languages != TemplateLanguageSource.none;

  /// 文件能不能在 core 里直接生成（[templateFiles]）。不能的要走 lib/templates/project_templates.dart。
  bool get builtIn => this == empty || this == web || this == lowcode;

  static ProjectTemplate byId(String? id) => ProjectTemplate.values.firstWhere((t) => t.id == id, orElse: () => ProjectTemplate.empty);

  /// 某一组里的模板，按目录顺序。
  static List<ProjectTemplate> inGroup(TemplateGroup group) => [
    for (final t in values)
      if (t.group == group) t,
  ];
}

/// 低代码页面在项目里的固定文件名。
const String kLowcodePageFile = 'page.lc.json';

/// 内置模板（empty / web / lowcode）→ 要写入的文件（相对路径 → 内容）。
///
/// 其余模板的文件不在这一层生成：返回 null，调用方要改用 lib/templates/project_templates.dart 的 `projectTemplateFiles`。
Map<String, String>? templateFiles(ProjectTemplate template, String name) {
  switch (template) {
    case ProjectTemplate.empty:
      return {'README.md': '# $name\n\n在这里写下项目说明。\n'};
    case ProjectTemplate.web:
      return {
        'index.html':
            '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${const HtmlEscape().convert(name)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="card">
    <h1>${const HtmlEscape().convert(name)}</h1>
    <p>改一改 index.html、style.css、script.js，保存后预览会自动刷新。</p>
    <button id="btn">点我</button>
    <p id="out"></p>
  </main>
  <script src="script.js"></script>
</body>
</html>
''',
        'style.css': '''* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: system-ui, -apple-system, "Noto Sans SC", sans-serif;
  background: #f6fbfd;
  color: #222435;
}
.card {
  width: min(92vw, 420px);
  padding: 24px;
  border-radius: 12px;
  background: #fff;
  box-shadow: 0 4px 6px rgba(0, 0, 0, .08);
}
h1 { margin: 0 0 8px; font-size: 24px; }
p { margin: 0 0 16px; line-height: 1.5; color: #5c6479; }
button {
  padding: 10px 16px;
  border: 0;
  border-radius: 8px;
  background: #058654;
  color: #fff;
  font-size: 16px;
}
''',
        'script.js': '''let count = 0;
document.getElementById('btn').addEventListener('click', () => {
  count += 1;
  document.getElementById('out').textContent = '点了 ' + count + ' 次';
  console.log('点击次数', count);
});
''',
      };
    case ProjectTemplate.lowcode:
      final doc = LcDocument.starter(name);
      final export = exportHtml(doc);
      return {kLowcodePageFile: const JsonEncoder.withIndent('  ').convert(doc.toJson()), 'index.html': export.html, 'style.css': export.css};
    case ProjectTemplate.backendBlocks:
    case ProjectTemplate.backendCode:
    case ProjectTemplate.fullstack:
      return null;
  }
}
