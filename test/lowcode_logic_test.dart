// 积木目录、表达式小工具、校验、中文读法、积木的编辑操作。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

/// 测试页面：n1 文本“标题”、n2 按钮“提交”、n3 输入框、n4 列表、n5 行。变量 count（数字）、name（文字）、on（是否）。
LcDocument makeDoc({List<Object?> handlers = const [], bool withVars = true}) => LcDocument.parse(
  jsonEncode({
    'title': '测试页',
    'root': {
      'id': 'root',
      'type': 'page',
      'children': [
        {
          'id': 'n1',
          'type': 'text',
          'props': {'text': '标题'},
        },
        {
          'id': 'n2',
          'type': 'button',
          'props': {'text': '提交'},
        },
        {
          'id': 'n3',
          'type': 'input',
          'props': {'placeholder': '请输入'},
        },
        {'id': 'n4', 'type': 'list'},
        {'id': 'n5', 'type': 'row'},
      ],
    },
    'logic': {
      'variables': withVars
          ? [
              {'name': 'count', 'type': 'number', 'initial': 0},
              {'name': 'name', 'type': 'text', 'initial': ''},
              {'name': 'on', 'type': 'bool', 'initial': false},
            ]
          : <Object?>[],
      'handlers': handlers,
    },
  }),
);

Map<String, Object?> block(String op, Map<String, Object?> args, {List<Object?> body = const [], List<Object?> orElse = const []}) => {'op': op, 'args': args, 'body': body, 'else': orElse};

Map<String, Object?> on(String event, List<Object?> body, {String? target, String id = 'h1'}) => {'id': id, 'event': event, 'target': ?target, 'body': body};

/// 一个点击处理里放这些积木，返回校验结果里的 code 列表。
List<String> codesFor(List<Object?> body, {String event = 'click', String? target = 'n2'}) => [
  for (final i in validateLogic(makeDoc(handlers: [on(event, body, target: target)]))) i.code,
];

