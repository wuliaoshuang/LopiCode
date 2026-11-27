// 写出器（lib/lang/lc_write.dart）：语法树 → 文字写法。
//
// 1. 仓库里现成的全部样例程序（核心 2、要等的事、小框架、类型原型、演示库、内置“接口服务”库）读进来 → 写出去 → 再读进来，
//    两次生成的 Node 代码一个字不差；写两遍的结果一样。
// 2. 文字的转义规矩：带双引号、反斜杠、换行的文字写成 (字 "…")，读回来一个字不差；老写法 "…" 照旧不做转义。
// 3. 写不了的东西给一句人话，不抛异常。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lc_write.dart';

String _gen(LProgram p) {
  try {
    final files = p.modules.length == 1 ? gen2Files('node', p.modules.single) : gen2ProgramFiles('node', p);
    return [for (final e in files.entries) '== ${e.key}\n${e.value}'].join('\n');
  } on LangUnsupported catch (e) {
    return '生成不了：${e.what}';
  }
}

void main() {
  final sources = <String, LProgram Function()>{};
  for (final dir in ['test/fixtures/core2', 'test/fixtures/waits', 'test/fixtures/framework']) {
    for (final f in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.lc'))) {
      final src = f.readAsStringSync();
      final program = src.trimLeft().startsWith('(模块 ') || src.contains('\n(模块 ');
      sources[f.path] = () => program ? lcProgram(src) : LProgram([lcModule(src)], entry: '');
    }
  }
  for (final d in Directory('docs/blocks-v5-prototypes/types').listSync().whereType<Directory>()) {
    final f = File('${d.path}/prog.lc');
    if (f.existsSync()) sources[f.path] = () => LProgram([lcModule(f.readAsStringSync())], entry: '');
  }
  for (final f in Directory('test/fixtures/libs/demo-kit/modules').listSync().whereType<File>()) {
    sources[f.path] = () {
      final p = lcProgram(f.readAsStringSync());
      return LProgram([
        ...p.modules,
        LModule(name: 'main', uses: [for (final m in p.modules) m.name]),
      ], entry: 'main');
    };
  }
  sources['内置库 接口服务'] = () {
    final lib = beServiceLibrary();
    return LProgram([...lib.modules, LModule(name: 'main', uses: lib.moduleNames)], entry: 'main');
  };

  test('现成的样例够多（少了说明目录挪了）', () => expect(sources.length, greaterThan(60)));

  test('读 → 写 → 读：生成的代码一个字不差，写两遍也一样', () {
    var done = 0;
    for (final e in sources.entries) {
      final LProgram first;
      try {
        first = e.value();
      } on Object {
        continue; // 故意写坏、读不了的样例不归这里管
      }
      final w = LcWriter();
      final text = first.modules.length == 1 && first.entry.isEmpty ? w.module(LModule(name: 'm', decls: first.modules.single.decls, body: first.modules.single.body), main: true) : w.program(first);
      final second = lcProgram(text.contains('(入口 ') ? text : '$text(入口 m)\n');
      final a = first.modules.length == 1 && first.entry.isEmpty ? LProgram([LModule(name: 'm', decls: first.modules.single.decls, body: first.modules.single.body)], entry: 'm') : first;
      expect(_gen(second), _gen(a), reason: e.key);
      expect(LcWriter().program(second), LcWriter().program(a), reason: '${e.key}（写两遍）');
      done++;
    }
    expect(done, greaterThan(60));
  });

  test('文字的转义：双引号、反斜杠、换行、制表都能存，读回来一个字不差', () {
    for (final s in ['', '你好', 'a"b', r'a\b', r'结尾是反斜杠\', 'a\nb', 'a\r\nb', 'tab\t这里', r'\n 不是换行', '"', r'\"', '(括号) ; 分号', '😀 表情']) {
      final text = lcWriteLiteral(s);
      final back = LcReader(const []).expr(lcParse(text).single);
      expect(back, isA<LLit>());
      expect((back as LLit).value, s, reason: text);
    }
    expect(lcWriteLiteral('你好'), '"你好"');
    expect(lcWriteLiteral('a"b'), r'(字 "a\"b")');
  });

  test('老写法不变：直接写的 "…" 里反斜杠就是反斜杠', () {
    final e = LcReader(const []).expr(lcParse(r'"a\nb"').single) as LLit;
    expect(e.value, r'a\nb');
  });

  test('数、是否、空', () {
    for (final v in <Object?>[null, true, false, 0, -5, 9007199254740991, 1.0, -2.5, 1e21, 1.5e-7]) {
      final back = LcReader(const []).expr(lcParse(lcWriteLiteral(v)).single) as LLit;
      expect(back.value, v);
      expect(back.value.runtimeType, v.runtimeType);
    }
  });

  test('写不了的给一句人话', () {
    expect(lcTryWriteModule(const LModule(name: '有 空格')).problem, contains('名字'));
    expect(lcTryWriteModule(const LModule(name: 'm', decls: [LVarDecl('x', LLit(double.nan))])).problem, contains('数'));
    expect(
      lcTryWriteModule(
        const LModule(
          name: 'm',
          decls: [
            LFuncDecl('f', [], [LHost('x')]),
          ],
        ),
      ).problem,
      contains('接口服务'),
    );
    expect(lcTryWriteModule(const LModule(name: 'm', decls: [LVarDecl('空', LLit(1))])).problem, contains('名字'));
  });
}
