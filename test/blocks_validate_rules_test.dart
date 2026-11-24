// 积木语法检查新增的规则：每条一个命中、一个不命中；规则编号；定位到哪一格；老文档；耗时；“停手后再查”。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_rules.dart';
import 'package:lopicode/lowcode/logic_validate_types.dart';
import 'package:lopicode/lowcode/model.dart';

// —— 页面逻辑 ——

/// n1 文本、n2 按钮、n3 输入框。变量 count（数字）、name（文字）、on（是否）。
LcDocument page(List<Object?> handlers) => LcDocument.parse(
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
        {'id': 'n3', 'type': 'input'},
      ],
    },
    'logic': {
      'variables': [
        {'name': 'count', 'type': 'number', 'initial': 0},
        {'name': 'name', 'type': 'text', 'initial': ''},
        {'name': 'on', 'type': 'bool', 'initial': false},
      ],
      'handlers': handlers,
    },
  }),
);

Map<String, Object?> blk(String op, Map<String, Object?> args, {List<Object?> body = const [], List<Object?> orElse = const []}) => {'op': op, 'args': args, 'body': body, 'else': orElse};
Map<String, Object?> on(String event, List<Object?> body, {String? target, String id = 'h1'}) => {'id': id, 'event': event, 'target': ?target, 'body': body};

List<LcLogicIssue> pageIssues(List<Object?> body) => validateLogic(page([on('click', body, target: 'n2')]));
List<String> pageCodes(List<Object?> body) => [for (final i in pageIssues(body)) i.code];

Map<String, Object?> say(Object? v) => blk('log', {'value': v});

// —— 后端 ——

LcBlock b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
LcBlock get ok => b('respondJson', {
  'status': exNum(200),
  'value': beObj({'ok': exBool(true)}),
});

BeDocument be(List<LcBlock> body) {
  final doc = BeDocument(
    variables: [
      LcVariable(name: 's'),
      LcVariable(name: 'n', type: 'number'),
      LcVariable(name: 'flag', type: 'bool'),
    ],
    collections: [BeCollection(name: 'todos')],
  );
  doc.routes.add(BeRoute(id: 'r1', method: 'GET', path: '/x/:id', body: [...body]));
  return doc;
}

List<LcLogicIssue> beIssues(List<LcBlock> body) => validateBackend(be(body));
List<String> beCodes(List<LcBlock> body) => [for (final i in beIssues(body)) i.code];

