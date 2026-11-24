// 后端积木“一致性测试”的支撑：一份覆盖面广的样本模型、一串请求和期望的响应、起服务并逐条比对的工具。
//
// 每种语言的生成器都跑同一份（见 test/backend_conformance_test.dart）：响应必须等于这里写死的期望值，
// 所以各语言之间也就逐字节相同。加一种语言不用改这个文件——除非要补新的边界情况（那就所有语言一起受检）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lowcode/logic_model.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
LcBlock _json(int status, Map<String, dynamic> value) => _b('respondJson', {'status': exNum(status), 'value': value});
LcBlock _text(int status, Map<String, dynamic> value) => _b('respondText', {'status': exNum(status), 'value': value});
LcBlock _set(String name, Map<String, dynamic> value) => _b('setVar', {'name': name, 'value': value});
LcBlock _if(Map<String, dynamic> cond, List<LcBlock> then, [List<LcBlock>? orElse]) => _b('if', {'cond': cond}, body: then, orElse: orElse);
Map<String, dynamic> _bin(String op, Map<String, dynamic> l, Map<String, dynamic> r) => exBin(op, l, r);

/// 一个“空”值：从空对象里取一个没有的字段。
Map<String, dynamic> get _nul => beField(beObj({}), 'x');

/// 把值变成“是 / 否”：两次“不是”。
Map<String, dynamic> _truth(Map<String, dynamic> x) => exNot(exNot(x));

/// 样本里故意放的特殊文字：引号、反斜杠、换行、`${`、`</script>`、注释结束符、表情、U+2028、控制字符。
const String kConformanceNasty = '引号"\'反斜杠\\换行\n制表\t\${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完';

