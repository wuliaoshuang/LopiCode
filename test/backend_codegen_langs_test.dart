// 后端积木：Node / Python 之外各语言生成器的结构检查（字面量、转义、关键片段、小库有没有漏函数）。
// 能真跑的语言（Go、Java）另有 test/backend_conformance_test.dart 真的编译、启动、发请求。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/target_go.dart';
import 'package:lopicode/backend/target_java.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);

/// 各语言里都容易出事的文字：引号、反斜杠、换行、各种插值符号、`</script>`、`?>`、注释结束符、U+2028、U+FEFF、
/// 写成文字的 `\u000a`（Java 会在注释里把它当成真的换行）、控制字符。
const String kTricky = '引号"\'反斜杠\\换行\n回车\r制表\t \${x} \$y #{z} {0} {{a}} @b %s `c` </script> ?> <?php */ /* \u2028\u2029\u0085\ufeff \\u000a \\u0022 \u0000\u0001\u001a\u007f 😀';

BeDocument _doc(List<LcBlock> body) {
  final doc = BeDocument(
    name: 'x \\u000a evil(); */ ?> $kTricky',
    variables: [
      LcVariable(name: 's'),
      LcVariable(name: 'n', type: 'number', initial: 2),
      LcVariable(name: 'class', type: 'number', initial: 1.5),
    ],
    collections: [BeCollection(name: 'todos')],
  );
  doc.addRoute('GET', '/x/:id')!.body.addAll(body);
  return doc;
}

BeDocument _trickyDoc() => _doc([
  _b('setVar', {'name': 's', 'value': exText(kTricky)}),
  _b('setVar', {'name': 'class', 'value': exNum(1e21)}),
  _b('log', {
    'value': exJoin([beField(beObj({}), 'x')]),
  }),
  _b('respondJson', {
    'status': exNum(200),
    'value': beObj({kTricky: exVar('s'), 'n': exNum(-42), 'half': exNum(0.5)}),
  }),
]);

/// 源码里所有双引号字符串字面量的内容都去掉以后剩下的部分（粗略）。
String _withoutStrings(String source) => source.replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

void _expectNoRawSpecials(String source, String where) {
  expect(source, isNot(matches(RegExp('[\\x00-\\x08\\x0b-\\x1f\\x7f\\u0085\\u2028\\u2029\\ufeff]'))), reason: '$where：源码里不许有原样的控制字符 / 换行类字符 / BOM');
}

