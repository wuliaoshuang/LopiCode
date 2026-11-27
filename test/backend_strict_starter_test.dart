// 新建文档默认是严格规矩以后，入门样本（backendStarterDocument）在严格规矩下：
// 一条类型问题都没有；五种语言照产品给的命令编译、启动，真跑一遍增删改查，结果和老规矩的样本一样。
// 服务只开在本机回环地址上，不联外网。缺哪种语言的编译器就跳过那种语言。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_strict_target.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:path/path.dart' as p;

import 'support/gen2_run.dart';
import 'support/gen2_serve.dart';

const List<(String, String, String?)> _requests = [
  ('GET', '/hello', null),
  ('GET', '/hello?name=%E5%B0%8F%E6%98%8E', null),
  ('GET', '/hello?name=', null),
  ('POST', '/todos', '{}'),
  ('POST', '/todos', '{"title":""}'),
  ('POST', '/todos', '{"title":"买菜"}'),
  ('GET', '/todos/count', null),
  ('GET', '/todos/1', null),
  ('GET', '/todos/9', null),
  ('PATCH', '/todos/1', '{"done":true}'),
  ('DELETE', '/todos/1', null),
  ('GET', '/todos', null),
];

const List<String> _expected = [
  '200 {"message":"你好，世界！"}',
  '200 {"message":"你好，小明！"}',
  '200 {"message":"你好，世界！"}',
  '400 {"error":"缺少 title"}',
  '400 {"error":"缺少 title"}',
  '201 {"createdAt":"T","done":false,"id":1,"title":"买菜"}',
  '200 {"count":1}',
  '200 {"createdAt":"T","done":false,"id":1,"title":"买菜"}',
  '404 {"error":"找不到 id 是 9 的待办"}',
  '200 {"createdAt":"T","done":true,"id":1,"title":"买菜"}',
  '200 {"ok":true}',
  '200 []',
];

void main() {
  late Directory tmp;
  late String ws;
  setUp(() {
    beStrictBackendGen = true;
    tmp = Directory.systemTemp.createTempSync('lopi_be_starter_');
    ws = p.join(tmp.path, 'proj');
    Directory(ws).createSync();
  });
  tearDown(() async {
    beStrictBackendGen = kLangStrictBackendGen;
    await pendingWrites();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('严格规矩的入门样本：没有类型问题、没有别的错误，用的是严格的生成器；老规矩的样本积木不变', () {
    final doc = backendStarterDocument('样本', rules: kLangRulesStrict);
    expect(doc.rules, kLangRulesStrict);
    expect([for (final f in beTypeCheck(doc)!.findings) '${f.issue.code} ${f.problem}'], isEmpty);
    expect([for (final e in backendErrors(doc)) '${e.code} ${e.where} ${e.problem}'], isEmpty);
    expect(backendTargetOf(doc), isA<StrictBackendTarget>());
    final loose = backendStarterDocument('样本', rules: kLangRulesLoose);
    expect(loose.encode(), isNot(contains('orElse')));
    expect(loose.encode(), isNot(contains('"rules"')));
  });

  for (final language in kGen2Languages) {
    test('$language：严格规矩的入门样本照产品给的命令真跑一遍增删改查', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final port = await gen2FreePort();
      final doc = backendStarterDocument('样本', language: language, port: port, rules: kLangRulesStrict);
      File(p.join(ws, kBackendFileName)).writeAsStringSync('${doc.encode()}\n');
      final r = await regenerateBackend(ws);
      expect(r.error, isNull);
      final info = (await findBackendProjects(ws)).single;
      final server = await gen2ServeShell(Directory(ws), build: info.buildCommands, start: info.startCommand!.replaceFirst('0.0.0.0:', '127.0.0.1:'), port: port, php: language == 'php');
      final got = <String>[];
      try {
        for (final (method, target, body) in _requests) {
          final reply = await server.send(method, target, headers: body == null ? const {} : const {'Content-Type': 'application/json'}, body: body == null ? null : utf8.encode(body));
          got.add('${reply.status} ${utf8.decode(reply.body).replaceAll(RegExp(r'"createdAt":"[0-9T:Z-]+"'), '"createdAt":"T"')}');
        }
      } finally {
        await server.stop();
      }
      expect(got, _expected, reason: server.stderrText);
    });
  }
}
