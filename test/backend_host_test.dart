// 后端积木宿主（BeBlockHost）的单元测试：目录、帽子、改动与撤销、参数可选项、校验、看代码。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';

void main() {
  late BeBlockHost host;
  late int edited;
  late List<String> notices;

  setUp(() {
    edited = 0;
    notices = [];
    host = BeBlockHost(doc: backendStarterDocument('样本'), onEdited: () => edited++, onNotice: notices.add);
  });

  BeRoute route(String method, String path) => host.doc.routes.firstWhere((r) => r.method == method && r.path == path);

  group('目录', () {
    test('积木盒：第一页是事件（五种请求方式的新接口），后面每类都有颜色；目录里的每种积木 / 表达式都排得进去', () {
      final cats = host.categories;
      expect(cats.first.id, 'event');
      expect([for (final h in cats.first.hats) h.id], kBeMethods);
      for (final c in cats) {
        expect(BlockColorKey.all, contains(c.colorKey), reason: c.id);
        expect(c.colorKey, isNot(BlockColorKey.unknown), reason: '${c.id} 要有自己的颜色');
        expect(BkPalette.light.tone(c.colorKey).fill, isNot(BkPalette.light.tone(BlockColorKey.unknown).fill));
      }
      expect({for (final c in cats) ...c.blocks}, beBlockSpecs.keys.toSet());
      expect({for (final c in cats) ...c.exprs}, beExprSpecs.keys.toSet()..remove('pair'));
      for (final op in beBlockSpecs.keys) {
        expect(host.blockColorKey(op), isNot(BlockColorKey.unknown), reason: op);
      }
      for (final e in beExprSpecs.keys) {
        expect(host.exprColorKey(e), isNot(BlockColorKey.unknown), reason: e);
      }
    });

    test('每种积木 / 表达式都有一句中文模板，模板里提到的参数都真有、没提到的不超过零个', () {
      for (final spec in beBlockSpecs.values) {
        final sentence = host.blockSentence(spec.op);
        expect(sentence, isNotNull, reason: spec.op);
        final parts = parseBlockSentence(sentence!, spec.args);
        expect({for (final p in parts) ?p.arg}, {for (final a in spec.args) a.name}, reason: spec.op);
        expect(RegExp(r'\{(\w+)\}').allMatches(sentence).length, spec.args.length, reason: '${spec.op} 模板里的参数要正好是它的参数');
      }
      for (final spec in beExprSpecs.values) {
        final sentence = host.exprSentence(spec.kind);
        if (spec.category == '直接填') {
          expect(sentence, isNull, reason: '${spec.kind} 是直接填的值，画成输入框，不用句子');
          continue;
        }
        expect(sentence, isNotNull, reason: spec.kind);
        expect(RegExp(r'\{(\w+)\}').allMatches(sentence!).map((m) => m[1]).toSet(), {for (final a in spec.args) a.name}, reason: spec.kind);
      }
      expect(host.blockSentence('respondJson'), '返回 JSON {value} 状态码 {status}');
      expect(host.blockSpec('没有这种'), isNull);
      expect(host.exprSpec('没有这种'), isNull);
    });

    test('是非类的表达式认得出来（画成六边形）', () {
      expect(host.isBooleanExpr(exBool(true)), isTrue);
      expect(host.isBooleanExpr(exBin('==', exNum(1), exNum(1))), isTrue);
      expect(host.isBooleanExpr(exBin('+', exNum(1), exNum(1))), isFalse);
      expect(host.isBooleanExpr(beIsNull(exText(''))), isTrue);
      expect(host.isBooleanExpr(beDbAll('todos')), isFalse);
    });
  });

  group('帽子', () {
    test('显示“当收到 [GET] [/todos/:id]”：方式是下拉槽，路径是文字槽', () {
      final r = route('GET', '/todos/:id');
      final hat = host.hatOf(r);
      expect([for (final p in hat.parts) p.text], ['当收到', 'GET', '/todos/:id']);
      expect([for (final p in hat.parts) p.slotId], [null, 'method', 'path']);
      expect(hat.parts[1].kind, LcArgKind.choice);
      expect(hat.parts[2].kind, LcArgKind.literalText);
      expect(hat.colorKey, BlockColorKey.event);
      expect([for (final o in host.hatSlotOptions(r, 'method')) o.value], kBeMethods);
      expect(host.hatSlotOptions(r, 'path'), isEmpty);
      expect(host.hatSlotValue(r, 'method'), 'GET');
      expect(host.hatSlotValue(r, 'path'), '/todos/:id');
    });

    test('改方式、改路径；路径参数只改了名字时，积木里读它的地方跟着改', () {
      final id = route('GET', '/todos/:id').id;
      host.edit(() => expect(host.setHatSlot(host.script(id)!, 'method', 'PUT'), isTrue));
      expect(host.doc.route(id)!.method, 'PUT');
      host.edit(() => expect(host.setHatSlot(host.script(id)!, 'path', ' /todos/:todoId '), isTrue));
      expect(host.doc.route(id)!.path, '/todos/:todoId', reason: '两头的空格去掉');
      expect(host.doc.route(id)!.encodeBody(), contains('"todoId"'));
      expect(host.doc.route(id)!.encodeBody(), isNot(contains('"name":"id"')));
      expect(edited, 2);
      expect(notices, isEmpty);
    });

    test('路径格式不对：不改、说原因、不留撤销记录、不触发落盘', () {
      final id = route('GET', '/hello').id;
      for (final (bad, why) in [('hello', '用 / 开头'), ('/a//b', '连着的两个 /'), ('/a/', '末尾不要带 /'), ('/你好', '不能用的字符'), ('/a/:1x', '参数名'), ('', '不能是空的')]) {
        notices.clear();
        host.edit(() => expect(host.setHatSlot(host.script(id)!, 'path', bad), isFalse, reason: bad));
        expect(notices.single, contains(why), reason: bad);
        expect(notices.single, contains('没有改'));
      }
      expect(host.doc.route(id)!.path, '/hello');
      expect(host.canUndo, isFalse);
      expect(edited, 0);
      expect(host.revision, 0);
    });

    test('新建接口：默认路径不和同一种方式下现有的重复；积木盒里的样子跟着变；删掉', () {
      late String a, b;
      host.edit(() => a = host.addScript('GET', x: 10, y: 20)!.id);
      expect((host.doc.route(a)!.method, host.doc.route(a)!.path, host.doc.route(a)!.x, host.doc.route(a)!.y), ('GET', '/new', 10, 20));
      expect(host.categories.first.hats.first.hat.parts.last.text, '/new2', reason: '下一个 GET 会叫 /new2');
      expect(host.categories.first.hats[1].hat.parts.last.text, '/new', reason: 'POST 还没有 /new');
      host.edit(() => b = host.addScript('GET')!.id);
      expect(host.doc.route(b)!.path, '/new2');
      expect(host.addScript('TRACE'), isNull);
      expect(validateBackend(host.doc).where((i) => i.code == BeIssueCode.duplicateRoute), isEmpty);
      host.edit(() => expect(host.removeScript(a), isTrue));
      expect(host.script(a), isNull);
      expect(host.scripts.length, 8);
    });
  });

  group('改动与撤销', () {
    test('一次改动一条记录；撤销重做换回整份文档；内容每变一次 revision 加一并通知', () {
      var changed = 0;
      host.onChanged = () => changed++;
      final before = host.doc.encode();
      host.edit(() => (host.scripts.first as BeRoute).body.add(host.newBlock('log')));
      final after = host.doc.encode();
      expect(after, isNot(before));
      expect((host.revision, changed, edited, host.canUndo, host.canRedo), (1, 1, 1, true, false));
      host.undo();
      expect(host.doc.encode(), before);
      expect((host.revision, changed, edited, host.canUndo, host.canRedo), (2, 2, 2, false, true));
      host.redo();
      expect(host.doc.encode(), after);
      expect((host.canUndo, host.canRedo), (true, false));
      host.undo();
      host.edit(() => host.doc.port = 9000);
      expect(host.canRedo, isFalse, reason: '撤销以后又改了：重做的那条作废');
      host.undo();
      host.undo(); // 没得撤了：什么都不做
      expect(host.doc.encode(), before);
    });

    test('撤销记录有上限；外面换了文档以后记录作废', () {
      final small = BeBlockHost(doc: backendStarterDocument('样本'), maxHistory: 3);
      for (var i = 0; i < 5; i++) {
        small.edit(() => small.doc.port = 9000 + i);
      }
      var undone = 0;
      while (small.canUndo) {
        small.undo();
        undone++;
      }
      expect(undone, 3);
      expect(small.doc.port, 9001);
      small.edit(() => small.doc.port = 1234);
      small.replaceDoc(BeDocument(name: '新的'));
      expect((small.canUndo, small.canRedo, small.doc.name), (false, false, '新的'));
    });
  });

  group('参数', () {
    test('变量、集合的可选项来自文档；可空的变量多一项“不选”', () {
      final insert = beBlockSpecs['dbInsert']!;
      expect([for (final o in host.options(insert.args[0])) o.value], ['todos']);
      expect([for (final o in host.options(insert.args[2])) o.value], ['', 'todo']);
      expect([for (final o in host.options(beBlockSpecs['setVar']!.args[0])) o.value], ['todo']);
      expect([for (final o in host.options(beBlockSpecs['fetch']!.args[1])) o.label], ['GET（取数据）', 'POST（提交）']);
      expect(host.optionLabel(beBlockSpecs['fetch']!.args[1], 'GET'), 'GET');
      expect(host.optionLabel(beExprSpecs['bin']!.args[1], '=='), '=');
    });

    test('“路径参数”的名字是下拉：列这个接口路径里的 :参数；对不上的那个也列出来并标明；菜单不会是空的', () {
      final spec = host.exprSpec('pathParam')!;
      expect(spec.args.single.kind, LcArgKind.choice);
      final r = route('GET', '/todos/:id');
      expect([for (final o in host.options(spec.args.single, tree: r, expr: bePathParam('id'))) o.value], ['id']);
      final stale = host.options(spec.args.single, tree: r, expr: bePathParam('old'));
      expect([for (final o in stale) o.value], ['id', 'old']);
      expect(stale.last.hint, contains('路径里没有'));
      final none = host.options(spec.args.single, tree: route('GET', '/hello'), expr: bePathParam(''));
      expect(none, isNotEmpty);
      expect(host.optionLabel(spec.args.single, 'id'), 'id');
    });

    test('往接口里放了默认叫 id 的“路径参数”：路径里正好一个参数就换成它；有两个就不猜', () {
      late String one, two;
      host.edit(() {
        one = host.doc.addRoute('GET', '/users/:userId')!.id;
        two = host.doc.addRoute('GET', '/a/:x/:y')!.id;
      });
      for (final id in [one, two]) {
        host.edit(() {
          final r = host.script(id)!;
          final b = host.newBlock('respondJson')..args['value'] = host.newExpr('pathParam');
          r.body.add(b);
          host.argChanged(r, b, 'value', const []);
        });
      }
      expect((host.doc.route(one)!.body.single.args['value'] as Map)['name'], 'userId');
      expect((host.doc.route(two)!.body.single.args['value'] as Map)['name'], 'id');
    });

    test('“对象”加一个字段放的是“名字 : 值”，别的“一串值”加一段空文字', () {
      final obj = host.newExpr('obj');
      expect(host.newListItem(obj, beExprSpecs['obj']!.args.single), bePair('name', exText('')));
      expect(host.newListItem(host.newExpr('join'), beExprSpecs['join']!.args.single), exText(''));
      expect(host.exprColorKey('pair'), host.exprColorKey('obj'));
    });

    test('新积木顺手填上第一个集合 / 变量', () {
      expect(host.newBlock('dbInsert').args['collection'], 'todos');
      expect(host.newBlock('setVar').args['name'], 'todo');
      expect(host.newExpr('dbAll')['collection'], 'todos');
    });
  });

  group('校验与代码', () {
    test('样本没有问题；弄出问题以后列得出来、定位到接口，改好以后消失', () {
      expect(host.issues, isEmpty);
      expect(host.errorCount, 0);
      final id = route('GET', '/hello').id;
      host.edit(() => host.script(id)!.body.insert(0, LcBlock(op: 'setVar', args: {'name': '没有这个变量', 'value': exText('')})));
      expect(host.errorCount, greaterThan(0));
      final issue = host.issues.firstWhere((i) => i.isError);
      expect(issue.scriptId, id);
      expect(issue.path, isNotEmpty);
      expect(issue.message, isNotEmpty);
      host.undo();
      expect(host.issues, isEmpty);
    });

    test('选了没有生成器的语言：有一条提示，看代码给一句说明而不是崩', () {
      host.edit(() => host.doc.language = 'cobol');
      expect(host.issues.any((i) => i.message.contains('cobol')), isTrue);
      expect(host.codeText, contains('还没有生成器'));
      expect(host.codeLanguage, 'cobol');
      expect(host.target, isNull);
    });

    test('看代码＝当前语言的入口文件；换语言跟着换', () {
      for (final t in backendTargets) {
        host.edit(() => host.doc.language = t.id);
        expect(host.codeLanguage, t.label);
        expect(host.codeText, t.generate(host.doc)[t.entryFile]);
        expect(host.codeText, contains('todos'));
      }
    });
  });
}

extension on BeRoute {
  String encodeBody() => '${[for (final b in body) b.toJson()]}'.replaceAll(' ', '').replaceAll('name:', '"name":').replaceAll(':todoId', ':"todoId"').replaceAll(':id', ':"id"');
}
