// 后端积木一致性测试：同一份样本模型翻成每种语言，真的把服务起起来（随机端口、只连 127.0.0.1），
// 发同一串请求——每条响应都要等于写死的期望值，各语言之间逐字节相同。
//
// 加一种语言：在 [_languages] 里加一行（语言 id → 本机要有的命令，只用来写“跳过”的原因），
// 再在 test/support/backend_conformance.dart 的 `toolchainFor` 里写怎么找它。本机没有对应工具时跳过并打印原因。
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';
import 'support/wait.dart';

/// 语言 id → 本机要有的命令。
const Map<String, String> _languages = {'node': 'node', 'python': 'python3', 'go': 'go', 'java': 'javac', 'php': 'php'};

/// 语法检查：语言 id → 对一个文件做语法检查的命令（文件路径接在最后）。
/// Go 和 Java 要编译，编译不过一致性测试那一条就会失败，这里不重复；Go 另有一条查 gofmt / go vet。
const Map<String, List<String>> _syntaxChecks = {
  'node': ['node', '--check'],
  'python': ['python3', '-m', 'py_compile'],
  'php': ['php', '-l'],
};

void _collectFns(List<BeS> list, Set<String> out) {
  void x(BeX e) {
    if (e is BeXCall) {
      out.add(e.fn);
      e.args.forEach(x);
    }
  }

  for (final s in list) {
    switch (s) {
      case BeSNote():
        break;
      case BeSSet(:final value) || BeSLet(:final value):
        x(value);
      case BeSDo(:final call):
        x(call);
      case BeSIf(:final cond, :final then, :final orElse):
        x(cond);
        _collectFns(then, out);
        _collectFns(orElse, out);
      case BeSRepeat(:final times, :final body):
        x(times);
        _collectFns(body, out);
      case BeSForEach(:final list, :final body):
        x(list);
        _collectFns(body, out);
      case BeSReturn(:final response):
        x(response);
    }
  }
}

/// 各语言里都容易出事的文字：全部 ASCII（含控制字符）、各种插值符号、写成文字的 `\u000a`（Java 在注释里也会把它当换行）、
/// U+2028 / U+FEFF、表情，再加一段很长的（Java 单个字符串常量有 65535 字节的上限）。
final String _tricky =
    '${String.fromCharCodes([for (var i = 0; i < 128; i++) i])}\u0085\u2028\u2029\ufeff'
    r' \u000a \u0022 \\u000a ${x} $y #{z} #$g #@i {0} {{a}} %s %d </script> <!-- ?> <?php */ /* '
    '😀${'好e\u0301' * 30000}';

/// 用各语言的关键字当变量名、文字里全是刁钻字符的一份后端：GET /t 把那段文字原样返回。
BeDocument _trickyDocument() {
  const names = [
    'int',
    'new',
    'var',
    'type',
    'function',
    'fn',
    'val',
    'object',
    'end',
    'echo',
    'match',
    'string',
    'package',
    'import',
    'nil',
    'null',
    'true',
    'self',
    'this',
    'lc',
    'req',
    'Lc',
    'main',
  ];
  final doc = BeDocument(
    name:
        r'x \u000a evil(); \u0022 */ ?> </script> '
        '\u2028\ufeff',
    variables: [for (final n in names) LcVariable(name: n, type: 'number', initial: 1)],
    collections: [BeCollection(name: 'int')],
  );
  final blocks = <LcBlock>[
    for (final n in names.skip(1)) LcBlock(op: 'changeVar', args: {'name': names.first, 'by': exVar(n)}),
    LcBlock(
      op: 'log',
      args: {
        'value': exJoin([beField(beObj({}), 'x')]),
      },
    ),
    LcBlock(
      op: 'respondJson',
      args: {
        'status': exNum(200),
        'value': beObj({'text': exText(_tricky), 'sum': exVar(names.first), _tricky.substring(0, 200): exNum(1)}),
      },
    ),
  ];
  doc.addRoute('GET', '/t')!.body.addAll(blocks);
  return doc;
}

/// 文字写成 JSON 的样子（值的规矩：只转义 `"`、`\\`、U+0000–U+001F）。
String _jsonText(String s) => jsonEncode(s).replaceAll(r'\u007f', '\x7f');