void main() {
  group('积木目录', () {
    test('和设计文档里的表一致（op、参数名、有没有 body / else）', () {
      final doc = File('docs/lowcode-v2-design.md').readAsStringSync();
      final rows = RegExp(r'^\| `(\w+)` \| (.*?) \| .* \|$', multiLine: true).allMatches(doc);
      final fromDoc = <String, Set<String>>{};
      for (final m in rows) {
        fromDoc[m[1]!] = {for (final a in RegExp(r'`(\w+)`').allMatches(m[2]!)) a[1]!};
      }
      expect(fromDoc.keys.toSet(), lcBlockSpecs.keys.toSet());
      for (final spec in lcBlockSpecs.values) {
        expect(fromDoc[spec.op], {for (final a in spec.args) a.name, if (spec.hasBody) 'body', if (spec.hasElse) 'else'}, reason: spec.op);
      }
      // 表达式那一段：`text{v}`、`prop{node, prop}`、`join{items:[…]}`…
      final exprLine = doc.split('\n').firstWhere((l) => l.startsWith('表达式（`e`）'));
      final next = doc.split('\n')[doc.split('\n').indexOf(exprLine) + 1];
      final exprs = <String, Set<String>>{};
      for (final m in RegExp(r'`(\w+)\{([^}]*)\}`').allMatches('$exprLine $next')) {
        exprs[m[1]!] = {for (final a in RegExp(r'[a-z]+').allMatches(m[2]!.split(':').first)) a[0]!};
      }
      expect(exprs.keys.toSet(), lcExprSpecs.keys.toSet());
      for (final spec in lcExprSpecs.values) {
        expect(exprs[spec.kind], {for (final a in spec.args) a.name}, reason: spec.kind);
      }
    });

    test('每块积木都有中文名、分类在清单里、选项和中文名一样多', () {
      for (final spec in lcBlockSpecs.values) {
        expect(spec.label, isNotEmpty);
        expect(lcBlockCategories, contains(spec.category), reason: spec.op);
        for (final a in spec.args) {
          expect(a.label, isNotEmpty);
          if (a.kind == LcArgKind.choice) expect(a.choiceLabels.length, a.choices.length, reason: '${spec.op}.${a.name}');
        }
      }
      for (final spec in lcExprSpecs.values) {
        expect(lcExprCategories, contains(spec.category), reason: spec.kind);
        for (final a in spec.args) {
          if (a.kind == LcArgKind.choice) expect(a.choiceLabels.length, a.choices.length, reason: '${spec.kind}.${a.name}');
        }
      }
      // 每个分类里都有积木，合起来不多不少。
      expect([for (final c in lcBlockCategories) ...blockSpecsIn(c)].length, lcBlockSpecs.length);
      expect([for (final c in lcExprCategories) ...exprSpecsIn(c)].length, lcExprSpecs.length);
      for (final c in lcBlockCategories) {
        expect(blockSpecsIn(c), isNotEmpty, reason: c);
      }
    });

    test('body / else 的叫法', () {
      expect(lcBlockSpecs['if']!.bodyLabel, '那么');
      expect(lcBlockSpecs['if']!.elseLabel, '否则');
      expect(lcBlockSpecs['fetch']!.bodyLabel, '成功后');
      expect(lcBlockSpecs['fetch']!.elseLabel, '失败后');
      expect(lcBlockSpecs['repeat']!.hasBody, isTrue);
      expect(lcBlockSpecs['repeat']!.hasElse, isFalse);
      expect(lcBlockSpecs['wait']!.hasBody, isTrue);
      expect(lcBlockSpecs['alert']!.hasBody, isFalse);
      expect(lcBlockSpecs['setProp']!.arg('prop')!.choiceLabel('visible'), '是否显示');
      expect(lcBlockSpecs['fetch']!.arg('into')!.optional, isTrue);
    });

    test('每种 newBlock 在有变量和控件的页面里都能直接通过校验', () {
      final doc = makeDoc();
      for (final op in lcBlockSpecs.keys) {
        final d = makeDoc();
        d.logic.addHandler('click', target: 'n2')!.insertBlock([], newBlock(op, doc));
        // 刚拿出来的“跳转网址”“请求网址”里是“https://”（等着填完），会有一条“网址没填完”的警告；别的都一条不报。
        expect([for (final i in validateLogic(d)) (i.code, i.isError)], op == 'navigate' || op == 'fetch' ? [(LcIssueCode.badUrl, false)] : isEmpty, reason: op);
        // 存了再读是一样的。
        expect(LcDocument.parse(d.encode()).logic.handlers.single.body.single.toJson(), newBlock(op, doc).toJson(), reason: op);
      }
    });

    test('newBlock 不给页面：变量和控件留空，校验提示“还没选”', () {
      for (final op in ['setVar', 'changeVar', 'setProp']) {
        final d = makeDoc();
        d.logic.addHandler('click', target: 'n2')!.insertBlock([], newBlock(op));
        expect([for (final i in validateLogic(d)) i.code], [LcIssueCode.missingArg], reason: op);
      }
      expect(newBlock('nope').args, isEmpty);
      // setVar 的默认值跟着变量的类型走；changeVar 挑数字变量；fetch 挑文字变量。
      final doc = makeDoc();
      expect(newBlock('setVar', doc).args, {'name': 'count', 'value': exNum(1)});
      expect(newBlock('changeVar', doc).args['name'], 'count');
      expect(newBlock('fetch', doc).args['into'], 'name');
      expect(newBlock('setProp', doc).args['node'], 'n1');
    });

    test('每种 newExpr 在 input 处理里都能通过校验', () {
      final doc = makeDoc();
      for (final kind in lcExprSpecs.keys) {
        final d = makeDoc();
        d.logic.addHandler('input', target: 'n3')!.insertBlock([], LcBlock(op: 'log', args: {'value': newExpr(kind, doc)}));
        expect(validateLogic(d), isEmpty, reason: kind);
      }
      expect(newExpr('prop', doc), exProp('n3', 'value'));
      expect(newExpr('nope'), exText(''));
      expect(defaultExprFor(LcType.number), exNum(1));
      expect(defaultExprFor(LcType.boolean), exBool(true));
      expect(defaultExprFor(LcType.any), exText(''));
    });

    test('哪种控件有哪些属性', () {
      expect(writablePropsFor('button'), ['text', 'visible', 'bg', 'color']);
      expect(writablePropsFor('input'), ['value', 'visible', 'bg', 'color', 'placeholder']);
      expect(writablePropsFor('image'), ['visible', 'bg', 'color', 'src']);
      expect(writablePropsFor('row'), ['visible', 'bg', 'color']);
      expect(readablePropsFor('input'), ['value', 'visible']);
      expect(readablePropsFor('text'), ['text', 'visible']);
      expect(propFitsNode('text', 'list'), isFalse);
    });
  });

  group('表达式小工具', () {
    test('读：类型不对一律返回 null，不抛异常', () {
      expect(exprKind(exNum(1)), 'num');
      expect(exprKind(null), isNull);
      expect(exprKind('text'), isNull);
      expect(exprKind({'e': 3}), isNull);
      expect(exprKind({'e': ''}), isNull);
      expect(isExpr({'e': 'whatever'}), isTrue);
      expect(exprString(exVar('a'), 'name'), 'a');
      expect(exprString({'e': 'var', 'name': 3}, 'name'), isNull);
      expect(exprNum(exNum(2.5), 'v'), 2.5);
      expect(exprNum(exText('2'), 'v'), isNull);
      expect(exprBool(exBool(false), 'v'), isFalse);
      expect(exprBool(exNum(0), 'v'), isNull);
      expect(exprField('x', 'v'), isNull);
      final bin = exBin('+', exVar('a'), exNum(1));
      expect(exprChild(bin, 'l'), exVar('a'));
      expect(exprChild(bin, 'op'), isNull);
      expect(exprChild(bin, 'nope'), isNull);
      expect(exprItems(exJoin([exText('a'), exNum(1)])), [exText('a'), exNum(1)]);
      expect(exprItems({'e': 'join', 'items': 'x'}), isEmpty);
      expect(
        exprItems({
          'e': 'join',
          'items': [1, exText('a'), null],
        }),
        [exText('a')],
      );
      // 从 jsonDecode 来的 Map 也认。
      expect(asExpr(jsonDecode('{"e":"num","v":1}')), exNum(1));
      expect(asExpr(<Object?, Object?>{'e': 'num', 'v': 1}), exNum(1));
      expect(asExpr([1]), isNull);
    });

    test('exprChild 返回的是原件；copyExpr 是深拷贝', () {
      final bin = exBin('+', exVar('a'), exNum(1));
      exprChild(bin, 'l')!['name'] = 'b';
      expect(bin['l'], exVar('b'));
      final copy = copyExpr(bin)!;
      exprChild(copy, 'l')!['name'] = 'c';
      expect(bin['l'], exVar('b'));
      expect(copyExpr('x'), isNull);
      expect(deepCopyJson({'a': DateTime(2026)}), {'a': null});
    });

    test('类型推断', () {
      String t(Object? e) => exprType(e, (name) => const {'count': 'number', 'name': 'text'}[name]);
      expect(t(exText('a')), LcType.text);
      expect(t(exNum(1)), LcType.number);
      expect(t(exBool(true)), LcType.boolean);
      expect(t(exVar('count')), LcType.number);
      expect(t(exVar('nope')), LcType.any);
      expect(t(exProp('n1', 'text')), LcType.text);
      expect(t(exProp('n1', 'visible')), LcType.boolean);
      expect(t(exEvent()), LcType.text);
      expect(t(exBin('*', exText('2'), exText('3'))), LcType.number);
      expect(t(exBin('<', exNum(1), exNum(2))), LcType.boolean);
      expect(t(exBin('and', exNum(1), exNum(2))), LcType.boolean);
      expect(t(exBin('??', exNum(1), exNum(2))), LcType.any);
      expect(t(exNot(exNum(1))), LcType.boolean);
      expect(t(exJoin([])), LcType.text);
      expect(t({'e': 'magic'}), LcType.any);
      expect(t(null), LcType.any);
    });
  });

  group('校验', () {
    test('没有逻辑、或逻辑都对：没有问题', () {
      expect(validateLogic(LcDocument.starter('新页面')), isEmpty);
      final d = makeDoc(
        handlers: [
          on('click', target: 'n2', [
            block('changeVar', {'name': 'count', 'by': exNum(1)}),
            block(
              'if',
              {'cond': exBin('>', exVar('count'), exNum(3))},
              body: [
                block('setProp', {
                  'node': 'n1',
                  'prop': 'text',
                  'value': exJoin([exText('第 '), exVar('count')]),
                }),
              ],
              orElse: [
                block('fetch', {'url': exText('/a'), 'method': 'GET'}),
              ],
            ),
          ]),
          on('input', target: 'n3', id: 'h2', [
            block('setVar', {'name': 'name', 'value': exEvent()}),
          ]),
          on('load', id: 'h3', [
            block('log', {'value': exProp('n3', 'value')}),
          ]),
        ],
      );
      expect(validateLogic(d), isEmpty);
    });

    test('用了没声明的变量（积木的参数里、表达式里、fetch 的 into）', () {
      expect(
        codesFor([
          block('setVar', {'name': 'total', 'value': exNum(1)}),
        ]),
        [LcIssueCode.unknownVar],
      );
      expect(
        codesFor([
          block('log', {'value': exBin('+', exVar('total'), exNum(1))}),
        ]),
        [LcIssueCode.unknownVar],
      );
      expect(
        codesFor([
          block('fetch', {'url': exText('/a'), 'method': 'GET', 'into': 'total'}),
        ]),
        [LcIssueCode.unknownVar],
      );
      // into 不填、填空都可以。
      expect(
        codesFor([
          block('fetch', {'url': exText('/a'), 'method': 'GET', 'into': ''}),
        ]),
        isEmpty,
      );
    });

    test('目标控件不存在：处理的 target、setProp 的 node、prop 表达式的 node', () {
      expect(codesFor([], target: 'n99'), [LcIssueCode.nodeNotFound]);
      expect(
        codesFor([
          block('setProp', {'node': 'n99', 'prop': 'text', 'value': exText('x')}),
        ]),
        [LcIssueCode.nodeNotFound],
      );
      expect(
        codesFor([
          block('log', {'value': exProp('n99', 'text')}),
        ]),
        [LcIssueCode.nodeNotFound],
      );
    });

    test('click / input 没有 target 是错误；load 不需要', () {
      expect(codesFor([], target: null), [LcIssueCode.missingTarget]);
      expect(codesFor([], event: 'input', target: null), [LcIssueCode.missingTarget]);
      // 帽子没问题、下面是空的：只有一条“下面还没有积木”的警告（2026-11-24 加的规则）。
      expect(codesFor([], event: 'load', target: null), [LcIssueCode.emptyScript]);
      expect(
        codesFor(
          [
            block('log', {'value': exText('a')}),
          ],
          event: 'load',
          target: null,
        ),
        isEmpty,
      );
    });

    test('input 事件挂在不是输入框的控件上：警告', () {
      final issues = validateLogic(makeDoc(handlers: [on('input', [], target: 'n2')]));
      expect(issues.single.code, LcIssueCode.inputOnNonInput);
      expect(issues.single.level, LcIssueLevel.warning);
      expect(issues.single.message, '「「按钮“提交”」的内容变化时」：“输入内容变化时”只有输入框会触发，「按钮“提交”」不是输入框');
      expect(codesFor([], event: 'input', target: 'n3'), [LcIssueCode.emptyScript]);
      expect(
        codesFor(
          [
            block('log', {'value': exText('a')}),
          ],
          event: 'input',
          target: 'n3',
        ),
        isEmpty,
      );
    });

    test('参数缺失', () {
      for (final op in lcBlockSpecs.keys) {
        final required = lcBlockSpecs[op]!.args.where((a) => !a.optional).length;
        expect(codesFor([block(op, {})]), List.filled(required, LcIssueCode.missingArg), reason: op);
      }
      expect(
        codesFor([
          block('log', {
            'value': {'e': 'bin', 'op': '+'},
          }),
        ]),
        [LcIssueCode.missingArg, LcIssueCode.missingArg],
      );
      expect(
        codesFor([
          block('log', {
            'value': {'e': 'text'},
          }),
        ]),
        [LcIssueCode.missingArg],
      );
    });

    test('参数类型不对', () {
      expect(
        codesFor([
          block('setVar', {'name': 3, 'value': 'x'}),
        ]),
        [LcIssueCode.badArg, LcIssueCode.badArg],
      );
      expect(
        codesFor([
          block('setProp', {'node': 7, 'prop': 'font', 'value': exText('x')}),
        ]),
        [LcIssueCode.badArg, LcIssueCode.badArg],
      );
      expect(
        codesFor([
          block('fetch', {'url': exText('/a'), 'method': 'DELETE'}),
        ]),
        [LcIssueCode.badArg],
      );
      expect(
        codesFor([
          block('log', {
            'value': {'e': 'num', 'v': '3'},
          }),
          block('log', {
            'value': {'e': 'bool', 'v': 'yes'},
          }),
          block('log', {
            'value': {'e': 'text', 'v': 3},
          }),
          block('log', {
            'value': {'e': 'bin', 'op': '**', 'l': exNum(1), 'r': exNum(2)},
          }),
          block('log', {
            'value': {'e': 'join', 'items': 'x'},
          }),
          block('log', {
            'value': {
              'e': 'join',
              'items': [exText('a'), 5],
            },
          }),
          block('log', {'value': exProp('n1', 'bg')}),
        ]),
        List.filled(7, LcIssueCode.badArg),
      );
    });

    test('不认识的积木 / 表达式：警告，数据还在', () {
      final d = makeDoc(
        handlers: [
          on('click', target: 'n2', [
            block('teleport', {'to': 'mars'}),
            block('log', {
              'value': {'e': 'magic', 'x': 1},
            }),
          ]),
        ],
      );
      final issues = validateLogic(d);
      expect([for (final i in issues) i.code], [LcIssueCode.unknownOp, LcIssueCode.unknownExpr]);
      expect(issues.every((i) => !i.isError), isTrue);
      expect(logicErrors(d), isEmpty);
      expect(d.logic.handlers.single.body.first.args, {'to': 'mars'});
    });

    test('changeVar 用在不是数字的变量上', () {
      final issues = validateLogic(
        makeDoc(
          handlers: [
            on('click', target: 'n2', [
              block('changeVar', {'name': 'name', 'by': exNum(1)}),
            ]),
          ],
        ),
      );
      expect(issues.single.code, LcIssueCode.changeVarNotNumber);
      expect(issues.single.isError, isTrue);
      expect(issues.single.arg, 'name');
      expect(issues.single.message, '「点击「按钮“提交”」时」第 1 块（把 name 加上 1）：变量 name 是文字，不是数字，不能“加上”；要改它请用“设置变量”');
    });

    test('“输入的内容”用在不是 input 的处理里', () {
      final body = [
        block('setVar', {
          'name': 'name',
          'value': exJoin([exText('你好'), exEvent()]),
        }),
      ];
      expect(codesFor(body), [LcIssueCode.eventOutsideInput]);
      expect(codesFor(body, event: 'load', target: null), [LcIssueCode.eventOutsideInput]);
      expect(codesFor(body, event: 'input', target: 'n3'), isEmpty);
    });

    test('嵌套过深：积木超过 13 层、表达式超过 24 层', () {
      var b = LcBlock(op: 'alert', args: {'message': exText('最里面')});
      for (var i = 0; i < LcBlock.maxDepth + 1; i++) {
        b = LcBlock(op: 'if', args: {'cond': exBool(true)}, body: [b]);
      }
      final d = makeDoc();
      d.logic.handlers.add(LcHandler(id: 'h1', event: 'load', body: [b]));
      final issues = validateLogic(d);
      expect(issues.single.code, LcIssueCode.tooDeep);
      expect(issues.single.path.length, LcBlock.maxDepth + 2);
      // 正好 13 层没问题。
      final ok = makeDoc();
      ok.logic.handlers.add(LcHandler(id: 'h1', event: 'load', body: b.body));
      expect(validateLogic(ok), isEmpty);

      var e = exNum(1);
      for (var i = 0; i < 3000; i++) {
        e = exNot(e);
      }
      expect(
        codesFor([
          block('log', {'value': e}),
        ]),
        [LcIssueCode.tooDeep],
      );
    });

    test('这种控件没有这个属性：警告', () {
      final issues = validateLogic(
        makeDoc(
          handlers: [
            on('click', target: 'n2', [
              block('setProp', {'node': 'n4', 'prop': 'text', 'value': exText('x')}),
              block('setProp', {'node': 'n2', 'prop': 'value', 'value': exText('x')}),
              block('log', {'value': exProp('n2', 'value')}),
              // 读容器的“文字”可以（读到里面所有的字）。
              block('log', {'value': exProp('n5', 'text')}),
            ]),
          ],
        ),
      );
      expect([for (final i in issues) i.code], List.filled(3, LcIssueCode.propNotSupported));
      expect(issues.every((i) => i.level == LcIssueLevel.warning), isTrue);
      expect(issues.first.problem, '「列表」没有“文字”可以改，这一块导出时会跳过');
      expect(issues.last.arg, 'value');
    });

    test('不能嵌积木的积木里放了积木：警告', () {
      expect(
        codesFor([
          block(
            'alert',
            {'message': exText('x')},
            body: [
              block('log', {'value': exText('x')}),
            ],
          ),
          block(
            'repeat',
            {'times': exNum(2)},
            orElse: [
              block('log', {'value': exText('x')}),
            ],
          ),
        ]),
        [LcIssueCode.strayBody, LcIssueCode.strayBody],
      );
    });

    test('变量本身有问题（内存里被改坏的）', () {
      final d = makeDoc();
      d.logic.variables.add(LcVariable(name: '1 abc'));
      d.logic.variables.add(LcVariable(name: 'count'));
      d.logic.variables.add(LcVariable(name: 'x', type: 'date'));
      final issues = validateLogic(d);
      expect([for (final i in issues) i.code], List.filled(3, LcIssueCode.badVariable));
      expect(issues[1].message, '变量 count：有两个变量叫这个名字');
      expect(issues.first.handlerId, isNull);
    });

    test('问题说得清在哪：处理、第几块、哪一格', () {
      final d = makeDoc(
        handlers: [
          on('click', target: 'n2', [
            block('log', {'value': exText('x')}),
            block(
              'if',
              {'cond': exBool(true)},
              orElse: [
                block('setVar', {'name': 'count', 'value': exBin('+', exVar('total'), exNum(1))}),
              ],
            ),
          ]),
        ],
      );
      final issue = validateLogic(d).single;
      expect(issue.handlerId, 'h1');
      expect(issue.path, [lcStep(1), lcStep(0, inElse: true)]);
      expect(issue.arg, 'value');
      expect(issue.where, '「点击「按钮“提交”」时」第 2 块 › 否则 › 第 1 块（把 count 设为 total + 1）');
      expect(issue.problem, '变量 total 还没有声明（先到“变量”里加一个）');
      expect('$issue', startsWith('错误 「点击'));
      expect(d.logic.handlers.single.blockAt(issue.path)!.op, 'setVar');
    });
  });

  group('中文读法', () {
    final doc = makeDoc();
    String b(Map<String, Object?> json) => describeBlock(LcBlock.tryParse(jsonDecode(jsonEncode(json)), 0)!, doc);

    test('控件：类型 + 上面的字，不说 id', () {
      expect(describeNode(doc, 'n2'), '「按钮“提交”」');
      expect(describeNode(doc, 'n3'), '「输入框“请输入”」');
      expect(describeNode(doc, 'n4'), '「列表」');
      expect(describeNode(doc, 'root'), '「页面“测试页”」');
      expect(describeNode(doc, 'n99'), '「已删除的控件」');
      expect(describeNode(doc, null), '「还没选控件」');
      doc.find('n1')!.props['text'] = '很长很长很长很长很长很长的\n一段标题';
      expect(describeNode(doc, 'n1'), '「文本“很长很长很长很长很长很长…”」');
      doc.find('n1')!.props['text'] = '标题';
    });

    test('表达式', () {
      String e(Object? x) => describeExpr(x, doc);
      expect(e(exText('你好')), '“你好”');
      expect(e(exNum(3)), '3');
      expect(e(exNum(2.5)), '2.5');
      expect(e(exBool(false)), '否');
      expect(e(exVar('count')), 'count');
      expect(e(exProp('n3', 'value')), '「输入框“请输入”」的输入内容');
      expect(e(exProp('n1', 'visible')), '「文本“标题”」的是否显示');
      expect(e(exEvent()), '输入的内容');
      expect(e(exBin('>', exVar('count'), exNum(10))), 'count > 10');
      expect(e(exBin('*', exBin('+', exVar('count'), exNum(1)), exNum(2))), '（count + 1） × 2');
      expect(e(exBin('and', exVar('on'), exNot(exBin('==', exVar('name'), exText(''))))), 'on 并且 不是（name = “”）');
      expect(e(exJoin([exText('共 '), exVar('count'), exText(' 次')])), '拼接（“共 ”、count、“ 次”）');
      expect(e(null), '（空）');
      expect(e({'e': 'magic'}), '不认识的值（magic）');
      expect(e(exVar('')), '（还没选变量）');
    });

    test('每种积木', () {
      expect(b(block('setVar', {'name': 'name', 'value': exText('小明')})), '把 name 设为 “小明”');
      expect(b(block('changeVar', {'name': 'count', 'by': exNum(1)})), '把 count 加上 1');
      expect(b(block('setProp', {'node': 'n2', 'prop': 'text', 'value': exText('好了')})), '把 「按钮“提交”」的文字 改成 “好了”');
      expect(b(block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exBool(false)})), '隐藏 「行」');
      expect(b(block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exBool(true)})), '显示 「行」');
      expect(b(block('setProp', {'node': 'n5', 'prop': 'visible', 'value': exVar('on')})), '把 「行」的是否显示 改成 on');
      expect(b(block('if', {'cond': exBin('>', exVar('count'), exNum(10))})), '如果 count > 10 那么…');
      expect(
        b(
          block(
            'if',
            {'cond': exVar('on')},
            orElse: [
              block('log', {'value': exText('x')}),
            ],
          ),
        ),
        '如果 on 那么…否则…',
      );
      expect(b(block('repeat', {'times': exNum(3)})), '重复 3 次…');
      expect(b(block('wait', {'ms': exNum(1000)})), '等 1000 毫秒，然后…');
      expect(b(block('alert', {'message': exText('你好')})), '弹出提示 “你好”');
      expect(b(block('navigate', {'url': exText('https://example.com')})), '跳转到 “https://example.com”');
      expect(b(block('log', {'value': exVar('count')})), '写到控制台 count');
      expect(b(block('fetch', {'url': exText('/api'), 'method': 'POST', 'into': 'name'})), '用 POST 请求 “/api”，结果放进 name');
      expect(b(block('fetch', {'url': exText('/api'), 'method': 'GET'})), '用 GET 请求 “/api”');
      expect(b(block('teleport', {})), '不认识的积木（teleport）');
      // 目录里的每种积木都有读法（不是“不认识的积木”），参数全缺也不崩。
      for (final op in lcBlockSpecs.keys) {
        expect(describeBlock(newBlock(op, doc), doc), isNot(contains('不认识')), reason: op);
        expect(() => describeBlock(LcBlock(op: op), doc), returnsNormally);
        expect(() => describeBlock(LcBlock(op: op, args: {'name': 1, 'node': <Object?>[], 'prop': <String, Object?>{}, 'method': 2, 'into': 3}), doc), returnsNormally);
      }
    });

    test('事件处理和位置', () {
      final d = makeDoc(
        handlers: [
          on('click', target: 'n2', [
            block(
              'fetch',
              {'url': exText('/a'), 'method': 'GET'},
              body: [
                block('log', {'value': exText('x')}),
              ],
              orElse: [
                block('log', {'value': exText('x')}),
                block(
                  'repeat',
                  {'times': exNum(2)},
                  body: [
                    block('log', {'value': exText('x')}),
                  ],
                ),
              ],
            ),
          ]),
          on('input', [], target: 'n3', id: 'h2'),
          on('load', [], id: 'h3'),
        ],
      );
      final hs = d.logic.handlers;
      expect(describeHandler(hs[0], d), '点击「按钮“提交”」时');
      expect(describeHandler(hs[1], d), '「输入框“请输入”」的内容变化时');
      expect(describeHandler(hs[2], d), '页面打开时');
      expect(describeEvent('click'), '点击时');
      expect(describeBlockPath(hs[0], [lcStep(0)]), '第 1 块');
      expect(describeBlockPath(hs[0], [lcStep(0), lcStep(0)]), '第 1 块 › 成功后 › 第 1 块');
      expect(describeBlockPath(hs[0], [lcStep(0), lcStep(1, inElse: true), lcStep(0)]), '第 1 块 › 失败后 › 第 2 块 › 重复做 › 第 1 块');
      expect(describeBlockPath(hs[0], [lcStep(7), lcStep(0)]), '第 8 块');
      expect(describeVarType('number'), '数字');
    });
  });

  group('编辑操作', () {
    LcHandler sample() => makeDoc(
      handlers: [
        on('click', target: 'n2', [
          block('log', {'value': exText('a')}),
          block(
            'if',
            {'cond': exBool(true)},
            body: [
              block('log', {'value': exText('b')}),
              block('log', {'value': exText('c')}),
            ],
            orElse: [
              block('log', {'value': exText('d')}),
            ],
          ),
          block('log', {'value': exText('e')}),
        ]),
      ],
    ).logic.handlers.single;
    String shape(LcHandler h) {
      String one(LcBlock b) => b.op == 'log' ? '${exprString(b.args['value'], 'v')}' : '${b.op}(${b.body.map(one).join()}|${b.orElse.map(one).join()})';
      return h.body.map(one).join(' ');
    }

    test('按路径找', () {
      final h = sample();
      expect(shape(h), 'a if(bc|d) e');
      expect(h.blockAt([lcStep(1)])!.op, 'if');
      expect(exprString(h.blockAt([lcStep(1), lcStep(1)])!.args['value'], 'v'), 'c');
      expect(exprString(h.blockAt([lcStep(1), lcStep(0, inElse: true)])!.args['value'], 'v'), 'd');
      expect(h.blockAt([]), isNull);
      expect(h.blockAt([lcStep(9)]), isNull);
      expect(h.blockAt([lcStep(0), lcStep(0)]), isNull);
      expect(h.blockAt([lcStep(-1)]), isNull);
      expect(h.listAt([lcStep(9)]), isNull);
      final seen = <String>[];
      h.visitBlocks((b, path) => seen.add('${b.op}@${path.map((s) => '${s.inElse ? 'e' : ''}${s.index}').join('.')}'));
      expect(seen, ['log@0', 'if@1', 'log@1.0', 'log@1.1', 'log@1.e0', 'log@2']);
    });

    test('插入、删除', () {
      final h = sample();
      LcBlock x(String v) => LcBlock(op: 'log', args: {'value': exText(v)});
      expect(h.insertBlock([], x('x'), index: 0), isTrue);
      expect(h.insertBlock([lcStep(2)], x('y')), isTrue);
      expect(h.insertBlock([lcStep(2)], x('z'), inElse: true, index: 0), isTrue);
      expect(h.insertBlock([], x('w'), index: 99), isTrue);
      expect(shape(h), 'x a if(bcy|zd) e w');
      expect(h.insertBlock([lcStep(42)], x('no')), isFalse);
      expect(exprString(h.removeBlock([lcStep(2), lcStep(0)])!.args['value'], 'v'), 'b');
      expect(h.removeBlock([lcStep(0)])!.op, 'log');
      expect(h.removeBlock([lcStep(42)]), isNull);
      expect(h.removeBlock([]), isNull);
      expect(shape(h), 'a if(cy|zd) e w');
    });

    test('插入会把嵌套拦在上限以内（超过的存盘后会丢）', () {
      final h = LcHandler(id: 'h1', event: 'load');
      var path = <LcBlockStep>[];
      for (var i = 0; i <= LcBlock.maxDepth; i++) {
        expect(
          h.insertBlock(path, LcBlock(op: 'if', args: {'cond': exBool(true)})),
          isTrue,
          reason: '第 ${i + 1} 层',
        );
        path = [...path, lcStep(0)];
      }
      expect(h.insertBlock(path, LcBlock(op: 'log')), isFalse);
      // 存了再读，一层都没丢。
      final again = LcHandler.tryParse(jsonDecode(jsonEncode(h.toJson())))!;
      expect(again.body.single.height, LcBlock.maxDepth + 1);
      expect(h.body.single.height, LcBlock.maxDepth + 1);
      // 带着两层的积木塞不进倒数第一层。
      final two = LcBlock(
        op: 'if',
        body: [LcBlock(op: 'log')],
      );
      expect(h.insertBlock(path.sublist(0, path.length - 1), two), isFalse);
      expect(h.insertBlock(path.sublist(0, path.length - 2), two), isTrue);
    });

    test('移动：同一串里、跨层、不能挪进自己里面', () {
      var h = sample();
      expect(h.moveBlock([lcStep(0)], [], index: 3), isTrue);
      expect(shape(h), 'if(bc|d) e a');
      h = sample();
      expect(h.moveBlock([lcStep(2)], [], index: 0), isTrue);
      expect(shape(h), 'e a if(bc|d)');
      h = sample();
      expect(h.moveBlock([lcStep(0)], [lcStep(1)], inElse: true), isTrue);
      expect(shape(h), 'if(bc|da) e');
      h = sample();
      expect(h.moveBlock([lcStep(1), lcStep(0)], [], index: 0), isTrue);
      expect(shape(h), 'b a if(c|d) e');
      h = sample();
      expect(h.moveBlock([lcStep(1)], [lcStep(1)]), isFalse);
      expect(h.moveBlock([lcStep(1)], [lcStep(1)], inElse: true), isFalse);
      expect(h.moveBlock([lcStep(9)], []), isFalse);
      expect(h.moveBlock([lcStep(0)], [lcStep(9)]), isFalse);
      expect(shape(h), 'a if(bc|d) e');
      // 上移 / 下移。
      expect(h.shiftBlock([lcStep(1), lcStep(0)], 1), isTrue);
      expect(h.shiftBlock([lcStep(0)], -1), isFalse);
      expect(h.shiftBlock([lcStep(2)], -1), isTrue);
      expect(shape(h), 'a e if(cb|d)');
    });

    test('深拷贝：改副本不影响原件', () {
      final h = sample();
      final copy = h.body[1].clone();
      copy.body.first.args['value'] = exText('改了');
      exprChild(copy.args, 'cond')!['v'] = false;
      copy.orElse.clear();
      expect(shape(h), 'a if(bc|d) e');
      expect(h.body[1].args['cond'], exBool(true));
      expect(copy.toJson(), isNot(h.body[1].toJson()));
      expect(h.body[1].clone().toJson(), h.body[1].toJson());
      final hc = h.clone();
      hc.body.clear();
      expect(shape(h), 'a if(bc|d) e');
      final logic = makeDoc(handlers: [on('load', [])]).logic;
      final lc = logic.clone();
      lc.variables.first.name = 'changed';
      lc.handlers.clear();
      expect(logic.variables.first.name, 'count');
      expect(logic.handlers, hasLength(1));
    });

    test('加处理、加变量', () {
      final logic = makeDoc(handlers: [on('load', [], id: 'h2')]).logic;
      expect(logic.addHandler('click', target: 'n2')!.id, 'h1');
      expect(logic.addHandler('load', target: 'n2')!.target, isNull);
      expect(logic.handlers.last.id, 'h3');
      expect(logic.addHandler('hover'), isNull);
      expect(logic.handler('h2')!.event, 'load');
      expect(logic.removeHandler('h2'), isTrue);
      expect(logic.removeHandler('h2'), isFalse);
      expect(logic.addVariable('total', type: 'number', initial: 5)!.initial, 5);
      expect(logic.addVariable('total'), isNull);
      expect(logic.addVariable('1x'), isNull);
      expect(logic.addVariable('y', type: 'date'), isNull);
      expect(logic.retypeVariable('total', 'text'), isTrue);
      expect(logic.variable('total')!.initial, '');
      expect(logic.retypeVariable('total', 'date'), isFalse);
      expect(logic.removeVariable('total'), isTrue);
      expect(logic.removeVariable('total'), isFalse);
    });

    LcDocument refs() => makeDoc(
      handlers: [
        on('click', target: 'n2', [
          block('setProp', {'node': 'n1', 'prop': 'text', 'value': exVar('count')}),
          block(
            'if',
            {'cond': exBin('==', exProp('n1', 'text'), exVar('name'))},
            body: [
              block('setProp', {'node': 'n1', 'prop': 'visible', 'value': exBool(false)}),
              block('changeVar', {'name': 'count', 'by': exNum(1)}),
            ],
            orElse: [
              block('fetch', {'url': exText('/a'), 'method': 'GET', 'into': 'name'}),
            ],
          ),
        ]),
        on('click', target: 'n1', id: 'h2', [
          block('log', {'value': exText('x')}),
        ]),
        on('load', id: 'h3', [
          block('log', {
            'value': exJoin([exProp('n1', 'text'), exVar('count')]),
          }),
        ]),
      ],
    );

    test('删控件时清理引用：处理删掉、改它的积木删掉、读它的表达式换成空文字', () {
      final d = refs();
      expect(d.logic.nodeRefCount('n1'), 5);
      expect(d.logic.nodeRefCount('n3'), 0);
      d.remove('n1');
      expect(logicErrors(d), isNotEmpty);
      expect(d.logic.removeNodeRefs('n1'), 5);
      expect(d.logic.nodeRefCount('n1'), 0);
      expect([for (final h in d.logic.handlers) h.id], ['h1', 'h3']);
      final h1 = d.logic.handlers.first;
      expect(h1.body.single.op, 'if');
      expect(h1.body.single.args['cond'], exBin('==', exText(''), exVar('name')));
      expect([for (final b in h1.body.single.body) b.op], ['changeVar']);
      expect(d.logic.handlers.last.body.single.args['value'], exJoin([exText(''), exVar('count')]));
      expect(validateLogic(d), isEmpty);
      expect(d.logic.removeNodeRefs('n1'), 0);
    });

    test('变量改名：声明和所有引用一起改；名字不行就什么都不改', () {
      final d = refs();
      expect(d.logic.variableRefCount('count'), 3);
      expect(d.logic.variableRefCount('name'), 2);
      expect(d.logic.renameVariable('count', 'total'), isTrue);
      expect(d.logic.variable('count'), isNull);
      expect(d.logic.variable('total')!.type, 'number');
      expect(d.logic.variableRefCount('count'), 0);
      expect(d.logic.variableRefCount('total'), 3);
      expect(validateLogic(d), isEmpty);
      expect(d.logic.renameVariable('name', 'into_var'), isTrue);
      expect(d.logic.handlers.first.body[1].orElse.single.args['into'], 'into_var');
      expect(validateLogic(d), isEmpty);
      final before = d.encode();
      expect(d.logic.renameVariable('total', 'on'), isFalse, reason: '重名');
      expect(d.logic.renameVariable('total', '1 x'), isFalse, reason: '名字不合规矩');
      expect(d.logic.renameVariable('nope', 'x'), isFalse);
      expect(d.logic.renameVariable('total', 'total'), isTrue);
      expect(d.encode(), before);
    });

    test('删变量不动引用，校验会标出来', () {
      final d = refs();
      expect(d.logic.removeVariable('name'), isTrue);
      expect([for (final i in validateLogic(d)) i.code], [LcIssueCode.unknownVar, LcIssueCode.unknownVar]);
    });
  });
}
