// 语言核心一致性测试的支撑：用语法树搭程序 → 生成四种语言的脚本 → 真的跑起来 → 拿标准输出。
// 运行时小库的文件直接取后端生成器带的那几份（lc_runtime.js、lc/values.go…），外加语言核心自己的那一份。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lang/lang.dart';

import 'backend_conformance.dart';

// —— 搭语法树的小写法 ——

LExpr n(num v) => LLit(v);
LExpr t(String v) => LLit(v);
const LExpr nul = LLit(null);
const LExpr yes = LLit(true);
const LExpr no = LLit(false);
LExpr v(String name) => LName(name);
LExpr rt(String fn, [List<LExpr> args = const []]) => LRt(fn, args);
LExpr bin(String op, LExpr l, LExpr r) => LBinary(op, l, r);
LExpr list([List<LExpr> items = const []]) => LListLit(items);
LExpr dict([Map<String, LExpr> entries = const {}]) => LDictLit([for (final e in entries.entries) LDictEntry(LLit(e.key), e.value)]);
LExpr at(LExpr of, LExpr key) => LIndex(of, key);
LExpr json(LExpr e) => rt('toJson', [e]);
LStmt log(LExpr e) => LExprStmt(rt('log', [e]));
LStmt logJson(LExpr e) => log(json(e));
LStmt let(String name, LExpr value, {bool isConst = false}) => LLet(name, value, isConst: isConst);
LStmt set(String name, LExpr value) => LAssign(LTName(name), value);
LStmt setAt(LExpr of, LExpr key, LExpr value) => LAssign(LTIndex(of, key), value);
LStmt run(LExpr e) => LExprStmt(e);
LStmt iff(LExpr cond, List<LStmt> then, [List<LStmt> orElse = const []]) => LIf([LIfArm(cond, then)], orElse: orElse);

/// 一个用例：一段程序 ＋ 写死的预期输出（一行一项）。
class LangCase {
  const LangCase(this.name, this.body, this.expected);
  final String name;
  final List<LStmt> body;
  final List<String> expected;
}

/// 一批“算这个式子，结果写成 JSON 应该是这样”的用例。
LangCase vals(String name, List<(LExpr, String)> pairs) => LangCase(name, [for (final p in pairs) logJson(p.$1)], [for (final p in pairs) p.$2]);

/// 跑一次的结果。
class LangRun {
  const LangRun(this.exitCode, this.out, this.err);
  final int exitCode;
  final String out;
  final String err;
}

const Map<String, String> kLangScriptFile = {'node': 'main.js', 'python': 'main.py', 'go': 'main.go', 'java': 'Main.java', 'php': 'main.php'};

/// 这种语言的一个完整小工程：运行时小库（后端带的那几份 ＋ 语言核心的）＋ 脚本。
Map<String, String> langProjectFiles(String language, List<LModule> modules) {
  final target = backendTargets.firstWhere((x) => x.id == language) as BeCodeTarget;
  final gen = langGenFor(language)!;
  final files = target.generate(BeDocument())
    ..remove(target.entryFile)
    ..remove('README.md');
  return {...files, gen.runtimeFile: target.langRuntimeSource, kLangScriptFile[language]!: gen.script(modules)};
}

/// 在 [dir] 里跑一条命令（有超时）。
Future<ProcessResult> runTool(List<String> command, Directory dir, Map<String, String> environment, [Duration limit = const Duration(minutes: 5)]) {
  return Process.run(command.first, command.sublist(1), workingDirectory: dir.path, environment: environment, stdoutEncoding: utf8, stderrEncoding: utf8).timeout(limit);
}

/// 生成、（要编译的先编译、）运行。本机没有这种语言的工具时返回 null。不联网、不下载。
Future<LangRun?> runLang(String language, List<LModule> modules) async {
  final tools = await toolchainFor(language);
  if (tools == null) return null;
  final dir = writeProject(langProjectFiles(language, modules), 'lopi_lang_${language}_');
  try {
    final env = {...tools.environment, 'PYTHONIOENCODING': 'utf-8', 'PYTHONDONTWRITEBYTECODE': '1'};
    final builds = switch (language) {
      'go' => [
        ['go', 'build', '-o', 'prog', '.'],
      ],
      'java' => [
        ['javac', '-encoding', 'UTF-8', '-d', 'out', 'Main.java'],
      ],
      _ => const <List<String>>[],
    };
    for (final b in builds) {
      final r = await runTool(tools.resolve(b, dir), dir, env, const Duration(minutes: 5));
      if (r.exitCode != 0) return LangRun(-1, '', '编译没过（${b.join(' ')}）：\n${r.stdout}\n${r.stderr}');
    }
    final start = switch (language) {
      'node' => ['node', 'main.js'],
      'python' => ['python3', 'main.py'],
      'go' => ['./prog'],
      _ => ['java', '-Dstderr.encoding=UTF-8', '-cp', 'out', 'Main'],
    };
    final r = await runTool(tools.resolve(start, dir), dir, env, const Duration(minutes: 2));
    return LangRun(r.exitCode, '${r.stdout}', '${r.stderr}');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// 把一批用例拼成一个程序：每个用例一个模块，开头先打印一行 `## 名字`。
List<LModule> casesProgram(List<LangCase> cases) => [
  for (final c in cases) LModule(name: c.name, body: [log(t('## ${c.name}')), ...c.body]),
];

/// 把输出按 `## 名字` 切开：名字 → 那一段的各行。
Map<String, List<String>> splitCases(String out) {
  final result = <String, List<String>>{};
  List<String>? current;
  for (final line in const LineSplitter().convert(out)) {
    if (line.startsWith('## ')) {
      current = result[line.substring(3)] = [];
    } else {
      current?.add(line);
    }
  }
  return result;
}

/// 真跑的四种语言（PHP 本机没有，跑不了）。
const List<String> kLangRunnable = ['node', 'python', 'go', 'java'];

/// 一组用例的一致性测试：每种语言各跑一遍，逐个用例比对写死的预期；最后比对四种语言的输出逐字节相同。
void langConformanceGroup(String title, List<LangCase> cases) {
  final outputs = <String, String>{};
  group('语言核心一致性·$title', () {
    for (final language in kLangRunnable) {
      test('$language：${cases.length} 个用例的输出都等于预期', () async {
        final run = await runLang(language, casesProgram(cases));
        if (run == null) {
          // ignore: avoid_print 跳过的原因要让跑测试的人看见
          print('跳过：本机没有 $language 的工具');
          markTestSkipped('本机没有 $language 的工具');
          return;
        }
        expect(run.exitCode, 0, reason: '退出码不是 0：\n${run.err}');
        outputs[language] = run.out;
        final got = splitCases(run.out);
        final wrong = <String>[];
        for (final c in cases) {
          final actual = got[c.name];
          if (actual == null) {
            wrong.add('【${c.name}】没有输出');
          } else if (actual.join('\n') != c.expected.join('\n')) {
            wrong.add('【${c.name}】\n  预期：${c.expected}\n  实际：$actual');
          }
        }
        expect(wrong, isEmpty, reason: wrong.join('\n'));
        expect(got.length, cases.length, reason: '用例名有重复');
      }, timeout: const Timeout(Duration(minutes: 8)));
    }

    test('各语言的输出逐字节相同', () {
      if (outputs.length < 2) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：能跑的语言不到两种');
        markTestSkipped('能跑的语言不到两种');
        return;
      }
      final first = outputs.entries.first;
      for (final e in outputs.entries.skip(1)) {
        expect(e.value, first.value, reason: '${e.key} 和 ${first.key} 的输出不一样');
      }
    });
  });
}