/// 样本模型：待办的增删改查 + 把“值的规矩”每一条都走到的接口。
BeDocument conformanceDocument() {
  final a = beQuery('a');
  final b = beQuery('b');
  final id = bePathParam('id');
  final notFound = _if(beIsNull(beDbGet('todos', id)), [
    _json(
      404,
      beObj({
        'error': exJoin([exText('找不到 id 是 '), id, exText(' 的待办')]),
      }),
    ),
  ]);
  final doc = BeDocument(
    name: '一致性样本 "</script>',
    port: 8123,
    variables: [
      LcVariable(name: 'n', type: 'number', initial: 7),
      LcVariable(name: 's', type: 'text', initial: '初始"值\\'),
      LcVariable(name: 'flag', type: 'bool', initial: true),
      LcVariable(name: 'todo'),
      LcVariable(name: 'item'),
      LcVariable(name: 'acc', type: 'number'),
      // 各语言的关键字当变量名：生成的代码不许因此坏掉。
      LcVariable(name: 'class', type: 'number', initial: 1),
      LcVariable(name: 'def', type: 'number', initial: 2),
      LcVariable(name: 'func', type: 'number', initial: 3),
    ],
    collections: [
      BeCollection(name: 'todos'),
      BeCollection(name: 'notes'),
    ],
  );
  void route(String method, String path, List<LcBlock> body) => doc.addRoute(method, path)!.body.addAll(body);

  // —— 待办：增删改查 ——
  route('GET', '/todos', [_json(200, beDbAll('todos'))]);
  route('POST', '/todos', [
    _if(beIsNull(beBodyField('title')), [
      _json(400, beObj({'error': exText('缺少 title')})),
    ]),
    _b('dbInsert', {
      'collection': 'todos',
      'value': beObj({'title': beBodyField('title'), 'done': exBool(false)}),
      'into': 'todo',
    }),
    _json(201, exVar('todo')),
  ]);
  route('GET', '/todos/count', [
    _json(200, beObj({'count': beDbCount('todos')})),
  ]);
  route('GET', '/todos/:id', [
    _set('todo', beDbGet('todos', id)),
    _if(beIsNull(exVar('todo')), [
      _json(
        404,
        beObj({
          'error': exJoin([exText('找不到 id 是 '), id, exText(' 的待办')]),
        }),
      ),
    ]),
    _json(200, exVar('todo')),
  ]);
  route('PATCH', '/todos/:id', [
    notFound.clone(),
    _b('dbUpdate', {'collection': 'todos', 'id': id, 'value': beBody()}),
    _json(200, beDbGet('todos', id)),
  ]);
  // 删除：成功时没有“返回”积木 → 204。
  route('DELETE', '/todos/:id', [
    notFound.clone(),
    _b('dbDelete', {'collection': 'todos', 'id': id}),
  ]);
  route('GET', '/done', [_json(200, beDbFind('todos', 'done', exBool(true)))]);
  route('GET', '/by-title', [_json(200, beDbFind('todos', 'title', beQuery('t')))]);
  // 往集合里加“不是对象”的东西、自带 id 的东西。
  route('POST', '/notes', [
    _b('dbInsert', {'collection': 'notes', 'value': beBody()}),
    _json(200, beDbAll('notes')),
  ]);

  // —— 运算 ——
  route('GET', '/calc', [
    _json(
      200,
      beObj({
        'sum': _bin('+', a, b),
        'diff': _bin('-', a, b),
        'prod': _bin('*', a, b),
        'quot': _bin('/', a, b),
        'rem': _bin('%', a, b),
        'lt': _bin('<', a, b),
        'le': _bin('<=', a, b),
        'gt': _bin('>', a, b),
        'ge': _bin('>=', a, b),
        'eq': _bin('==', a, b),
        'ne': _bin('!=', a, b),
        'and': _bin('and', a, b),
        'or': _bin('or', a, b),
        'notA': exNot(a),
      }),
    ),
  ]);
  route('GET', '/numbers', [
    _json(
      200,
      beObj({
        'third': _bin('/', exNum(1), exNum(3)),
        'pointThree': _bin('+', exNum(0.1), exNum(0.2)),
        'whole': _bin('/', exNum(6), exNum(2)),
        'half': _bin('/', exNum(1), exNum(2)),
        'negRem': _bin('%', exNum(-7), exNum(3)),
        'fracRem': _bin('%', exNum(5.5), exNum(2)),
        'divZero': _bin('/', exNum(5), exNum(0)),
        'remZero': _bin('%', exNum(5), exNum(0)),
        'negZero': _bin('*', exNum(0), exNum(-1)),
        'overflow': _bin('*', exNum(1e308), exNum(10)),
        'big': exNum(1e21),
        'e15': exNum(1e15),
        'justUnder': exNum(999999999999999),
        'nines': exNum(999999999999999.9),
        'small': exNum(2.5e-10),
        'tiny': exNum(0.00000012),
        'tinier': exNum(0.000000012),
        'tie': exNum(12345678901.25),
        'negTie': exNum(-12345678901.25),
        'frac': exNum(123456.789),
        'neg': exNum(-42),
        'negFrac': exNum(-0.5),
        'long': exNum(1234567890.123456789),
        'bigInt': exNum(123456789012345678),
      }),
    ),
  ]);
  route('GET', '/equal', [
    _json(
      200,
      beObj({
        'numText': _bin('==', exNum(5), exText('5')),
        'numTextDot': _bin('==', exNum(5), exText('5.0')),
        'nullEmpty': _bin('==', _nul, exText('')),
        'nullNull': _bin('==', _nul, _nul),
        'nullZero': _bin('==', _nul, exNum(0)),
        'zeroEmpty': _bin('==', exNum(0), exText('')),
        'boolText': _bin('==', exBool(true), exText('true')),
        'oneTrue': _bin('==', exNum(1), exBool(true)),
        'objOrder': _bin('==', beObj({'a': exNum(1), 'b': exNum(2)}), beObj({'b': exNum(2), 'a': exNum(1)})),
        'objDiff': _bin('==', beObj({'a': exNum(1)}), beObj({'a': exNum(2)})),
        'objText': _bin('==', beObj({'a': exNum(1)}), exText('{"a":1}')),
        'listSame': _bin('==', beDbAll('todos'), beDbAll('todos')),
        'floatSum': _bin('==', _bin('+', exNum(0.1), exNum(0.2)), exNum(0.3)),
        'neText': _bin('!=', exText('a'), exText('b')),
      }),
    ),
  ]);
  route('GET', '/truthy', [
    _json(
      200,
      beObj({
        'null': _truth(_nul),
        'false': _truth(exBool(false)),
        'zero': _truth(exNum(0)),
        'empty': _truth(exText('')),
        'textZero': _truth(exText('0')),
        'space': _truth(exText(' ')),
        'emptyObj': _truth(beObj({})),
        'emptyList': _truth(beDbAll('notes')),
        'one': _truth(exNum(1)),
        'true': _truth(exBool(true)),
      }),
    ),
  ]);
  route('GET', '/len', [
    _json(
      200,
      beObj({
        'text': beLen(exText('你好😀')),
        'list': beLen(beDbAll('todos')),
        'obj': beLen(beObj({'a': exNum(1), 'b': exNum(2)})),
        'num': beLen(exNum(12345)),
        'null': beLen(_nul),
      }),
    ),
  ]);

  // —— 文字 ——
  route('GET', '/text/:what', [
    _text(
      200,
      exJoin([
        exText('你好，'),
        bePathParam('what'),
        exText('！'),
        exNum(3),
        exBool(true),
        _nul,
        exNum(1.50),
        beObj({'a': exNum(1)}),
        beQuery('q'),
      ]),
    ),
  ]);
  route('GET', '/special', [
    _json(
      200,
      beObj({
        'value': exText(kConformanceNasty),
        kConformanceNasty: exNum(1),
        // 键的顺序：按 Unicode 码点（表情 U+1F600 排在全角 Ａ U+FF21 后面；UTF-16 的顺序正好反过来）。
        '\uFF21': exNum(2),
        '😀': exNum(3),
        'a': exNum(4),
        'B': exNum(5),
        '10': exNum(6),
        '9': exNum(7),
        '__proto__': exNum(8),
        'constructor': exNum(9),
      }),
    ),
  ]);
  route('GET', '/special-text', [_text(200, exText(kConformanceNasty))]);

  // —— 流程 ——
  route('GET', '/loop', [
    _set('n', exNum(0)),
    _b(
      'repeat',
      {'times': exNum(5)},
      body: [
        _b('changeVar', {'name': 'n', 'by': exNum(2)}),
      ],
    ),
    _b(
      'repeat',
      {'times': beQuery('times')},
      body: [
        _b('changeVar', {'name': 'n', 'by': exNum(1)}),
      ],
    ),
    _json(200, beObj({'n': exVar('n')})),
  ]);
  route('GET', '/each', [
    _set('s', exText('')),
    _b(
      'forEach',
      {'list': beDbAll('todos'), 'item': 'item'},
      body: [
        _set('s', exJoin([exVar('s'), beField(exVar('item'), 'title'), exText(';')])),
        _b('changeVar', {'name': 'acc', 'by': beField(exVar('item'), 'id')}),
        // 循环中途往集合里加东西，不影响这一轮。
        _if(_bin('==', beQuery('grow'), exText('1')), [
          _b('dbInsert', {
            'collection': 'notes',
            'value': beObj({'from': beField(exVar('item'), 'id')}),
          }),
        ]),
      ],
    ),
    // 不是列表的东西：一遍也不做。
    _b(
      'forEach',
      {'list': exText('abc'), 'item': 'item'},
      body: [
        _b('changeVar', {'name': 'acc', 'by': exNum(1000)}),
      ],
    ),
    _json(200, beObj({'titles': exVar('s'), 'sum': exVar('acc'), 'count': beLen(beDbAll('todos'))})),
  ]);
  route('GET', '/early', [
    _text(200, exText('先返回')),
    _b('dbInsert', {
      'collection': 'notes',
      'value': beObj({'bad': exText('返回之后不该执行')}),
    }),
    _text(500, exText('不该到这里')),
  ]);
  route('GET', '/early-loop', [
    _set('n', exNum(0)),
    _b(
      'repeat',
      {'times': exNum(10)},
      body: [
        _b('changeVar', {'name': 'n', 'by': exNum(1)}),
        _if(_bin('==', exVar('n'), exNum(3)), [
          _json(200, beObj({'stoppedAt': exVar('n')})),
        ]),
      ],
    ),
    _text(500, exText('不该到这里')),
  ]);
  route('GET', '/nothing', [
    _b('log', {
      'value': exJoin([
        exText('日志：'),
        exNum(1.5),
        exText(' '),
        beObj({'k': exText('v')}),
      ]),
    }),
  ]);
  route('GET', '/branch', [
    _if(
      _bin('>', beQuery('x'), exNum(10)),
      [_text(200, exText('大'))],
      [
        _if(beQuery('x'), [_text(200, exText('小'))], [_text(200, exText('没有'))]),
      ],
    ),
  ]);

  // —— 变量 ——
  route('GET', '/vars', [
    _json(200, beObj({'n': exVar('n'), 's': exVar('s'), 'flag': exVar('flag'), 'todo': exVar('todo'), 'acc': exVar('acc')})),
  ]);
  // 每次请求变量都从初始值开始：调几次都是 8。
  route('GET', '/bump', [
    _b('changeVar', {'name': 'n', 'by': exNum(1)}),
    // “加上”用在文字变量上：先当数字（转不了当 0）。
    _b('changeVar', {'name': 's', 'by': exNum(2)}),
    _set('class', _bin('+', exVar('class'), _bin('+', exVar('def'), exVar('func')))),
    _json(200, beObj({'n': exVar('n'), 's': exVar('s'), 'class': exVar('class')})),
  ]);

  // —— 请求 ——
  route('POST', '/echo', [
    _json(
      200,
      beObj({
        'body': beBody(),
        'name': beBodyField('name'),
        'nameLen': beLen(beBodyField('name')),
        'q': beQuery('q'),
        'missing': beQuery('nope'),
        'header': beHeader('X-Test'),
        'noHeader': beHeader('X-Nope'),
        'noBody': beIsNull(beBody()),
      }),
    ),
  ]);
  route('GET', '/status', [
    _b('respondJson', {
      'status': beQuery('code'),
      'value': beObj({'ok': exBool(true)}),
    }),
  ]);
  route('GET', '/', [_text(200, exText('根'))]);
  route('PUT', '/a/:x/b/:y', [
    _json(200, beObj({'x': bePathParam('x'), 'y': bePathParam('y')})),
  ]);

  // —— 没填好的地方：照样能生成、能跑，当成空的 ——
  route('GET', '/holes', [
    _b('没有这种积木', {'x': 1}),
    _set('没声明', exNum(1)),
    _b('dbInsert', {'collection': 'nope', 'value': beBody()}),
    _b('forEach', {'list': beDbAll('todos'), 'item': 'nope'}, body: [_text(500, exText('不该到这里'))]),
    _json(
      200,
      beObj({
        'unknown': {'e': 'wat'},
        'undeclared': exVar('nope'),
        'badParam': bePathParam('nope'),
        'badCollection': beDbAll('nope'),
        'missing': {'e': 'bin', 'op': '+'},
        'badOp': {'e': 'bin', 'op': '**', 'l': exNum(1), 'r': exNum(2)},
        'ok': exNum(1),
      }),
    ),
  ]);

  // —— 请求别的网址（请求自己）——
  route('GET', '/relay', [
    _b(
      'fetch',
      {
        'url': exJoin([exText('http://'), beHeader('Host'), exText('/text/relay?q=%E5%A5%BD')]),
        'method': 'GET',
        'into': 's',
      },
      body: [
        _text(200, exJoin([exText('拿到：'), exVar('s')])),
      ],
      orElse: [_text(502, exText('失败'))],
    ),
  ]);
  route('GET', '/relay-post', [
    _b(
      'fetch',
      {
        'url': exJoin([exText('http://'), beHeader('Host'), exText('/echo')]),
        'method': 'POST',
        'data': beObj({'name': exText('转发')}),
        'into': 's',
      },
      body: [_text(200, exVar('s'))],
      orElse: [_text(502, exText('失败'))],
    ),
  ]);
  route('GET', '/relay-fail', [
    _b(
      'fetch',
      {'url': beQuery('url'), 'method': 'GET', 'into': 's'},
      body: [_text(200, exText('不该成功'))],
      orElse: [
        _text(502, exJoin([exText('失败，s 还是：'), exVar('s')])),
      ],
    ),
  ]);
  // 请求任意网址，成功就把拿到的文字原样返回。
  route('GET', '/relay-get', [
    _b('fetch', {'url': beQuery('url'), 'method': 'GET', 'into': 's'}, body: [_text(200, exVar('s'))], orElse: [_text(502, exText('失败'))]),
  ]);
  route('GET', '/now', [_text(200, beNow())]);
  return doc;
}

