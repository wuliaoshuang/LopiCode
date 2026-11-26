// 接通后端文档生成的前置（核心 2·A5 段的第 2 步）：服务端的值和规矩怎么和严格规矩对齐。
// “接口服务”这一层按现有后端小库的规矩用严格规矩的语言核心写了一遍（test/fixtures/framework/service_v1.lc），
// 这里拿现有一致性样本里“只考服务这一层”的那些请求（原样取自 test/support/backend_conformance.dart，期望一个字不改）对着它跑：
// 五种语言真起服务，状态码、Content-Type、内容逐字节比。服务只开在本机回环地址的随机端口上，不联外网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/backend_conformance.dart';
import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';
import 'support/proto_lc.dart';

/// 样本里有的接口（去掉网址参数以后的路径开头）。
bool _covered(BeCase c) {
  final path = c.target.split('?').first;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  final first = segs.isEmpty ? '' : segs.first;
  // “循环中途往集合里加东西”那几条要靠 /each 接口先加进去，这里没有那个接口。
  if (first == 'notes' && c.expect.contains('"from"')) return false;
  return const {'', 'todos', 'done', 'by-title', 'notes', 'echo', 'status', 'a', 'say', 'now', 'nope'}.contains(first);
}

void main() {
  final src = File('test/fixtures/framework/service_v1.lc').readAsStringSync();
  final cases = [
    for (final c in conformanceCases)
      if (_covered(c)) c,
  ];

  test('取到的样本条数', () {
    expect(conformanceCases, hasLength(135));
    // ignore: avoid_print — 条数要让跑测试的人看见
    print('一致性样本 135 条里，只考服务这一层的有 ${cases.length} 条');
    expect(cases.length, greaterThan(60));
  });

  test('检查一条问题都没有', () {
    final linked = linkProgram(lcProgram(src));
    expect(linked.issues, isEmpty);
    expect([for (final e in checkModuleTypes(linked.module!).errors) '${e.code} ${e.where} ${e.message}'], isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：这些请求的状态码、Content-Type、内容逐字节一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final server = await gen2Serve(language, gen2ProgramFiles(language, lcProgram(src)));
      final wrong = <String>[];
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
          if (bad.isNotEmpty) wrong.add('第 ${i + 1} 条 ${c.method} ${c.target}：${bad.join('；')}');
        }
      } finally {
        await server.stop();
      }
      expect(wrong, isEmpty, reason: '$language 的标准错误：\n${server.stderrText}');
    });
  }
}
