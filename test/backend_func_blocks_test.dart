// 积木第 4 版·第 2 阶段（函数和“我的积木”）：用积木文档（backend.lc.json 的结构）搭接口 → 生成 Node / Python / Go / Java → 真起服务发请求，
// 四种语言的响应逐字节一致，而且等于写死的预期。PHP 本机跑不了，只做文本检查（“未实测”）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';

import 'support/backend_conformance.dart';
import 'support/backend_func_blocks.dart';
import 'support/lang_conformance.dart';

void main() {
  final doc = funcBlocksDocument();

  test('样本文档：有函数（版本 3）、/wrap/after 那一截真的包成了积木、没有校验错误', () {
    expect(doc.usesFunctions, isTrue);
    expect(doc.toJson()['version'], 3);
    expect(doc.functions.map((f) => f.name), contains('填一截'));
    final wrapped = doc.functions.firstWhere((f) => f.name == '填一截');
    expect(wrapped.paramNames, ['out', 'a']);
    expect(wrapped.body.map((b) => b.op), ['listPush', 'forCount', 'log']);
    expect(doc.route('wrapAfter')!.body[2].body.map((b) => b.op), ['listPush', 'call:${wrapped.id}']);
    expect(doc.route('wrapBefore')!.body[2].body.map((b) => b.op), ['listPush', 'listPush', 'forCount', 'log']);
    expect([for (final i in backendErrors(doc)) i.message], isEmpty);
  });

  group('函数和“我的积木”搭的接口', () {
    final bodies = <String, List<String>>{};
    for (final language in kLangRunnable) {
      test('$language：生成的后端能（编译）启动，${funcBlocksCases.length} 条请求的响应都等于预期', () async {
        final tools = await toolchainFor(language);
        if (tools == null) {
          // ignore: avoid_print 跳过的原因要让跑测试的人看见
          print('跳过：本机没有 $language 的工具');
          markTestSkipped('本机没有 $language 的工具');
          return;
        }
        final generated = generateBackend(doc, language: language)!;
        final dir = writeProject(generated.files, 'lopi_func_blocks_${language}_');
        try {
          await buildProject(generated.target, dir, tools);
          final server = await startBackend(dir, tools.resolve(generated.target.startCommandFor(0), dir), environment: tools.environment);
          try {
            final got = <String>[];
            final dump = Platform.environment['LOPI_DUMP'] == '1';
            for (final c in funcBlocksCases) {
              final r = await sendRaw(
                server.port,
                c.method,
                c.target,
                body: c.body == null ? null : utf8.encode(c.body!),
                headers: c.body == null ? const {} : const {'Content-Type': 'application/json'},
              );
              final text = utf8.decode(r.body);
              got.add('${r.status} ${r.type} $text');
              if (dump) continue;
              final where = '[$language] $c\n服务的错误输出：${server.stderrText}';
              expect(text, c.expect, reason: where);
              expect(r.status, c.status, reason: where);
              expect(r.type, startsWith(c.type), reason: where);
            }
            if (dump) File('.tmp/func_blocks_$language.txt').writeAsStringSync('${got.join('\n')}\n--- stdout\n${server.stdoutLines.join('\n')}\n--- stderr\n${server.stderrText}');
            await Future<void>.delayed(const Duration(milliseconds: 200));
            if (!dump) expect(server.stdoutLines, funcBlocksLogLines, reason: '[$language] “写到日志”的输出');
            bodies[language] = got;
          } finally {
            await server.stop();
          }
        } finally {
          dir.deleteSync(recursive: true);
        }
      }, timeout: const Timeout(Duration(minutes: 8)));
    }

    test('各语言的响应逐字节相同', () {
      if (bodies.length < 2) {
        // ignore: avoid_print 跳过的原因要让跑测试的人看见
        print('跳过：能跑的语言不到两种');
        markTestSkipped('能跑的语言不到两种');
        return;
      }
      for (final e in bodies.entries.skip(1)) {
        expect(e.value, bodies.values.first, reason: e.key);
      }
    });
  });
}
