// 三块类型积木（“看是哪一类值”“当成某类型用”“标上类型”）和原生绑定积木（“调宿主接口”）：
// 积木盒里找得到；积木 → 语法树 → 五种后端语言开服务真跑，回的内容逐字节一样；永远成不了的、放不进去的，搭的时候就报；
// “调宿主接口”在默认状态下（自己的库不能直接碰宿主接口）积木盒里没有、文档里已有的每一块都报清楚的问题、库文件出不来；
// 开关打开时库出得来、清单里一个不落地写明用了哪些宿主接口。浏览器目标的在 lowcode_front_typeops_test.dart。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/types.dart';

import 'backend_core_fix_test.dart' show hostOf, dump;
import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/lib_switches.dart';
import 'support/typeops_sample.dart';
import 'support/user_libs.dart';

bool _inPalette(List<BlockCategory> categories, String id) =>
    categories.any((c) => c.blocks.contains(id) || c.exprs.contains(id) || c.groups.any((g) => g.blocks.contains(id) || g.exprs.contains(id)));

void main() {
  tearDown(libSwitchesReset);

  test('目录：三块类型积木在积木盒里（严格规矩的文档），都有那句话，拖得出来', () {
    final h = hostOf(typeOpsDoc());
    expect(_inPalette(h.categories, 'isType'), isTrue, reason: '看是哪一类值');
    for (final kind in [kBeCast, kBeAscribe]) {
      expect(beCoreExprSpecs[kind], isNotNull, reason: kind);
      expect(beCoreExprSentences[kind], isNotNull, reason: kind);
      expect(h.newExpr(kind), isNotNull, reason: kind);
      expect(_inPalette(h.categories, kind), isTrue, reason: kind);
    }
    expect(beCoreExprSpecs[kBeCast]!.label, '当成某类型用');
    expect(beCoreExprSpecs[kBeAscribe]!.label, '标上类型');
  });

  test('类型的下拉：基础的、它们的列表和字典、文档里定义的类型；存的字读得回来', () {
    final h = hostOf(typeOpsDoc());
    final keys = [for (final o in beTypeOptions(h.doc.core)) o.value];
    expect(keys.toSet().length, keys.length, reason: '没有重样的');
    for (final t in const [LType.integer, LType.text, LType.listOf(LType.integer), LType.dictOf(LType.text), LType.ref('名片'), LType.listOf(LType.ref('名片'))]) {
      expect(keys, contains(beTypeKey(t)), reason: t.show());
      expect(beTypeOfKey(beTypeKey(t)), t, reason: t.show());
    }
    expect(beTypeOfKey('(列表 整数'), isNull);
    expect(beTypeOfKey(''), isNull);
  });

  test('样例文档没有问题', () => expect(dump(hostOf(typeOpsDoc())), isEmpty));

  test('永远当不成的，搭的时候就报（T15）；标的类型放不进去也报', () {
    final never = hostOf(coreDoc('错', main: [log(castTo(tx('字'), LType.integer))]));
    expect(dump(never), contains('永远当不成'));
    final wrong = hostOf(coreDoc('错', main: [log(ascribe(tx('字'), LType.integer))]));
    expect(dump(wrong), contains('这里标的是'));
  });

  for (final language in kGen2Languages) {
    test('$language：积木文档生成、开服务真跑，回的内容逐字节一样', () async {
      final doc = BeDocument.fromJson({...typeOpsDoc(), 'language': language}).doc;
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
        expect(utf8.decode(reply.body), kTypeOpsWant);
      } finally {
        await server.stop();
      }
    });
  }

  group('原生绑定积木（调宿主接口）', () {
    J hostLib({String? side}) => {
      ...libDoc(
        '文件小库',
        'shuang/files',
        functions: [
          tfn(
            'f1',
            '有没有文件',
            [tpar('路径', tText)],
            [
              ret(
                ex(kBeHostCall, {
                  'name': 'file.exists',
                  'args': [pm('路径')],
                }),
              ),
            ],
            returns: tBool,
          ),
        ],
        blocks: [def('exists', 'call', fn: 'f1', look: look('有没有文件', '有没有文件 {路径}'))],
      ),
      if (side != null)
        'library': {
          ...(libDoc('x', 'shuang/files', blocks: const [])['library'] as Map),
          'for': side,
          'blocks': [def('exists', 'call', fn: 'f1', look: look('有没有文件', '有没有文件 {路径}'))],
        },
    };

    test('默认状态（开关关着）：积木盒里没有；文档里已有的报清楚的问题；库文件出不来，原因说得明白', () {
      expect(kUserLibHostEnabled, isFalse, reason: '默认值不许动');
      expect(userLibHostEntry, isFalse);
      final h = hostOf(hostLib());
      expect(_inPalette(h.categories, kBeHostCall), isFalse);
      expect(_inPalette(h.categories, kBeHostCallStmt), isFalse);
      expect(dump(h), contains('这一版自己的库还不能直接碰宿主接口'));
      final built = beLibFiles(h.doc);
      expect(built.files, isNull);
      expect(built.problems.join('；'), contains('还不能直接碰宿主接口'));
    });

    test('不是库的文档里：开不开都没有这块；硬放进去就报“只能用在库里”', () {
      userLibHostEntry = true;
      final h = hostOf(
        coreDoc(
          '甲',
          main: [
            log(ex(kBeHostCall, {'name': 'time.now', 'args': <J>[]})),
          ],
        ),
      );
      expect(_inPalette(h.categories, kBeHostCall), isFalse);
      expect(dump(h), contains('只能用在库里'));
    });

    test('开关打开：后端的库积木盒里有，接口从表里挑；库出得来，清单 hosts 写明；五种语言都生成得出', () {
      userLibHostEntry = true;
      final h = hostOf(hostLib());
      expect(_inPalette(h.categories, kBeHostCall), isTrue);
      expect(_inPalette(h.categories, kBeHostCallStmt), isTrue);
      expect([for (final o in beHostOptions(LibSide.backend)) o.value], contains('file.exists'));
      expect(dump(h), isEmpty);
      final built = buildUserLib(hostLib());
      final manifest = jsonDecode(built.files['lib.json']!) as Map;
      expect(manifest['hosts'], ['file.exists']);
      for (final language in kGen2Languages) {
        final user = userDocument(
          {
            ...coreDoc('用它', main: const []),
            'language': language,
            'uses': [use('shuang/files')],
            'routes': [
              route('r1', 'GET', '/go', [
                text(
                  cat([
                    lx('shuang/files', 'exists', {'路径': tx('/没有这个文件')}),
                  ]),
                ),
              ]),
            ],
          },
          [built.lib],
        );
        expect(beServiceGenerate(user, language).problem, isNull, reason: language);
      }
    });

    test('开关打开：没选接口、这一边没有的接口、“都行”的库，各报各的', () {
      userLibHostEntry = true;
      J lib(String name, {String? side}) {
        final d = hostLib(side: side);
        final fn = (d['functions'] as List).single as Map;
        final call = (((fn['body'] as List).single as Map)['args'] as Map)['value'] as Map;
        call['name'] = name;
        return d;
      }

      expect(dump(hostOf(lib(''))), contains('还没选调哪个宿主接口'));
      expect(dump(hostOf(lib('page.nope'))), contains('没有叫「page.nope」的宿主接口'));
      expect(dump(hostOf(lib('file.exists', side: 'both'))), contains('两边都能用的库只能用语言核心'));
    });
  });
}
