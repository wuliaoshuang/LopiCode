// 积木第 4 版·第 1 阶段：用积木文档（backend.lc.json 的结构）搭接口 → 生成 Node / Python / Go / Java → 真起服务发请求，
// 四种语言的响应逐字节一致，而且等于写死的预期。PHP 也真跑（2026-11-26 起；本机没有 php 时跳过）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';

import 'support/backend_conformance.dart';
import 'support/backend_lang_blocks.dart';
import 'support/backend_lang_blocks_cases.dart';
import 'support/backend_lang_blocks_routes.dart';
import 'support/lang_conformance.dart';
import 'support/wait.dart';

void main() {
  final doc = parseLangBlocksDocument(langBlocksDocumentJson(langBlocksRoutes()));

  test('样本文档：用到了新积木（版本 2）、没有校验错误', () {
    expect(doc.usesLang, isTrue);
    expect(doc.toJson()['version'], 2);
    expect([for (final i in backendErrors(doc)) i.message], isEmpty);
  });

  group('新积木搭的接口', () {
    final bodies = <String, List<String>>{};
    for (final language in kLangRunnable) {
      test('$language：生成的后端能（编译）启动，${langBlocksCases.length} 条请求的响应都等于预期', () async {
        final tools = await toolchainFor(language);
        if (tools == null) {
          // ignore: avoid_print 跳过的原因要让跑测试的人看见
          print('跳过：本机没有 $language 的工具');
          markTestSkipped('本机没有 $language 的工具');
          return;
        }
        final generated = generateBackend(doc, language: language)!;
        final dir = writeProject(generated.files, 'lopi_lang_blocks_${language}_');
        try {
          await buildProject(generated.target, dir, tools);
          final server = await startBackend(dir, tools.resolve(generated.target.startCommandFor(0), dir), environment: tools.environment);
          try {
            final got = <String>[];
            final dump = Platform.environment['LOPI_DUMP'] == '1';
            for (final c in langBlocksCases) {
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
            if (dump) File('.tmp/lang_blocks_$language.txt').writeAsStringSync('${got.join('\n')}\n--- stdout\n${server.stdoutLines.join('\n')}\n--- stderr\n${server.stderrText}');
            if (!dump) await waitUntilReal(() => server.stdoutLines.length >= langBlocksLogLines.length, '[$language] 服务把 ${langBlocksLogLines.length} 行日志写到标准输出（现在 ${server.stdoutLines.length} 行）');
            await Future<void>.delayed(const Duration(milliseconds: 50)); // 条件已经成立；再多留一小会儿只为了抓“多写出来的行”，不靠它等
            if (!dump) expect(server.stdoutLines, langBlocksLogLines, reason: '[$language] “写到日志”的输出');
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
