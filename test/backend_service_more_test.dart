// 库 1·A1：74 条没考到的几样，走同一条产品路径（后端文档 → 翻译 → 内置库 → 版本 2 生成器）五种语言真跑：
// 新建变量、重复、对每一项、变量加上、写到日志、比较、“我的积木”（函数）里用数据集合、文档里声明的变量每次请求从初始值开始。
// 服务只开在本机回环地址的随机端口上，不联外网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
Map<String, dynamic> _list(List<Map<String, dynamic>> items) => {'e': 'listLit', 'items': items};

BeDocument _doc() {
  final doc = BeDocument(
    name: '库 1 的小样本',
    port: 8124,
    rules: kLangRulesStrict,
    variables: [LcVariable(name: 'seen', type: 'number', initial: 5)],
    collections: [BeCollection(name: 'things')],
  );
  // 我的积木：往集合里加一条，交回现在有几条。
  final add = BeFunction(
    id: 'addThing',
    look: const CustomBlockLook('addThing'),
    params: [BeParam('title', type: LType.text)],
    body: [
      _b('dbInsert', {
        'collection': 'things',
        'value': beObj({
          'title': {'e': 'param', 'name': 'title'},
        }),
      }),
      _b('return', {'value': beDbCount('things')}),
    ],
  );
  doc.functions.add(add);
  void route(String method, String path, List<LcBlock> body) => doc.addRoute(method, path)!.body.addAll(body);
  route('GET', '/mix', [
    _b('let', {'name': 'total', 'value': exNum(0)}),
    _b(
      'repeat',
      {'times': exNum(3)},
      body: [
        _b('changeVar', {'name': 'total', 'by': exNum(2)}),
      ],
    ),
    _b('let', {'name': 'it', 'value': exNum(0)}),
    _b(
      'forEach',
      {
        'list': _list([exNum(1), exNum(2), exNum(3)]),
        'item': 'it',
      },
      body: [
        _b('changeVar', {'name': 'total', 'by': exVar('it')}),
      ],
    ),
    _b('log', {
      'value': exJoin([exText('total='), exVar('total')]),
    }),
    _b(
      'if',
      {'cond': exBin('>', exVar('total'), exNum(10))},
      body: [
        _b('respondJson', {
          'status': exNum(200),
          'value': beObj({'total': exVar('total')}),
        }),
      ],
    ),
    _b('respondText', {'status': exNum(200), 'value': exText('小')}),
  ]);
  route('POST', '/things', [
    _b('respondJson', {
      'status': exNum(201),
      'value': beObj({
        'count': {'e': beCallOp('addThing'), 'title': beQuery('t')},
      }),
    }),
  ]);
  // 文档里声明的变量：改了也只管这一次请求。
  route('GET', '/seen', [
    _b('setVar', {'name': 'seen', 'value': exNum(9)}),
    _b('respondJson', {
      'status': exNum(200),
      'value': beObj({'seen': exVar('seen')}),
    }),
  ]);
  route('GET', '/seen-first', [
    _b('respondJson', {
      'status': exNum(200),
      'value': beObj({'seen': exVar('seen')}),
    }),
  ]);
  return doc;
}

void main() {
  test('翻得出来，检查一条问题都没有', () {
    final out = beServiceProgram(_doc());
    expect(out.problems, isEmpty);
    final (linked, checked) = checkProgramTypes(out.program!);
    expect(linked.issues, isEmpty);
    expect([for (final e in checked!.errors) '${e.code} ${e.where} ${e.message}'], isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：真跑，回应一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final gen = beServiceGenerate(_doc(), language);
      expect(gen.problem, isNull);
      final server = await gen2Serve(language, gen.files!);
      final got = <String>[];
      try {
        for (final (method, target) in [('GET', '/mix'), ('POST', '/things?t=a'), ('POST', '/things?t=b'), ('GET', '/seen'), ('GET', '/seen-first'), ('GET', '/seen')]) {
          final reply = await server.send(method, target);
          got.add('${reply.status} ${utf8.decode(reply.body)}');
        }
      } finally {
        await server.stop();
      }
      expect(got, ['200 {"total":12}', '201 {"count":1}', '201 {"count":2}', '200 {"seen":9}', '200 {"seen":5}', '200 {"seen":9}'], reason: server.stderrText);
    });
  }
}