/// 一条请求和期望的响应。
class BeCase {
  const BeCase(this.method, this.target, this.status, this.expect, {this.body, this.bodyBytes, this.headers = const {}, this.type = kJson, this.pattern});

  final String method;

  /// 请求行里的路径（原样发出去，不做任何转义）。
  final String target;
  final int status;

  /// 期望的响应内容（UTF-8）；[pattern] 不为 null 时不看它。
  final String expect;
  final String? body;
  final List<int>? bodyBytes;
  final Map<String, String> headers;

  /// 期望的 Content-Type；null＝不该有（204）。
  final String? type;

  /// 内容不固定时（现在的时间）用正则表达式核对。
  final String? pattern;

  @override
  String toString() => '$method $target';
}

const String kJson = 'application/json; charset=utf-8';
const String kText = 'text/plain; charset=utf-8';

BeCase _t(String method, String target, int status, String expect, {String? body, Map<String, String> headers = const {}}) =>
    BeCase(method, target, status, expect, body: body, headers: headers, type: kText);
BeCase _none(String method, String target, {String? body}) => BeCase(method, target, 204, '', body: body, type: null);

/// [kConformanceNasty] 写成 JSON 字符串的样子（两种语言都必须写成这样）。
const String _nastyJson =
    r'''"引号\"'反斜杠\\换行\n制表\t${x}`</script><!--*/ #{y} %s 😀'''
    '\u2028'
    r'''\u0001完"''';

