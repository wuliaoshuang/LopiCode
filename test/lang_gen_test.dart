// 语言核心的生成器：入口函数、能力表、“未支持”的报错、小库函数表和五份小库对得上、Go 的格式、PHP 的文本检查。
// 真跑的一致性在 lang_conformance_*_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/backend_conformance.dart';
import 'support/lang_cases_flow.dart';
import 'support/lang_cases_rt.dart';
import 'support/lang_conformance.dart';

/// 这种语言的全部小库源码（后端带的 ＋ 语言核心的）。
String _runtime(String language) {
  final target = backendTargetFor(language)! as BeCodeTarget;
  final files = target.generate(BeDocument())
    ..remove(target.entryFile)
    ..remove('README.md');
  return [...files.values, target.langRuntimeSource].join('\n');
}

/// 生成的代码里调了小库的哪些函数（各语言的写法：lc.x( / Lc.x( / LcLang.x( / lc_x(）。
Set<String> _called(String language, String code) => {for (final m in RegExp(language == 'php' ? r'\b(lc_[A-Za-z0-9_]+)\(' : r'\b(?:lc|Lc|LcLang)\.([A-Za-z0-9_]+)\(').allMatches(code)) m[1]!};

/// 小库里有没有定义这个函数。
bool _defined(String language, String runtime, String name) => switch (language) {
  'node' => runtime.contains('function $name(') || runtime.contains('const $name = '),
  'python' => runtime.contains('def $name('),
  'go' => runtime.contains('func $name('),
  'java' => RegExp('static [^\\n(=]*\\b$name\\(').hasMatch(runtime),
  _ => runtime.contains('function $name('),
};

/// 调一次小库函数的语句（参数个数照表里的；个数不定的给两个）。
LStmt _useFn(String name, LRtFn fn) {
  final call = LRt(name, [for (var i = 0; i < (fn.variadic ? 2 : fn.params.length); i++) t('a$i')]);
  return fn.ret == LRet.none ? LExprStmt(call) : LLet('x', call);
}

