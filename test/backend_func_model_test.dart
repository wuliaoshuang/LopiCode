// 积木第 4 版·第 2 阶段（函数和“我的积木”）在模型这一层：文档里的 functions 读写往返、旧文档字节不变、坏数据不崩、版本号；
// 新建 / 改参数（各处调用跟着变）/ 删除 / 包成积木；五种语言的代码里函数排在接口前面。校验在 backend_func_validate_test.dart。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_edit.dart';
import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_palette.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';

BeDocument docOf(List<J> fns, List<J> body, {String path = '/x'}) => parseLangBlocksDocument({
  ...langBlocksDocumentJson([route('r1', 'GET', path, body)]),
  'functions': fns,
});
final J ok = json(dc({'ok': yes()}));

/// 校验结果：`规则 E|W 哪一串`。
List<String> found(BeDocument doc) => [
  for (final i in validateBackend(doc, languages: ['node'])) '${i.rule} ${i.isError ? 'E' : 'W'} ${i.handlerId}',
];
List<LcLogicIssue> issuesOf(BeDocument doc, String rule) => [
  for (final i in validateBackend(doc, languages: ['node']))
    if (i.rule == rule) i,
];

void main() {
  // 这个文件考的是老规矩（规矩版本 1）的行为：新建的文档现在默认是严格规矩，这里钉回 1，测完改回去。
  setUp(() => beNewDocRules = kLangRulesLoose);
  tearDown(() => beNewDocRules = kLangRulesForNewDocs);

  group('读写', () {
    test('往返：带函数的样本文档读进来再写出去再读，内容一样；functions 排在 routes 后面，版本是 3', () {
      final source = funcBlocksDocumentJson();
      final doc = parseLangBlocksDocument(source);
      final once = doc.encode();
      final again = BeDocument.parse(once);
      expect(again.note, isNull);
      expect(again.doc.encode(), once);
      final json = jsonDecode(once) as Map<String, dynamic>;
      expect(json['version'], 3);
      expect(json['routes'], source['routes'], reason: '接口里的积木（调用、匿名函数的口）一个字段不改');
      expect(json.keys.toList().indexOf('functions'), greaterThan(json.keys.toList().indexOf('routes')));
      expect([for (final f in json['functions'] as List) (f as Map)['id']], [for (final f in source['functions'] as List) (f as Map)['id']]);
      final f4 = doc.function('f4')!;
      expect((f4.name, f4.paramNames.join(','), f4.params.last.rest, f4.params.first.defaultValue), ('总和', '起点,其余', true, 0));
      expect(lcExprBody((doc.function('f8')!.body.last.args['value'] as Map).cast<String, dynamic>()), hasLength(2), reason: '匿名函数口里的积木读成了真的积木');
      expect(doc.clone().encode(), once, reason: '复制一份也一样');
    });

    test('旧文档字节不变：第 1 版、第 2 版（阶段 1 的新积木）的文档读进来再写出去一个字节不差，不多出 functions', () {
      final v2 = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));
      for (final (doc, version) in [(backendStarterDocument('样本'), 1), (conformanceDocument(), 1), (v2, 2)]) {
        final before = doc.encode();
        expect(doc.usesFunctions, isFalse);
        expect(jsonDecode(before)['version'], version);
        final parsed = BeDocument.parse(before);
        expect(parsed.note, isNull);
        expect(parsed.doc.encode(), before);
        expect(before, isNot(contains('"functions"')));
      }
      // 手写的旧文件（键的顺序、空白都是存盘时的样子）：读进来、原样存回去。
      const old = '{\n  "version": 1,\n  "kind": "backend",\n  "name": "老的",\n  "port": 8080,\n  "language": "node",\n  "variables": [],\n  "collections": [],\n  "routes": []\n}';
      final viaOld = BeDocument.parse(old).doc.encode();
      expect(BeDocument.parse(viaOld).doc.encode(), viaOld);
      expect(jsonDecode(viaOld), jsonDecode(old));
    });

    test('版本号：有函数、或者接口里用到第 2 阶段的积木才是 3；拿掉又回去', () {
      int version(List<J> fns, List<J> body) => docOf(fns, body).toJson()['version'] as int;
      expect(version([], [ok]), 1);
      expect(version([], [let('a', nm(1)), ok]), 2);
      expect(version([fnDef('f1', '甲', [], [])], [ok]), 3, reason: '只有定义、没人调用也是 3');
      expect(
        version([], [
          let('f', arrow(['x'], pm('x'))),
          ok,
        ]),
        3,
        reason: '没有定义、用了匿名函数',
      );
      expect(
        version([], [
          json(hof('listMap', ls([]), arrow(['x'], pm('x')))),
        ]),
        3,
      );
      final doc = docOf([fnDef('f1', '甲', [], [])], [callS('f1'), ok]);
      expect(beRemoveFunction(doc, 'f1'), isTrue);
      expect(doc.toJson()['version'], 1, reason: '删掉函数，调用一起拿掉，回到 1');
      expect(doc.encode(), isNot(contains('functions')));
    });

    test('坏数据不崩：functions 不是列表、条目不是对象、外观 / 参数 / 积木的类型全错、id 缺了重了、太多', () {
      for (final bad in <Object?>[
        null,
        'x',
        3,
        {'a': 1},
        [null, 1, 'x', <Object>[]],
      ]) {
        final parsed = BeDocument.fromJson({...langBlocksDocumentJson([]), 'functions': bad});
        expect(parsed.doc.functions, isEmpty, reason: '$bad');
        expect(() => validateBackend(parsed.doc, languages: ['node', 'go']), returnsNormally);
      }
      final parsed = BeDocument.fromJson({
        ...langBlocksDocumentJson([route('f1', 'GET', '/x', [])]),
        'functions': [
          {'id': 'f1', 'look': 5, 'params': 'no', 'body': 'no'},
          {
            'id': 'f1',
            'look': {'name': 7},
            'params': [
              1,
              {'name': ''},
              {'name': 'a'},
              {'name': 'a'},
              {
                'name': 'b',
                'default': [1],
                'rest': 'yes',
              },
            ],
            'body': [
              1,
              {'op': 3},
              {'op': 'return', 'args': 'x'},
            ],
          },
          {
            'look': {'name': '好的', 'shape': '怪', 'slots': 'x', 'template': 9},
            'x': 'a',
            'y': double.nan,
          },
          {
            'id': '../etc',
            'look': {'name': '路径'},
          },
        ],
      });
      final doc = parsed.doc;
      expect(doc.functions, hasLength(4));
      expect({for (final f in doc.functions) f.id}.length, 4, reason: 'id 不重');
      expect(doc.functions.every((f) => BeFunction.validId(f.id)), isTrue);
      expect(doc.functions.first.id, 'f1', reason: '第一个 f1 留着（调用按它认）');
      expect(doc.routes.single.id, isNot('f1'), reason: '接口的 id 和函数撞了，换的是接口的');
      expect(doc.functions[1].paramNames, ['a', 'b'], reason: '空名、重名的参数丢掉');
      expect(doc.functions.first.name, '积木', reason: '外观坏了给默认的');
      expect(() => validateBackend(doc, languages: [for (final t in backendTargets) t.id]), returnsNormally);
      for (final t in backendTargets) {
        expect(() => t.generate(doc), returnsNormally, reason: t.id);
      }
      expect(BeDocument.parse(doc.encode()).doc.encode(), doc.encode(), reason: '读进来的再存一次是稳定的');
      final many = BeDocument.fromJson({
        ...langBlocksDocumentJson([]),
        'functions': [for (var i = 0; i < kBeMaxFunctions + 20; i++) fnDef('f$i', '积木$i', [], [])],
      }).doc;
      expect(many.functions, hasLength(kBeMaxFunctions));
      final params = BeDocument.fromJson({
        ...langBlocksDocumentJson([]),
        'functions': [
          fnDef('f1', '甲', [for (var i = 0; i < 20; i++) par('p$i')], []),
        ],
      }).doc;
      expect(params.functions.single.params, hasLength(kBeMaxParams));
    });

    test('积木盒：第 2 阶段的每块积木、每种值都排得进某一页；8 个拿函数当参数的列表操作都在“列表”页；“函数”页有“定义”帽子；都有别名', () {
      final placed = {
        for (final c in bePaletteCategories) ...[for (final b in c.allBlocks) 'block:$b', for (final e in c.allExprs) 'expr:$e'],
      };
      for (final op in beFuncBlockSpecs.keys) {
        expect(placed, contains('block:$op'));
        expect(beAliasesOf(BlockItemRef.block(op)), isNotEmpty, reason: op);
      }
      for (final kind in beFuncExprSpecs.keys) {
        expect(placed, contains('expr:$kind'));
        expect(beAliasesOf(BlockItemRef.expr(kind)), isNotEmpty, reason: kind);
      }
      final lists = bePaletteCategories.firstWhere((c) => c.id == '列表');
      expect({...lists.allBlocks, ...lists.allExprs}, containsAll(['listEach', 'listMap', 'listFilter', 'listFind', 'listSome', 'listEvery', 'listReduce', 'listSortBy']));
      final fn = bePaletteCategories.firstWhere((c) => c.id == '函数');
      expect([for (final h in fn.allHats) h.id], ['define']);
    });
  });

  group('改动', () {
    test('新建：多一串定义、id 不和接口撞；调用积木的槽里先放默认值，“剩下的全收”先放空列表', () {
      final doc = docOf([], [ok]);
      final f = beAddFunction(
        doc,
        const CustomBlockLook(
          '问好',
          slots: [
            CustomBlockSlot('次数', defaultValue: 2),
            CustomBlockSlot('大声', kind: CustomSlotKind.boolean),
            CustomBlockSlot('语气', kind: CustomSlotKind.choice, options: ['轻', '重']),
          ],
        ),
        ['谁', '次数', '大声', '语气', '谁', ' '],
      );
      expect((f.id, f.paramNames.join(',')), ('f1', '谁,次数,大声,语气'));
      expect(f.params[1].defaultValue, 2, reason: '值槽“先放什么”就是参数的默认值');
      final call = beNewCallBlock(f);
      expect(call.op, 'call:f1');
      expect((exprString(call.args['谁'], 'v'), exprNum(call.args['次数'], 'v'), exprKind(call.args['大声']), call.args['语气']), ('', 2, 'bool', '轻'));
      expect(beNewCallExpr(f)['e'], 'call:f1');
      f.params.add(BeParam('其余', rest: true));
      expect(exprKind(beNewCallBlock(f).args['其余']), 'listLit');
      expect(doc.addRoute('GET', '/y')!.id, isNot('f1'));
      expect(doc.duplicateRoute('r1')!.id, isNot('f1'));
      expect(beFreshFunctionName(doc, '问好'), '问好2');
    });

    test('改参数：改名（定义里读它的地方、各处调用的槽跟着改）、加一个（各处补默认值）、删一个（各处丢掉，报丢了几格）、换顺序', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a'), par('b')],
            [
              ret(
                cat([
                  pm('a'),
                  pm('b'),
                  arrow(['a'], pm('a')),
                ]),
              ),
            ],
          ),
        ],
        [
          callS('f1', {'a': tx('一'), 'b': tx('二')}),
          json(
            call('f1', {
              'a': call('f1', {'a': nm(1), 'b': tx('')}),
              'b': tx('二'),
            }),
          ),
        ],
      );
      final f = doc.function('f1')!;
      // 改名 a → 头
      var dropped = beReshapeFunction(doc, f, f.look, [BeParam('头'), BeParam('b')], [0, 1]);
      expect(dropped, 0);
      expect(f.paramNames, ['头', 'b']);
      expect(f.body.single.toJson().toString(), contains('name: 头'));
      expect(doc.route('r1')!.body.first.args.keys, ['头', 'b']);
      final outer = (doc.route('r1')!.body.last.args['value'] as Map).cast<String, dynamic>();
      expect(outer.keys, ['e', '头', 'b']);
      expect((outer['头'] as Map).keys, ['e', '头', 'b'], reason: '套在里面的调用也改');
      // 加一个 c（默认 9）、换顺序
      final look = f.look.copyWith(slots: [const CustomBlockSlot('c', defaultValue: 9)]);
      dropped = beReshapeFunction(doc, f, look, [BeParam('b'), BeParam('头'), BeParam('c', defaultValue: 9)], [1, 0, null], lookIsNew: true);
      expect(dropped, 0);
      final first = doc.route('r1')!.body.first.args;
      expect(first.keys, ['b', '头', 'c']);
      expect((exprString(first['b'], 'v'), exprNum(first['c'], 'v'), exprString(first['头'], 'v')), ('二', 9, '一'));
      // 删掉 b：两处调用里 b 填了“二”→ 丢 2 格；里面那次调用的 b 是空文字，不算。
      dropped = beReshapeFunction(doc, f, f.look, [BeParam('头'), BeParam('c', defaultValue: 9)], [1, 2]);
      expect(dropped, 2);
      expect(doc.route('r1')!.body.first.args.keys, ['头', 'c']);
      expect(found(doc).where((x) => x.contains(' E ')), ['G03 E f1'], reason: '定义里还读着 b：校验指出来（这里没有叫 b 的参数）');
    });

    test('普通参数改成“剩下的全收”：各处那一格装进列表；改回来只留第一项（多的算丢）', () {
      final doc = docOf(
        [
          fnDef('f1', '甲', [par('a')], [ret(pm('a'))]),
        ],
        [
          json(call('f1', {'a': nm(5)})),
        ],
      );
      final f = doc.function('f1')!;
      expect(beReshapeFunction(doc, f, f.look, [BeParam('a', rest: true)], [0]), 0);
      Map<String, dynamic> arg() => ((doc.route('r1')!.body.single.args['value'] as Map)['a'] as Map).cast<String, dynamic>();
      expect(arg()['e'], 'listLit');
      (arg()['items'] as List).add(exNum(6));
      expect(beReshapeFunction(doc, f, f.look, [BeParam('a')], [0]), 1);
      expect(exprNum(arg(), 'v'), 5);
    });

    test('删除：定义没了；单独成句的调用拿掉，当值用的地方、“这块积木本身”换成空文字；用了几处数得对（自己调自己不算）', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('n')],
            [
              iff(pm('n'), [
                callS('f1', {'n': nm(0)}),
              ], noElse: true),
              ret(nm(1)),
            ],
          ),
          fnDef('f2', '乙', [], [
            ret(call('f1', {'n': nm(1)})),
          ]),
        ],
        [
          callS('f1', {'n': nm(1)}),
          let(
            'g',
            lam([], [
              callS('f1', {'n': nm(2)}),
              ret(ref('f1')),
            ]),
          ),
          json(call('f1', {'n': nm(3)})),
        ],
      );
      expect(beFunctionUses(doc, 'f1'), 5);
      expect(beFunctionUses(doc, 'f2'), 0);
      expect(beRemoveFunction(doc, 'nope'), isFalse);
      expect(beRemoveFunction(doc, 'f1'), isTrue);
      expect(doc.function('f1'), isNull);
      final body = doc.route('r1')!.body;
      expect([for (final b in body) b.op], ['let', 'respondJson']);
      expect(exprKind(body.last.args['value']), 'text');
      final mouth = body.first.exprMouths.single;
      expect([for (final b in mouth) b.op], ['return']);
      expect(exprKind(mouth.single.args['value']), 'text');
      expect(exprKind(doc.function('f2')!.body.single.args['value']), 'text');
      expect(doc.encode(), isNot(contains('call:f1')));
      expect(found(doc).where((x) => x.contains(' E ')), isEmpty);
    });

    test('包成积木：这一截搬进新定义，原处换成调用；用到的外面的变量 / 参数变成参数；包不了的说得出原因', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('p')],
            [
              let('a', nm(1)),
              blk('log', {
                'value': cat([pm('p'), vr('a')]),
              }),
              ret(nm(1)),
            ],
          ),
        ],
        [
          let('a', nm(1)),
          let('xs', ls([])),
          push('xs', vr('a')),
          blk('log', {'value': vr('total')}),
          setv('a', nm(2)),
          ok,
        ],
      );
      final r = doc.route('r1')!;
      expect(beWrapBlocker(doc, r, [lcStep(2)]), contains('返回响应'));
      expect(beWrapBlocker(doc, r, [lcStep(9)]), isNotNull);
      expect(beWrapBlocker(doc, r, const []), isNotNull);
      // 只包中间两块包不了（“往下相连的一截”一直到底）；把后面的挪开再包。
      final tailOff = r.body.sublist(4);
      r.body.removeRange(4, r.body.length);
      expect(beWrapBlocker(doc, r, [lcStep(2)]), isNull);
      expect(beWrapOuterNames(doc, r, [lcStep(2)]), ['xs', 'a', 'total']);
      expect(beWrapTail(doc, r, [lcStep(2)], const CustomBlockLook('记下来'), ['xs']), isNull, reason: '参数没给全：不包，什么都不改');
      expect(r.body, hasLength(4));
      final made = beWrapTail(doc, r, [lcStep(2)], const CustomBlockLook('记下来'), ['xs', 'a', 'total'])!;
      expect((made.id, made.paramNames.join(','), [for (final b in made.body) b.op].join(',')), ('f2', 'xs,a,total', 'listPush,log'));
      expect(made.look.shape, CustomBlockShape.statement);
      expect(jsonEncode([for (final b in made.body) b.toJson()]), isNot(contains('"var"')), reason: '读外面变量的地方都改成读参数');
      final call = r.body.last;
      expect((call.op, [for (final v in call.args.values) exprString(v, 'name')].join(',')), ('call:f2', 'xs,a,total'));
      r.body.addAll(tailOff);
      expect(found(doc).where((x) => x.contains(' E ')), isEmpty);

      // 改外面的变量 / 带“返回”/ 带管外面循环的“跳出”：包不了。
      expect(beWrapBlocker(doc, r, [lcStep(3)]), contains('返回响应'));
      r.body.removeLast();
      expect(beWrapBlocker(doc, r, [lcStep(3)]), contains('改了外面的变量 a'));
      final f1 = doc.function('f1')!;
      expect(beWrapBlocker(doc, f1, [lcStep(1)]), contains('“返回”'));
      f1.body.removeLast();
      expect(beWrapOuterNames(doc, f1, [lcStep(1)]), ['p', 'a'], reason: '定义里再包：外面的参数、外面新建的变量都算');
      final inner = beWrapTail(doc, f1, [lcStep(1)], const CustomBlockLook('里面的'), ['p', 'a'])!;
      expect(exprKind(f1.body.last.args['p']), 'param', reason: '原处的调用：参数还是按参数读');
      expect(exprKind(f1.body.last.args['a']), 'var');
      expect(inner.paramNames, ['p', 'a']);
      final loop = docOf([], [
        blk('forever', {}, [let('i', nm(1)), blk('break')]),
        ok,
      ]);
      expect(beWrapBlocker(loop, loop.route('r1')!, [lcStep(0), lcStep(1)]), contains('跳出'));
      expect(beWrapBlocker(loop, loop.route('r1')!, [lcStep(0), lcStep(0)]), contains('跳出'));
    });

    test('集合改名走进函数和匿名函数的口；变量改名不进函数（那里看不见文档变量）', () {
      final doc = docOf(
        [
          fnDef('f1', '甲', [], [
            let('total', nm(0)),
            ret(ex('dbCount', {'collection': 'notes'})),
          ]),
        ],
        [
          let(
            'g',
            lam([], [
              setv('total', nm(1)),
              ret(ex('dbAll', {'collection': 'notes'})),
            ]),
          ),
          json(call('f1')),
        ],
      );
      expect(doc.collectionRefCount('notes'), 2);
      expect(doc.renameCollection('notes', 'memo'), isTrue);
      expect(doc.encode(), isNot(contains('"notes"')));
      expect(doc.renameVariable('total', 'sum'), isTrue);
      expect((doc.function('f1')!.body.first.args['name'], doc.route('r1')!.body.first.exprMouths.single.first.args['name']), ('total', 'sum'));
    });
  });

  group('生成', () {
    final doc = funcBlocksDocument();

    test('五种语言：函数排在接口前面；每个函数都在入口文件里；没有函数的文档入口文件里没有函数的影子', () {
      final plain = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));
      for (final t in backendTargets) {
        final target = t as BeCodeTarget;
        final entry = target.generate(doc)[target.entryFile]!;
        final firstRoute = entry.indexOf('/call');
        expect(firstRoute, greaterThan(0), reason: t.id);
        for (final f in doc.functions) {
          final at = entry.indexOf('f_${f.ident}');
          expect(at, greaterThanOrEqualTo(0), reason: '${t.id}：${f.name}');
          expect(at, lessThan(firstRoute), reason: '${t.id}：${f.name} 要排在接口前面');
        }
        expect(target.generate(plain)[target.entryFile]!, isNot(contains('f_')), reason: t.id);
      }
    });

    test('表：调用积木的形状跟着定义走（没有返回＝语句、有＝值、一定是是否＝是否）；声明了形状的照声明', () {
      final table = BeFuncTable(doc);
      CustomBlockShape shape(String id) => table.shapeOf(doc.function(id)!);
      expect((shape('f6'), shape('f1'), shape('f2'), shape('f5')), (CustomBlockShape.statement, CustomBlockShape.value, CustomBlockShape.boolean, CustomBlockShape.value));
      expect(table.isBool({'e': 'call:f2'}), isTrue);
      expect(table.isBool({'e': 'call:f1'}), isFalse);
      expect(table.blockSpec('call:f3')!.args.map((a) => a.name), ['谁', '语气']);
      expect(table.exprSpec('call:nope'), isNull);
      expect(table.sentenceOf('call:f3'), '打招呼 {谁} {语气}');
    });

    test('PHP（文本检查）：带函数的入口文件——引了语言核心的小库、函数在接口前、括号配对、变量带 \$', () {
      final target = backendTargetFor('php')! as BeCodeTarget;
      final files = target.generate(doc);
      final entry = files[target.entryFile]!;
      expect(files.keys, contains('lc_lang.php'));
      expect(entry, contains('lc_lang.php'));
      expect(entry, contains('function f_'));
      expect(RegExp(r'function \(').hasMatch(entry) || entry.contains('fn('), isTrue, reason: '匿名函数');
      for (final f in files.entries.where((e) => e.key == target.entryFile || e.key == 'lc_lang.php')) {
        final code = f.value.replaceAll(RegExp(r"'(?:\\.|[^'\\])*'"), "''").replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), '""').replaceAll(RegExp(r'//.*'), '');
        for (final (open, close) in [('{', '}'), ('(', ')'), ('[', ']')]) {
          expect(open.allMatches(code).length, close.allMatches(code).length, reason: '${f.key} 的 $open $close 不配对');
        }
        expect(f.value.trimLeft(), startsWith('<?php'), reason: f.key);
      }
      expect(entry, isNot(contains('let ')));
      expect(entry, isNot(contains('=> {')), reason: '没有 JS 的箭头函数写法');
    });
  });
}
