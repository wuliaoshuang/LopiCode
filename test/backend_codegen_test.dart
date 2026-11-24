// 后端积木的代码生成：中间形式、转义与注入、生成物的样子、注册表。
// 真跑起来的检查在 test/backend_conformance_test.dart。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/target_python.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);

BeDocument _one(List<LcBlock> body, {String path = '/x'}) {
  final doc = BeDocument(
    variables: [
      LcVariable(name: 's'),
      LcVariable(name: 'n', type: 'number', initial: 2),
    ],
    collections: [BeCollection(name: 'todos')],
  );
  doc.addRoute('GET', path)!.body.addAll(body);
  return doc;
}

/// 生成的源码里所有不在字符串和注释里的部分（粗略：去掉双引号字符串和整行注释）。
String _codeOnly(String source, String commentMark) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith(commentMark)) continue;
    out.writeln(line.replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""'));
  }
  return out.toString();
}

void main() {
  group('字符串字面量', () {
    test('beQuoted：只留可见的安全字符，其余都转义；按 JSON 读回来还是原文', () {
      const samples = [
        '',
        '普通文字 abc',
        '引号"和\'',
        r'反斜杠\ 和 \n',
        '换行\n回车\r制表\t',
        '\u0000\u0001\u001f\u007f\u0085\u2028\u2029',
        r'${x} #{y} %s {0} `x`',
        '</script><!-- */ """',
        "'''",
        '😀👨‍👩‍👧',
        kConformanceNasty,
      ];
      for (final s in samples) {
        final q = beQuoted(s);
        expect(jsonDecode(q), s, reason: q);
        expect(q, isNot(matches(RegExp(r'[\u0000-\u001f\u007f\u0085\u2028\u2029]'))), reason: '不许有原样的控制字符和换行类字符');
        expect(q.startsWith('"') && q.endsWith('"'), isTrue);
        // 中间没有没转义的双引号
        expect(RegExp(r'^"(?:[^"\\]|\\.)*"$').hasMatch(q), isTrue, reason: q);
      }
    });

    test('不成对的代理项换成 U+FFFD（生成的文件必须是合法 UTF-8）', () {
      final lone = String.fromCharCodes([0x61, 0xD800, 0x62, 0xDC00]);
      expect(beWellFormed(lone), 'a\uFFFDb\uFFFD');
      expect(beWellFormed('😀'), '😀');
      expect(beQuoted(lone), '"a\uFFFDb\uFFFD"');
    });

    test('注释：换行类字符都去掉，拆开会结束注释 / 脚本的写法', () {
      final c = beComment('第一行\n第二行\r\u2028\u0085*/ </script> 尾');
      expect(c, isNot(matches(RegExp(r'[\u0000-\u001f\u007f\u0085\u2028\u2029]'))));
      expect(c, isNot(contains('*/')));
      expect(c, isNot(contains('</')));
      expect(beComment('很长' * 500).length, lessThan(300));
    });

    test('数字字面量：整数不带小数点，不是有限数当 0', () {
      expect(beNumberLiteral(3), '3');
      expect(beNumberLiteral(3.0), '3');
      expect(beNumberLiteral(-2.5), '-2.5');
      expect(beNumberLiteral(double.nan), '0');
      expect(beNumberLiteral(double.infinity), '0');
      expect(beNumberLiteral(-0.0), '0');
      expect(beNumberLiteral(1e21), '1e+21');
      expect(beNumberLiteral(2.5e-10), '2.5e-10');
    });
  });

  group('中间形式', () {
    test('每种运算都是一次小库函数调用；函数名都在表上', () {
      final program = lowerBackend(
        _one([
          _b('respondJson', {'status': exNum(200), 'value': exBin('+', exVar('n'), exBin('*', exNum(2), bePathParam('id')))}),
        ], path: '/x/:id'),
      );
      final ret = program.routes.single.body.whereType<BeSReturn>().single;
      final call = ret.response;
      expect(call.fn, 'sendJson');
      final add = call.args[1] as BeXCall;
      expect(add.fn, 'add');
      expect((add.args[0] as BeXVar).name, 'n');
      expect(((add.args[1] as BeXCall).args[1] as BeXCall).fn, 'pathParam');
      expect([for (final v in program.routes.single.variables) v.name], ['n']);
    });

    test('只声明用到的变量，初始值按类型', () {
      final program = lowerBackend(
        _one([
          _b('setVar', {'name': 's', 'value': exNum(1)}),
        ]),
      );
      expect([for (final v in program.routes.single.variables) '${v.name}=${beInitialValue(v)}'], ['s=']);
      expect(beInitialValue(LcVariable(name: 'a', type: 'number', initial: 4)), 4);
      expect(beInitialValue(LcVariable(name: 'a', type: 'bool')), false);
    });

    test('名字不是标识符的变量 / 集合 / 接口不进生成的代码', () {
      final doc = BeDocument.fromJson({
        'variables': [
          {'name': 'ok'},
        ],
        'collections': [
          {'name': 'todos'},
        ],
        'routes': [
          {'id': 'r1', 'method': 'GET', 'path': '/a"); process.exit(1); ("', 'body': <Object>[]},
          {'id': 'r2', 'method': 'GET', 'path': '/ok', 'body': <Object>[]},
        ],
      }).doc;
      doc.routes[1].body.addAll([
        _b('setVar', {'name': 'x; import os', 'value': exNum(1)}),
        _b('dbInsert', {'collection': 'todos"); evil(); ("', 'value': beBody()}),
        _b(
          'forEach',
          {'list': beDbAll('a b'), 'item': 'ok'},
          body: [
            _b('log', {'value': exVar('__import__("os")')}),
          ],
        ),
      ]);
      final program = lowerBackend(doc);
      expect([for (final r in program.routes) r.path], ['/ok']);
      expect(program.skipped.single, contains('路径'));
      for (final t in backendTargets) {
        final files = t.generate(doc);
        final code = _codeOnly(files[t.entryFile]!, t.id == 'python' ? '#' : '//');
        for (final bad in ['evil', 'process.exit', 'import os', '__import__', 'a b']) {
          expect(code, isNot(contains(bad)), reason: '${t.id}: $bad');
        }
      }
    });

    test('返回之后的积木不生成；套得太深的不生成', () {
      final program = lowerBackend(
        _one([
          _b('respondText', {'status': exNum(200), 'value': exText('a')}),
          _b('log', {'value': exText('不该出现')}),
        ]),
      );
      final body = program.routes.single.body;
      expect(body.whereType<BeSReturn>(), hasLength(1));
      expect(body.whereType<BeSDo>(), isEmpty);
      expect(body.last, isA<BeSNote>());

      var deep = _b('log', {'value': exText('最里面')});
      for (var i = 0; i < 40; i++) {
        deep = _b('if', {'cond': exBool(true)}, body: [deep]);
      }
      for (final t in backendTargets) {
        final src = t.generate(_one([deep]))[t.entryFile]!;
        expect(src, isNot(contains('"最里面"')), reason: t.id);
      }
    });
  });

  group('生成物', () {
    test('注册表：id 不重复、和文档默认语言对得上、每个都有启动命令', () {
      expect({for (final t in backendTargets) t.id}.length, backendTargets.length);
      expect(backendTargetFor(kBeDefaultLanguage), isNotNull);
      expect(backendTargetFor('cobol'), isNull);
      expect(generateBackend(BeDocument(language: 'cobol')), isNull);
      expect(generateBackend(BeDocument(language: 'cobol'), language: 'python')!.target.id, 'python');
      for (final t in backendTargets) {
        expect(t.label, isNotEmpty);
        expect(t.summary, isNotEmpty);
        expect(t.startCommand, isNotEmpty);
        expect(beNamePattern.hasMatch(t.id), isTrue);
      }
    });

    test('每种语言：入口 + 小库 + README；空文档也能生成；文件都是合法 UTF-8、以换行结尾', () {
      for (final t in backendTargets) {
        for (final doc in [BeDocument(), conformanceDocument()]) {
          final files = t.generate(doc);
          expect(files.keys, containsAll([t.entryFile, 'README.md']));
          expect(files, hasLength(3), reason: t.id);
          for (final f in files.entries) {
            expect(f.key, isNot(anyOf(startsWith('/'), contains('..'))));
            expect(f.value.endsWith('\n'), isTrue, reason: f.key);
            expect(utf8.decode(utf8.encode(f.value)), f.value);
            expect(f.value, isNot(contains('\uFFFD')), reason: '${t.id} ${f.key} 里有坏字符');
            expect(f.value, isNot(contains('\r')));
          }
          expect(files['README.md'], contains(t.startCommand.join(' ')));
          expect(files['README.md'], contains('${doc.port}'));
        }
      }
    });

    test('生成的入口文件：每个接口一段中文注释，每块积木一行读法；用户的文字只出现在字符串和注释里', () {
      final doc = conformanceDocument();
      for (final t in backendTargets) {
        final src = t.generate(doc)[t.entryFile]!;
        final mark = t.id == 'python' ? '#' : '//';
        expect(src, contains('$mark 接口：GET /todos/:id'));
        expect(src, contains('$mark 把 todo 设为 集合 todos 里 id 是 路径参数 id 的那条'));
        final code = _codeOnly(src, mark);
        expect(code, isNot(matches(RegExp(r'[\u4e00-\u9fff😀]'))), reason: '${t.id}：字符串和注释之外不该有用户的文字');
        expect(code, isNot(contains('script')));
        // 每行都没有行尾空格、没有制表符
        for (final line in src.split('\n')) {
          expect(line, isNot(endsWith(' ')), reason: line);
          expect(line, isNot(contains('\t')));
        }
      }
    });

    test('Node：字符串里的 </ 和 <!-- 被拆开；关键字当变量名不碍事', () {
      final src = backendTargetFor('node')!.generate(conformanceDocument())['server.js']!;
      expect(_codeOnly(src, '//'), isNot(contains('</')));
      expect(src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n'), isNot(anyOf(contains('</script'), contains('<!--'))));
      expect(src, contains('let v_class = 1;'));
      expect(src, contains('await lc.fetch('));
      expect(RegExp(r'(?<!await )lc\.fetch\(').hasMatch(src), isFalse, reason: '请求别的网址都要等');
    });

    test('Python：函数名转成下划线写法；空的分支补 pass', () {
      expect(PythonBackendTarget.snake('dbGet'), 'db_get');
      expect(PythonBackendTarget.snake('sendJson'), 'send_json');
      expect(PythonBackendTarget.snake('add'), 'add');
      final src = backendTargetFor('python')!.generate(
        _one([
          _b('if', {'cond': exBool(true)}),
          _b('repeat', {'times': exNum(2)}),
          _b('forEach', {'list': beDbAll('todos'), 'item': 's'}),
          _b('fetch', {'url': exText('http://a'), 'method': 'GET'}),
        ]),
      )['server.py']!;
      expect('pass'.allMatches(src).length, greaterThanOrEqualTo(2));
      final py = backendTargetFor('python')!.generate(conformanceDocument())['server.py']!;
      expect(py, contains('v_def = 2'));
      expect(py, contains('lc.db_get("todos", lc.path_param(req, "id"))'));
    });

    test('小库实现了表上的每个函数（按名字找得到）', () {
      final node = backendTargetFor('node')!.generate(BeDocument())['lc_runtime.js']!;
      final exports = node.substring(node.indexOf('module.exports'));
      final py = backendTargetFor('python')!.generate(BeDocument())['lc_runtime.py']!;
      for (final fn in kBeRuntimeFns.keys) {
        expect(RegExp('\\b$fn\\b').hasMatch(exports), isTrue, reason: 'lc_runtime.js 没导出 $fn');
        expect(py, contains('\ndef ${PythonBackendTarget.snake(fn)}('), reason: 'lc_runtime.py 没有 $fn');
      }
      for (final fn in kBeBoolFns) {
        expect(kBeRuntimeFns.containsKey(fn), isTrue);
      }
      expect(node, contains('$kBeRepeatLimit'));
      expect(py, contains('$kBeBodyLimit'));
      expect(py, contains('FETCH_TIMEOUT_SECONDS = $kBeFetchTimeoutSeconds'));
      expect(node, contains('FETCH_TIMEOUT_MS = ${kBeFetchTimeoutSeconds * 1000}'));
    });

    test('小库只用自带的东西：不 require / import 第三方包', () {
      final node = backendTargetFor('node')!.generate(conformanceDocument());
      final requires = {for (final f in node.values) ...RegExp(r'require\("([^"]+)"\)').allMatches(f).map((m) => m[1]!)};
      expect(requires, {'node:http', './lc_runtime.js'});
      final py = backendTargetFor('python')!.generate(conformanceDocument());
      final imports = {for (final f in py.values) ...RegExp(r'^(?:import|from) ([a-z_.]+)', multiLine: true).allMatches(f).map((m) => m[1]!.split('.').first)};
      expect(imports, {'json', 'math', 'os', 're', 'sys', 'threading', 'time', 'traceback', 'urllib', 'decimal', 'http', 'lc_runtime'});
    });
  });

  test('lib/backend 不带界面：不 import 界面库；每个文件不超过 600 行', () {
    for (final f in Directory('lib/backend').listSync().whereType<File>()) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('package:flutter/')), reason: f.path);
      expect(text, isNot(contains("import '../")), reason: f.path);
      expect(text.split('\n').length, lessThanOrEqualTo(600), reason: f.path);
    }
  });
}
