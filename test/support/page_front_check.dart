// 新的页面逻辑的样例：三种产物真编译 0 错 0 警告，再在 Node＋jsdom 里真跑一串步骤（各个 lowcode_front_*_test.dart 共用）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'bind_export_files.dart';
import 'dev_tools.dart';

const Map<String, String> kFrontKinds = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

String frontEntry(String kind, Map<String, String> files) => switch (kind) {
  'html' => 'index.html',
  'vue' => files.containsKey('LcApp.vue') ? 'LcApp.vue' : files.keys.firstWhere((k) => k.endsWith('.vue') && !k.contains('/')),
  _ => files.containsKey('LcApp.jsx') ? 'LcApp.jsx' : files.keys.firstWhere((k) => k.endsWith('.jsx') && !k.contains('/')),
};

/// 一份样例、好几组步骤：只编译一次，每组步骤各开一个新的页面从头跑。[strict]＝React 开着 StrictMode 跑。
/// [patch]＝导出的文件在编译前先改一下（只给“组件事件”的样例用：线 B 摊开组件的那一步还没合过来，先替它把事件发出来）。
Future<void> frontCheckAll(String kind, LcDocument doc, List<List<Map<String, Object?>>> stepSets, {bool strict = false, Map<String, String> Function(Map<String, String> files)? patch}) async {
  // 画布上的检查先过：每一页的新逻辑都没有标红（积木文档自己的、对着页面才查得出的）。
  final keep = doc.pageIndex;
  for (var i = 0; i < doc.pages.length; i++) {
    final page = doc.pages[i];
    final front = lcFrontOf(page.logic);
    if (front == null) continue;
    expect([for (final x in validateBackend(front).where((x) => x.isError)) '${page.title}：${x.where} ${x.problem}'], isEmpty);
    expect([for (final x in lcFrontPageIssues(doc, page, front)) '${page.title}：${x.where} ${x.problem}'], isEmpty);
    doc.openPageAt(i);
    expect(lcLogicErrorCount(doc), 0, reason: '${page.title} 导出前的检查');
  }
  doc.openPageAt(keep);
  final exported = exportFilesOf(doc, kind);
  final files = patch == null ? exported : patch(exported);
  final all = files.values.join('\n');
  expect(all, contains('function lcProgram(lc, lcHost)'), reason: '应该走新路');
  expect(all, isNot(contains('这一页的逻辑没有导出')));
  final entry = frontEntry(kind, files);
  final c = await compileExport('compile_$kind.mjs', files, entry);
  expect(c.errors, isEmpty, reason: c.raw);
  expect(c.warnings, isEmpty, reason: c.raw);
  for (var k = 0; k < stepSets.length; k++) {
    final steps = stepSets[k];
    final r = await runInDom(kind, files, entry, steps, strict: strict);
    expect(r.errors, isEmpty, reason: '第 ${k + 1} 组步骤');
    expect(r.warnings, isEmpty, reason: '第 ${k + 1} 组步骤');
    expect(r.done, steps.length, reason: '第 ${k + 1} 组步骤');
    expect(r.ok, isTrue, reason: '第 ${k + 1} 组步骤');
  }
}

Future<void> frontCheck(String kind, LcDocument doc, List<Map<String, Object?>> steps) => frontCheckAll(kind, doc, [steps]);