/// 套了 `depth` 层的列表：`[[[]]]`。
String _nested(int depth) => '${'[' * depth}${']' * depth}';

/// 套了 `depth` 层的对象（列表和对象交替）：`{"a":[{"a":[1]}]}`。
String _nestedObjects(int depth) => '${[for (var i = 0; i < depth; i++) i.isEven ? '{"a":' : '['].join()}1${[for (var i = depth - 1; i >= 0; i--) i.isEven ? '}' : ']'].join()}';

/// 请求脚本：按顺序发（后面的依赖前面留下的数据）。
final List<BeCase> conformanceCases = [
  // —— 待办：增删改查 ——
  const BeCase('GET', '/todos', 200, '[]'),
  const BeCase('GET', '/todos/count', 200, '{"count":0}'),
  const BeCase('POST', '/todos', 201, '{"done":false,"id":1,"title":"买菜"}', body: '{"title":"买菜"}'),
  const BeCase('POST', '/todos', 201, '{"done":false,"id":2,"title":"写 \\"代码\\"\\n第二行 😀"}', body: '{"title":"写 \\"代码\\"\\n第二行 \\ud83d\\ude00","id":99,"done":true}'),
  const BeCase('POST', '/todos', 400, '{"error":"缺少 title"}', body: '{"name":"没有标题"}'),
  const BeCase('POST', '/todos', 400, '{"error":"缺少 title"}'),
  const BeCase('POST', '/todos', 400, '{"error":"缺少 title"}', body: '这不是 JSON'),
  const BeCase('POST', '/todos', 400, '{"error":"缺少 title"}', body: '{"title":null}'),
  const BeCase('POST', '/todos', 201, '{"done":false,"id":3,"title":3}', body: '{"title":3.0}'),
  const BeCase('GET', '/todos', 200, '[{"done":false,"id":1,"title":"买菜"},{"done":false,"id":2,"title":"写 \\"代码\\"\\n第二行 😀"},{"done":false,"id":3,"title":3}]'),
  const BeCase('GET', '/todos/', 200, '[{"done":false,"id":1,"title":"买菜"},{"done":false,"id":2,"title":"写 \\"代码\\"\\n第二行 😀"},{"done":false,"id":3,"title":3}]'),
  const BeCase('GET', '/todos/count', 200, '{"count":3}'),
  const BeCase('GET', '/todos/1', 200, '{"done":false,"id":1,"title":"买菜"}'),
  const BeCase('GET', '/todos/1.0', 200, '{"done":false,"id":1,"title":"买菜"}'),
  const BeCase('GET', '/todos/%201%20', 200, '{"done":false,"id":1,"title":"买菜"}'),
  const BeCase('GET', '/todos/99', 404, '{"error":"找不到 id 是 99 的待办"}'),
  const BeCase('GET', '/todos/abc', 404, '{"error":"找不到 id 是 abc 的待办"}'),
  const BeCase('GET', '/todos/%E4%B8%AD%E6%96%87', 404, '{"error":"找不到 id 是 中文 的待办"}'),
  const BeCase('PATCH', '/todos/1', 200, '{"done":true,"extra":[1,2,{"k":null}],"id":1,"title":"买菜"}', body: '{"done":true,"id":500,"extra":[1,2,{"k":null}]}'),
  const BeCase('PATCH', '/todos/1', 200, '{"done":true,"extra":[1,2,{"k":null}],"id":1,"title":"买菜"}', body: '[1,2,3]'),
  const BeCase('PATCH', '/todos/1', 200, '{"done":true,"extra":[1,2,{"k":null}],"id":1,"title":"买菜"}'),
  const BeCase('PATCH', '/todos/77', 404, '{"error":"找不到 id 是 77 的待办"}', body: '{"done":true}'),
  const BeCase('GET', '/done', 200, '[{"done":true,"extra":[1,2,{"k":null}],"id":1,"title":"买菜"}]'),
  const BeCase('GET', '/by-title?t=3', 200, '[{"done":false,"id":3,"title":3}]'),
  const BeCase('GET', '/by-title?t=%E4%B9%B0%E8%8F%9C', 200, '[{"done":true,"extra":[1,2,{"k":null}],"id":1,"title":"买菜"}]'),
  const BeCase('GET', '/by-title', 200, '[]'),
  const BeCase('GET', '/each', 200, '{"count":3,"sum":6,"titles":"买菜;写 \\"代码\\"\\n第二行 😀;3;"}'),
  _none('DELETE', '/todos/2'),
  const BeCase('DELETE', '/todos/2', 404, '{"error":"找不到 id 是 2 的待办"}'),
  const BeCase('GET', '/todos/2', 404, '{"error":"找不到 id 是 2 的待办"}'),
  // 删掉的号不回收
  const BeCase('POST', '/todos', 201, '{"done":false,"id":4,"title":""}', body: '{"title":""}'),
  const BeCase('GET', '/todos/count', 200, '{"count":3}'),
  const BeCase('GET', '/len', 200, '{"list":3,"null":0,"num":0,"obj":2,"text":3}'),
  // 往集合里加不是对象的东西 / 自带 id 的东西
  const BeCase('POST', '/notes', 200, '[{"id":1}]', body: '[1,2]'),
  const BeCase('POST', '/notes', 200, '[{"id":1},{"id":2}]'),
  const BeCase('POST', '/notes', 200, '[{"id":1},{"id":2},{"a":{"b":[]},"id":3}]', body: ' {"id":"x","a":{"b":[]}} '),
  // 循环中途往集合里加东西
  const BeCase('GET', '/each?grow=1', 200, '{"count":3,"sum":8,"titles":"买菜;3;;"}'),
  const BeCase('POST', '/notes', 200, '[{"id":1},{"id":2},{"a":{"b":[]},"id":3},{"from":1,"id":4},{"from":3,"id":5},{"from":4,"id":6},{"id":7}]', body: '7'),

  // —— 运算 ——
  const BeCase('GET', '/calc?a=7&b=2', 200, '{"and":true,"diff":5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":14,"quot":3.5,"rem":1,"sum":9}'),
  const BeCase(
    'GET',
    '/calc?a=%207%20&b=2.50',
    200,
    '{"and":true,"diff":4.5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":17.5,"quot":2.8,"rem":2,"sum":9.5}',
  ),
  const BeCase('GET', '/calc?a=abc&b=0', 200, '{"and":true,"diff":0,"eq":false,"ge":true,"gt":false,"le":true,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":0}'),
  const BeCase('GET', '/calc?a=5', 200, '{"and":false,"diff":5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":5}'),
  const BeCase('GET', '/calc', 200, '{"and":false,"diff":0,"eq":true,"ge":true,"gt":false,"le":true,"lt":false,"ne":false,"notA":true,"or":false,"prod":0,"quot":0,"rem":0,"sum":0}'),
  const BeCase(
    'GET',
    '/calc?a=1e3&b=.5',
    200,
    '{"and":true,"diff":999.5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":500,"quot":2000,"rem":0,"sum":1000.5}',
  ),
  // 不算数字的写法：十六进制、全角数字、Infinity、带下划线 → 0
  const BeCase('GET', '/calc?a=0x10&b=%EF%BC%95', 200, '{"and":true,"diff":0,"eq":false,"ge":true,"gt":false,"le":true,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":0}'),
  const BeCase('GET', '/calc?a=Infinity&b=1_000', 200, '{"and":true,"diff":0,"eq":false,"ge":true,"gt":false,"le":true,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":0}'),
  const BeCase('GET', '/calc?a=1e999&b=-1e999', 200, '{"and":true,"diff":0,"eq":false,"ge":true,"gt":false,"le":true,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":0}'),
  const BeCase(
    'GET',
    '/calc?a=-7&b=3',
    200,
    '{"and":true,"diff":-10,"eq":false,"ge":false,"gt":false,"le":true,"lt":true,"ne":true,"notA":false,"or":true,"prod":-21,"quot":-2.33333333333,"rem":-1,"sum":-4}',
  ),
  const BeCase('GET', '/calc?a=5&b=5.0', 200, '{"and":true,"diff":0,"eq":false,"ge":true,"gt":false,"le":true,"lt":false,"ne":true,"notA":false,"or":true,"prod":25,"quot":1,"rem":0,"sum":10}'),
  // 网址参数：+ 是空格、重名取第一个、没有等号是空文字
  const BeCase('GET', '/calc?a=+3+&a=100&b', 200, '{"and":false,"diff":3,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":0,"rem":0,"sum":3}'),
  const BeCase(
    'GET',
    '/numbers',
    200,
    '{"big":1e21,"bigInt":1.23456789012e17,"divZero":0,"e15":1e15,"frac":123456.789,"fracRem":1.5,"half":0.5,"justUnder":999999999999999,"long":1234567890.12,'
        '"neg":-42,"negFrac":-0.5,"negRem":-1,"negTie":-12345678901.3,"negZero":0,"nines":1e15,"overflow":0,"pointThree":0.3,"remZero":0,"small":2.5e-10,'
        '"third":0.333333333333,"tie":12345678901.3,"tinier":1.2e-8,"tiny":0.00000012,"whole":3}',
  ),
  const BeCase(
    'GET',
    '/equal',
    200,
    '{"boolText":true,"floatSum":false,"listSame":true,"neText":true,"nullEmpty":true,"nullNull":true,"nullZero":false,"numText":true,"numTextDot":false,'
        '"objDiff":false,"objOrder":true,"objText":true,"oneTrue":false,"zeroEmpty":false}',
  ),
  const BeCase('GET', '/truthy', 200, '{"empty":false,"emptyList":true,"emptyObj":true,"false":false,"null":false,"one":true,"space":true,"textZero":true,"true":true,"zero":false}'),

  // —— 文字 ——
  _t('GET', '/text/%E4%B8%96%E7%95%8C', 200, '你好，世界！3true1.5{"a":1}'),
  _t('GET', '/text/a%2Fb?q=x%26y%3Dz', 200, '你好，a/b！3true1.5{"a":1}x&y=z'),
  // 百分号写法不对 / 解出来不是合法 UTF-8：原样
  _t('GET', '/text/%zz?q=%', 200, '你好，%zz！3true1.5{"a":1}%'),
  _t('GET', '/text/%FF%FE?q=%C3', 200, '你好，%FF%FE！3true1.5{"a":1}%C3'),
  _t('GET', '/text/a+b?q=a+b%2B', 200, '你好，a+b！3true1.5{"a":1}a b+'),
  const BeCase('GET', '/special', 200, '{"10":6,"9":7,"B":5,"__proto__":8,"a":4,"constructor":9,"value":$_nastyJson,$_nastyJson:1,"\uFF21":2,"😀":3}'),
  _t('GET', '/special-text', 200, kConformanceNasty),

  // —— 流程 ——
  const BeCase('GET', '/loop?times=3', 200, '{"n":13}'),
  const BeCase('GET', '/loop?times=2.9', 200, '{"n":12}'),
  const BeCase('GET', '/loop?times=-5', 200, '{"n":10}'),
  const BeCase('GET', '/loop?times=abc', 200, '{"n":10}'),
  const BeCase('GET', '/loop', 200, '{"n":10}'),
  const BeCase('GET', '/loop?times=99999999', 200, '{"n":10010}'),
  _t('GET', '/early', 200, '先返回'),
  const BeCase('GET', '/early-loop', 200, '{"stoppedAt":3}'),
  _none('GET', '/nothing'),
  _t('GET', '/branch?x=11', 200, '大'),
  _t('GET', '/branch?x=10', 200, '小'),
  _t('GET', '/branch?x=0', 200, '小'),
  _t('GET', '/branch?x=', 200, '没有'),
  _t('GET', '/branch', 200, '没有'),

  // —— 变量：每次请求都从初始值开始 ——
  const BeCase('GET', '/vars', 200, '{"acc":0,"flag":true,"n":7,"s":"初始\\"值\\\\","todo":""}'),
  const BeCase('GET', '/bump', 200, '{"class":6,"n":8,"s":2}'),
  const BeCase('GET', '/bump', 200, '{"class":6,"n":8,"s":2}'),

  // —— 请求 ——
  const BeCase(
    'POST',
    '/echo?q=%E4%BD%A0',
    200,
    '{"body":{"name":"小明"},"header":"abc 1","missing":null,"name":"小明","nameLen":2,"noBody":false,"noHeader":null,"q":"你"}',
    body: '{"name":"小明"}',
    headers: {'x-TEST': 'abc 1'},
  ),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}'),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: '{"name": "半截'),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: '{"name": NaN}'),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: "{'name': 1}"),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: '   '),
  // 带 BOM 的不算合法 JSON
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', bodyBytes: [0xEF, 0xBB, 0xBF, 0x7B, 0x7D]),
  // 不是合法 UTF-8
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', bodyBytes: [0x22, 0xFF, 0x22]),
  // 请求内容不是对象：字段读出来是空
  const BeCase('POST', '/echo', 200, '{"body":"name","header":null,"missing":null,"name":null,"nameLen":0,"noBody":false,"noHeader":null,"q":null}', body: '"name"'),
  const BeCase('POST', '/echo', 200, '{"body":false,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":false,"noHeader":null,"q":null}', body: 'false'),
  const BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: 'null'),
  // 数字的各种写法、超出范围的数、键的顺序、重复的键、会捣乱的键、不成对的代理项
  const BeCase(
    'POST',
    '/echo',
    200,
    '{"body":{"__proto__":{"x":1},"a":[1,-0.5,100,0,0,1.23456789012e19,1.5e300,0,0.1,0.0000001,1.23456789012],"constructor":"c","dup":2,"name":["x","y"],"toString":null,"z":"\uFFFD|😀|é|\\u0000|/"},'
        '"header":null,"missing":null,"name":["x","y"],"nameLen":2,"noBody":false,"noHeader":null,"q":null}',
    body:
        '{"z":"\\ud800|\\ud83d\\ude00|\\u00e9|\\u0000|\\/","name":["x","y"],"dup":1,"dup":2,"constructor":"c","toString":null,"__proto__":{"x":1},'
        '"a":[1.0,-0.50,1e2,-0,1e400,12345678901234567890,1.5E+300,-1E400,0.1,0.0000001,1.2345678901234567]}',
  ),
  const BeCase('POST', '/echo', 200, '{"body":{"name":"你好😀"},"header":null,"missing":null,"name":"你好😀","nameLen":3,"noBody":false,"noHeader":null,"q":null}', body: '{"name":"你好😀"}'),
  // 列表 / 对象最多套 64 层：正好 64 层照常，65 层整份当成空
  BeCase('POST', '/echo', 200, '{"body":${_nested(64)},"header":null,"missing":null,"name":null,"nameLen":0,"noBody":false,"noHeader":null,"q":null}', body: _nested(64)),
  BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: _nested(65)),
  BeCase('POST', '/echo', 200, '{"body":${_nestedObjects(64)},"header":null,"missing":null,"name":null,"nameLen":0,"noBody":false,"noHeader":null,"q":null}', body: _nestedObjects(64)),
  BeCase('POST', '/echo', 200, '{"body":null,"header":null,"missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', body: _nestedObjects(65)),
  const BeCase('GET', '/status?code=201', 201, '{"ok":true}'),
  const BeCase('GET', '/status?code=404.9', 404, '{"ok":true}'),
  const BeCase('GET', '/status?code=999', 200, '{"ok":true}'),
  const BeCase('GET', '/status?code=100', 200, '{"ok":true}'),
  const BeCase('GET', '/status?code=abc', 200, '{"ok":true}'),
  const BeCase('GET', '/status', 200, '{"ok":true}'),
  const BeCase('GET', '/status?code=503', 503, '{"ok":true}'),
  _none('GET', '/status?code=204'),
  _t('GET', '/', 200, '根'),
  _t('GET', '', 200, '根'),
  _t('GET', '/?x=1', 200, '根'),
  const BeCase('PUT', '/a/1/b/%E4%BA%8C', 200, '{"x":"1","y":"二"}'),
  const BeCase('PUT', '//a/1//b/2/', 200, '{"x":"1","y":"2"}'),

  // —— 没有这个接口 / 方式不对 / 预检 ——
  const BeCase('GET', '/nope', 404, '{"error":"没有这个接口"}'),
  const BeCase('GET', '/todos/1/2', 404, '{"error":"没有这个接口"}'),
  const BeCase('GET', '/a/1/b', 404, '{"error":"没有这个接口"}'),
  const BeCase('PUT', '/todos', 405, '{"error":"这个地址不支持这种请求方式"}'),
  const BeCase('POST', '/todos/1', 405, '{"error":"这个地址不支持这种请求方式"}', body: '{}'),
  const BeCase('DELETE', '/echo', 405, '{"error":"这个地址不支持这种请求方式"}'),
  _none('OPTIONS', '/todos'),
  _none('OPTIONS', '/nope'),

  // —— 没填好的地方当成空的 ——
  const BeCase('GET', '/holes', 200, '{"badCollection":null,"badOp":null,"badParam":null,"missing":0,"ok":1,"undeclared":null,"unknown":null}'),

  // —— 请求别的网址 ——
  _t('GET', '/relay', 200, '拿到：你好，relay！3true1.5{"a":1}好'),
  _t('GET', '/relay-post', 200, '{"body":{"name":"转发"},"header":null,"missing":null,"name":"转发","nameLen":2,"noBody":false,"noHeader":null,"q":null}'),
  _t('GET', '/relay-fail?url=http://127.0.0.1:1/', 502, '失败，s 还是：初始"值\\'),
  _t('GET', '/relay-fail?url=file:///etc/hostname', 502, '失败，s 还是：初始"值\\'),
  _t('GET', '/relay-fail?url=not-a-url', 502, '失败，s 还是：初始"值\\'),
  _t('GET', '/relay-fail', 502, '失败，s 还是：初始"值\\'),
  // 对方回 404 也算失败（请求自己一个不存在的地址）——用 /relay-fail 的 url 参数指回自己，见 runConformance 里的 {self}。
  _t('GET', '/relay-fail?url={self}/nope', 502, '失败，s 还是：初始"值\\'),
  // 网址里的空格、中文、写法不对的百分号：发出去之前自动做百分号转义（对方收到 a b中 和 %zz）
  _t('GET', '/relay-get?url={self}/text/a%20b%E4%B8%AD?q=%25zz%2520', 200, '你好，a b中！3true1.5{"a":1}%zz '),
  _t('GET', '/relay-get?url={self}/text/x%23frag', 200, '你好，x！3true1.5{"a":1}'),
  _t('GET', '/relay-get?url=HTTP://127.0.0.1:{port}/text/%E5%A4%A7%E5%86%99?q=%22%3C%3E%5C%5E%60%7B%7C%7D', 200, '你好，大写！3true1.5{"a":1}"<>\\^`{|}'),
  _t('GET', '/relay-get?url=%20{self}/', 502, '失败'),
  _t('GET', '/relay-get?url={self}/text/a%5Bb%5D?q=%2540', 200, '你好，a[b]！3true1.5{"a":1}@'),
  // 网址里带用户名密码的不请求
  _t('GET', '/relay-get?url=http://user:pw@127.0.0.1:{port}/', 502, '失败'),
  _t('GET', '/relay-get?url=http://user@127.0.0.1:{port}/', 502, '失败'),
  // 请求头的值：两头的空格去掉，中间的留着
  const BeCase('POST', '/echo', 200, '{"body":null,"header":"a  b","missing":null,"name":null,"nameLen":0,"noBody":true,"noHeader":null,"q":null}', headers: {'X-Test': '  a  b  '}),
  const BeCase('GET', '/now', 200, '', type: kText, pattern: r'^20[0-9]{2}-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-6][0-9]Z$'),

  // “返回”之后的积木没有执行（/early 里那条没有加进 notes）
  const BeCase('POST', '/notes', 200, '[{"id":1},{"id":2},{"a":{"b":[]},"id":3},{"from":1,"id":4},{"from":3,"id":5},{"from":4,"id":6},{"id":7},{"id":8}]'),
];

