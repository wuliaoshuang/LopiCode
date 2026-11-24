// 后端积木一致性测试：同一份样本模型翻成每种语言，真的把服务起起来（随机端口、只连 127.0.0.1），
// 发同一串请求——每条响应都要等于写死的期望值，各语言之间逐字节相同。
//
// 加一种语言：在 [_languages] 里加一行（语言 id → 用来判断本机有没有的命令）。本机没有对应工具时跳过并打印原因。
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';

import 'support/backend_conformance.dart';

/// 语言 id → 本机要有的命令。
const Map<String, String> _languages = {'node': 'node', 'python': 'python3'};

/// 语法检查：语言 id → 对一个文件做语法检查的命令（文件路径接在最后）。
const Map<String, List<String>> _syntaxChecks = {
  'node': ['node', '--check'],
  'python': ['python3', '-m', 'py_compile'],
};

void _collectFns(List<BeS> list, Set<String> out) {
  void x(BeX e) {
    if (e is BeXCall) {
      out.add(e.fn);
      e.args.forEach(x);
    }
  }

  for (final s in list) {
    switch (s) {
      case BeSNote():
        break;
      case BeSSet(:final value) || BeSLet(:final value):
        x(value);
      case BeSDo(:final call):
        x(call);
      case BeSIf(:final cond, :final then, :final orElse):
        x(cond);
        _collectFns(then, out);
        _collectFns(orElse, out);
      case BeSRepeat(:final times, :final body):
        x(times);
        _collectFns(body, out);
      case BeSForEach(:final list, :final body):
        x(list);
        _collectFns(body, out);
      case BeSReturn(:final response):
        x(response);
    }
  }
}

void main() {
  test('样本模型用到了运行时小库的每一个函数、每一种积木和表达式（这样跑通＝每个函数都真的跑过）', () {
    final program = lowerBackend(conformanceDocument());
    final used = <String>{};
    for (final r in program.routes) {
      _collectFns(r.body, used);
    }
    expect(kBeRuntimeFns.keys.toSet().difference(used), isEmpty, reason: '样本没用到的函数');
    expect(used.difference(kBeRuntimeFns.keys.toSet()), isEmpty, reason: '中间形式里出现了表上没有的函数');
    expect(program.skipped, isEmpty);
  });

  test('样本模型除了故意留的坑（/holes）之外没有校验错误', () {
    final doc = conformanceDocument();
    final holes = doc.routes.firstWhere((r) => r.path == '/holes').id;
    final errors = [
      for (final i in validateBackend(doc, languages: [for (final t in backendTargets) t.id]))
        if (i.isError && i.handlerId != holes) i,
    ];
    expect(errors, isEmpty);
  });

  final results = <String, List<BeResponse>>{};
  for (final entry in _languages.entries) {
    final language = entry.key;
    test('$language：生成的工程能启动，${conformanceCases.length} 条请求的响应都等于期望值', () async {
      if (!await hasCommand(entry.value)) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过 $language 的一致性测试：本机找不到 ${entry.value} 命令');
        markTestSkipped('本机找不到 ${entry.value} 命令');
        return;
      }
      results[language] = await runConformance(language);
    });

    test('$language：生成的文件语法检查通过', () async {
      final check = _syntaxChecks[language];
      if (check == null || !await hasCommand(entry.value)) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过 $language 的语法检查：本机找不到 ${entry.value} 命令');
        markTestSkipped('本机找不到 ${entry.value} 命令');
        return;
      }
      final generated = generateBackend(conformanceDocument(), language: language)!;
      final dir = writeProject(generated.files, 'be_syntax_${language}_');
      try {
        for (final name in generated.files.keys.where((n) => !n.endsWith('.md'))) {
          final r = await Process.run(check.first, [...check.sublist(1), name], workingDirectory: dir.path);
          expect(r.exitCode, 0, reason: '$name：\n${r.stdout}\n${r.stderr}');
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }

  test('各语言的响应逐字节相同', () {
    if (results.length < 2) {
      // ignore: avoid_print 跳过的原因要让跑测试的人看见
      print('跳过“各语言互相比”：真跑起来的语言不到两种（${results.keys.join('、')}）');
      markTestSkipped('真跑起来的语言不到两种');
      return;
    }
    final first = results.entries.first;
    for (final other in results.entries.skip(1)) {
      for (var i = 0; i < conformanceCases.length; i++) {
        if (conformanceCases[i].pattern != null) continue; // 现在的时间：两边差一秒是正常的
        final a = first.value[i];
        final b = other.value[i];
        final where = '第 ${i + 1} 条 ${conformanceCases[i]}：${first.key} 和 ${other.key} 不一样';
        expect(b.status, a.status, reason: where);
        expect(b.type, a.type, reason: where);
        expect(b.body, a.body, reason: where);
      }
    }
  });
}