void main() {
  test('样本模型用到了运行时小库的每一个函数、每一种积木和表达式（这样跑通＝每个函数都真的跑过）', () {
    final program = lowerBackend(conformanceDocument());
    final used = <String>{};
    for (final r in program.routes) {
      _collectFns(r.body, used);
    }
    expect(kBeRuntimeFns.keys.toSet().difference(used), isEmpty, reason: '样本没用到的函数');
    expect(used.difference(kBeRuntimeFns.keys.toSet()), isEmpty, reason: '中间形式里出现了表上没有的函数');
    expect(program.skipped, isEmpty);
  });

  test('样本模型除了故意留的坑（/holes）之外没有校验错误', () {
    final doc = conformanceDocument();
    final holes = doc.routes.firstWhere((r) => r.path == '/holes').id;
    final errors = [
      for (final i in validateBackend(doc, languages: [for (final t in backendTargets) t.id]))
        if (i.isError && i.handlerId != holes) i,
    ];
    expect(errors, isEmpty);
  });

  final results = <String, List<BeResponse>>{};
  for (final entry in _languages.entries) {
    final language = entry.key;
    test('$language：生成的工程能启动，${conformanceCases.length} 条请求的响应都等于期望值', () async {
      final tools = await toolchainFor(language);
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过 $language 的一致性测试：本机找不到 ${entry.value} 命令');
        markTestSkipped('本机找不到 ${entry.value} 命令');
        return;
      }
      results[language] = await runConformance(language, tools);
    });

    test('$language：关键字当变量名、文字里全是刁钻字符的后端也能（编译）启动，文字原样返回', () async {
      final tools = await toolchainFor(language);
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过 $language 的刁钻文字检查：本机找不到 ${entry.value} 命令');
        markTestSkipped('本机找不到 ${entry.value} 命令');
        return;
      }
      final generated = generateBackend(_trickyDocument(), language: language)!;
      final dir = writeProject(generated.files, 'be_tricky_${language}_');
      try {
        await buildProject(generated.target, dir, tools);
        final server = await startBackend(dir, tools.resolve(generated.target.startCommandFor(0), dir), environment: tools.environment);
        try {
          final r = await sendRaw(server.port, 'GET', '/t');
          expect(r.status, 200, reason: '${server.stderrText}');
          // 键按码点排：那段文字的开头是 U+0000，排在 sum 和 text 前面
          final expected = '{${_jsonText(_tricky.substring(0, 200))}:1,"sum":23,"text":${_jsonText(_tricky)}}';
          expect(utf8.decode(r.body), expected);
          await waitUntilReal(() => server.stdoutLines.isNotEmpty, '服务把那一行日志写到标准输出');
          expect(server.stdoutLines, [''], reason: '“写到日志”一个空值：一个空行');
        } finally {
          await server.stop();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('$language：生成的文件语法检查通过', () async {
      final check = _syntaxChecks[language];
      if (check == null) return; // 要编译的语言：上面那条已经编译过了
      final tools = await toolchainFor(language);
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过 $language 的语法检查：本机找不到 ${entry.value} 命令');
        markTestSkipped('本机找不到 ${entry.value} 命令');
        return;
      }
      final generated = generateBackend(conformanceDocument(), language: language)!;
      final dir = writeProject(generated.files, 'be_syntax_${language}_');
      try {
        for (final name in generated.files.keys.where((n) => !n.endsWith('.md'))) {
          final command = tools.resolve([...check, name], dir);
          final r = await Process.run(command.first, command.sublist(1), workingDirectory: dir.path);
          expect(r.exitCode, 0, reason: '$name：\n${r.stdout}\n${r.stderr}');
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }

  test('go：生成的工程已经是 gofmt 的规范格式，go vet 没有意见', () async {
    final tools = await toolchainFor('go');
    if (tools == null) {
      // ignore: avoid_print 跳过的原因要让跑测试的人看见
      print('跳过 gofmt / go vet 检查：本机找不到 go 命令');
      markTestSkipped('本机找不到 go 命令');
      return;
    }
    final generated = generateBackend(conformanceDocument(), language: 'go')!;
    final dir = writeProject(generated.files, 'be_syntax_go_');
    try {
      final fmt = await Process.run(tools.executables['gofmt']!, const ['-l', '.'], workingDirectory: dir.path, environment: tools.environment);
      expect(fmt.exitCode, 0, reason: '${fmt.stderr}');
      expect('${fmt.stdout}'.trim(), isEmpty, reason: '这些文件 gofmt 还想改：\n${fmt.stdout}');
      final vet = await Process.run(tools.executables['go']!, const ['vet', './...'], workingDirectory: dir.path, environment: tools.environment);
      expect(vet.exitCode, 0, reason: 'go vet：\n${vet.stdout}\n${vet.stderr}');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('各语言的响应逐字节相同', () {
    if (results.length < 2) {
      // ignore: avoid_print 跳过的原因要让跑测试的人看见
      print('跳过“各语言互相比”：真跑起来的语言不到两种（${results.keys.join('、')}）');
      markTestSkipped('真跑起来的语言不到两种');
      return;
    }
    final first = results.entries.first;
    for (final other in results.entries.skip(1)) {
      for (var i = 0; i < conformanceCases.length; i++) {
        if (conformanceCases[i].pattern != null) continue; // 现在的时间：两边差一秒是正常的
        final a = first.value[i];
        final b = other.value[i];
        final where = '第 ${i + 1} 条 ${conformanceCases[i]}：${first.key} 和 ${other.key} 不一样';
        expect(b.status, a.status, reason: where);
        expect(b.type, a.type, reason: where);
        expect(b.body, a.body, reason: where);
      }
    }
  });
}