/// 样本跑完以后，服务的标准输出里（除了“已启动”那行）应该正好是这些（“写到日志”积木写的）。
const List<String> conformanceLogLines = ['日志：1.5 {"k":"v"}'];

/// 一条响应。
typedef BeResponse = ({int status, String? type, List<int> body});

/// 发一条原始的 HTTP 请求（自己拼请求行：`HttpClient` 会把路径重新转义，测不了“写法不对的百分号”）。只连 127.0.0.1。
Future<BeResponse> sendRaw(int port, String method, String target, {List<int>? body, Map<String, String> headers = const {}}) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 10));
  try {
    final head = StringBuffer('$method ${target.isEmpty ? '/' : target} HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n');
    for (final h in headers.entries) {
      head.write('${h.key}: ${h.value}\r\n');
    }
    if (body != null) head.write('Content-Length: ${body.length}\r\n');
    head.write('\r\n');
    socket.add(utf8.encode(head.toString()));
    if (body != null) socket.add(body);
    await socket.flush();
    final bytes = <int>[];
    await socket.forEach(bytes.addAll).timeout(const Duration(seconds: 30));
    var split = -1;
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        split = i;
        break;
      }
    }
    if (split < 0) throw StateError('响应不完整：${latin1.decode(bytes)}');
    final lines = latin1.decode(bytes.sublist(0, split)).split('\r\n');
    final status = int.parse(lines.first.split(' ')[1]);
    String? type;
    int? length;
    for (final line in lines.skip(1)) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      final name = line.substring(0, i).trim().toLowerCase();
      final value = line.substring(i + 1).trim();
      if (name == 'content-type') type = value;
      if (name == 'content-length') length = int.tryParse(value);
      if (name == 'transfer-encoding') throw StateError('响应不该分块传输：$line');
    }
    final rest = bytes.sublist(split + 4);
    if (length != null && length != rest.length) throw StateError('Content-Length 是 $length，实际收到 ${rest.length} 字节');
    return (status: status, type: type, body: rest);
  } finally {
    socket.destroy();
  }
}

