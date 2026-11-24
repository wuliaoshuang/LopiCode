// 后端积木的校验：每种问题都能查出来、定位到 接口 + 积木 + 参数；没问题的不误报。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lowcode/logic_model.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
LcBlock get _ok => _b('respondJson', {
  'status': exNum(200),
  'value': beObj({'ok': exBool(true)}),
});

BeDocument _doc({String method = 'GET', String path = '/x/:id', List<LcBlock> body = const []}) {
  final doc = BeDocument(
    variables: [
      LcVariable(name: 's'),
      LcVariable(name: 'n', type: 'number'),
      LcVariable(name: 'flag', type: 'bool'),
    ],
    collections: [BeCollection(name: 'todos')],
  );
  doc.routes.add(BeRoute(id: 'r1', method: method, path: path, body: [...body]));
  return doc;
}

List<String> _codes(List<LcBlock> body, {String path = '/x/:id'}) => [for (final i in validateBackend(_doc(path: path, body: body))) i.code];

void main() {
  test('没问题的接口：一条都不报', () {
    expect(
      _codes([
        _b('setVar', {'name': 's', 'value': bePathParam('id')}),
        _b('dbInsert', {
          'collection': 'todos',
          'value': beObj({'t': beBodyField('t')}),
          'into': 's',
        }),
        _b('if', {'cond': beIsNull(exVar('s'))}, body: [_ok], orElse: [_ok]),
      ]),
      isEmpty,
    );
    expect(validateBackend(BeDocument()), isEmpty);
  });

  test('变量：没选、没声明', () {
    expect(
      _codes([
        _b('setVar', {'name': '', 'value': exNum(1)}),
        _ok,
      ]),
      [LcIssueCode.missingArg],
    );
    expect(
      _codes([
        _b('setVar', {'name': 'nope', 'value': exNum(1)}),
        _ok,
      ]),
      [LcIssueCode.unknownVar],
    );
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': exVar('nope')}),
      ]),
      [LcIssueCode.unknownVar],
    );
    expect(
      _codes([
        _b('dbInsert', {'collection': 'todos', 'value': beObj({}), 'into': 'nope'}),
        _ok,
      ]),
      [LcIssueCode.unknownVar],
    );
    // “放进变量”不填是允许的
    expect(
      _codes([
        _b('dbInsert', {'collection': 'todos', 'value': beObj({})}),
        _ok,
      ]),
      isEmpty,
    );
    expect(
      _codes([
        _b('dbInsert', {'collection': 'todos', 'value': beObj({}), 'into': ''}),
        _ok,
      ]),
      isEmpty,
    );
  });

  test('集合：没选、不存在', () {
    expect(
      _codes([
        _b('dbDelete', {'collection': '', 'id': exNum(1)}),
        _ok,
      ]),
      [LcIssueCode.missingArg],
    );
    expect(
      _codes([
        _b('dbDelete', {'collection': 'nope', 'id': exNum(1)}),
        _ok,
      ]),
      [BeIssueCode.unknownCollection],
    );
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': beDbAll('nope')}),
      ]),
      [BeIssueCode.unknownCollection],
    );
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': beDbFind('todos', '', exNum(1))}),
      ]),
      [LcIssueCode.missingArg],
    );
  });

  test('路径参数：这个接口的地址里没有', () {
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': bePathParam('other')}),
      ]),
      [BeIssueCode.unknownPathParam],
    );
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': bePathParam('id')}),
      ]),
      isEmpty,
    );
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200), 'value': bePathParam('')}),
      ]),
      [LcIssueCode.missingArg],
    );
    final issue = validateBackend(
      _doc(
        body: [
          _b(
            'if',
            {'cond': exBool(true)},
            body: [
              _b('log', {
                'value': exJoin([exText('a'), bePathParam('zz')]),
              }),
            ],
          ),
          _ok,
        ],
      ),
    ).single;
    expect(issue.handlerId, 'r1');
    expect(issue.path, [lcStep(0), lcStep(0)]);
    expect(issue.arg, 'value');
    expect(issue.isError, isTrue);
    expect(issue.message, contains('zz'));
  });

  test('缺参数、不认识的积木和值、运算符不对', () {
    expect(
      _codes([
        _b('respondJson', {'status': exNum(200)}),
      ]),
      [LcIssueCode.missingArg],
    );
    expect(_codes([_b('飞起来', {}), _ok]), [LcIssueCode.unknownOp]);
    expect(
      _codes([
        _b('log', {
          'value': {'e': 'wat'},
        }),
        _ok,
      ]),
      [LcIssueCode.unknownExpr],
    );
    expect(
      _codes([
        _b('log', {
          'value': {'e': 'bin', 'op': '**', 'l': exNum(1), 'r': exNum(2)},
        }),
        _ok,
      ]),
      [LcIssueCode.badArg],
    );
    expect(
      _codes([
        _b('log', {
          'value': {'e': 'bin', 'op': '+', 'l': exNum(1)},
        }),
        _ok,
      ]),
      [LcIssueCode.missingArg],
    );
    expect(
      _codes([
        _b('fetch', {'url': exText('http://a'), 'method': 'DELETE'}),
        _ok,
      ]),
      [LcIssueCode.badArg],
    );
    // 前端的值（控件属性）在后端不认识
    expect(
      _codes([
        _b('log', {
          'value': {'e': 'prop', 'node': 'n1', 'prop': 'text'},
        }),
        _ok,
      ]),
      [LcIssueCode.unknownExpr],
    );
  });

  test('对象的字段：只能是“一个字段”，名字不能空、不能重复', () {
    expect(
      _codes([
        _b('respondJson', {
          'status': exNum(200),
          'value': {
            'e': 'obj',
            'fields': [exNum(1)],
          },
        }),
      ]),
      [BeIssueCode.badPair],
    );
    expect(
      _codes([
        _b('respondJson', {
          'status': exNum(200),
          'value': beObj({'': exNum(1)}),
        }),
      ]),
      [LcIssueCode.missingArg],
    );
    expect(
      _codes([
        _b('respondJson', {
          'status': exNum(200),
          'value': {
            'e': 'obj',
            'fields': [bePair('a', exNum(1)), bePair('a', exNum(2))],
          },
        }),
      ]),
      [BeIssueCode.badPair],
    );
    // 字段单独放在别处
    expect(
      _codes([
        _b('log', {'value': bePair('a', exNum(1))}),
        _ok,
      ]),
      [BeIssueCode.badPair],
    );
  });

  test('状态码：直接填的数字不在 200–599 里', () {
    expect(
      _codes([
        _b('respondJson', {'status': exNum(99), 'value': beObj({})}),
      ]),
      [BeIssueCode.badStatus],
    );
    expect(
      _codes([
        _b('respondText', {'status': exNum(600), 'value': exText('x')}),
      ]),
      [BeIssueCode.badStatus],
    );
    expect(
      _codes([
        _b('respondText', {'status': exNum(200.5), 'value': exText('x')}),
      ]),
      [BeIssueCode.badStatus],
    );
    // 算出来的不查
    expect(
      _codes([
        _b('respondText', {'status': beQuery('code'), 'value': exText('x')}),
      ]),
      isEmpty,
    );
  });

  test('返回之后还有积木：提示，不是错误；分支都返回了也算', () {
    final issues = validateBackend(
      _doc(
        body: [
          _ok,
          _b('log', {'value': exText('x')}),
        ],
      ),
    );
    expect([for (final i in issues) i.code], [BeIssueCode.unreachable]);
    expect(issues.single.isError, isFalse);
    expect(issues.single.path, [lcStep(1)]);
    expect(
      _codes([
        _b('if', {'cond': exBool(true)}, body: [_ok], orElse: [_ok]),
        _b('log', {'value': exText('x')}),
      ]),
      [BeIssueCode.unreachable],
    );
    // 只有一边返回：后面还会执行
    expect(
      _codes([
        _b('if', {'cond': exBool(true)}, body: [_ok]),
        _ok,
      ]),
      isEmpty,
    );
    // 循环里返回：循环后面的还可能执行（一遍都不做的时候）
    expect(
      _codes([
        _b('repeat', {'times': exNum(3)}, body: [_ok]),
        _ok,
      ]),
      isEmpty,
    );
  });

  test('没有返回：空接口、有的走法不返回 → 提示；一个返回都没有（故意 204）不提示', () {
    expect(_codes([]), [BeIssueCode.noRespond]);
    expect(
      _codes([
        _b('if', {'cond': exBool(true)}, body: [_ok]),
      ]),
      [BeIssueCode.noRespond],
    );
    expect(
      _codes([
        _b('dbDelete', {'collection': 'todos', 'id': exNum(1)}),
      ]),
      isEmpty,
    );
    expect(validateBackend(_doc()).single.isError, isFalse);
  });

  test('“加上”用在不是数字的变量上：提示', () {
    final issues = validateBackend(
      _doc(
        body: [
          _b('changeVar', {'name': 's', 'by': exNum(1)}),
          _ok,
        ],
      ),
    );
    expect([for (final i in issues) i.code], [LcIssueCode.changeVarNotNumber]);
    expect(issues.single.isError, isFalse);
    expect(
      _codes([
        _b('changeVar', {'name': 'n', 'by': exNum(1)}),
        _ok,
      ]),
      isEmpty,
    );
  });

  test('接口：方式不认识、路径格式不对', () {
    expect(
      [
        for (final i in validateBackend(_doc(method: 'HEAD', path: '/a', body: [_ok]))) i.code,
      ],
      [BeIssueCode.badMethod],
    );
    for (final bad in ['a', '/a/', '/中文', '/a//b', '']) {
      final issues = validateBackend(_doc(path: bad, body: [_ok]));
      expect([for (final i in issues) i.code], [BeIssueCode.badPath], reason: bad);
      expect(issues.single.handlerId, 'r1');
      expect(issues.single.path, isEmpty);
    }
    // 同一个地址里两个参数重名
    expect(
      [
        for (final i in validateBackend(_doc(path: '/a/:id/b/:id', body: [_ok]))) i.code,
      ],
      [BeIssueCode.badPath],
    );
  });

  test('接口：方式和地址重复是错误；被前面的挡住是提示', () {
    final doc = _doc(path: '/todos/:id', body: [_ok]);
    doc.routes.add(BeRoute(id: 'r2', method: 'GET', path: '/todos/:other', body: [_ok]));
    doc.routes.add(BeRoute(id: 'r3', method: 'GET', path: '/todos/count', body: [_ok]));
    doc.routes.add(BeRoute(id: 'r4', method: 'POST', path: '/todos/:id', body: [_ok]));
    final issues = validateBackend(doc);
    expect([for (final i in issues) '${i.handlerId}:${i.code}:${i.isError}'], ['r2:${BeIssueCode.duplicateRoute}:true', 'r3:${BeIssueCode.shadowedRoute}:false']);
    // 具体的排在前面就没事
    final good = _doc(path: '/todos/count', body: [_ok]);
    good.routes.add(BeRoute(id: 'r2', method: 'GET', path: '/todos/:id', body: [_ok]));
    expect(validateBackend(good), isEmpty);
  });

  test('集合 / 变量声明、端口、语言', () {
    final doc = BeDocument()..addRoute('GET', '/')!.body.add(_ok);
    doc.language = 'cobol';
    final issues = validateBackend(doc, languages: const ['node', 'python']);
    expect([for (final i in issues) i.code], [BeIssueCode.noGenerator]);
    expect(issues.single.handlerId, isNull);
    expect(issues.single.isError, isFalse);
    // 不传语言清单就不查
    expect(validateBackend(doc), isEmpty);
    expect(backendErrors(doc..routes.first.path = 'x'), hasLength(1));
  });

  test('坏数据不崩：参数类型乱七八糟、嵌套很深', () {
    Map<String, dynamic> deep = exNum(1);
    for (var i = 0; i < 300; i++) {
      deep = exNot(deep);
    }
    final doc = _doc(
      body: [
        _b('setVar', {'name': 5, 'value': 'x'}),
        _b('if', {
          'cond': [1, 2],
        }),
        _b('respondJson', {
          'status': {'e': 'num', 'v': 'x'},
          'value': {'e': 'obj', 'fields': 'x'},
        }),
        _b('forEach', {
          'list': {'e': 5},
          'item': null,
        }),
        _b('log', {'value': deep}),
      ],
    );
    expect(() => validateBackend(doc), returnsNormally);
    expect(validateBackend(doc), isNotEmpty);
  });
}
