// 开发用的小工具（不是测试）：把一个样例（test/support/proto_lc.dart 的写法）交给规矩版本 2 的生成器，把生成的整套文件写进一个目录，
// 方便手工看、手工跑。用法：dart run test/support/gen2_dump_one.dart <样例.lc> <语言|all> <输出目录>
// 多模块的样例（开头是 `(模块 …)`）自动按程序读。类型检查没过就把问题一条条打出来，退出码 2。
import 'dart:io';

import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'proto_lc.dart';

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('用法：dart run test/support/gen2_dump_one.dart <样例.lc> <语言|all> <输出目录>');
    exit(64);
  }
  final src = File(args[0]).readAsStringSync();
  final isProgram = lcParse(src).any((d) => d is List && d.isNotEmpty && d[0] == '模块');
  final module = isProgram ? linkProgram(lcProgram(src)).module : lcModule(src);
  if (module == null) {
    for (final i in linkProgram(lcProgram(src)).issues) {
      stderr.writeln('${i.code} ${i.message}');
    }
    exit(2);
  }
  final result = checkModuleTypes(module);
  for (final i in result.issues) {
    stderr.writeln('${i.isError ? '错' : '提'} ${i.code} [${i.where}] ${i.message}');
  }
  if (result.hasErrors) exit(2);
  for (final language in args[1] == 'all' ? kGen2Languages : [args[1]]) {
    try {
      final files = gen2Files(language, module, result);
      for (final f in files.entries) {
        File('${args[2]}/$language/${f.key}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.value);
      }
    } on LangUnsupported catch (e) {
      stderr.writeln('$language 生成不了：${e.message}');
      exitCode = 3;
    }
  }
}