/// 找得到这个命令吗（`node`、`python3`…）。找不到的语言跳过一致性测试。
Future<bool> hasCommand(String exe, [List<String> versionArgs = const ['--version']]) async {
  try {
    final r = await Process.run(exe, versionArgs).timeout(const Duration(seconds: 20));
    return r.exitCode == 0;
  } on Exception {
    return false;
  }
}

/// 一种语言在本机的工具：命令名 → 实际要执行的路径，外加跑它们时要带的环境变量。
class BeToolchain {
  const BeToolchain(this.executables, [this.environment = const {}]);

  final Map<String, String> executables;
  final Map<String, String> environment;

  /// 把命令的第一项换成实际路径；`./server` 这种相对路径换成 `dir` 里的绝对路径。
  List<String> resolve(List<String> command, Directory dir) {
    final exe = command.first;
    final resolved = executables[exe] ?? (exe.startsWith('./') ? '${dir.path}/${exe.substring(2)}' : exe);
    return [resolved, ...command.sublist(1)];
  }
}

/// Go 命令在哪：先看 PATH，再看环境变量 `LOPI_GO`，再看这台机器上装的位置。都没有返回 null。
Future<String?> findGo() async {
  final home = Platform.environment['HOME'] ?? '';
  for (final exe in ['go', ?Platform.environment['LOPI_GO'], if (home.isNotEmpty) '$home/workspace/tools/gosdk/go/bin/go']) {
    if (await hasCommand(exe, const ['version'])) return exe;
  }
  return null;
}

