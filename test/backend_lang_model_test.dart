// 积木第 4 版·第 1 阶段：新积木在模型这一层——读写往返、坏数据不崩、旧文档字节不变、版本号规则；
// 每块新积木刚拖出来的默认样子能过校验、五种语言都能生成；小库第 1 阶段的函数每个都有积木；
// Go 的格式和 vet；PHP（本机没有 php，未实测）只查生成出来的文本。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_palette.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';
import 'support/lang_conformance.dart' show runTool;

BeDocument docOf(List<J> body) => parseLangBlocksDocument(langBlocksDocumentJson([route('r1', 'GET', '/x', body)]));
final J ok = json(dc({'ok': yes()}));

void main() {
  group('读写', () {
    test('往返：用了全部新积木的样本文档，读进来再写出去再读，内容一样；接口里的积木原样（op、参数、段、收起的否则）', () {
      final source = langBlocksDocumentJson(langBlocksRoutes());
      final doc = parseLangBlocksDocument(source);
      final once = doc.encode();
      final again = BeDocument.parse(once);
      expect(again.note, isNull);
      expect(again.doc.encode(), once);
      expect(jsonDecode(once)['routes'], source['routes'], reason: '积木一块不多、一块不少、一个字段不改');
      expect(jsonDecode(once)['version'], 2);
    });

    test('旧文档字节不变：没用新积木的文档读进来再写出去一个字节不差，版本还是 1，“如果”不多出新字段', () {
      for (final doc in [backendStarterDocument('样本'), conformanceDocument()]) {
        final before = doc.encode();
        expect(doc.usesLang, isFalse);
        expect(jsonDecode(before)['version'], 1);
        final parsed = BeDocument.parse(before);
        expect(parsed.note, isNull);
        expect(parsed.doc.encode(), before);
        expect(before, isNot(contains('"arms"')));
        expect(before, isNot(contains('"noElse"')));
      }
      // 生成的代码也一个字不变（没用新积木的接口照旧走旧路）。
      final plain = generateBackend(backendStarterDocument('样本'), language: 'node')!.files;
      expect(plain.keys, isNot(contains('lc_lang.js')));
    });

    test('版本号：用到新积木才是 2；拿掉又回到 1', () {
      int version(List<J> body) => docOf(body).toJson()['version'] as int;
      expect(version([ok]), 1);
      expect(
        version([
          iff(yes(), [ok], orElse: [ok]),
        ]),
        1,
        reason: '旧的两个口的如果',
      );
      expect(
        version([
          blk('forEach', {
            'list': ex('dbAll', {'collection': 'todos'}),
            'item': 'item',
          }, []),
          ok,
        ]),
        1,
      );
      expect(
        version([
          blk('forEach', {'list': ls([]), 'item': 'item', 'index': ''}, []),
          ok,
        ]),
        2,
        reason: '列表字面量是新的',
      );
      expect(
        version([
          blk('forEach', {
            'list': ex('dbAll', {'collection': 'todos'}),
            'item': 'item',
            'index': 'i',
          }, []),
          ok,
        ]),
        2,
        reason: '带序号',
      );
      expect(version([let('a', nm(1)), ok]), 2);
      expect(
        version([
          iff(
            yes(),
            [ok],
            arms: [
              arm({'cond': no()}, [ok]),
            ],
            orElse: [ok],
          ),
        ]),
        2,
        reason: '否则如果',
      );
      expect(
        version([
          iff(yes(), [ok], noElse: true),
          ok,
        ]),
        2,
        reason: '收起了“否则”',
      );
      expect(
        version([
          json(ex('neg', {'x': nm(1)})),
        ]),
        2,
        reason: '只在值里用到',
      );
      expect(
        version([
          iff(
            yes(),
            [
              blk('repeat', {'times': nm(1)}, [blk('break')]),
            ],
            orElse: [ok],
          ),
          ok,
        ]),
        2,
        reason: '套在里面',
      );

      final doc = docOf([let('a', nm(1)), ok]);
      doc.routes.single.body.removeAt(0);
      expect(doc.toJson()['version'], 1);
      expect(BeDocument.parse(doc.encode()).doc.usesLang, isFalse);
    });

    test('坏数据不崩：段不是列表 / 不是对象、参数类型不对、选项不是文字、套得太深——读、校验、五种语言生成都不抛异常', () {
      J deep(int n) => n == 0 ? blk('break') : blk('forever', {}, [deep(n - 1)]);
      J deepExpr(int n) => n == 0 ? nm(1) : ex('neg', {'x': deepExpr(n - 1)});
      final bad = <List<Object?>>[
        [
          {
            'op': 'if',
            'args': {'cond': yes()},
            'body': [ok],
            'arms': '不是列表',
            'else': [ok],
          },
        ],
        [
          {
            'op': 'if',
            'args': {'cond': yes()},
            'body': [ok],
            'arms': [
              1,
              null,
              '段',
              {'args': 3, 'body': '也不对'},
              {
                'body': [ok],
              },
            ],
            'noElse': '是',
          },
        ],
        [
          {
            'op': 'switch',
            'args': '不是对象',
            'arms': {
              '0': arm({'value': nm(1)}, [ok]),
            },
          },
        ],
        [
          {
            'op': 'let',
            'args': {'name': 7, 'value': '直接一段文字'},
          },
          {
            'op': 'const',
            'args': {
              'name': ['a'],
              'value': null,
            },
          },
          {
            'op': 'forCount',
            'args': {
              'name': {'e': 'num'},
              'from': 'x',
              'to': <Object?>[],
              'step': <String, Object?>{},
            },
            'body': <String, Object?>{},
          },
          {
            'op': 'forPairs',
            'args': {'dict': 1, 'key': null, 'value': 2},
          },
          {
            'op': 'while',
            'args': {
              'cond': {'e': 'logic', 'l': 1, 'op': 9, 'r': null},
            },
          },
          {'op': 'listPush'},
          {
            'op': 'setItem',
            'args': {
              'of': {'e': 'listLit', 'items': '不是列表'},
              'key': {'e': 'obj', 'fields': 3},
            },
          },
        ],
        [
          json(ex('round', {'x': nm(1), 'fn': 5})),
          json(ex('textHas', {'s': tx('a'), 'fn': 'nope', 'sub': tx('a')})),
          json(
            ex('isType', {
              'x': nm(1),
              'type': ['number'],
            }),
          ),
          json(ex('dictPart', {'d': 3})),
          json(ex('cond', {})),
          json(
            ex('listLit', {
              'items': [
                1,
                'a',
                null,
                {'e': 'nope'},
              ],
            }),
          ),
        ],
        [deep(LcBlock.maxDepth + 6), json(deepExpr(80))],
        [
          {
            'op': 'if',
            'args': {'cond': yes()},
            'arms': [
              for (var i = 0; i < LcBlock.maxArms + 30; i++) arm({'cond': no()}, []),
            ],
          },
        ],
      ];
      for (final body in bad) {
        final source = jsonEncode(
          langBlocksDocumentJson([
            {'id': 'r1', 'method': 'GET', 'path': '/x', 'body': body},
          ]),
        );
        final parsed = BeDocument.parse(source);
        final doc = parsed.doc;
        expect(() => validateBackend(doc), returnsNormally, reason: source);
        expect(doc.encode, returnsNormally);
        expect(BeDocument.parse(doc.encode()).doc.encode(), doc.encode(), reason: '读进来的再存一次是稳定的');
        for (final t in backendTargets) {
          expect(() => t.generate(doc), returnsNormally, reason: '${t.id}\n$source');
        }
      }
      // 段太多：只留到上限。
      final many = BeDocument.parse(
        jsonEncode(
          langBlocksDocumentJson([
            {'id': 'r1', 'method': 'GET', 'path': '/x', 'body': bad.last},
          ]),
        ),
      ).doc;
      expect(many.routes.single.body.single.arms.length, LcBlock.maxArms);
    });
  });

  group('规格', () {
    test('每块新积木刚拖出来的默认样子：能过校验（没有错误）、五种语言都能生成；每块都有句子、分类、提示', () {
      for (final op in beLangBlockSpecs.keys) {
        final doc = backendStarterDocument('样本');
        final r = BeRoute(id: 'n1', method: 'GET', path: '/n1');
        doc.routes.add(r);
        final inLoop = op == 'break' || op == 'continue';
        final b = newBeBlock(op, doc);
        r.body.add(inLoop ? LcBlock(op: 'repeat', args: {'times': exNum(2)}, body: [b]) : b);
        r.body.add(LcBlock(op: 'respondText', args: {'status': exNum(200), 'value': exText('好')}));
        final errors = [for (final i in backendErrors(doc)) i.message];
        expect(errors, isEmpty, reason: '新拖出来的 $op');
        expect(doc.usesLang, isTrue, reason: op);
        for (final t in backendTargets) {
          expect(t.generate(doc), isNotEmpty, reason: '${t.id} $op');
        }
        final spec = beBlockSpecs[op]!;
        expect(spec.label, isNotEmpty);
        expect(spec.hint, isNotEmpty, reason: '$op 要有一句提示');
        expect(beCategories, contains(spec.category), reason: op);
      }
      for (final kind in beLangExprSpecs.keys) {
        final doc = backendStarterDocument('样本');
        final r = BeRoute(id: 'n1', method: 'GET', path: '/n1');
        doc.routes.add(r);
        r.body.add(LcBlock(op: 'respondJson', args: {'status': exNum(200), 'value': newBeExpr(kind, doc, r)}));
        expect([for (final i in backendErrors(doc)) i.message], isEmpty, reason: '新拖出来的 $kind');
        for (final t in backendTargets) {
          expect(t.generate(doc), isNotEmpty, reason: '${t.id} $kind');
        }
        final spec = beExprSpecs[kind]!;
        expect(spec.hint, isNotEmpty, reason: '$kind 要有一句提示');
        expect(beCategories, contains(spec.category), reason: kind);
      }
      expect((beLangBlockSpecs.length, beLangExprSpecs.length), (18, 38));
    });

    test('小库第 1 阶段的函数（不算内部用的）每一个都有积木能用到', () {
      final wanted = {
        for (final e in kLangRtFns.entries)
          if (e.value.stage == 1 && !e.value.internal) e.key,
      };
      expect(wanted.length, 55);
      // 每种新表达式、它的每个下拉选项各放一块；每块新语句各放一块。
      final body = <LcBlock>[];
      final doc = backendStarterDocument('样本');
      for (final e in beLangExprSpecs.entries) {
        final base = newBeExpr(e.key, doc);
        final fn = [
          for (final a in e.value.args)
            if (a.name == 'fn') a,
        ];
        final variants = fn.isEmpty
            ? [base]
            : [
                for (final c in fn.single.choices) {...base, 'fn': c},
              ];
        for (final v in variants) {
          body.add(LcBlock(op: 'do', args: {'value': v}));
        }
      }
      for (final op in beLangBlockSpecs.keys) {
        body.add(newBeBlock(op, doc));
      }
      // 字典字面量＝原来的“对象”积木（在用了新积木的接口里就是语法树的字典）。
      body.add(LcBlock(op: 'do', args: {'value': newBeExpr('obj', doc)}));
      doc.routes.add(BeRoute(id: 'n1', method: 'GET', path: '/n1', body: body));
      final used = <String>{};
      // 五个不是直接调小库的：语法树里有专门的节点，生成器把它们写成对应的小库函数。
      void visit(LExpr e) {
        switch (e) {
          case LRt(:final fn):
            used.add(fn);
          case LBinary(op: '**'):
            used.add('pow');
          case LListLit():
            used.add('listOf');
          case LDictLit():
            used.add('dictOf');
          case LIndex():
            used.add('item');
          default:
        }
        lExprChildren(e).forEach(visit);
      }

      final stmts = beLangShadow(doc, doc.routes.last)!.stmts;
      lWalkExprs(stmts, visit);
      lWalk(stmts, (s) {
        if (s is LAssign && s.target is LTIndex) used.add('setItem');
      });
      expect(wanted.difference(used), isEmpty, reason: '这些小库函数还没有积木');
    });

    test('积木盒：每块新积木都排得进某一页；“一块顶多块”的族成员就是那个下拉的选项；入门积木都认识', () {
      final placed = {
        for (final c in bePaletteCategories) ...[for (final b in c.allBlocks) 'block:$b', for (final e in c.allExprs) 'expr:$e'],
      };
      for (final op in beLangBlockSpecs.keys) {
        expect(placed, contains('block:$op'));
      }
      for (final kind in beLangExprSpecs.keys) {
        expect(placed, contains('expr:$kind'));
      }
      for (final s in beStarterItems) {
        expect(s.kind.name == 'block' ? beBlockSpecs.containsKey(s.id) : beExprSpecs.containsKey(s.id), isTrue, reason: s.id);
      }
      expect(beStarterItems.length, lessThanOrEqualTo(16));
      for (final key in beAliases.keys) {
        final (kind, id) = (key.split(':').first, key.split(':').last);
        expect(kind == 'block' ? beBlockSpecs.containsKey(id) : beExprSpecs.containsKey(id), isTrue, reason: '别名表里的 $key');
      }
    });

    test('“这次请求”在语法树里统一叫 req；各语言生成时换成自己的写法（PHP 是 \$req）', () {
      final doc = docOf([json(q('n'))]);
      expect(doc.usesLang, isFalse);
      final lang = docOf([let('a', q('n')), json(vr('a'))]);
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        expect(target.request.replaceFirst(r'$', ''), kBeRequestName, reason: t.id);
        final entry = target.generate(lang)[target.entryFile]!;
        expect(entry, contains('(${target.request}, "n")'), reason: '${t.id}：新路上读请求用的名字');
      }
    });
  });

  group('生成', () {
    final doc = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));

    test('五种语言：用了新积木的工程都带上语言核心的小库，入口文件里有新积木的影子', () {
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final files = target.generate(doc);
        final langFile = target.langGen(const LangHost()).runtimeFile;
        expect(files.keys, contains(langFile), reason: target.id);
        final entry = files[target.entryFile]!;
        expect(entry, contains('lcTsw1'), reason: '${target.id}：“分情况”的临时名');
        expect(entry, contains('v_'), reason: target.id);
      }
    });

    test('PHP（本机没有 php，未实测）：生成出来的文本——引了小库、括号配对、请求变量带 \$、没有别的语言的写法', () {
      final target = backendTargetFor('php')! as BeCodeTarget;
      final files = target.generate(doc);
      final entry = files[target.entryFile]!;
      expect(files.keys, contains('lc_lang.php'));
      expect(entry, contains('lc_lang.php'));
      expect(entry, contains(r'$req'));
      expect(RegExp(r'[^$\w]req\b(?!uire)').allMatches(entry.replaceAll(RegExp(r'//.*'), '')).length, 0, reason: '请求变量不能少了 \$');
      // 只看积木翻出来的入口文件和语言核心的小库（别的小工具文件里有正则，这种数括号的土办法看不准）。
      for (final f in files.entries.where((e) => e.key == target.entryFile || e.key == 'lc_lang.php')) {
        final code = f.value.replaceAll(RegExp(r"'(?:\\.|[^'\\])*'"), "''").replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), '""').replaceAll(RegExp(r'//.*'), '');
        for (final (open, close) in [('{', '}'), ('(', ')'), ('[', ']')]) {
          expect(open.allMatches(code).length, close.allMatches(code).length, reason: '${f.key} 的 $open $close 不配对');
        }
        expect(f.value.trimLeft(), startsWith('<?php'), reason: f.key);
      }
      expect(entry, isNot(contains('let ')));
      expect(entry, contains('while ('));
      expect(entry, anyOf(contains('elseif ('), contains('else if (')));
    });

    test('go：用了新积木的工程是 gofmt 的规范格式，go vet 没有意见', () async {
      final tools = await toolchainFor('go');
      if (tools == null) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：本机没有 go');
        markTestSkipped('本机没有 go');
        return;
      }
      final dir = writeProject(generateBackend(doc, language: 'go')!.files, 'lopi_lang_blocks_fmt_');
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
  });
}
