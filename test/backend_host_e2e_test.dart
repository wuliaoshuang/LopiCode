// 不走界面的端到端：用后端积木宿主（BeBlockHost）照“用户操作”的顺序搭两个接口，生成 Node 代码，
// 真的起起来（只绑 / 只连 127.0.0.1、随机端口），请求几下看结果。机器上没有 node 就跳过并说明。
// 结束只杀自己起的那个进程，绝不按名字杀。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';

import 'support/starter_servers.dart';

void main() {
  test('用宿主搭“加一条笔记 / 按编号取笔记”两个接口 → 生成的 Node 服务真能跑、结果对', () async {
    if (!await toolExists('node')) {
      markTestSkipped('这台机器上没有 node，跳过真跑');
      return;
    }
    final host = BeBlockHost(
      doc: BeDocument(name: '笔记', language: 'node')..collections.add(BeCollection(name: 'notes')),
    );

    // 1. 从积木盒拖出 POST 帽子，就地把路径改成 /notes；拖一块“往集合里加一条”和一块“返回 JSON”进去。
    late String post;
    host.edit(() => post = host.addScript('POST')!.id);
    host.edit(() => expect(host.setHatSlot(host.script(post)!, 'path', '/notes'), isTrue));
    host.edit(() {
      final tree = host.script(post)!;
      final obj = host.newExpr('obj');
      (obj['fields'] as List)
        ..clear()
        ..add(bePair('text', beBodyField('text')));
      tree.body.add(host.newBlock('dbInsert')..args['value'] = obj);
    });
    host.edit(() {
      final tree = host.script(post)!;
      tree.body.add(
        host.newBlock('respondJson')
          ..args['status'] = exNum(201)
          ..args['value'] = beDbCount('notes'),
      );
    });

    // 2. 再拖一个 GET 帽子，路径 /notes/:noteId；放一块“返回 JSON”，内容是“集合里的一条（路径参数）”。
    late String get;
    host.edit(() => get = host.addScript('GET')!.id);
    host.edit(() => expect(host.setHatSlot(host.script(get)!, 'path', '/notes/:noteId'), isTrue));
    host.edit(() {
      final tree = host.script(get)!;
      final block = host.newBlock('respondJson')..args['value'] = beDbGet('notes', host.newExpr('pathParam'));
      tree.body.add(block);
      host.argChanged(tree, block, 'value', const ['id']); // 编辑器在把表达式放进槽以后会调这个钩子
    });
    expect(jsonEncode(host.doc.route(get)!.toJson()), contains('"noteId"'), reason: '新拖进来的“路径参数”顺手选上这个接口唯一的参数');

    expect(validateBackend(host.doc).where((i) => i.isError), isEmpty, reason: '${host.issues.map((i) => i.message).toList()}');
    final target = backendTargetFor('node')!;
    final files = target.generate(host.doc);
    expect(host.codeText, files[target.entryFile]);

    final dir = writeTempProject(files, 'lopi_be_host_e2e_');
    try {
      final server = await startServer(dir, target.startCommand);
      try {
        final made = await server.send('POST', '/notes', json: {'text': '买牛奶'});
        expect(made.status, 201, reason: server.stderrText.toString());
        expect(jsonDecode(made.body), 1);
        expect(jsonDecode((await server.send('POST', '/notes', json: {'text': '写周报'})).body), 2);
        final second = await server.send('GET', '/notes/2');
        expect(second.status, 200);
        expect(jsonDecode(second.body), {'id': 2, 'text': '写周报'});
        expect((await server.send('GET', '/nope')).status, 404);
      } finally {
        await server.stop();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
