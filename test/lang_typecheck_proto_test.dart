// 规矩版本 2 的类型推断和推断原型逐行对照（积木第 5 版·核心 1）。
//
// 原型：docs/blocks-v5-prototypes/types/infer.py。它对 16 个程序（p01–p16）推出来的签名和变量类型记在各目录的 types.txt，
// 对 4 组错例（e01–e04）报的问题记在 errors.txt。这里把同样的程序交给 Dart 的检查器（lib/lang/typecheck.dart），结果必须一样：
// - p01–p16：每个函数的签名、每个变量的类型，逐行相同（不比先后）；而且一个错都不报。
// - e01–e04：报的问题，规则号、在哪、提示语，按顺序逐字相同。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/proto_lc.dart';

const String _dir = 'docs/blocks-v5-prototypes/types';

List<String> _read(String path) => [
  for (final l in File(path).readAsLinesSync())
    if (l.trim().isNotEmpty) l,
];

void main() {
  final dirs = [for (final d in Directory(_dir).listSync().whereType<Directory>()) d.path.split('/').last]..sort();
  final progs = dirs.where((d) => RegExp(r'^p\d\d-').hasMatch(d)).toList();
  final errs = dirs.where((d) => RegExp(r'^e\d\d-').hasMatch(d)).toList();

  test('原型的程序都在：16 个程序、4 组错例', () {
    expect(progs.length, 16);
    expect(errs.length, 4);
  });

  var lines = 0;
  for (final p in progs) {
    test('$p：签名和变量的类型和原型记的一样，没有错', () {
      final r = checkModuleTypes(lcModule(File('$_dir/$p/prog.lc').readAsStringSync()));
      final want = _read('$_dir/$p/types.txt');
      final cut = want.indexOf('—— 报的问题 ——');
      // 核心 2 起“出错时”接到的是错误对象：原型记成“文字”的错误变量，现在是“错误”（原型的 types.txt 不改，在这里换算）。
      final errVars = {
        for (final v in r.vars)
          if (v.kind == LVarKind.error) '${v.scope}.${v.name}',
      };
      final wantTypes = [
        for (final l in cut < 0 ? want : want.sublist(0, cut))
          if (l.endsWith(': 文字') && errVars.contains(l.substring(0, l.length - 4))) '${l.substring(0, l.length - 4)}: 错误' else l,
      ];
      final wantIssues = cut < 0 ? const <String>[] : want.sublist(cut + 1);
      // 行的先后不比（原型记录里循环变量排在后面，和它自己打印的先后也不完全一样）；内容逐行相同。
      expect([...r.describe()]..sort(), [...wantTypes]..sort());
      expect(r.errors.map((e) => '$e').toList(), isEmpty);
      expect([
        for (final i in r.issues)
          if (i.level == LTypeLevel.hint) '$i',
      ], wantIssues);
      lines += wantTypes.length;
    });
  }

  test('16 个程序一共对了 155 行', () => expect(lines, 155));

  var count = 0;
  for (final p in errs) {
    test('$p：报的问题和原型记的一样（规则号、在哪、提示语、顺序）', () {
      final r = checkModuleTypes(lcModule(File('$_dir/$p/prog.lc').readAsStringSync()));
      final got = <String>[];
      for (final i in r.issues) {
        if (i.level == LTypeLevel.warning) continue; // 原型没做的规则（T13、T14）不参加对照。
        if (!got.contains('$i')) got.add('$i'); // 原型：同一句话只说一次。
      }
      final want = _read('$_dir/$p/errors.txt');
      expect(got, want);
      count += want.length;
    });
  }

  test('4 组错例一共对了 24 条', () => expect(count, 24));
}