void main() {
  group('规则表', () {
    test('每种问题都有稳定的规则编号、标题和默认建议；编号不重复', () {
      final ids = <String>{};
      for (final e in kLcRules.entries) {
        expect(e.value.id, matches(RegExp(r'^[GPS]\d\d$')), reason: e.key);
        expect(e.value.title, isNotEmpty, reason: e.key);
        expect(e.value.fix, isNotEmpty, reason: e.key);
        expect(ids.add(e.value.id), isTrue, reason: '编号重复：${e.value.id}');
      }
      expect(lcRuleId(LcIssueCode.missingArg), 'G01');
      expect(lcRuleId(LcIssueCode.badType), 'G10');
      expect(lcRuleId(LcIssueCode.duplicateEvent), 'P07');
      expect(lcRuleId(BeIssueCode.noRespond), 'S11');
    });

    test('校验出来的每一条都带编号、原因和建议', () {
      final issues = [
        ...pageIssues([
          blk('setVar', {'name': 'nope', 'value': exNum(1)}),
          blk('repeat', {'times': exNum(-1)}, body: [say(exText('a'))]),
        ]),
        ...beIssues([
          b('fetch', {'url': exText(''), 'method': 'GET'}),
        ]),
      ];
      expect(issues.length, greaterThanOrEqualTo(3));
      for (final i in issues) {
        expect(i.rule, matches(RegExp(r'^[GPS]\d\d$')), reason: i.code);
        expect(i.problem, isNotEmpty);
        expect(i.advice, isNotEmpty, reason: i.code);
      }
    });
  });

  group('页面逻辑：类型', () {
    test('数字格里填了不是数字的文字＝错误；填“12”这样的文字不报', () {
      final hit = pageIssues([
        blk('changeVar', {'name': 'count', 'by': exText('abc')}),
      ]);
      expect([for (final i in hit) i.code], [LcIssueCode.badType]);
      expect(hit.single.isError, isTrue);
      expect(hit.single.arg, 'by');
      expect(hit.single.exprPath, isEmpty);
      expect(
        pageCodes([
          blk('changeVar', {'name': 'count', 'by': exText('12')}),
        ]),
        isEmpty,
      );
    });

    test('数字格里放“是 / 否”＝警告；放数字变量不报', () {
      final hit = pageIssues([
        blk('changeVar', {'name': 'count', 'by': exVar('on')}),
      ]);
      expect([for (final i in hit) i.code], [LcIssueCode.badType]);
      expect(hit.single.isError, isFalse);
      expect(
        pageCodes([
          blk('changeVar', {'name': 'count', 'by': exVar('count')}),
        ]),
        isEmpty,
      );
    });

    test('条件格里放数字 / 文字＝警告；放比较、“是 / 否”变量不报', () {
      for (final cond in [exNum(1), exText('x'), exVar('count'), exVar('name')]) {
        final hit = pageIssues([
          blk('if', {'cond': cond}, body: [say(exText('a'))]),
        ]);
        expect([for (final i in hit) i.code], [LcIssueCode.badType], reason: '$cond');
        expect(hit.single.isError, isFalse);
      }
      for (final cond in [exBool(true), exVar('on'), exBin('>', exVar('count'), exNum(1)), exNot(exVar('on'))]) {
        expect(
          pageCodes([
            blk('if', {'cond': cond}, body: [say(exText('a'))]),
          ]),
          isEmpty,
          reason: '$cond',
        );
      }
    });

    test('算术 / 比大小的两边要数字：里面那一格被点名（exprPath 指到那一边）', () {
      final hit = pageIssues([say(exBin('+', exNum(1), exText('abc')))]);
      expect([for (final i in hit) i.code], [LcIssueCode.badType]);
      expect(hit.single.arg, 'value');
      expect(hit.single.exprPath, ['r']);
      // “并且”的两边要条件。
      expect(pageCodes([say(exBin('and', exVar('on'), exNum(3)))]), [LcIssueCode.badType]);
      expect(pageCodes([say(exBin('and', exVar('on'), exBin('<', exVar('count'), exNum(3))))]), isEmpty);
    });

    test('等于 / 不等于：一边“是 / 否”一边不是＝警告；同类型、说不准类型的不报', () {
      final hit = pageIssues([say(exBin('==', exVar('on'), exNum(1)))]);
      expect([for (final i in hit) i.code], [LcIssueCode.badType]);
      expect(hit.single.isError, isFalse);
      expect(
        pageCodes([
          say(exBin('==', exVar('count'), exNum(1))),
          say(exBin('==', exVar('name'), exNum(1))),
          say(exBin('!=', exVar('on'), exBool(false))),
          say(exBin('==', exVar('name'), exProp('n3', 'value'))),
        ]),
        isEmpty,
      );
    });
  });

  group('页面逻辑：结构', () {
    test('空帽子＝警告，定位到那一串；下面有积木就不报', () {
      final issues = validateLogic(page([on('click', [], target: 'n2')]));
      expect([for (final i in issues) i.code], [LcIssueCode.emptyScript]);
      expect(issues.single.isError, isFalse);
      expect(issues.single.handlerId, 'h1');
      expect(issues.single.path, isEmpty);
      expect(pageCodes([say(exText('a'))]), isEmpty);
    });

    test('同一个控件同一个事件两串＝警告（两串都会执行），标在后面那一串；不同控件 / 不同事件不报', () {
      final issues = validateLogic(
        page([
          on('click', [say(exText('a'))], target: 'n2'),
          on('click', [say(exText('b'))], target: 'n2', id: 'h2'),
        ]),
      );
      expect([for (final i in issues) i.code], [LcIssueCode.duplicateEvent]);
      expect(issues.single.isError, isFalse);
      expect(issues.single.handlerId, 'h2');
      expect(issues.single.arg, 'target');
      expect(
        validateLogic(
          page([
            on('click', [say(exText('a'))], target: 'n2'),
            on('click', [say(exText('b'))], target: 'n1', id: 'h2'),
            on('input', [say(exText('c'))], target: 'n3', id: 'h3'),
            on('load', [say(exText('d'))], id: 'h4'),
          ]),
        ),
        isEmpty,
      );
      // 两串“页面打开时”也算重复。
      final loads = validateLogic(
        page([
          on('load', [say(exText('a'))]),
          on('load', [say(exText('b'))], id: 'h2'),
        ]),
      );
      expect([for (final i in loads) i.code], [LcIssueCode.duplicateEvent]);
    });

    test('重复的次数：负数＝错误，小数 / 超过上限＝警告；正常的整数、放变量不报', () {
      List<LcLogicIssue> rep(Object? times) => pageIssues([
        blk('repeat', {'times': times}, body: [say(exText('a'))]),
      ]);
      expect(rep(exNum(-1)).single.code, LcIssueCode.badRepeat);
      expect(rep(exNum(-1)).single.isError, isTrue);
      expect(rep(exNum(-1)).single.arg, 'times');
      expect(rep(exNum(2.5)).single.code, LcIssueCode.badRepeat);
      expect(rep(exNum(2.5)).single.isError, isFalse);
      expect(rep(exNum(10001)).single.code, LcIssueCode.badRepeat);
      expect(rep(exNum(10001)).single.isError, isFalse);
      expect(rep(exNum(0)), isEmpty);
      expect(rep(exNum(3)), isEmpty);
      expect(rep(exNum(10000)), isEmpty);
      expect(rep(exVar('count')), isEmpty);
    });

    test('除以 / 取余常量 0＝警告，点名右边那一格；除以别的数、除以变量不报', () {
      for (final op in ['/', '%']) {
        final hit = pageIssues([say(exBin(op, exVar('count'), exNum(0)))]);
        expect([for (final i in hit) i.code], [LcIssueCode.divByZero], reason: op);
        expect(hit.single.isError, isFalse);
        expect(hit.single.exprPath, ['r']);
      }
      expect(pageCodes([say(exBin('/', exVar('count'), exNum(2))), say(exBin('/', exNum(1), exVar('count'))), say(exBin('*', exVar('count'), exNum(0)))]), isEmpty);
    });
  });

  group('页面逻辑：网址', () {
    test('跳转网址：空 / 明显不是网址＝警告；相对地址、完整网址、拼出来的不报', () {
      for (final url in ['', '  ', 'https://', 'a b.html', 'http:/x']) {
        final hit = pageIssues([
          blk('navigate', {'url': exText(url)}),
        ]);
        expect([for (final i in hit) i.code], [LcIssueCode.badUrl], reason: '“$url”');
        expect(hit.single.isError, isFalse);
        expect(hit.single.arg, 'url');
      }
      for (final url in ['about.html', '/list', '#top', 'https://example.com/a?b=1', 'mailto:a@b.c']) {
        expect(
          pageCodes([
            blk('navigate', {'url': exText(url)}),
          ]),
          isEmpty,
          reason: url,
        );
      }
      expect(
        pageCodes([
          blk('navigate', {
            'url': exJoin([exText('/item/'), exVar('count')]),
          }),
        ]),
        isEmpty,
      );
    });

    test('请求网址：空＝错误，没填完＝警告；填好了不报', () {
      final empty = pageIssues([
        blk('fetch', {'url': exText(''), 'method': 'GET'}),
      ]);
      expect([for (final i in empty) i.code], [LcIssueCode.badUrl]);
      expect(empty.single.isError, isTrue);
      final partial = pageIssues([
        blk('fetch', {'url': exText('https://'), 'method': 'GET'}),
      ]);
      expect(partial.single.isError, isFalse);
      expect(
        pageCodes([
          blk('fetch', {'url': exText('/api/list'), 'method': 'GET'}),
        ]),
        isEmpty,
      );
    });

    test('lcUrlProblem', () {
      expect(lcUrlProblem('', httpOnly: false), 'empty');
      expect(lcUrlProblem('http://', httpOnly: true), 'partial');
      expect(lcUrlProblem('a b', httpOnly: false), 'bad');
      expect(lcUrlProblem('/api', httpOnly: true), 'bad');
      expect(lcUrlProblem('ftp://x', httpOnly: true), 'bad');
      expect(lcUrlProblem('/api', httpOnly: false), isNull);
      expect(lcUrlProblem('https://a.b/c', httpOnly: true), isNull);
    });
  });

  group('页面逻辑：变量', () {
    test('变量名重复 / 非法＝错误；正常的名字不报', () {
      LcDocument withVars(List<Object?> vars) => LcDocument.parse(
        jsonEncode({
          'title': 't',
          'root': {'id': 'root', 'type': 'page', 'children': <Object?>[]},
          'logic': {'variables': vars, 'handlers': <Object?>[]},
        }),
      );
      // 读文件时重名的会被丢掉，所以这里直接往模型里塞（老版本、别的工具写出来的可能是这样）。
      final dupDoc = withVars([
        {'name': 'a', 'type': 'number', 'initial': 0},
      ]);
      dupDoc.logic.variables.add(LcVariable(name: 'a'));
      final dup = validateLogic(dupDoc);
      expect([for (final i in dup) i.code], [LcIssueCode.badVariable]);
      expect(dup.single.isError, isTrue);
      final badDoc = withVars([]);
      badDoc.logic.variables.add(LcVariable(name: '1x', type: 'number'));
      final bad = validateLogic(badDoc);
      expect([for (final i in bad) i.code], [LcIssueCode.badVariable]);
      expect(
        validateLogic(
          withVars([
            {'name': 'a', 'type': 'number', 'initial': 0},
            {'name': 'b', 'type': 'text', 'initial': ''},
          ]),
        ),
        isEmpty,
      );
    });
  });

  group('后端：类型、次数、除以 0、网址', () {
    test('数字格里填文字＝错误；条件格里放数字＝警告；对的不报', () {
      final hit = beIssues([
        b('changeVar', {'name': 'n', 'by': exText('abc')}),
        ok,
      ]);
      expect([for (final i in hit) i.code], [LcIssueCode.badType]);
      expect(hit.single.isError, isTrue);
      final cond = beIssues([
        b(
          'if',
          {'cond': exNum(3)},
          body: [
            b('log', {'value': exText('a')}),
          ],
        ),
        ok,
      ]);
      expect([for (final i in cond) i.code], [LcIssueCode.badType]);
      expect(cond.single.isError, isFalse);
      expect(
        beCodes([
          b('changeVar', {'name': 'n', 'by': exNum(2)}),
          b(
            'if',
            {'cond': exVar('flag')},
            body: [
              b('log', {'value': exText('a')}),
            ],
          ),
          // 后端的变量运行中可能装进请求里读来的任何东西，一律当“说不准”；请求里读来的东西也说不准：都不报。
          b(
            'if',
            {'cond': exVar('s')},
            body: [
              b('log', {'value': exText('a')}),
            ],
          ),
          b('changeVar', {'name': 'n', 'by': beQuery('step')}),
          ok,
        ]),
        isEmpty,
      );
    });

    test('后端自己的值：个数、条数是数字，“是空的”是条件', () {
      expect(beExprType(beLen(exVar('s'))), LcType.number);
      expect(beExprType(beDbCount('todos')), LcType.number);
      expect(beExprType(beIsNull(exVar('s'))), LcType.boolean);
      expect(beExprType(beBody()), LcType.any);
      expect(
        beCodes([
          b(
            'if',
            {'cond': beLen(exVar('s'))},
            body: [
              b('log', {'value': exText('a')}),
            ],
          ),
          ok,
        ]),
        [LcIssueCode.badType],
      );
    });

    test('重复的次数、除以 0', () {
      List<LcLogicIssue> rep(Object? times) => beIssues([
        b(
          'repeat',
          {'times': times},
          body: [
            b('log', {'value': exText('a')}),
          ],
        ),
        ok,
      ]);
      expect(rep(exNum(-2)).single.code, LcIssueCode.badRepeat);
      expect(rep(exNum(-2)).single.isError, isTrue);
      expect(rep(exNum(1.5)).single.isError, isFalse);
      expect(rep(exNum(5)), isEmpty);
      final div = beIssues([
        b('log', {'value': exBin('/', exVar('n'), exNum(0))}),
        ok,
      ]);
      expect([for (final i in div) i.code], [LcIssueCode.divByZero]);
      expect(div.single.isError, isFalse);
      expect(
        beCodes([
          b('log', {'value': exBin('/', exVar('n'), exNum(4))}),
          ok,
        ]),
        isEmpty,
      );
    });

    test('请求别的网址：空＝错误；不是 http(s) 的完整网址＝警告；对的不报', () {
      final empty = beIssues([
        b('fetch', {'url': exText(''), 'method': 'GET'}),
        ok,
      ]);
      expect([for (final i in empty) i.code], [LcIssueCode.badUrl]);
      expect(empty.single.isError, isTrue);
      for (final url in ['/api', 'ftp://x.y', 'https://']) {
        final hit = beIssues([
          b('fetch', {'url': exText(url), 'method': 'GET'}),
          ok,
        ]);
        expect([for (final i in hit) i.code], [LcIssueCode.badUrl], reason: url);
        expect(hit.single.isError, isFalse);
      }
      expect(
        beCodes([
          b('fetch', {'url': exText('https://api.example.com/v1'), 'method': 'GET'}),
          ok,
        ]),
        isEmpty,
      );
    });

    test('定位：对象里第二个字段的值有问题 → exprPath 指到那一格', () {
      final hit = beIssues([
        b('respondJson', {
          'status': exNum(200),
          'value': beObj({'a': exNum(1), 'b': exBin('/', exNum(1), exNum(0))}),
        }),
      ]);
      expect([for (final i in hit) i.code], [LcIssueCode.divByZero]);
      expect(hit.single.arg, 'value');
      expect(hit.single.exprPath, ['fields', 1, 'value', 'r']);
    });
  });

  group('有错误时的规矩（页面逻辑）', () {
    test('错误条数、给模型看的报告', () {
      final good = page([
        on('click', [say(exText('a'))], target: 'n2'),
      ]);
      expect(lcLogicErrorCount(good), 0);
      expect(lcLogicToolReport(good), isEmpty);

      final warn = page([on('click', [], target: 'n2')]);
      expect(lcLogicErrorCount(warn), 0);
      expect(lcLogicToolReport(warn), allOf(contains('提醒（不影响导出）'), contains('[G11]'), isNot(contains('没有更新'))));

      final bad = page([
        on('click', [
          blk('setVar', {'name': 'nope', 'value': exNum(1)}),
        ], target: 'n2'),
      ]);
      expect(lcLogicErrorCount(bad), 1);
      final text = lcLogicToolReport(bad);
      expect(text, contains('有 1 个错误，logic.js 没有更新'));
      expect(text, contains('[G03]'));
      expect(text, contains('nope'));
      expect(text, contains('建议：'));
      expect(lcExportBlockedText(2), contains('有 2 个错误，代码没有更新'));
    });
  });

  group('老文档', () {
    test('缺字段、类型乱、不认识的积木：只标出来，不崩、不改写文档', () {
      const raw = {
        'title': '老页面',
        'root': {
          'id': 'root',
          'type': 'page',
          'children': [
            {'id': 'n2', 'type': 'button'},
          ],
        },
        'logic': {
          'variables': [
            {'name': 'count'},
          ],
          'handlers': [
            {
              'id': 'h1',
              'event': 'click',
              'target': 'gone',
              'body': [
                {'op': 'setVar'},
                {
                  'op': 'repeat',
                  'args': {'times': 'three'},
                },
                {
                  'op': 'someFutureBlock',
                  'args': {'x': 1},
                },
                {
                  'op': 'if',
                  'args': {
                    'cond': {'e': 'mystery'},
                  },
                  'body': 'oops',
                },
                {
                  'op': 'navigate',
                  'args': {
                    'url': {'e': 'text'},
                  },
                },
              ],
            },
            {'id': 'h2', 'event': 'swipe', 'body': <Object?>[]},
          ],
        },
      };
      final doc = LcDocument.parse(jsonEncode(raw));
      final before = jsonEncode(doc.toJson());
      final issues = validateLogic(doc);
      expect(issues, isNotEmpty);
      for (final i in issues) {
        expect(i.rule, isNotEmpty);
        expect(i.problem, isNotEmpty);
      }
      expect(jsonEncode(doc.toJson()), before, reason: '校验只读，不改文档');
      expect(lcLogicToolReport(doc), isNotEmpty);
    });

    test('老的后端文档同理', () {
      final doc = BeDocument.fromJson({
        'kind': 'backend',
        'port': 'abc',
        'routes': [
          {
            'id': 'r1',
            'method': 'FETCH',
            'path': 'no-slash',
            'body': [
              {'op': 'respondJson'},
              {
                'op': 'repeat',
                'args': {'times': null},
              },
              {'op': 'whatever'},
            ],
          },
          {'id': 'r2'},
        ],
      }).doc;
      final before = jsonEncode(doc.toJson());
      final issues = validateBackend(doc);
      expect(issues, everyElement(isA<LcLogicIssue>())); // 读不懂的条目读文件时已经跳过了；剩下的校验一遍不崩、不改文档就行
      expect(jsonEncode(doc.toJson()), before);
    });
  });

  group('耗时与“停手后再查”', () {
    test('200 块积木：两套各校验一遍都很快', () {
      final bodyJson = <Object?>[];
      for (var i = 0; i < 50; i++) {
        bodyJson.add(blk('changeVar', {'name': 'count', 'by': exBin('+', exNum(i), exVar('count'))}));
        bodyJson.add(
          blk(
            'if',
            {'cond': exBin('>', exVar('count'), exNum(i))},
            body: [
              blk('setProp', {
                'node': 'n1',
                'prop': 'text',
                'value': exJoin([exText('第 '), exVar('count')]),
              }),
            ],
            orElse: [say(exBin('/', exVar('count'), exNum(i % 5)))],
          ),
        );
      }
      final doc = page([on('click', bodyJson, target: 'n2')]);
      var blocks = 0;
      void count(List<LcBlock> list) {
        for (final x in list) {
          blocks++;
          count(x.body);
          count(x.orElse);
        }
      }

      count(doc.logic.handlers.single.body);
      expect(blocks, 200);
      for (var i = 0; i < 40; i++) {
        validateLogic(doc); // 预热
      }
      final w = Stopwatch()..start();
      const rounds = 50;
      for (var i = 0; i < rounds; i++) {
        validateLogic(doc);
      }
      final perPage = w.elapsedMicroseconds / rounds / 1000;

      final beBody = <LcBlock>[];
      for (var i = 0; i < 66; i++) {
        beBody.add(b('changeVar', {'name': 'n', 'by': exNum(i)}));
        beBody.add(
          b(
            'if',
            {'cond': exBin('>', exVar('n'), exNum(i))},
            body: [
              b('dbInsert', {
                'collection': 'todos',
                'value': beObj({'t': beBodyField('t'), 'i': exNum(i)}),
              }),
            ],
          ),
        );
      }
      beBody.addAll([
        b('log', {'value': exText('done')}),
        ok,
      ]);
      final beDoc = be(beBody);
      for (var i = 0; i < 40; i++) {
        validateBackend(beDoc); // 预热
      }
      w
        ..reset()
        ..start();
      for (var i = 0; i < rounds; i++) {
        validateBackend(beDoc);
      }
      final perBe = w.elapsedMicroseconds / rounds / 1000;
      // 汇报里要写实测数，所以打出来（测试输出，不是应用日志）。
      // ignore: avoid_print 汇报里要写实测数，这是测试输出不是应用日志。
      print('PERF 200 块：页面逻辑 ${perPage.toStringAsFixed(2)} ms/遍，后端 ${perBe.toStringAsFixed(2)} ms/遍');
      // 上限放得很松（慢机器、别的任务在抢 CPU 都不该红）：一遍 200 毫秒以内。
      expect(perPage, lessThan(200));
      expect(perBe, lessThan(200));
    });

    testWidgets('BlockIssueCache：快的时候每次改动立刻重查；连着慢的时候先给旧结果、停手 180 毫秒后再查并通知', (tester) async {
      var rev = 0;
      var runs = 0;
      var late = 0;
      List<BlockIssue> compute() {
        runs++;
        return [BlockIssue(message: '第 $rev 版', isError: true)];
      }

      // 快：读一次算一次；版本没变不重算；怎么改都不会改成“停手后再查”。
      final quick = BlockIssueCache(compute, () => rev, () => late++, const Duration(days: 1));
      expect(quick.read().single.message, '第 0 版');
      expect(quick.read().single.message, '第 0 版');
      expect(runs, 1);
      for (rev = 1; rev <= 5; rev++) {
        expect(quick.read().single.message, '第 $rev 版');
      }
      expect(runs, 6);
      expect(quick.pending, isFalse);

      // 慢（预算给成负的＝每一遍都算超时）：偶尔慢一遍不算，连着两遍才改成“停手后再查”。
      runs = 0;
      rev = 2;
      final cache = BlockIssueCache(compute, () => rev, () => late++, const Duration(microseconds: -1));
      expect(cache.read().single.message, '第 2 版');
      expect(cache.pending, isFalse);
      rev = 3;
      expect(cache.read().single.message, '第 3 版');
      expect(runs, 2);
      // 之后的改动：先给旧结果，不卡这一帧。
      rev = 4;
      expect(cache.read().single.message, '第 3 版');
      expect(runs, 2);
      expect(cache.pending, isTrue);
      // 还在连着改：计时重来。
      await tester.pump(const Duration(milliseconds: 100));
      rev = 5;
      expect(cache.read().single.message, '第 3 版');
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, 2);
      expect(late, 0);
      // 停手够久：重查并通知一次。
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, 3);
      expect(late, 1);
      expect(cache.pending, isFalse);
      expect(cache.read().single.message, '第 5 版');

      // fresh()：不等，立刻要最新的（生成代码、拦截、问题列表用）。
      rev = 6;
      expect(cache.read().single.message, '第 5 版');
      expect(cache.fresh().single.message, '第 6 版');
      expect(cache.pending, isFalse);

      // stop()：页面关了，不再回调。
      rev = 7;
      cache.read();
      expect(cache.pending, isTrue);
      cache.stop();
      await tester.pump(const Duration(seconds: 1));
      expect(late, 1);
    });
  });
}
