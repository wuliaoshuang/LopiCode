// 核心 3 的验收（积木第 5 版）：“要等的事”。
//
// test/fixtures/waits/ 下 12 个样例（推断的各种形状、开始做、超时、等全部 / 等最先的一个、取消、一次只让一个做、函数值、
// 没接住的超时、主程序先做完）交给规矩版本 2 的生成器，生成 Node / Python / PHP / Go / Java 五种语言的整套文件，**真的编译、真的跑**：
// 标准输出和 .expect 逐字节一样；.expect 最后一行是“出错：…”的退出码是 1，别的是 0。
//
// PHP 里“开始做”是当场做完的（没有“同时做”），有三个样例的输出因此不一样：这三个另有一份 `.expect.php`，PHP 按它比
// （哪里不一样、为什么，写在样例开头和 docs/blocks-v5-parts/B-gen-notes.md 第 16.6 节）。别的 9 个五种语言一个期望。
// 谁都没标“要等”——全靠检查器推；故意写错的那一组在 test/lang_waits_infer_test.dart。
//
// 要调外部程序：缺哪种语言的编译器就跳过那种语言并打印原因。样例的写法见 test/support/proto_lc.dart。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _dir = 'test/fixtures/waits';

bool _isProgram(String src) => lcParse(src).any((d) => d is List && d.isNotEmpty && d[0] == '模块');

Map<String, String> _files(String language, String name) {
  final src = File('$_dir/$name.lc').readAsStringSync();
  return _isProgram(src) ? gen2ProgramFiles(language, lcProgram(src)) : gen2Files(language, lcModule(src));
}

/// 这种语言该比哪份期望：PHP 有自己那份就用自己的。
File _expect(String language, String name) {
  final own = File('$_dir/$name.expect.$language');
  return own.existsSync() ? own : File('$_dir/$name.expect');
}

void main() {
  final names = [
    for (final f in Directory(_dir).listSync().whereType<File>())
      if (f.path.endsWith('.lc')) f.path.split('/').last.replaceAll('.lc', ''),
  ]..sort();

  test('样例都在：12 个，每个都有 .expect；只有 PHP 有另外的期望，一共 3 份', () {
    expect(names, hasLength(12));
    for (final n in names) {
      expect(File('$_dir/$n.expect').existsSync(), isTrue, reason: n);
    }
    final own = [
      for (final f in Directory(_dir).listSync().whereType<File>())
        if (!f.path.endsWith('.lc') && !f.path.endsWith('.expect')) f.path.split('/').last,
    ]..sort();
    expect(own, ['w03-spawn-order.expect.php', 'w08-cancel-effects.expect.php', 'w12-main-ends-first.expect.php']);
  });

  test('样例里谁都没手标“要等”，检查没有问题', () {
    for (final n in names) {
      final src = File('$_dir/$n.lc').readAsStringSync();
      expect(RegExp('要等函数|要等方法|要等λ|不等函数|不等方法').hasMatch(src), isFalse, reason: n);
      final module = _isProgram(src) ? linkProgram(lcProgram(src)).module! : lcModule(src);
      expect([for (final i in checkModuleTypes(module).errors) '${i.code} ${i.message}'], isEmpty, reason: n);
    }
  });

  for (final language in kGen2Languages) {
    group('$language：12 个样例生成、真跑，输出逐字节一样，退出码对', () {
      final skip = gen2SkipReason(language);
      for (final n in names) {
        test(n, () async {
          final files = _files(language, n);
          expect(files, isNotEmpty);
          if (skip != null) {
            // ignore: avoid_print — 跳过的原因要让跑测试的人看见
            print('跳过：$skip');
            markTestSkipped(skip);
            return;
          }
          final run = await gen2RunFiles(language, files);
          expect(run.problem, isNull, reason: '$language / $n 没跑成');
          final want = _expect(language, n).readAsBytesSync();
          expect(utf8.decode(run.stdout, allowMalformed: true), utf8.decode(want), reason: '$language / $n 的输出不一样');
          expect(run.stdout, want, reason: '$language / $n 的输出字节不一样');
          final uncaught = utf8.decode(want).trimRight().split('\n').last.startsWith('出错：');
          expect(run.exitCode, uncaught ? 1 : 0, reason: '$language / $n 的退出码');
        });
      }
    });
  }
}
