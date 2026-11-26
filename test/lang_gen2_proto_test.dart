// 规矩版本 2 的生成器验收（积木第 5 版·核心 1·第二段）：类型原型的 16 个程序（docs/blocks-v5-prototypes/types/p01–p16）
// 交给生成器（lib/lang/gen2_all.dart）生成 Node / Python / PHP / Go / Java 五种语言的整套文件，**真的编译、真的跑**，
// 标准输出和原型的 expect.txt 逐字节一样。4 组错例（e01–e04）在类型检查阶段就被拦下，不生成代码。
//
// 要调外部程序：缺哪种语言的编译器就跳过那种语言并打印原因。一次只跑一个程序（Go、Java 的编译很吃内存）。
// TypeScript 不在这里：TS 生成器不属于核心 1（总设计 8.2 的分期表），产品里还没有。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _dir = 'docs/blocks-v5-prototypes/types';

void main() {
  final dirs = [for (final d in Directory(_dir).listSync().whereType<Directory>()) d.path.split('/').last]..sort();
  final progs = dirs.where((d) => RegExp(r'^p\d\d-').hasMatch(d)).toList();
  final errs = dirs.where((d) => RegExp(r'^e\d\d-').hasMatch(d)).toList();

  test('原型的程序都在：16 个程序、4 组错例；生成器有五种语言', () {
    expect(progs.length, 16);
    expect(errs.length, 4);
    expect(kGen2Languages, ['node', 'python', 'php', 'go', 'java']);
  });

  for (final language in kGen2Languages) {
    group('$language：16 个程序生成、真跑、输出和原型逐字节一样', () {
      final skip = gen2SkipReason(language);
      for (final p in progs) {
        test(p, () async {
          // 生成这一步不靠外部程序，缺编译器也照做：至少保证每个程序都生成得出来。
          final files = gen2Files(language, lcModule(File('$_dir/$p/prog.lc').readAsStringSync()));
          expect(files, isNotEmpty);
          if (skip != null) {
            // ignore: avoid_print — 跳过的原因要让跑测试的人看见
            print('跳过：$skip');
            markTestSkipped(skip);
            return;
          }
          final run = await gen2RunFiles(language, files);
          expect(run.problem, isNull, reason: '$language / $p 没跑成');
          final want = File('$_dir/$p/expect.txt').readAsBytesSync();
          expect(utf8.decode(run.stdout, allowMalformed: true), utf8.decode(want), reason: '$language / $p 的输出和原型不一样');
          expect(run.stdout, want, reason: '$language / $p 的输出字节和原型不一样');
        });
      }
    });
  }

  for (final p in errs) {
    test('$p：类型检查阶段就拦下，五种语言都不生成代码', () {
      final module = lcModule(File('$_dir/$p/prog.lc').readAsStringSync());
      expect(checkModuleTypes(module).hasErrors, isTrue);
      for (final language in kGen2Languages) {
        expect(() => gen2Files(language, module), throwsA(isA<LangUnsupported>().having((e) => e.what, '原因', contains('类型检查没过'))), reason: language);
      }
    });
  }
}