/// 跑 Go 命令要带的环境变量：缓存放在工程的 `.tmp/` 下（`/tmp` 太小），**不许联网**（只用标准库，本来也不用下载）。
Map<String, String> goEnvironment() {
  final base = '${Directory.current.path}/.tmp';
  return {'GOCACHE': '$base/gocache', 'GOPATH': '$base/gopath', 'GOFLAGS': '-mod=mod', 'GOPROXY': 'off', 'GOSUMDB': 'off', 'GOTOOLCHAIN': 'local', 'GOWORK': 'off', 'CGO_ENABLED': '0'};
}

/// 这种语言在本机能不能跑：能就返回工具，不能返回 null（调用方跳过并打印原因）。
Future<BeToolchain?> toolchainFor(String language) async {
  switch (language) {
    case 'node':
      return await hasCommand('node') ? const BeToolchain({}) : null;
    case 'python':
      return await hasCommand('python3') ? const BeToolchain({}) : null;
    case 'go':
      final go = await findGo();
      if (go == null) return null;
      final gofmt = go == 'go' ? 'gofmt' : '${File(go).parent.path}/gofmt';
      return BeToolchain({'go': go, 'gofmt': gofmt}, goEnvironment());
    case 'java':
      return await hasCommand('javac') && await hasCommand('java') ? const BeToolchain({}) : null;
  }
  return null;
}

