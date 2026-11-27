// 库 1·A1：后端文档 → 翻译（backend_to_service.dart）→ 内置库“接口服务”（lib_service.dart）→ 版本 2 生成器，这条产品路径。
// 拿一致性样本里只考服务这一层的那些请求（期望一个字不改）在五种语言里真起服务比：状态码、Content-Type、内容逐字节。
// 服务只开在本机回环地址的随机端口上，不联外网。这里是直接调翻译（不看开关）。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_check.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/backend_conformance.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/service_strict_doc.dart';

void main() {
  final cases = serviceCases();

  test('三个开关都开了（库 1 下半，2026-11-27）', () {
    expect(kLangStrictBackendGen, isTrue);
    expect(kStrictRulesUpgradeEnabled, isTrue);
    expect(kLangRulesForNewDocs, kLangRulesStrict);
  });

  test('内置库读得进来、查不出问题：19 块积木、3 个类型、2 个设置项', () {
    final lib = beServiceLibrary();
    expect(lib.problems, isEmpty);
    expect(libCheck(lib), isEmpty);
    expect(lib.builtin, isTrue);
    expect(lib.id, kBeServiceLibId);
    expect(
      [for (final b in lib.blocks) b.id],
      [
        'onRequest', 'respondJson', 'respondText', 'respond', 'pathParam', 'query', 'bodyField', 'body', 'header', //
        'dbAll', 'dbGet', 'dbFind', 'dbCount', 'dbInsert', 'dbUpdate', 'dbDelete', 'fetch', 'field', 'nowText',
      ],
    );
    expect([for (final t in lib.types) t.name], ['请求', '回应类型', '一条记录']);
    expect([for (final s in lib.settings) '${s.id}=${s.legacyKey}'], ['port=port', 'collections=collections']);
    // 旧小库的名字各对着一块积木。
    for (final fn in [
      'sendJson',
      'sendText',
      'pathParam',
      'query',
      'bodyField',
      'body',
      'header',
      'dbAll',
      'dbGet',
      'dbFind',
      'dbCount',
      'dbInsert',
      'dbUpdate',
      'dbDelete',
      'field',
      'now',
      'fetch',
    ]) {
      expect(lib.legacy(fn), isNotNull, reason: fn);
    }
    // 宿主接口只碰这七个。
    expect(lib.hosts.toSet(), {'http.serve', 'sys.env', 'sys.print', 'time.now', 'store.read', 'store.update', 'net.fetch'});
  });

  test('取到的样本条数', () {
    expect(conformanceCases, hasLength(135));
    expect(cases, hasLength(74));
  });

  test('严格规矩的样本文档翻得出来，检查一条问题都没有', () {
    final out = beServiceProgram(serviceStrictDocument());
    expect(out.problems, isEmpty);
    expect(out.skipped, isEmpty);
    final (linked, checked) = checkProgramTypes(out.program!);
    expect(linked.issues, isEmpty);
    expect([for (final e in checked!.errors) '${e.code} ${e.where} ${e.message}'], isEmpty);
  });

  test('规矩版本 1 的文档不走这条路', () {
    final out = beServiceProgram(conformanceDocument());
    expect(out.program, isNull);
    expect(beServiceGenerate(conformanceDocument(), 'node').files, isNull);
  });

  test('“请求别的网址”接到库上了；不认识的语言说得出来', () {
    final fetch = beServiceLibrary().legacy('fetch')!;
    expect(fetch.look.name, '请求别的网址');
    expect(fetch.isValue, isFalse);
    expect(beServiceGenerate(serviceStrictDocument(), 'cobol').problem, '这种语言还没有生成器');
  });

  test('设置项的值取自文档：端口、集合名单', () {
    expect(beServiceSettings(serviceStrictDocument()), {
      'port': 8123,
      'collections': ['todos', 'notes'],
    });
  });

  for (final language in kGen2Languages) {
    test('$language：这些请求的状态码、Content-Type、内容逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final gen = beServiceGenerate(serviceStrictDocument(), language);
      expect(gen.problem, isNull);
      final server = await gen2Serve(language, gen.files!);
      final wrong = <String>[];
      var passed = 0;
      try {
        for (var i = 0; i < cases.length; i++) {
          final c = cases[i];
          final body = c.bodyBytes ?? (c.body == null ? null : utf8.encode(c.body!));
          final reply = await server.send(c.method, c.target.isEmpty ? '/' : c.target, headers: c.headers, body: body);
          final text = utf8.decode(reply.body, allowMalformed: true);
          final bad = <String>[
            if (reply.status != c.status) '状态码 ${reply.status}（要 ${c.status}）',
            if (reply.headers['content-type'] != c.type) 'Content-Type ${reply.headers['content-type']}（要 ${c.type}）',
            if (c.pattern != null && !RegExp(c.pattern!).hasMatch(text)) '内容 $text（要对上 ${c.pattern}）',
            if (c.pattern == null && text != c.expect) '内容 $text（要 ${c.expect}）',
          ];
          if (bad.isNotEmpty) {
            wrong.add('第 ${i + 1} 条 ${c.method} ${c.target}：${bad.join('；')}');
          } else {
            passed++;
          }
        }
      } finally {
        await server.stop();
      }
      // ignore: avoid_print — 逐语言的通过数要让跑测试的人看见
      print('$language：${cases.length} 条里通过 $passed 条');
      expect(wrong, isEmpty, reason: '$language 的标准错误：\n${server.stderrText}');
      expect(passed, cases.length);
    });
  }
}
