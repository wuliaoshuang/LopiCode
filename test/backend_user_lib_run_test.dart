// 用户自己写的库（积木第 5 版·库 2）的验收：用积木从零写库，在另一份文档里用它，五种语言真编译真跑，输出逐字节一样。
// 每个库都走整条产品路径：库文档 → 写出器 → 库文件 → 读入器 → 放进用它的文档 → 五种语言生成（见 support/user_libs.dart）。
// 缺哪种语言的编译器就跳过那种并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/backend_lang_blocks.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/user_libs.dart';

void main() {
  final cases = <(String, J Function(), List<J Function()>, String)>[
    ('校验器（类与接口）', checkUserDoc, [checkLibDoc], kCheckWant),
    ('流程（帽子、隐含的东西、带口）', flowUserDoc, [flowLibDoc], kFlowWant),
    ('三个库一起用（故意同名）', manyUserDoc, [flowLibDoc, notesLibDoc, checkLibDoc], kManyWant),
  ];
  for (final (name, user, libs, want) in cases) {
    for (final language in kGen2Languages) {
      test('$name · $language', () async {
        final doc = userDocument(user(), [for (final l in libs) buildUserLib(l()).lib]);
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
        expect(utf8.decode(run.stdout), want, reason: language);
      });
    }
  }

  // 导出再导入：三个库存进一个项目 → 各导出成一个文件 → 导入到另一个项目 → 在那边用它们，真跑的结果和上面一样。
  for (final language in kGen2Languages) {
    test('导出再导入以后再用（三个库） · $language', () async {
      final from = await Directory.systemTemp.createTemp('lopi_lib_a_'), to = await Directory.systemTemp.createTemp('lopi_lib_b_');
      addTearDown(() async {
        await pendingWrites();
        await from.delete(recursive: true);
        await to.delete(recursive: true);
      });
      final a = PathGuard(from.path), b = PathGuard(to.path);
      for (final l in [flowLibDoc, notesLibDoc, checkLibDoc]) {
        final doc = parseLangBlocksDocument(l());
        final rel = beLibSourceRel(doc.library!.id);
        await File(a.resolve(rel)).parent.create(recursive: true);
        await saveBackendFile(File(a.resolve(rel)), doc);
        expect((await beLibSaveSource(a, rel, doc)).problems, isEmpty);
        final out = await beLibExport(a, doc.library!.id);
        await File(a.resolve(out.rel!)).copy('${to.path}/in.lopilib');
        final opened = await beLibOpenPack(b, 'in.lopilib');
        expect((await beLibInstall(b, opened.preview!)).problems, isEmpty);
      }
      final doc = parseLangBlocksDocument(manyUserDoc());
      await beLibsAttach(b, doc);
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
      expect(utf8.decode(run.stdout), kManyWant, reason: language);
    });
  }

  // 开着服务的两个库：对着真起来的服务逐条发请求，状态码和内容逐字节比。
  final served = <(String, J Function(), List<J Function()>, List<(String, String, int, String)>)>[
    ('待办（叠在接口服务上）', todoUserDoc, [todoLibDoc], kTodoCases),
    ('批量任务（要等的事）', batchUserDoc, [batchLibDoc], const [('GET', '/go', 200, kBatchWant), ('GET', '/go', 200, kBatchWant)]),
  ];
  for (final (name, user, libs, wants) in served) {
    for (final language in kGen2Languages) {
      test('$name · $language', () async {
        final doc = userDocument({...user(), 'language': language}, [for (final l in libs) buildUserLib(l()).lib]);
        final gen = beServiceGenerate(doc, language);
        expect(gen.problem, isNull);
        final skip = gen2SkipReason(language);
        if (skip != null) {
          // ignore: avoid_print — 跳过的原因要让跑测试的人看见
          print('跳过：$skip');
          markTestSkipped(skip);
          return;
        }
        final server = await gen2Serve(language, gen.files!);
        try {
          for (final (method, target, status, want) in wants) {
            final reply = await server.send(method, target);
            expect(utf8.decode(reply.body), want, reason: '$method $target\n${server.stderrText}');
            expect(reply.status, status, reason: '$method $target');
          }
        } finally {
          await server.stop();
        }
      });
    }
  }
}
