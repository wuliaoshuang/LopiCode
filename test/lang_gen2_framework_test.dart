// 核心 2 的验收（设计 §8.2）：“小框架”库（七个模块）＋示例服务“小书店”由规矩版本 2 的生成器产出，
// 五种语言真编译、真起服务，原型的 39 条请求一条条发过去，回应和标准输出与原型的期望逐字节一样。
// 样例 test/fixtures/framework/bookshop.lc 是从原型 docs/blocks-v5-prototypes/02-web-framework/ 搬来加上类型的（换算表见同目录 README.md）；
// 39 条请求和期望直接读原型的 cases.json、expected-logs.json，一个字不改。
// 服务只开在本机回环地址的随机空闲端口上，测试自己发请求、自己关，不联外网。故意写错的那几组在 lang_gen2_framework_bad_test.dart。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/proto_lc.dart';

const _proto = 'docs/blocks-v5-prototypes/02-web-framework';

void main() {
  final src = File('test/fixtures/framework/bookshop.lc').readAsStringSync();
  final cases = (jsonDecode(File('$_proto/cases.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final logs = (jsonDecode(File('$_proto/expected-logs.json').readAsStringSync()) as List).cast<String>();

  test('原型的样本是 39 条，日志也是 39 行', () {
    expect(cases, hasLength(39));
    expect(logs, hasLength(39));
  });

  test('小框架＋小书店：检查一条问题都没有，七个库模块连成一个', () {
    final program = lcProgram(src);
    expect(program.modules.map((m) => m.name), ['错误们', '响应', '上下文', '中间件', '路由', '校验', '仓库', '书店服务']);
    final linked = linkProgram(program);
    expect(linked.issues, isEmpty);
    expect(checkModuleTypes(linked.module!).errors, isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：39 条请求的回应、39 行日志逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final server = await gen2Serve(language, gen2ProgramFiles(language, lcProgram(src)));
      final wrong = <String>[];
      List<String> printed;
      try {
        for (var i = 0; i < cases.length; i++) {
          final c = cases[i];
          final body = c['body'] as String?;
          final reply = await server.send(
            c['method'] as String,
            c['target'] as String,
            headers: ((c['headers'] as Map?) ?? const {}).cast<String, String>(),
            body: body == null ? null : utf8.encode(body),
          );
          final bad = <String>[
            if (reply.status != c['status']) '状态码 ${reply.status}（要 ${c['status']}）',
            if (reply.headers['content-type'] != c['type']) 'Content-Type ${reply.headers['content-type']}（要 ${c['type']}）',
            if (!_same(reply.body, utf8.encode(c['expect'] as String))) '内容 ${utf8.decode(reply.body, allowMalformed: true)}（要 ${c['expect']}）',
            for (final h in ((c['resHeaders'] as Map?) ?? const {}).entries)
              if (reply.headers['${h.key}'.toLowerCase()] != h.value) '${h.key} ${reply.headers['${h.key}'.toLowerCase()]}（要 ${h.value}）',
          ];
          if (bad.isNotEmpty) wrong.add('第 ${i + 1} 条 ${c['method']} ${c['target']}（${c['note']}）：${bad.join('；')}');
        }
      } finally {
        printed = await server.stop();
      }
      expect(wrong, isEmpty, reason: '$language 的标准错误：\n${server.stderrText}');
      expect(printed, logs, reason: '$language 的标准错误：\n${server.stderrText}');
    });
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
