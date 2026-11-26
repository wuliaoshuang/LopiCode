// 开发时用的小工具（不是测试）：把类型原型的 16 个程序用版本 2 的生成器生成出来，写到一个目录里，方便手工跑、对照。
// 用法：dart run test/support/gen2_dump.dart <语言> <输出目录> [程序名…]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';

import 'proto_lc.dart';

void main(List<String> args) {
  final language = args[0], out = args[1];
  final only = args.skip(2).toSet();
  final root = Directory('docs/blocks-v5-prototypes/types');
  final dirs = root.listSync().whereType<Directory>().where((d) => RegExp(r'/p\d\d').hasMatch(d.path)).toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final d in dirs) {
    final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (only.isNotEmpty && !only.any(name.startsWith)) continue;
    final dir = Directory('$out/$name')..createSync(recursive: true);
    try {
      final files = gen2Files(language, lcModule(File('${d.path}/prog.lc').readAsStringSync()));
      for (final f in files.entries) {
        File('${dir.path}/${f.key}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.value);
      }
      print('$name 生成好了');
    } on LangUnsupported catch (e) {
      print('$name 生成不了：${e.what}');
    }
  }
}
