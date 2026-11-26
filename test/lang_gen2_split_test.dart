// 模块分文件（库 1 下半）：一个模块一个文件，入口模块在主文件里。
//
// 1. 文件名单：五种语言各自叫什么；只有一个模块有东西时还是一个文件。
// 2. 难缠的模块名（Go 当成特殊文件的结尾 `_test`、只差大小写的两个、带空格和斜杠的）真编译、真跑，输出和不分文件时一样。
// 3. 别的模块公开的变量：读到的是那个模块里现在的值（不是引进来那一刻的）。
// 样例程序本身的对错在 lang_gen2_core2_test.dart（m01–m05）、lang_gen2_classes_test.dart（c13）里逐字节考。
// 要调外部程序：缺哪种语言的编译器就跳过那种语言并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/link.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _odd = '''
(入口 主程序)
(模块 主程序 (用 a_test A_Test 带空格/的 底)
  (主
    (打印 (连 "一开始＝" 计数))
    (打印 (调 甲 "x"))
    (打印 (调 乙 "y"))
    (打印 (调 丙 "z"))
    (打印 (连 "最后＝" 计数))))
(模块 a_test (用 底)
  (公开 (函数 甲 ((话 文字)) -> 文字 (返回 (调 记一笔 (连 "甲" 话))))))
(模块 A_Test (用 底)
  (公开 (函数 乙 ((话 文字)) -> 文字 (返回 (调 记一笔 (连 "乙" 话))))))
(模块 带空格/的 (用 底)
  (公开 (函数 丙 ((话 文字)) -> 文字 (返回 (调 记一笔 (连 "丙 lc.x " 话))))))
(模块 底
  (公开 (变量 计数 整数 0))
  (公开 (函数 记一笔 ((话 文字)) -> 文字
    (改 计数 (+ 计数 1))
    (返回 (连 话 "#" 计数)))))
''';

const String _oddOut = '一开始＝0\n甲x#1\n乙y#2\n丙 lc.x z#3\n最后＝3\n';

void main() {
  test('文件名单：主文件排第一个；内置错误种类一份；别的模块按启动顺序各一个', () {
    final program = lcProgram(_odd);
    expect(gen2SplitOf(program, linkProgram(program))!.ident, {'底': '底', 'a_test': 'a_test', 'A_Test': 'A_Test_2', '带空格/的': '带空格_u2f_的'});
    List<String> own(String language) => [
      for (final k in gen2ProgramFiles(language, program).keys)
        if (!k.startsWith('lc2.') && !k.startsWith('lc/') && k != 'go.mod' && k != 'Lc.java' && k != 'LcHost.java') k,
    ];
    expect(own('node'), ['main.js', 'lc_kinds.js', 'm_底.js', 'm_a_test.js', 'm_A_Test_2.js', 'm_带空格_u2f_的.js']);
    expect(own('python'), ['main.py', 'lc_kinds.py', 'm_底.py', 'm_a_test.py', 'm_A_Test_2.py', 'm_带空格_u2f_的.py']);
    expect(own('php'), ['main.php', 'lc_kinds.php', 'm_底.php', 'm_a_test.php', 'm_A_Test_2.php', 'm_带空格_u2f_的.php']);
    expect(own('go'), ['main.go', 'lc_kinds.go', 'm_底_lc.go', 'm_a_test_lc.go', 'm_A_Test_2_lc.go', 'm_带空格_u2f_的_lc.go']);
    expect(own('java'), hasLength(6));
    expect(own('java').take(2), ['Main.java', 'LcKinds.java']);
    expect(own('java').skip(2).every(RegExp(r'^M_[A-Za-z0-9_]+\.java$').hasMatch), isTrue, reason: 'Java 的类文件名只用英文字母、数字、下划线');
  });

  test('只有一个模块有东西：还是一个文件，和以前一个字不差', () {
    const src = '(入口 主) (模块 主 (主 (打印 "好")))';
    final program = lcProgram(src);
    expect(gen2SplitOf(program, linkProgram(program)), isNull);
    for (final language in kGen2Languages) {
      expect(gen2ProgramFiles(language, program), gen2Files(language, linkProgram(program).module!), reason: language);
    }
  });

  for (final language in kGen2Languages) {
    test('$language：难缠的模块名真编译、真跑；别的模块的变量读到的是现在的值', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final run = await gen2RunFiles(language, gen2ProgramFiles(language, lcProgram(_odd)));
      expect(run.problem, isNull);
      expect(utf8.decode(run.stdout), _oddOut);
      expect(run.exitCode, 0);
    });
  }
}