/// PHP 源码去掉字符串和注释以后剩下的部分；引号没配上、双引号里有没转义的 $ 就抛错。
String _phpCodeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final two = i + 1 < source.length ? source.substring(i, i + 2) : '';
    if (two == '//' || c == '#') {
      final end = source.indexOf('\n', i);
      final line = source.substring(i, end < 0 ? source.length : end);
      if (line.contains('?>')) throw StateError('注释里有 ?>：$line');
      i = end < 0 ? source.length : end;
    } else if (two == '/*') {
      final end = source.indexOf('*/', i + 2);
      if (end < 0) throw StateError('块注释没有结束');
      i = end + 2;
    } else if (c == '"' || c == "'") {
      var j = i + 1;
      while (j < source.length && source[j] != c) {
        if (source[j] == r'\') {
          j += 2;
          continue;
        }
        if (c == '"' && source[j] == r'$') throw StateError('双引号文字里有没转义的 \$：${source.substring(i, j + 1)}');
        j++;
      }
      if (j >= source.length) throw StateError('引号没有配上：${source.substring(i, (i + 40).clamp(0, source.length))}');
      out.write(c == '"' ? '""' : "''");
      i = j + 1;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

void _expectBalanced(String code, String where) {
  const pairs = {')': '(', ']': '[', '}': '{'};
  final stack = <String>[];
  for (final ch in code.split('')) {
    if (pairs.containsValue(ch)) stack.add(ch);
    if (pairs.containsKey(ch)) {
      expect(stack, isNotEmpty, reason: '$where：多了一个 $ch');
      expect(stack.removeLast(), pairs[ch], reason: '$where：括号没对上');
    }
  }
  expect(stack, isEmpty, reason: '$where：括号没关上');
}

void main() {
  final allCases = [...kLangFlowCases, ...kLangRtCases, for (final e in kLangErrorCases) LangCase(e.$1, e.$2, const [])];

  group('入口 langFragment', () {
    test('一段语句 ＋ 目标语言 → 要声明的名字 ＋ 一行行代码（不带缩进）', () {
      final body = [
        let('x', bin('+', n(1), t('a"b'))),
        LForCount('i', n(1), n(3), n(1), [
          iff(bin('>', v('i'), n(2)), [const LBreak()]),
        ]),
      ];
      final node = langFragment('node', body);
      expect(node.declares, ['x', 'i']);
      expect(node.lines, [
        r'v_x = lc.add(1, "a\"b");',
        'const lcvA1 = lc.toNumber(1);',
        'const lcvB1 = lc.toNumber(3);',
        'const lcvS1 = lc.toNumber(1);',
        'const lcvN1 = lc.countSteps(lcvA1, lcvB1, lcvS1);',
        'for (let lcvK1 = 0; lcvK1 < lcvN1; lcvK1++) {',
        '  v_i = lcvA1 + lcvK1 * lcvS1;',
        '  if (lc.gt(v_i, 2)) {',
        '    break;',
        '  }',
        '}',
      ]);
      expect(langFragment('python', body).lines.first, r'v_x = lc.add(1, "a\"b")');
      expect(langFragment('go', body).lines.first, r'v_x = lc.Add(1.0, "a\"b")');
      expect(langFragment('java', body).lines.first, r'v_x = Lc.add(1.0, "a\"b");');
      expect(langFragment('php', body).lines.first, r'$v_x = lc_add(1.0, "a\"b");');
    });

    test('五种语言都有生成器；不认识的语言报清楚的错', () {
      expect(kLangTargets, ['node', 'python', 'go', 'java', 'php']);
      expect([for (final t in backendTargets) t.id], kLangTargets, reason: '和后端的语言一一对应');
      for (final l in kLangTargets) {
        expect(langGenFor(l)!.id, l);
      }
      expect(langGenFor('rust'), isNull);
      expect(() => langFragment('rust', const []), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('rust'))));
    });

    test('同一个函数体里分几段生成：共用一个 ctx，循环的临时名字不重', () {
      for (final l in kLangTargets) {
        final ctx = LangCtx();
        final a = langFragment(l, [LRepeat(n(2), [])], ctx: ctx).lines.join('\n');
        final b = langFragment(l, [LRepeat(n(2), [])], ctx: ctx).lines.join('\n');
        expect(a, contains('lcvN1'), reason: l);
        expect(b, contains('lcvN2'), reason: l);
        expect(b, isNot(contains('lcvN1')), reason: l);
      }
    });

    test('生成是确定的：同一棵树生成两遍，文本一样', () {
      for (final l in kLangTargets) {
        expect(langGenFor(l)!.script(casesProgram(allCases)), langGenFor(l)!.script(casesProgram(allCases)), reason: l);
      }
    });

    test('“一定退出”的语句后面的不生成（Java / Go 不许有执行不到的代码）', () {
      for (final l in kLangTargets) {
        final code = langFragment(l, [
          LRepeat(n(1), [const LBreak(), log(t('死代码'))]),
        ]).lines.join('\n');
        expect(code, isNot(contains('死代码')), reason: l);
      }
    });

    test('宿主：LNative 交给宿主的 call，LHost 交给宿主的 stmt；没接宿主时报清楚的错', () {
      final host = LangHost(call: (fn, args) => 'HOST_$fn(${args.join(', ')})', stmt: (payload) => ['HOST_STMT $payload']);
      final f = langFragment('node', [
        let('x', const LNative('query', [LLit('a')])),
        const LHost('东西'),
      ], host: host);
      expect(f.lines, ['v_x = HOST_query("a");', 'HOST_STMT 东西']);
      expect(() => langFragment('node', [const LHost('东西')]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('没有接宿主'))));
      expect(() => langFragment('node', [run(const LNative('query', []))]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('query'))));
      expect(() => langFragment('node', [const LReturn(null)], host: const LangHost(allowReturn: false)), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('返回响应'))));
    });
  });

  group('能力表（设计稿 4.4）', () {
    test('每种语言对每项特性都有说法；这一阶段的都能生成，以后的标“以后”', () {
      for (final l in kLangTargets) {
        final caps = langGenFor(l)!.caps;
        expect(caps.keys.toSet(), kLangFeatures.toSet(), reason: l);
        expect(caps['operators'], LCap.runtime, reason: '$l：这一阶段运算全走小库（按建议先做，可改）');
        for (final f in ['classes', 'errors', 'async']) {
          expect(caps[f], LCap.later, reason: '$l $f');
        }
        // 第 2 阶段：函数、闭包做实了
        for (final f in ['functions', 'closures', 'logic', 'while', 'forCount', 'forEach', 'forPairs', 'repeat', 'switch', 'const', 'hoist', 'listMutation', 'cond']) {
          expect(caps[f], isNot(anyOf(LCap.later, LCap.forbidden)), reason: '$l $f');
        }
      }
      expect(langGenFor('go')!.caps['cond'], LCap.runtime, reason: 'Go 没有三目运算，值版的如果走小库的 Pick');
      expect(langGenFor('node')!.caps['cond'], LCap.native);
      expect({for (final l in kLangTargets) l: langGenFor(l)!.caps['closures']}, {'node': LCap.native, 'python': LCap.lowered, 'go': LCap.native, 'java': LCap.lowered, 'php': LCap.lowered});
    });
  });

  group('还不支持的节点：清楚的报错，带“第几阶段才有”', () {
    final later = <String, (LStmt, String, int)>{
      '新建对象': (run(const LNew('C', [])), '类和对象', 5),
      '调方法': (run(const LSend(LLit(1), 'm', [])), '类和对象', 5),
      '调父类方法': (run(const LSuperSend('m', [])), '类和对象', 5),
      '自己': (run(const LThis()), '类和对象', 5),
      '取字段': (run(const LField(LLit(1), 'f')), '类和对象', 5),
      '是不是某类': (run(const LIsA(LLit(1), 'C')), '类和对象', 5),
      '改字段': (const LAssign(LTField(LLit(1), 'f'), LLit(1)), '对象的字段', 5),
      '抛出': (const LThrow(LLit('x')), '抛出错误', 6),
      '试着做': (const LTry([]), '试着做 / 出错了', 6),
      '等待': (run(const LAwait(LLit(1))), '异步', 6),
      '同时做': (run(const LSpawn([])), '异步', 6),
    };
    for (final e in later.entries) {
      test('${e.key} → 第 ${e.value.$3} 阶段', () {
        for (final l in kLangTargets) {
          expect(
            () => langFragment(l, [e.value.$1]),
            throwsA(isA<LangUnsupported>().having((x) => x.stage, 'stage', e.value.$3).having((x) => x.message, 'message', allOf(contains(e.value.$2), contains('第 ${e.value.$3} 阶段')))),
            reason: l,
          );
        }
      });
    }

    test('模块里的函数 / 类 / 接口声明；不认识的运算、不认识的小库函数、没有返回值的函数当值用', () {
      final gen = langGenFor('node')!;
      // 第 2 阶段：函数声明能生成了
      expect(
        gen.script([
          const LModule(decls: [LFuncDecl('f', [], [])]),
        ]),
        contains('function f1_f()'),
      );
      expect(
        () => gen.script([
          const LModule(decls: [LClassDecl('C')]),
        ]),
        throwsA(isA<LangUnsupported>().having((e) => e.stage, 'stage', 5)),
      );
      expect(
        () => gen.script([
          const LModule(decls: [LInterfaceDecl('I', [])]),
        ]),
        throwsA(isA<LangUnsupported>().having((e) => e.stage, 'stage', 5)),
      );
      expect(() => langFragment('node', [run(bin('<=>', n(1), n(2)))]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('<=>'))));
      expect(() => langFragment('node', [run(LUnary('~', n(1)))]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('~'))));
      expect(() => langFragment('node', [run(const LLogic('xor', yes, no))]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('xor'))));
      expect(() => langFragment('node', [run(rt('没有这个'))]), throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('没有这个'))));
      expect(
        () => langFragment('node', [
          let('x', rt('listPush', [list(), n(1)])),
        ]),
        throwsA(isA<LangUnsupported>().having((e) => e.message, 'message', contains('没有返回值'))),
      );
      const e = LangUnsupported('函数', stage: 2, src: LSrc(block: 'b3'));
      expect(e.toString(), allOf(contains('还不支持“函数”'), contains('b3')));
    });
  });

  group('小库函数表', () {
    test('最底下那 20 个函数，第 3 版后端的小库里都有（名字对得上）', () {
      expect(kLangCoreFns.keys.toSet().difference(kBeRuntimeFns.keys.toSet()), isEmpty);
      expect(kLangCoreFns.keys.toSet().intersection(kLangRtFns.keys.toSet()), isEmpty, reason: '两张表不重名');
    });

    test('数目：第 1 阶段新加的函数 55 个；要函数当参数的 8 个先占位（第 2 阶段）', () {
      final stage1 = kLangRtFns.entries.where((e) => e.value.stage == 1 && !e.value.internal).length;
      final stage2 = [
        for (final e in kLangRtFns.entries)
          if (e.value.stage == 2) e.key,
      ];
      expect(stage1, 55);
      expect(stage2, ['listSortBy', 'listMap', 'listFilter', 'listReduce', 'listFind', 'listEvery', 'listSome', 'listEach']);
      for (final f in kLangRtFns.values) {
        expect(f.doc, isNotEmpty);
      }
      expect(kLangBinaryFns.values.every((f) => kLangCoreFns.containsKey(f) || kLangRtFns.containsKey(f)), isTrue);
    });

    for (final l in kLangTargets) {
      test('$l${l == 'php' ? '（只核对文本）' : ''}：每个第 1 阶段的函数生成出来调的名字，小库里都有定义；抛错的四句话都在', () {
        final runtime = _runtime(l);
        for (final e in [...kLangCoreFns.entries, ...kLangRtFns.entries]) {
          if (e.value.stage != 1 || e.key == 'now') continue;
          final code = langFragment(l, [_useFn(e.key, e.value)]).lines.join('\n');
          final called = _called(l, code);
          expect(called, hasLength(1), reason: '$l ${e.key}：$code');
          expect(_defined(l, runtime, called.single), isTrue, reason: '$l 的小库里没有 ${called.single}（${e.key}）');
        }
        for (final m in kLangErrors.values) {
          expect(runtime, contains(m), reason: l);
        }
      });
    }

    test('上限的数值写进了五份小库（重复 / 数列最多 10000）', () {
      expect(kLangRepeatLimit, 10000);
      expect(kLangRangeLimit, 10000);
      for (final l in kLangTargets) {
        expect(_runtime(l), contains('10000'), reason: l);
      }
    });
  });

  group('Go', () {
    test('语言核心的小库和生成的脚本是 gofmt 的规范格式，go vet 没有意见', () async {
      final tools = await toolchainFor('go');
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：本机没有 go');
        markTestSkipped('本机没有 go');
        return;
      }
      final dir = writeProject(langProjectFiles('go', casesProgram(allCases)), 'lopi_lang_fmt_');
      try {
        final fmt = await runTool(tools.resolve(['gofmt', '-l', '.'], dir), dir, tools.environment);
        expect(fmt.exitCode, 0, reason: '${fmt.stderr}');
        expect('${fmt.stdout}'.trim(), isEmpty, reason: '这些文件不是 gofmt 的格式');
        final vet = await runTool(tools.resolve(['go', 'vet', './...'], dir), dir, tools.environment);
        expect(vet.exitCode, 0, reason: '${vet.stdout}\n${vet.stderr}');
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 8)));

    test('源码里的制表符只在行首（文字里的制表写成 \\t）', () {
      final files = langProjectFiles('go', casesProgram(allCases));
      for (final f in files.entries.where((f) => f.key.endsWith('.go'))) {
        for (final line in f.value.split('\n')) {
          expect(line.trimLeft().contains('\t'), isFalse, reason: '${f.key}: $line');
        }
      }
    });
  });

  group('PHP（文本检查；真跑在 lang_conformance_*_test.dart）', () {
    final gen = langGenFor('php')!;
    final target = backendTargetFor('php')! as BeCodeTarget;

    test('全部一致性用例都能生成；引号、括号配得上；文字里的 \$ 都转义了；没有 ?>', () {
      final script = gen.script(casesProgram(allCases));
      expect(script, startsWith('<?php\n'));
      expect(script, isNot(contains('?>')));
      for (final entry in {'main.php': script, 'lc_lang.php': target.langRuntimeSource}.entries) {
        _expectBalanced(_phpCodeOnly(entry.value), entry.key);
      }
      expect(target.langRuntimeSource, startsWith('<?php\n'));
      // 2026-11-26 改：原来断言小库开头写着“还没有（实际运行过）”；PHP 真跑过了，改成断言开头如实写着跑过。
      expect(target.langRuntimeSource.split('\n').take(8).join('\n'), allOf(contains('PHP 8.3 跑通过'), isNot(contains('还没有'))), reason: '小库开头如实写跑没跑过');
      // 2026-11-26 PHP 第一次真跑撞到的：命令行的 PHP 默认把报错写到标准输出，混进程序的输出里。
      expect(script, contains("ini_set('display_errors', 'stderr');"));
    });

    test('生成的脚本里调的每个 lc_ 函数，小库里都有定义', () {
      final runtime = _runtime('php');
      final called = _called('php', _phpCodeOnly(gen.script(casesProgram(allCases))));
      expect(called, isNotEmpty);
      for (final name in called) {
        if (RegExp(r'^lc_module[0-9]+$').hasMatch(name)) continue;
        expect(runtime.contains('function $name('), isTrue, reason: '小库里没有 $name');
      }
    });

    test('每句话都以分号 / 花括号结尾；变量都带 \$', () {
      final lines = _phpCodeOnly(gen.script(casesProgram(allCases))).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (final line in lines.skip(1)) {
        expect(RegExp(r'[;{}]$').hasMatch(line) || line.startsWith('function '), isTrue, reason: line);
        expect(RegExp(r'(?<![\$A-Za-z0-9_>])(v_|lcv|lcT)[A-Za-z0-9_]').hasMatch(line), isFalse, reason: '变量少了 \$：$line');
      }
    });

    test('列表是引用（LcList 对象），原地改的函数直接改它', () {
      final src = _runtime('php');
      expect(src, contains('class LcList'));
      expect(
        langFragment('php', [
          let('xs', list([n(1)])),
          run(rt('listPush', [v('xs'), n(2)])),
        ]).lines,
        [r'$v_xs = lc_listOf(1.0);', r'lc_listPush($v_xs, 2.0);'],
      );
    });
  });
}
