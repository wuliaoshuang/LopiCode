// 核心 2 的样例文档（test/support/backend_core_samples.dart，用积木文档的数据模型搭的）：
// 读得进来、存出去再读回来一个字不差、没有标红、五种语言都生成得出代码。真跑在 backend_core_run_test.dart。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_core_edit.dart';
import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/backend_conformance.dart';
import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_routes.dart';

void main() {
  test('样例至少 8 个，六类每一类都有', () {
    expect(coreSamples.length, greaterThanOrEqualTo(8));
    expect({for (final s in coreSamples) ...s.covers}, {1, 2, 3, 4, 5, 6});
  });

  test('旧文档字节不变：没用到核心 2 的文档（第 1、2、3 版）读进来再写出去一个字节不差，不多出 core；版本号不变', () {
    final v2 = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));
    final v3 = parseLangBlocksDocument({
      ...langBlocksDocumentJson(langBlocksRoutes()),
      'functions': [
        fnDef('f1', '加倍', [par('x')], [ret(op2('*', pm('x'), nm(2)))]),
      ],
    });
    for (final (doc, version) in [(backendStarterDocument('样本'), 1), (conformanceDocument(), 1), (v2, 2), (v3, 3)]) {
      final before = doc.encode();
      expect(doc.usesCore, isFalse);
      expect(doc.core.isEmpty, isTrue);
      expect(jsonDecode(before)['version'], version);
      expect(before, isNot(contains('"core"')));
      final parsed = BeDocument.parse(before);
      expect(parsed.note, isNull);
      expect(parsed.doc.encode(), before);
      expect(doc.clone().encode(), before);
    }
    // 手写的旧文件（键的顺序、空白都是存盘时的样子）：读进来、原样存回去。
    const old = '{\n  "version": 1,\n  "kind": "backend",\n  "name": "老的",\n  "port": 8080,\n  "language": "node",\n  "variables": [],\n  "collections": [],\n  "routes": []\n}';
    final viaOld = BeDocument.parse(old).doc.encode();
    expect(BeDocument.parse(viaOld).doc.encode(), viaOld);
    expect(jsonDecode(viaOld), jsonDecode(old));
  });

  test('版本号用到才升：加一个类型是 4，拿掉又回到原来；“程序开始时”里只有老积木也算用到（有 core）', () {
    final doc = backendStarterDocument('样本')..rules = 2;
    final was = jsonDecode(doc.encode())['version'];
    final t = beAddType(doc, BeTypeKind.record)!;
    expect(jsonDecode(doc.encode())['version'], 4);
    expect(beRemoveType(doc, t.id), isNull);
    expect(jsonDecode(doc.encode())['version'], was);
    expect(doc.encode(), isNot(contains('"core"')));
  });

  test('老规矩的文档里出现核心 2 的积木：不认识，原样留着（读写不丢），不当成新积木', () {
    final json = langBlocksDocumentJson(langBlocksRoutes());
    final routes = [...(json['routes'] as List)];
    final first = {...(routes.first as Map)};
    first['body'] = [thro(tx('x')), ...(first['body'] as List)];
    routes[0] = first;
    final doc = parseLangBlocksDocument({...json, 'routes': routes});
    expect(doc.rules, 1);
    expect(doc.routes.first.body.first.op, 'throw');
    expect(BeDocument.parse(doc.encode()).doc.encode(), doc.encode());
    expect(BeBlockHost(doc: doc).blockSpec('throw'), isNull);
  });

  for (final s in coreSamples) {
    group(s.name, () {
      late BeDocument doc;
      setUp(() => doc = parseLangBlocksDocument(s.doc));

      test('读进来、存出去、再读回来，内容一样；版本号是 4', () {
        final text = doc.encode();
        expect(jsonDecode(text)['version'], 4);
        expect(BeDocument.parse(text).doc.encode(), text);
        expect(doc.clone().encode(), text);
      });

      test('没有标红', () {
        final check = beTypeCheck(doc)!;
        expect([
          for (final f in check.findings)
            if (f.issue.isError) '${f.issue.code} ${f.issue.where} ${f.problem}',
        ], isEmpty);
        expect([
          for (final i in validateBackend(doc))
            if (i.isError) i.message,
        ], isEmpty);
      });

      for (final language in kGen2Languages) {
        test('$language：生成得出代码', () {
          final out = beCoreGenerate(doc, language);
          expect(out.problem, isNull);
          expect(out.files, isNotEmpty);
        });
      }
    });
  }
}