/// 把生成的工程写进一个临时目录。用完自己删。
Directory writeProject(Map<String, String> files, String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  for (final f in files.entries) {
    File('${dir.path}/${f.key}')
      ..createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

/// 一个起好的服务。
class RunningBackend {
  RunningBackend(this.process, this.port, this.stdoutLines, this.stderrText, this._subs);

  final Process process;
  final int port;

  /// “已启动”之后标准输出的每一行。
  final List<String> stdoutLines;
  final StringBuffer stderrText;
  final List<StreamSubscription<String>> _subs;

  Future<void> stop() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

/// 在 `dir` 里用 `command` 起服务（随机端口、只绑 127.0.0.1），等它打印“已启动”那一行。
Future<RunningBackend> startBackend(Directory dir, List<String> command, {Map<String, String> environment = const {}}) async {
  final process = await Process.start(command.first, command.sublist(1), workingDirectory: dir.path, environment: {...environment, 'PORT': '0', 'HOST': '127.0.0.1'});
  final ready = Completer<int>();
  final lines = <String>[];
  final err = StringBuffer();
  final subs = [
    process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
      final m = RegExp(r'^后端已启动：http://127\.0\.0\.1:([0-9]+)$').firstMatch(line);
      if (!ready.isCompleted && m != null) {
        ready.complete(int.parse(m[1]!));
      } else {
        lines.add(line);
      }
    }, onError: (_) {}), // 进程被杀时管道断开，不用管
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(err.writeln, onError: (_) {}), // 同上
  ];
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) ready.completeError(StateError('服务没起来就退出了（$code）：\n$err'));
    }),
  );
  try {
    final port = await ready.future.timeout(const Duration(seconds: 60));
    return RunningBackend(process, port, lines, err, subs);
  } on Object {
    process.kill(ProcessSignal.sigkill);
    for (final s in subs) {
      await s.cancel();
    }
    rethrow;
  }
}

/// 对着起好的服务把 [conformanceCases] 逐条发一遍，核对状态码、Content-Type、内容。返回每条的响应（给“各语言互相比”用）。
Future<List<BeResponse>> runCases(RunningBackend server, String label) async {
  final out = <BeResponse>[];
  for (var i = 0; i < conformanceCases.length; i++) {
    final c = conformanceCases[i];
    final target = c.target.replaceAll('{self}', 'http://127.0.0.1:${server.port}').replaceAll('{port}', '${server.port}');
    final body = c.bodyBytes ?? (c.body == null ? null : utf8.encode(c.body!));
    final r = await sendRaw(server.port, c.method, target, body: body, headers: c.headers);
    final text = utf8.decode(r.body, allowMalformed: true);
    final where = '[$label] 第 ${i + 1} 条 $c\n服务的错误输出：${server.stderrText}';
    expect(r.status, c.status, reason: '$where\n响应内容：$text');
    expect(r.type, c.type, reason: where);
    if (c.pattern != null) {
      expect(text, matches(c.pattern!), reason: where);
    } else {
      expect(text, c.expect, reason: where);
      expect(r.body, utf8.encode(c.expect), reason: '$where（逐字节）');
    }
    out.add(r);
  }
  return out;
}

/// 在 `dir` 里把生成器要求的编译命令跑一遍（没有就什么都不做）。
Future<void> buildProject(BackendTarget target, Directory dir, BeToolchain tools) async {
  for (final build in target.buildCommands) {
    final command = tools.resolve(build, dir);
    final r = await Process.run(command.first, command.sublist(1), workingDirectory: dir.path, environment: tools.environment);
    expect(r.exitCode, 0, reason: '[${target.id}] ${build.join(' ')} 失败：\n${r.stdout}\n${r.stderr}');
  }
}

/// 一种语言的完整一致性检查：生成样本工程 → （编译）→ 起服务 → 跑请求脚本 → 核对日志 → 杀进程、删目录。
/// 返回每条的响应。
Future<List<BeResponse>> runConformance(String language, BeToolchain tools) async {
  final generated = generateBackend(conformanceDocument(), language: language);
  expect(generated, isNotNull, reason: '没有 $language 的生成器');
  final target = generated!.target;
  final dir = writeProject(generated.files, 'be_conf_${language}_');
  try {
    await buildProject(target, dir, tools);
    final server = await startBackend(dir, tools.resolve(target.startCommandFor(0), dir), environment: tools.environment);
    try {
      final responses = await runCases(server, language);
      // 给标准输出一点时间落地
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.stdoutLines, conformanceLogLines, reason: '[$language] “写到日志”的输出');
      return responses;
    } finally {
      await server.stop();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}