void main() {
  test('beQuotedWith：指定的字符加反斜杠，控制字符按给的写法转义，其余原样', () {
    expect(beQuotedWith('a"b\\c\$d\n\t\r', escape: r'$', unicode: beUnicodeBraced), r'"a\"b\\c\$d\n\t\r"');
    expect(beQuotedWith('\u0001\u007f\u2028\ufeff', unicode: beUnicode4), r'"\u0001\u007f\u2028\ufeff"');
    expect(beQuotedWith('\u0001\u2028', unicode: beUnicodeBraced), r'"\u{1}\u{2028}"');
    expect(beQuotedWith('中文😀 #{x}', escape: '#', unicode: beUnicode4), r'"中文😀 \#{x}"');
    expect(beQuotedWith(String.fromCharCodes([0x61, 0xD800]), unicode: beUnicode4), '"a\uFFFD"');
    expect(beComment('a\ufeffb'), 'a b');
  });

  group('Go', () {
    const target = GoBackendTarget();

    test('数字都带小数点（Go 里才是 float64）；空是 nil；U+FEFF 写成转义', () {
      expect(target.literal(200), '200.0');
      expect(target.literal(-42), '-42.0');
      expect(target.literal(0.5), '0.5');
      expect(target.literal(1e21), '1e+21');
      expect(target.literal(2.5e-10), '2.5e-10');
      expect(target.literal(null), 'nil');
      expect(target.literal(true), 'true');
      expect(target.literal('a\ufeffb'), r'"a\ufeffb"');
      expect(target.call('dbGet', ['"todos"', 'x']), 'lc.DbGet("todos", x)');
    });

    test('刁钻的文字：只出现在字符串和注释里，源码里没有原样的控制字符', () {
      final files = target.generate(_trickyDoc());
      final src = files['main.go']!;
      _expectNoRawSpecials(src, 'main.go');
      final code = _withoutStrings(src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n'));
      expect(code, isNot(anyOf(contains('evil'), contains('script'), contains('php'), contains('"'.padRight(2, 'x')))));
      expect(code.replaceAll('""', ''), isNot(contains('"')), reason: '字符串都成对');
      expect(src, contains('var v_class any = 1.5'));
      expect(src, contains('_ = v_class'));
      expect(src, contains('v_class = 1e+21'));
      expect(src, contains('lc.Join(lc.Field(lc.Obj(), "x"))'));
      expect(src, contains('"n", -42.0'));
    });

    test('没有“怎么走都会返回”的接口末尾补 return nil；一定返回的不补', () {
      final open = target.generate(
        _doc([
          _b(
            'if',
            {'cond': exBool(true)},
            body: [
              _b('respondText', {'status': exNum(200), 'value': exText('a')}),
            ],
          ),
        ]),
      )['main.go']!;
      expect(open, contains('\treturn nil\n}'));
      final closed = target.generate(_trickyDoc())['main.go']!;
      expect(closed, isNot(contains('return nil')));
      final empty = target.generate(BeDocument())['main.go']!;
      expect(empty, contains('func main() {\n\tlc.Start(8080)\n}'));
    });

    test('go.mod：模块名是写死的安全名字，go 版本写保守值；启动命令', () {
      final files = target.generate(_trickyDoc());
      expect(files['go.mod'], 'module $kGoModuleName\n\ngo 1.18\n');
      expect(RegExp(r'^[a-z]+$').hasMatch(kGoModuleName), isTrue);
      expect(files['main.go'], contains('import "$kGoModuleName/lc"'));
      expect(target.buildCommands, [
        ['go', 'build', '-o', 'server', '.'],
      ]);
      expect(target.startCommand, ['./server']);
      expect(target.verified, isTrue);
      expect(target.summary, contains('真跑'));
    });

    test('小库实现了表上的每个函数；只 import 标准库', () {
      final files = target.generate(conformanceDocument());
      final lib = [
        for (final f in files.entries)
          if (f.key.startsWith('lc/')) f.value,
      ].join('\n');
      for (final fn in kBeRuntimeFns.keys) {
        expect(lib, contains('\nfunc ${fn[0].toUpperCase()}${fn.substring(1)}('), reason: '小库没有 $fn');
      }
      for (final fn in ['Collection', 'Route', 'Start']) {
        expect(lib, contains('\nfunc $fn('));
      }
      final imports = {for (final m in RegExp(r'^\t"([^"]+)"$', multiLine: true).allMatches(lib)) m[1]!};
      expect(imports, {'bytes', 'context', 'encoding/json', 'fmt', 'io', 'math', 'net', 'net/http', 'os', 'sort', 'strconv', 'strings', 'sync', 'time', 'unicode/utf8'});
      expect(lib, contains('bodyLimit      = $kBeBodyLimit'));
      expect(lib, contains('repeatLimit    = $kBeRepeatLimit'));
      expect(lib, contains('jsonDepthLimit = $kBeJsonDepthLimit'));
      expect(lib, contains('fetchTimeout = $kBeFetchTimeoutSeconds * time.Second'));
    });
  });

  group('Java', () {
    const target = JavaBackendTarget();

    test('数字都带小数点（才是 Double）；只有一项的“连起来”里的 null 要写明是一个值', () {
      expect(target.literal(200), '200.0');
      expect(target.literal(1e21), '1e+21');
      expect(target.literal(null), 'null');
      expect(target.call('join', ['null']), 'Lc.join((Object) null)');
      expect(target.call('join', ['null', 'null']), 'Lc.join(null, null)');
      expect(target.call('obj', []), 'Lc.obj()');
    });

    test('注释里的 \\u 被拆开（Java 会把注释里的 \\u000a 当成真的换行）', () {
      expect(javaComment(r'a \u000a evil(); \\u0022 \uuuu000a'), r'a \ u000a evil(); \\ u0022 \ uuuu000a');
      final src = target.generate(_trickyDoc())['Main.java']!;
      for (final line in src.split('\n').where((l) => l.trimLeft().startsWith('//'))) {
        expect(line, isNot(contains(r'\u')), reason: line);
      }
      _expectNoRawSpecials(src, 'Main.java');
    });

    test('字符串里的反斜杠都成对：写成文字的 \\u000a 不会被当成转义', () {
      expect(target.literal(r'\u000a'), r'"\\u000a"');
      expect(target.literal('a\nb"'), r'"a\nb\""');
      // 字面量里出现的 \uXXXX 只会是我们自己写的控制字符转义，而且不会是换行、回车、引号、反斜杠（那几个有短写法）
      final lit = target.literal(kTricky);
      for (final m in RegExp(r'(?<!\\)(?:\\\\)*\\u([0-9a-f]{4})').allMatches(lit)) {
        expect(const {'000a', '000d', '0022', '005c'}.contains(m[1]), isFalse, reason: m[0]);
      }
    });

    test('太长的文字拆成几段在运行时拼（单个字符串常量有 65535 字节的上限）', () {
      final long = '好' * (kJavaLiteralChunk * 2 + 5);
      final lit = javaStringLiteral(long);
      expect(lit, startsWith('String.join("", "'));
      expect(RegExp('"好+"').allMatches(lit).length, 3);
      expect(javaStringLiteral('好' * kJavaLiteralChunk), startsWith('"好'));
      // 拆的时候不会把一个表情拆成两半
      final emoji = javaStringLiteral('😀' * (kJavaLiteralChunk + 1));
      expect(emoji, isNot(contains('\uFFFD')));
    });

    test('一定返回的接口后面不再有代码；其余的末尾补 return null', () {
      final closed = target.generate(_trickyDoc())['Main.java']!;
      expect(closed, isNot(contains('return null;')));
      final open = target.generate(
        _doc([
          _b(
            'repeat',
            {'times': exNum(3)},
            body: [
              _b('respondText', {'status': exNum(200), 'value': exText('a')}),
            ],
          ),
        ]),
      )['Main.java']!;
      expect(open, contains('        return null;\n    }'));
      expect(open, contains('for (int lcI1 = 0, lcN1 = Lc.times(3.0); lcI1 < lcN1; lcI1++) {'));
      final src = target.generate(conformanceDocument())['Main.java']!;
      expect(src, contains('Object v_class = 1.0;'));
      expect(src, contains('Main::route_'));
    });

    test('小库实现了表上的每个函数；只用 JDK 自带的包；不用 Maven / Gradle', () {
      final files = target.generate(conformanceDocument());
      final lib = files['Lc.java']!;
      for (final fn in kBeRuntimeFns.keys) {
        expect(RegExp('\\n    public static [A-Za-z<>]+ $fn\\(').hasMatch(lib), isTrue, reason: 'Lc.java 没有 $fn');
      }
      for (final fn in kBeBoolFns) {
        expect(lib, contains('public static boolean $fn('), reason: '$fn 要返回 boolean');
      }
      final all = files.entries.where((f) => f.key.endsWith('.java')).map((f) => f.value).join('\n');
      final imports = {for (final m in RegExp(r'^import ([a-z.]+)\.[A-Z]', multiLine: true).allMatches(all)) m[1]!};
      expect(imports.every((i) => i.startsWith('java.')), isTrue, reason: '$imports');
      expect(all, isNot(contains('import com.sun')));
      expect(lib, contains('BODY_LIMIT = $kBeBodyLimit;'));
      expect(lib, contains('REPEAT_LIMIT = $kBeRepeatLimit;'));
      expect(lib, contains('JSON_DEPTH_LIMIT = $kBeJsonDepthLimit;'));
      expect(lib, contains('FETCH_TIMEOUT_MS = ${kBeFetchTimeoutSeconds * 1000};'));
      expect(target.buildCommands.single.first, 'javac');
      expect(target.buildCommands.single, containsAll(files.keys.where((k) => k.endsWith('.java'))));
      expect(files['README.md'], contains('不用 Maven / Gradle'));
      expect(target.verified, isTrue);
    });
  });

  test('每个生成器的名字和说明写清了有没有在本机验证过', () {
    for (final t in backendTargets) {
      if (const {'node', 'python'}.contains(t.id)) continue; // 最早做的两种，说明里没写，一致性测试守着
      expect(t.summary, t.verified ? contains('真跑验证') : contains('未实际运行'), reason: t.id);
    }
  });
}
