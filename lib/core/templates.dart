import 'dart:convert';

import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';

enum ProjectTemplate {
  empty('empty', '空项目', '只有一个 README，从零开始'),
  web('web', '前端网页', 'HTML + CSS + JS，可直接预览'),
  lowcode('lowcode', '低代码页面', '拖拽搭建页面，导出网页或 Flutter 代码');

  const ProjectTemplate(this.id, this.label, this.description);
  final String id;
  final String label;
  final String description;

  static ProjectTemplate byId(String? id) => ProjectTemplate.values.firstWhere((t) => t.id == id, orElse: () => ProjectTemplate.empty);
}

/// 低代码页面在项目里的固定文件名。
const String kLowcodePageFile = 'page.lc.json';

/// 模板 → 要写入的文件（相对路径 → 内容）。
Map<String, String> templateFiles(ProjectTemplate template, String name) {
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
  }
}
