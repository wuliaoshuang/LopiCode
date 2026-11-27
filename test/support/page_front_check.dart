// 新的页面逻辑的样例：三种产物真编译 0 错 0 警告，再在 Node＋jsdom 里真跑一串步骤（各个 lowcode_front_*_test.dart 共用）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/model.dart';

import 'bind_export_files.dart';
import 'dev_tools.dart';

const Map<String, String> kFrontKinds = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

String frontEntry(String kind, Map<String, String> files) => switch (kind) {
  'html' => 'index.html',
  'vue' => files.containsKey('LcApp.vue') ? 'LcApp.vue' : files.keys.firstWhere((k) => k.endsWith('.vue') && !k.contains('/')),
  _ => files.containsKey('LcApp.jsx') ? 'LcApp.jsx' : files.keys.firstWhere((k) => k.endsWith('.jsx') && !k.contains('/')),
};

Future<void> frontCheck(String kind, LcDocument doc, List<Map<String, Object?>> steps) async {
  // 画布上的检查先过：每一页的新逻辑都没有标红。
  for (final page in doc.pages) {
    final front = lcFrontOf(page.logic);
    if (front == null) continue;
    expect([for (final i in validateBackend(front).where((i) => i.isError)) '${page.title}：${i.where} ${i.problem}'], isEmpty);
  }
  final files = exportFilesOf(doc, kind);
  final all = files.values.join('\n');
  expect(all, contains('function lcProgram(lc, lcHost)'), reason: '应该走新路');
  expect(all, isNot(contains('这一页的逻辑没有导出')));
  final entry = frontEntry(kind, files);
  final c = await compileExport('compile_$kind.mjs', files, entry);
  expect(c.errors, isEmpty, reason: c.raw);
  expect(c.warnings, isEmpty, reason: c.raw);
  final r = await runInDom(kind, files, entry, steps);
  expect(r.errors, isEmpty);
  expect(r.warnings, isEmpty);
  expect(r.done, steps.length);
  expect(r.ok, isTrue);
}
