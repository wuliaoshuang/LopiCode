// 后端积木的数据模型、积木目录、连带修改、中文读法。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_edit.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_conformance.dart';

void main() {
  group('读写', () {
    test('存了再读，内容一样', () {
      final doc = conformanceDocument();
      doc.routes.first
        ..x = 24
        ..y = 48.5;
      final again = BeDocument.parse(doc.encode());
      expect(again.note, isNull);
      expect(again.doc.toJson(), doc.toJson());
      expect(again.doc.routes.first.x, 24);
      expect(doc.toJson()['kind'], 'backend');
      // 没摆过位置的不写 x / y
      expect(doc.routes[1].toJson().containsKey('x'), isFalse);
    });

    test('整份读不懂：空白文档 + 说明，不抛异常', () {
      for (final bad in ['', '{', '乱码', '[]', '123', 'null', '"x"', '{"kind":"page"}', '{"kind":5}']) {
        final r = BeDocument.parse(bad);
        expect(r.note, isNotNull, reason: bad);
        expect(r.doc.routes, isEmpty);
        expect(r.doc.port, kBeDefaultPort);
        expect(r.doc.language, kBeDefaultLanguage);
      }
      // 空对象是一份合法的空白文档
      expect(BeDocument.parse('{}').note, isNull);
    });

    test('坏字段逐条跳过，好的留下；类型不对的用默认值', () {
      final r = BeDocument.parse(
        jsonEncode({
          'version': 99,
          'name': 5,
          'port': '80',
          'language': ['x'],
          'variables': [
            {'name': 'ok', 'type': 'number', 'initial': 'x'},
            {'name': '1bad'},
            'x',
            {'name': 'ok'},
            null,
          ],
          'collections': [
            {'name': 'todos'},
            {'name': 'bad name'},
            7,
            {'name': 'todos'},
          ],
          'routes': [
            {'id': 'r1', 'method': 'get', 'path': '/a', 'x': 'left', 'y': double.maxFinite, 'body': 'x'},
            {
              'id': 'r1',
              'method': 'POST',
              'path': '/b',
              'body': [
                1,
                {'op': ''},
                {'op': 'log', 'args': 3},
                {
                  'op': 'weird',
                  'args': {'k': 1},
                },
              ],
            },
            {'method': 'TRACE', 'path': '/c'},
            {'method': 'GET'},
            {'id': 'bad id!', 'method': 'GET', 'path': 'no-slash'},
            'x',
          ],
        }),
      );
      final doc = r.doc;
      expect(r.note, contains('读不懂'));
      expect(doc.name, '我的后端');
      expect(doc.port, kBeDefaultPort);
      expect(doc.language, kBeDefaultLanguage);
      expect([for (final v in doc.variables) '${v.name}:${v.type}:${v.initial}'], ['ok:number:0']);
      expect([for (final c in doc.collections) c.name], ['todos']);
      expect([for (final x in doc.routes) '${x.id} ${x.method} ${x.path}'], ['r1 GET /a', 'r2 POST /b', 'r3 GET no-slash']);
      expect(doc.routes[0].x, isNull);
      expect(doc.routes[0].y, double.maxFinite);
      // 不认识的积木留着（数据不丢），坏的跳过
      expect([for (final b in doc.routes[1].body) b.op], ['log', 'weird']);
      expect(doc.routes[1].body[1].args, {'k': 1});
    });

    test('端口、语言不合规矩时回默认值；没有生成器的语言 id 留着', () {
      expect(BeDocument(port: 0).port, kBeDefaultPort);
      expect(BeDocument(port: 70000).port, kBeDefaultPort);
      expect(BeDocument(port: 3000).port, 3000);
      expect(BeDocument(language: 'rust').language, 'rust');
      expect(BeDocument(language: '../x').language, kBeDefaultLanguage);
    });

    test('存盘文件：不存在返回 null；坏了备份原件、回空白文档；存了能读回来', () async {
      final dir = Directory.systemTemp.createTempSync('be_file_');
      try {
        final file = File('${dir.path}/$kBackendFileName');
        expect(await loadBackendFile(file), isNull);
        for (final bad in ['{半截', '[1,2]', '{"kind":"page"}']) {
          file.writeAsStringSync(bad);
          final r = await loadBackendFile(file);
          expect(r!.note, isNotNull, reason: bad);
          expect(r.doc.routes, isEmpty);
        }
        expect(dir.listSync().where((e) => e.path.contains('.bad-')), isNotEmpty);
        file.writeAsStringSync('   ');
        expect((await loadBackendFile(file))!.doc.routes, isEmpty);
        final doc = conformanceDocument();
        await saveBackendFile(file, doc);
        final again = await loadBackendFile(file);
        expect(again!.note, isNull);
        expect(again.doc.toJson(), doc.toJson());
      } finally {
        await pendingWrites();
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('路径', () {
    test('合法的路径拆成段', () {
      expect(parseBePath('/'), isEmpty);
      expect([for (final s in parseBePath('/todos/:id/x-y_z.1~')!) '${s.isParam ? ':' : ''}${s.text}'], ['todos', ':id', 'x-y_z.1~']);
      expect(bePathParams('/a/:x/b/:y'), ['x', 'y']);
      expect(bePathShape('/todos/:id'), bePathShape('/todos/:other'));
      expect(bePathShape('/todos/:id'), isNot(bePathShape('/todos/count')));
    });

    test('不合法的路径', () {
      for (final bad in ['', 'todos', '/todos/', '//', '/a//b', '/中文', '/a b', '/:', '/:1x', '/a?b=1', '/a#b', '/:id-x', '/a/../b/%20', '/${'a' * 300}']) {
        expect(parseBePath(bad), isNull, reason: bad);
        expect(bePathParams(bad), isEmpty);
        expect(bePathShape(bad), isNull);
      }
    });
  });

  group('增删改', () {
    test('加接口：id 自动取没用过的；方式不认识不加', () {
      final doc = BeDocument();
      expect(doc.addRoute('get', '/a')!.id, 'r1');
      expect(doc.addRoute('POST', '/a', x: 1, y: 2)!.id, 'r2');
      expect(doc.addRoute('HEAD', '/a'), isNull);
      expect(doc.removeRoute('r1'), isTrue);
      expect(doc.removeRoute('r1'), isFalse);
      expect(doc.addRoute('GET', '/b')!.id, 'r1');
      expect(doc.route('r2')!.method, 'POST');
      expect(doc.route('nope'), isNull);
    });

    test('加变量 / 集合：名字不合规矩或重名不加', () {
      final doc = BeDocument();
      expect(doc.addVariable('n', type: 'number', initial: 3)!.initial, 3);
      expect(doc.addVariable('n'), isNull);
      expect(doc.addVariable('1n'), isNull);
      expect(doc.addVariable('x', type: 'list'), isNull);
      expect(doc.addCollection('todos'), isNotNull);
      expect(doc.addCollection('todos'), isNull);
      expect(doc.addCollection('to dos'), isNull);
    });

    test('变量改名：积木参数和表达式里的引用一起改；数引用', () {
      final doc = conformanceDocument();
      final before = doc.variableRefCount('todo');
      expect(before, greaterThan(3));
      expect(doc.renameVariable('todo', 'n'), isFalse, reason: '已经有 n 了');
      expect(doc.renameVariable('todo', '1x'), isFalse);
      expect(doc.renameVariable('nope', 'x'), isFalse);
      expect(doc.renameVariable('todo', 'record'), isTrue);
      expect(doc.variableRefCount('todo'), 0);
      expect(doc.variableRefCount('record'), before);
      // 对象里叫 todo 的键是文字，不是变量，不跟着改
      expect(doc.encode(), isNot(contains('"name": "todo"')));
      expect(doc.encode(), contains('"key": "todo"'));
      // 集合也叫 todos 的不受影响
      expect(doc.collection('todos'), isNotNull);
      expect(doc.removeVariable('record'), isTrue);
      expect(doc.variableRefCount('record'), before, reason: '删变量不动积木');
    });

    test('集合改名：所有用到它的地方一起改', () {
      final doc = conformanceDocument();
      final before = doc.collectionRefCount('todos');
      expect(before, greaterThan(8));
      expect(doc.renameCollection('todos', 'notes'), isFalse);
      expect(doc.renameCollection('todos', 'tasks'), isTrue);
      expect(doc.collectionRefCount('tasks'), before);
      expect(doc.collectionRefCount('todos'), 0);
      expect(doc.removeCollection('tasks'), isTrue);
      expect(doc.removeCollection('tasks'), isFalse);
    });

    test('改变量类型 / 初始值', () {
      final doc = BeDocument(
        variables: [LcVariable(name: 'n', type: 'number', initial: 5)],
      );
      expect(doc.retypeVariable('n', 'text'), isTrue);
      expect(doc.variable('n')!.initial, '');
      expect(doc.setVariableInitial('n', '你好'), isTrue);
      expect(doc.variable('n')!.initial, '你好');
      expect(doc.setVariableInitial('n', 5), isTrue);
      expect(doc.variable('n')!.initial, '', reason: '类型对不上用默认值');
      expect(doc.retypeVariable('n', 'list'), isFalse);
      expect(doc.setVariableInitial('nope', 1), isFalse);
    });

    test('改接口路径：参数个数一样时，读旧参数名的地方跟着改', () {
      final doc = conformanceDocument();
      final r = doc.routes.firstWhere((x) => x.method == 'PUT');
      expect(doc.setRoutePath(r.id, '/a/:first/b/:second'), isTrue);
      expect(jsonEncode(r.toJson()), allOf(contains('"first"'), contains('"second"'), isNot(contains('"name":"x"'))));
      // 个数变了：不动积木
      expect(doc.setRoutePath(r.id, '/a/:only'), isTrue);
      expect(jsonEncode(r.toJson()), contains('"second"'));
      expect(doc.setRoutePath(r.id, 'bad'), isFalse);
      expect(r.path, '/a/:only');
      expect(doc.setRoutePath('nope', '/x'), isFalse);
      expect(doc.setRouteMethod(r.id, 'patch'), isTrue);
      expect(r.method, 'PATCH');
      expect(doc.setRouteMethod(r.id, 'HEAD'), isFalse);
    });

    test('挪接口、复制接口', () {
      final doc = BeDocument();
      doc.addRoute('GET', '/a')!.body.add(newBeBlock('respondJson'));
      doc.addRoute('GET', '/b/:id');
      doc.addRoute('GET', '/');
      expect(doc.moveRoute('r3', 0), isTrue);
      expect([for (final r in doc.routes) r.id], ['r3', 'r1', 'r2']);
      expect(doc.moveRoute('r3', 99), isTrue);
      expect([for (final r in doc.routes) r.id], ['r1', 'r2', 'r3']);
      final copy = doc.duplicateRoute('r1')!;
      expect(copy.id, 'r4');
      expect(copy.path, '/a/copy');
      expect(doc.routes[1], same(copy));
      copy.body.first.args['status'] = exNum(500);
      expect(exprNum(doc.route('r1')!.body.first.args['status'], 'v'), 200, reason: '积木是新对象');
      expect(parseBePath(doc.duplicateRoute('r2')!.path), isNotNull);
      expect(doc.duplicateRoute('r3')!.path, '/copy');
      expect(doc.duplicateRoute('nope'), isNull);
    });

    test('接口混了 LcBlockTree：按路径插、挪、删积木', () {
      final r = BeRoute(id: 'r1', method: 'GET', path: '/');
      expect(r.insertBlock(const [], newBeBlock('if')), isTrue);
      expect(r.insertBlock([lcStep(0)], newBeBlock('log'), inElse: true), isTrue);
      expect(r.blockAt([lcStep(0), lcStep(0, inElse: true)])!.op, 'log');
      expect(r.moveBlock([lcStep(0), lcStep(0, inElse: true)], const []), isTrue);
      expect([for (final b in r.body) b.op], ['if', 'log']);
      expect(r.removeBlock([lcStep(0)])!.op, 'if');
      final copy = r.clone();
      copy.body.clear();
      expect(r.body, hasLength(1));
    });
  });

  group('积木目录', () {
    test('和设计文档里的表一致（op、参数名、有没有 body / else；表达式的种类和参数）', () {
      final doc = File('docs/blocks-v3-design.md').readAsStringSync();
      String section(String name) => doc.substring(doc.indexOf('<!-- $name:start -->'), doc.indexOf('<!-- $name:end -->'));
      final fromDoc = <String, Set<String>>{};
      for (final m in RegExp(r'^\| `(\w+)` \| (.*?) \| .* \|$', multiLine: true).allMatches(section('be-ops'))) {
        fromDoc[m[1]!] = {for (final a in RegExp(r'`(\w+)`').allMatches(m[2]!)) a[1]!};
      }
      expect(fromDoc.keys.toSet(), beBlockSpecs.keys.toSet());
      for (final spec in beBlockSpecs.values) {
        expect(fromDoc[spec.op], {for (final a in spec.args) a.name, if (spec.hasBody) 'body', if (spec.hasElse) 'else'}, reason: spec.op);
      }
      final exprs = <String, Set<String>>{};
      for (final m in RegExp(r'`(\w+)\{([^}]*)\}`').allMatches(section('be-exprs'))) {
        exprs[m[1]!] = {for (final a in RegExp(r'[A-Za-z]+').allMatches(m[2]!.split(':').first)) a[0]!};
      }
      expect(exprs.keys.toSet(), beExprSpecs.keys.toSet());
      for (final spec in beExprSpecs.values) {
        expect(exprs[spec.kind], {for (final a in spec.args) a.name}, reason: spec.kind);
      }
    });

    test('每块积木都有中文名、分类在清单里、选项和中文名一样多；每类都有东西', () {
      for (final spec in beBlockSpecs.values) {
        expect(spec.label, isNotEmpty);
        expect(spec.hint, isNotEmpty, reason: spec.op);
        expect(beBlockCategories, contains(spec.category), reason: spec.op);
        expect(beCategories, contains(spec.category));
        for (final a in spec.args) {
          expect(a.label, isNotEmpty);
          if (a.kind == LcArgKind.choice) expect(a.choiceLabels.length, a.choices.length, reason: '${spec.op}.${a.name}');
          expect(a.kind, isNot(LcArgKind.node), reason: '后端没有控件');
        }
      }
      for (final spec in beExprSpecs.values) {
        expect(beExprCategories, contains(spec.category), reason: spec.kind);
        expect(beCategories, contains(spec.category));
        for (final a in spec.args) {
          if (a.kind == LcArgKind.choice) expect(a.choiceLabels.length, a.choices.length);
        }
      }
      expect([for (final c in beBlockCategories) ...beBlockSpecsIn(c)].length, beBlockSpecs.length);
      // “一个字段”只能在对象里，不单独挑
      expect([for (final c in beExprCategories) ...beExprSpecsIn(c)].length, beExprSpecs.length - 1);
      for (final c in beBlockCategories) {
        expect(beBlockSpecsIn(c), isNotEmpty, reason: c);
      }
      for (final c in beExprCategories) {
        expect(beExprSpecsIn(c), isNotEmpty, reason: c);
      }
    });

    test('新建的积木 / 表达式：参数名都在表里，种类对得上；给了文档就挑好变量和集合', () {
      final doc = BeDocument(
        variables: [
          LcVariable(name: 's'),
          LcVariable(name: 'n', type: 'number'),
        ],
        collections: [BeCollection(name: 'todos')],
      );
      for (final spec in beBlockSpecs.values) {
        final b = newBeBlock(spec.op, doc);
        expect(b.op, spec.op);
        expect(b.args.keys.toSet().difference({for (final a in spec.args) a.name}), isEmpty, reason: spec.op);
        for (final a in spec.args.where((a) => !a.optional)) {
          expect(b.args.containsKey(a.name), isTrue, reason: '${spec.op}.${a.name}');
        }
        final again = newBeBlock(spec.op, doc);
        expect(identical(again.args, b.args), isFalse);
      }
      for (final spec in beExprSpecs.values) {
        final e = newBeExpr(spec.kind, doc, BeRoute(id: 'r', method: 'GET', path: '/x/:key'));
        expect(exprKind(e), spec.kind);
        expect(e.keys.toSet(), {'e', for (final a in spec.args) a.name}, reason: spec.kind);
      }
      expect(newBeBlock('changeVar', doc).args['name'], 'n');
      expect(newBeBlock('dbInsert', doc).args['collection'], 'todos');
      expect(newBeBlock('dbInsert').args['collection'], '');
      expect(newBeExpr('pathParam', doc, BeRoute(id: 'r', method: 'GET', path: '/x/:key'))['name'], 'key');
      expect(newBeExpr('pathParam')['name'], 'id');
      expect(newBeBlock('没有的').args, isEmpty);
      expect(exprKind(newBeExpr('没有的')), 'text');
      expect(exprKind(newBeListItem('obj', 'fields')), 'pair');
      expect(exprKind(newBeListItem('join', 'items')), 'text');
    });

    test('是非类的表达式', () {
      expect(beExprIsBool(exBool(true)), isTrue);
      expect(beExprIsBool(beIsNull(beBody())), isTrue);
      expect(beExprIsBool(exBin('<', exNum(1), exNum(2))), isTrue);
      expect(beExprIsBool(exBin('and', exNum(1), exNum(2))), isTrue);
      expect(beExprIsBool(exBin('+', exNum(1), exNum(2))), isFalse);
      expect(beExprIsBool(beBody()), isFalse);
      expect(beExprIsBool(null), isFalse);
    });
  });

  group('中文读法', () {
    test('每种积木、每种表达式都有读法（不是“不认识的…”）', () {
      for (final op in beBlockSpecs.keys) {
        expect(describeBeBlock(newBeBlock(op)), isNot(contains('不认识')), reason: op);
      }
      for (final kind in beExprSpecs.keys) {
        expect(describeBeExpr(newBeExpr(kind)), isNot(contains('不认识')), reason: kind);
      }
    });

    test('几句典型的', () {
      final id = bePathParam('id');
      expect(describeBeExpr(beDbGet('todos', id)), '集合 todos 里 id 是 路径参数 id 的那条');
      expect(describeBeExpr(beObj({'title': beBodyField('title'), 'done': exBool(false)})), '{title: 请求内容的 title, done: 否}');
      expect(describeBeExpr(beObj({})), '空对象 {}');
      expect(describeBeExpr(beField(exVar('todo'), 'title')), 'todo 的 title');
      expect(describeBeExpr(exBin('+', exNum(1), exBin('*', exNum(2), exNum(3)))), '1 + （2 × 3）');
      expect(describeBeExpr(beDbFind('todos', 'done', exBool(true))), '集合 todos 里 done 等于 是 的那些');
      expect(describeBeExpr(beLen(beDbAll('todos'))), '集合 todos 的全部 有几个');
      expect(describeBeBlock(newBeBlock('respondJson')), '返回 200 和数据 {ok: 是}');
      expect(describeBeBlock(LcBlock(op: 'dbInsert', args: {'collection': 'todos', 'value': beBody(), 'into': 'todo'})), '往 集合 todos 里加一条 整个请求内容，放进 todo');
      expect(describeBeBlock(LcBlock(op: 'dbDelete', args: {'collection': '', 'id': id})), '删掉 集合 （还没选集合） 里 id 是 路径参数 id 的那条');
      expect(describeBeBlock(LcBlock(op: 'forEach', args: {'list': beDbAll('todos'), 'item': 'item'})), '对 集合 todos 的全部 里的每一项（放进 item）依次做…');
      expect(describeBeBlock(LcBlock(op: 'fetch', args: {'url': exText('https://a'), 'method': 'POST', 'data': beBody(), 'into': 's'})), '用 POST 请求 “https://a”，提交 整个请求内容，结果放进 s');
      expect(describeBeBlock(LcBlock(op: 'if', args: {'cond': exBool(true)}, orElse: [newBeBlock('log')])), '如果 是 那么…否则…');
      expect(describeBeBlock(LcBlock(op: '怪积木')), '不认识的积木（怪积木）');
      expect(describeBeExpr({'e': 'wat'}), '不认识的值（wat）');
      expect(describeBeExpr(null), '（空）');
      expect(describeBeExpr({'e': 'pathParam'}), '路径参数 （没填名字）');
      expect(describeBeRoute(BeRoute(id: 'r1', method: 'GET', path: '/todos/:id')), 'GET /todos/:id');
    });

    test('坏数据不崩；换行不进读法；位置的读法', () {
      expect(describeBeExpr(exText('第一行\n第二行')), isNot(contains('\n')));
      expect(describeBeBlock(LcBlock(op: 'setVar', args: {'name': 5, 'value': 'x'})), '把 （还没选变量） 设为 （空）');
      Map<String, dynamic> deep = exNum(1);
      for (var i = 0; i < 200; i++) {
        deep = exNot(deep);
      }
      expect(describeBeExpr(deep), contains('…'));
      final r = BeRoute(
        id: 'r1',
        method: 'GET',
        path: '/',
        body: [
          newBeBlock('log'),
          LcBlock(
            op: 'if',
            args: {'cond': exBool(true)},
            orElse: [
              LcBlock(op: 'fetch', body: [newBeBlock('log')]),
            ],
          ),
        ],
      );
      expect(describeBeBlockPath(r, [lcStep(1), lcStep(0, inElse: true), lcStep(0)]), '第 2 块 › 否则 › 第 1 块 › 成功后 › 第 1 块');
      expect(describeBeBlockPath(r, [lcStep(9), lcStep(0)]), '第 10 块');
      for (final m in kBeMethods) {
        expect(describeBeMethod(m), isNot(m));
      }
    });
  });
}
