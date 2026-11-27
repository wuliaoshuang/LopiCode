// 第四轮·A1 真跑的验收：
// 1. “接口服务”复制一份来改的那一份：文档指定用它顶替以后，74 条只考服务层的样例在五种语言里真起服务，
//    状态码、Content-Type、内容和期望逐字节一样（期望就是原库那 74 条的期望，一个字没改）。
// 2. 带手写代码的库（五种语言各一份手写函数）：导入并确认以后在另一份文档里用上，五种语言真编译真跑，输出逐字节一样。
// 服务只开在本机回环地址的随机端口上，不联外网。缺哪种语言的编译器就跳过那种并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service_fork.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/lib_switches.dart';
import 'support/native_lib.dart';
import 'support/service_strict_doc.dart';
import 'support/user_libs.dart';

void main() {
  // 中途包：带手写代码的库的启用、自己的库直接用宿主接口默认都关着（rules.dart）；这里测的是开着时的样子，每条先打开、测完改回默认。
  libSwitchesOn();
  late Directory dir;
  late PathGuard guard;
  setUp(() async {
    LibNativeTrust.instance = LibNativeTrust();
    dir = await Directory.systemTemp.createTemp('lopi_a1_run_');
    guard = PathGuard(dir.path);
  });
  tearDown(() async {
    await pendingWrites();
    await dir.delete(recursive: true);
    LibNativeTrust.instance = LibNativeTrust();
  });

  final cases = serviceCases();
  for (final language in kGen2Languages) {
    test('复制来改的“接口服务” · $language：74 条的状态码、Content-Type、内容逐字节一样', () async {
      expect(cases, hasLength(74));
      expect((await beServiceFork(guard, id: 'shuang/svc', name: '我的接口服务')).problem, isNull);
      // 走一遍“改库的文字”再用：加一句注释，证明改过的那一份也照样对。
      final stored = (await beLibsRead(guard)).single;
      expect(await beLibSaveText(guard, 'shuang/svc', 'modules/service.lc', '${stored.files['modules/service.lc']}\n; 改过了\n'), isNull);
      final doc = serviceStrictDocument()..serviceLib = 'shuang/svc';
      await beLibsAttach(guard, doc);
      final gen = beServiceGenerate(doc, language);
      expect(gen.problem, isNull);
      expect(gen.files!.values.join('\n'), contains('shuang'), reason: '工程里用的是复制件的模块');
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
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
      print('复制件 · $language：${cases.length} 条里通过 $passed 条');
      expect(wrong, isEmpty, reason: '$language 的标准错误：\n${server.stderrText}');
      expect(passed, cases.length);
    });
  }

  for (final language in kGen2Languages) {
    test('复制来改的“接口服务” · $language：在回应里多加一个头，真跑出来的回应确实多了这个头', () async {
      expect((await beServiceFork(guard, id: 'shuang/svc', name: '我的接口服务')).problem, isNull);
      final stored = (await beLibsRead(guard)).single;
      const from = '(设 头 (字典 文字) (典 ("Access-Control-Allow-Origin" "*")))';
      const to = '(设 头 (字典 文字) (典 ("Access-Control-Allow-Origin" "*") ("X-Lopi-Fork" "shuang")))';
      final module = stored.files['modules/service.lc']!;
      expect(from.allMatches(module), hasLength(1), reason: '自带库里“回应”那一句变了的话，这条测试要跟着改');
      expect(await beLibSaveText(guard, 'shuang/svc', 'modules/service.lc', module.replaceFirst(from, to)), isNull);
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final c = cases.firstWhere((c) => c.method == 'GET' && c.status == 200 && c.body == null && c.bodyBytes == null);
      Future<Gen2Reply> ask(String lib) async {
        final doc = serviceStrictDocument()..serviceLib = lib;
        await beLibsAttach(guard, doc);
        final gen = beServiceGenerate(doc, language);
        expect(gen.problem, isNull);
        final server = await gen2Serve(language, gen.files!);
        try {
          return await server.send(c.method, c.target.isEmpty ? '/' : c.target, headers: c.headers);
        } finally {
          await server.stop();
        }
      }

      final changed = await ask('shuang/svc');
      final plain = await ask('');
      expect(changed.status, c.status);
      expect(changed.headers['x-lopi-fork'], 'shuang', reason: '改过的复制件：多了这个头');
      expect(plain.headers.containsKey('x-lopi-fork'), isFalse, reason: '不顶替的时候用的还是自带库，没有这个头');
      expect(utf8.decode(changed.body), utf8.decode(plain.body), reason: '别的没变');
      // ignore: avoid_print
      print('复制件改一处 · $language：回应多了 X-Lopi-Fork');
    });
  }

  for (final language in kGen2Languages) {
    test('带手写代码的库 · $language：导入并确认以后用上，真跑的输出逐字节一样', () async {
      // 开关关着：导入被拒。
      final preview = beLibPreview(beLibUnpack(beLibPack(handLibFiles())).files!);
      expect((await beLibInstall(guard, preview, nativeConfirmed: true)).problems, isNotEmpty);
      // 打开开关、看过并确认：导入。
      await LibNativeTrust.instance.setEnabled(true);
      final ok = beLibPreview(beLibUnpack(beLibPack(handLibFiles())).files!);
      expect((await beLibInstall(guard, ok, nativeConfirmed: true)).problems, isEmpty);
      final doc = userDocument(handUserDoc(), const []);
      await beLibsAttach(guard, doc);
      final gen = beServiceGenerate(doc, language);
      expect(gen.problem, isNull);
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final run = await gen2RunFiles(language, gen.files!);
      expect(run.problem, isNull, reason: language);
      expect(utf8.decode(run.stdout), kHandWant, reason: language);
      // ignore: avoid_print
      print('手写代码 · $language：输出一样');
    });
  }
}
