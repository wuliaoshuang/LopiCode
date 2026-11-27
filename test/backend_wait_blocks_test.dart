// 核心 3 的积木（“要等的事”）在后端积木文档里能用：积木 → 语法树 → 五种语言真跑，输出逐字节一样；
// 放错地方的在类型问题里说，一键修落在积木上（去掉“等”、改成“开始算”），撤销重做都成立。
// 积木上没有“要等”这回事：样例里的函数、“程序开始时”谁都没标。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_wait.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'backend_core_fix_test.dart' show fixed, hostOf, dump;
import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_wait_sample.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';

void main() {
  test('目录：四块语句、六块值都在核心积木的表里，都有那句话，积木盒拖得出来', () {
    expect(beWaitBlockSpecs.keys, ['spawn', 'sleep', 'cancel', 'critical']);
    expect(beWaitExprSpecs.keys, ['spawnOf', 'await', 'awaitMax', 'awaitAll', 'awaitAny', 'cancelled']);
    final h = hostOf(waitSampleDoc());
    for (final op in beWaitBlockSpecs.keys) {
      expect(beCoreBlockSpecs[op], isNotNull, reason: op);
      expect(beCoreBlockSentences[op], isNotNull, reason: op);
      expect(h.newBlock(op), isNotNull, reason: op);
    }
    for (final kind in beWaitExprSpecs.keys) {
      expect(beCoreExprSpecs[kind], isNotNull, reason: kind);
      expect(beCoreExprSentences[kind], isNotNull, reason: kind);
      expect(h.newExpr(kind), isNotNull, reason: kind);
    }
    expect(h.categories.where((c) => c.id == kBeCatWait), hasLength(1));
  });

  test('样例文档没有问题；积木上、文档里都没有“要等”这个标记', () {
    final h = hostOf(waitSampleDoc());
    expect(dump(h), isEmpty);
    expect(jsonEncode(h.doc.toJson()), isNot(contains('waits')));
    expect(jsonEncode(h.doc.toJson()), isNot(contains('要等函数')));
  });

  test('只在“程序开始时”或“开始做”里用到的积木，不算“没人用”', () {
    // 原来“没人用的积木”只看接口和别的积木，“开始做”里面也整个不看：这两处用到的积木会多一条不对的提醒。
    final inMain = hostOf(coreDoc('甲', functions: [waitSlowFn()], main: [log(slow(1, 2))]));
    expect(dump(inMain), isNot(contains('没有人用')));
    final inSpawn = hostOf({
      ...coreDoc('乙', functions: [waitSlowFn()], main: const []),
      'routes': [
        route('r1', 'GET', '/a', [
          blk(
            'spawn',
            {'name': ''},
            [
              blk('do', {'value': slow(1, 2)}),
            ],
          ),
          text(tx('好')),
        ]),
      ],
    });
    expect(dump(inSpawn), isNot(contains('没有人用')));
    final unused = hostOf(coreDoc('丙', functions: [waitSlowFn()], main: [log(tx('好'))]));
    expect(dump(unused), contains('没有人用'), reason: '真没人用的照样提醒');
  });

  for (final language in kGen2Languages) {
    test('$language：积木文档生成、开服务真跑，回的内容逐字节一样', () async {
      final doc = BeDocument.fromJson({...waitSampleDoc(), 'language': language}).doc;
      final gen = beServiceGenerate(doc, language);
      expect(gen.problem, isNull);
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final server = await gen2Serve(language, gen.files!);
      try {
        final reply = await server.send('GET', '/go');
        expect(reply.status, 200, reason: server.stderrText);
        expect(utf8.decode(reply.body), kWaitSampleWant);
        // 再来一次：上一次没做完的事（被取消的、超时没等的）不碍着这一次。
        expect(utf8.decode((await server.send('GET', '/go')).body), kWaitSampleWant);
      } finally {
        await server.stop();
      }
    });
  }

  group('放错地方：类型问题里说，一键修落在积木上', () {
    test('“等”后面不是“稍后的结果”（T31）：去掉“等”', () {
      final d = fixed(hostOf(coreDoc('错', main: [log(await_(nm(3)))])), '去掉');
      expect(d.core.main!.body.single.args['value'], nm(3));
    });

    test('“创建时”里不能等（T29）：改成“开始算”', () {
      final h = hostOf(
        coreDoc(
          '错',
          functions: [waitSlowFn()],
          types: [
            typeDef(
              't1',
              'class',
              '东西',
              ctor: method('m1', '创建时', [], [
                blk('do', {'value': slow(1, 5)}),
              ]),
            ),
          ],
          main: [log(tx('好'))],
        ),
      );
      expect(dump(h), contains('T29'));
      final d = fixed(h, '开始');
      expect(d.core.type('t1')!.ctor!.body.single.args['value'], spawnOf(slow(1, 5)));
    });

    test('要等的函数放进只收不用等的函数的地方（T30）：说得出是哪一块', () {
      final h = hostOf(
        coreDoc(
          '错',
          functions: [waitSlowFn()],
          main: [
            log(hof('listMap', ls([nm(1), nm(2)]), arrow(['x'], slow(1, 5)))),
          ],
        ),
      );
      expect(dump(h), contains('T30'));
      expect(dump(h), contains('只收不用等的函数'));
    });
  });
}
