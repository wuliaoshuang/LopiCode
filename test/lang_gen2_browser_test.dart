// 浏览器目标的验收之一（积木第 5 版·第四轮·A2）：语言核心的既有样例——“要等的事”12 个、核心 2 的全部——交给浏览器目标生成，
// 在 Node 里真跑（假窗口：只有控制台和定时器），标准输出和 Node 目标用的同一份 .expect 逐字节一样，退出码的约定也一样。
// 也就是：同一棵语法树、同一套类型检查，换一个目标，行为不变。用了后端才有的宿主接口的样例（读写格子）在浏览器目标里要被拒绝。
//
// 要调 node：没有就跳过并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/gen_support.dart';

import 'support/browser_run.dart';
import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

bool _isProgram(String src) => lcParse(src).any((d) => d is List && d.isNotEmpty && d[0] == '模块');

String _gen(String src) => _isProgram(src) ? gen2BrowserProgram(lcProgram(src)) : gen2BrowserModule(lcModule(src));

List<String> _names(String dir) => [
  for (final f in Directory(dir).listSync().whereType<File>())
    if (f.path.endsWith('.lc')) f.path.split('/').last.replaceAll('.lc', ''),
]..sort();

void main() {
  final skip = gen2SkipReason('node');

  for (final dir in ['test/fixtures/waits', 'test/fixtures/core2']) {
    final names = _names(dir);
    test('$dir：${names.length} 个样例在浏览器目标里真跑，输出和期望逐字节一样', () async {
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      expect(names, isNotEmpty);
      final refused = <String>[];
      var ran = 0;
      for (final n in names) {
        final src = File('$dir/$n.lc').readAsStringSync();
        final String program;
        try {
          program = _gen(src);
        } on LangUnsupported catch (e) {
          // 只许因为“用了后端才有的宿主接口”被拒绝。
          expect(e.message, contains('宿主接口'), reason: n);
          refused.add(n);
          continue;
        }
        // 每个“等”都写成“先记下这条线、等回来放回去”，不许有光秃秃的 await。
        for (final m in RegExp(r'await (?!lc\.safe\()').allMatches(program)) {
          fail('$n：有一个没包好的 await：${program.substring(m.start, (m.start + 60).clamp(0, program.length))}');
        }
        final got = await browserRunProgram(program);
        expect(got.problem, isNull, reason: n);
        final want = File('$dir/$n.expect').readAsBytesSync();
        expect(utf8.decode(got.stdout), utf8.decode(want), reason: n);
        final lastLine = utf8.decode(want).trimRight().split('\n').last;
        expect(got.exitCode, lastLine.startsWith('出错：') ? 1 : 0, reason: n);
        ran++;
      }
      // ignore: avoid_print
      print('$dir：跑了 $ran 个，拒绝 ${refused.length} 个（${refused.join('、')}）');
      if (dir.endsWith('waits')) {
        expect(ran, 12);
        expect(refused, isEmpty);
      } else {
        expect(refused, ['c11-host-and-rt']);
      }
    });
  }

  test('浏览器目标不认后端的宿主接口，不接手写代码', () {
    expect(() => _gen('(宿主 sys.env ((名 文字)) -> (可空 文字)) (主 (做 (宿 sys.env "A")))'), throwsA(isA<LangUnsupported>().having((e) => e.message, '话', contains('宿主接口「sys.env」这里还没有'))));
  });
}
