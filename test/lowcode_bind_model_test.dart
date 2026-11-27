import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_check.dart';
import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_preview.dart';
import 'package:lopicode/lowcode/bind_refs.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/state_model.dart';

import 'support/bind_sample.dart';
import 'support/pages_sample.dart';

String _save(LcDocument d) => const JsonEncoder.withIndent('  ').convert(d.toJson());

void main() {
  group('状态放哪', () {
    test('项目级状态在最外层 state；页面级就是每页的变量；页面同名的优先', () {
      final d = bindSample();
      expect([for (final v in lcProjectStates(d)) v.name], ['user', 'cart', 'visits', 'cartCount']);
      expect([for (final s in lcStatesInScope(d)) '${s.name}${s.project ? '*' : ''}'], ['count', 'keyword', 'agree', 'names', 'tip', 'user*', 'cart*', 'visits*', 'cartCount*']);
      d.openPage('cart');
      expect(lcStateOf(d, 'user')!.project, isFalse, reason: '第二页自己的 user 盖住项目级的');
      expect(lcStateOf(d, 'cart')!.project, isTrue);
      expect(lcProjectNamesInScope(d), {'cart', 'visits', 'cartCount'});
    });

    test('存盘再读：状态、派生、8 种绑定一个不丢，再存一次逐字节一样', () {
      final d = bindSample();
      final once = _save(d);
      final again = _save(LcDocument.parse(once));
      expect(again, once);
      final back = LcDocument.parse(once);
      expect(back.logic.variable('tip')!.isDerived, isTrue);
      expect(back.logic.variable('names')!.initial, ['甲', '乙']);
      expect(lcRepeatOf(back.find('rowItem')!)!.item, 'it');
      expect(lcModelOf(back.find('kw')!), 'keyword');
    });

    test('没用状态和绑定的旧页面：读进来再存，和以前一个字不差（不多出任何字段）', () {
      final d = pagesSample();
      final text = _save(d);
      expect(text.contains('"state"'), isFalse);
      expect(text.contains('"kind"'), isFalse);
      expect(lcTreeHasBindings(d.root), isFalse);
      expect(LcViewEnv.of(d).isPlain, isTrue, reason: '没有绑定时画布走的还是原来那条路');
      expect(identical(lcViewNode(d.root, LcViewEnv.of(d)), d.root), isTrue);
    });

    test('改项目级状态：读不懂的项原样留在后面；空了字段去掉', () {
      final d = LcDocument.starter('t');
      d.more['state'] = [
        {'name': 'a', 'type': 'number', 'initial': 1},
        '看不懂的',
        {'name': '9bad'},
      ];
      lcEditProjectStates(d, (l) => l.add(LcVariable(name: 'b', type: 'list', initial: [1, 2])));
      expect(d.more['state'], [
        {'name': 'a', 'type': 'number', 'initial': 1},
        {
          'name': 'b',
          'type': 'list',
          'initial': [1, 2],
        },
        '看不懂的',
        {'name': '9bad'},
      ]);
      final e = LcDocument.starter('t');
      lcEditProjectStates(e, (l) => l.add(LcVariable(name: 'x')));
      lcEditProjectStates(e, (l) => l.clear());
      expect(e.more.containsKey('state'), isFalse);
    });

    test('坏数据不崩：state 不是数组、绑定字段乱写', () {
      final d = LcDocument.starter('t');
      d.more['state'] = {'oops': 1};
      expect(lcProjectStates(d), isEmpty);
      final n = d.root.children.first;
      n.more['data'] = 'x';
      n.more['repeat'] = [1];
      n.more['showIf'] = 3;
      n.more['classIf'] = {'a': 1};
      n.more['styles'] = <Object?>[];
      n.more['model'] = 'k';
      expect(lcHasBindings(n), isFalse);
      expect(lcBoundProps(n), isEmpty);
      expect(lcRepeatOf(n), isNull);
      expect(lcCheckBindings(d), isEmpty);
      expect(identical(lcBoundNode(n, LcBindEnv.of(d)), n), isTrue);
    });
  });

  group('按初值算', () {
    test('文字、派生、取记录的一格、列表长度、比较', () {
      final d = bindSample();
      final env = LcBindEnv.of(d);
      expect(lcEval(lcDataExpr(d.find('hello')!, 'text'), env), '你好，小塔塔');
      expect(lcEval(lcDataExpr(d.find('tipText')!, 'text'), env), '已点 0 次');
      expect(lcEval(lcDataExpr(d.find('total')!, 'text'), env), '共 2 件');
      expect(lcEvalBool(lcEval(lcShowIfExpr(d.find('echo')!), env)), isFalse);
      expect(lcCondHolds(d.find('enough')!, env), isFalse);
      expect(lcEval(exLen(exRead('cart')), env), 2);
      final scopes = lcRepeatScopes(d.find('rowItem')!, env)!;
      expect(scopes.length, 2);
      expect(lcEval(lcDataExpr(d.find('itemName')!, 'text'), scopes[1]), '2. 香蕉 ¥2');
    });

    test('派生值绕圈不死循环；算术规矩和导出的 JS 一样', () {
      final d = LcDocument.starter('t');
      d.logic.variables.addAll([LcVariable(name: 'a', derived: exVar('b')), LcVariable(name: 'b', derived: exVar('a'))]);
      final env = LcBindEnv.of(d);
      expect(env.read('a'), isNull);
      expect(lcEval(exBin('/', exNum(1), exNum(0)), env), 0);
      expect(lcEval(exBin('+', exText('3'), exText('x')), env), 3);
      expect(lcEval(exBin('==', exNum(1), exText('1')), env), isTrue);
      expect(lcEvalText(1.50), '1.5');
      expect(lcEvalText(3.0), '3');
      expect(lcCheckBindings(d).where((i) => i.message.contains('绕回来')).length, 2);
    });

    test('画布看到的节点：绑了的属性换成初值；空文字显示 {说明}；双向显示状态的初值；样式绑定并进样式', () {
      final d = bindSample();
      final env = LcViewEnv.of(d);
      expect(env.isPlain, isFalse);
      expect(lcViewNode(d.find('hello')!, env).strProp('text'), '你好，小塔塔');
      expect(lcViewNode(d.find('submit')!, env).props['disabled'], isTrue);
      expect(lcViewNode(d.find('submit')!, env).style['width'], '120px');
      expect(lcViewNode(d.find('nameList')!, env).props['items'], ['甲', '乙']);
      expect(lcViewNode(d.find('agreeBox')!, env).props['checked'], isFalse);
      d.openPage('cart');
      expect(lcViewNode(d.find('who')!, LcViewEnv.of(d)).strProp('text'), '本页的名字');
      final e = LcDocument.starter('t');
      e.logic.addVariable('name', type: 'text', initial: '');
      final t = e.root.children.first;
      lcSetData(t, 'text', lcSrcVar('name'));
      expect(lcViewNode(t, LcViewEnv.of(e)).strProp('text'), '{name}');
      expect(t.strProp('text'), isNot('{name}'), reason: '原来的节点不动');
    });
  });

  group('哪里在用、改名、删除', () {
    test('页面级：绑定、双向、派生、积木里的都算', () {
      final d = bindSample();
      final uses = lcStateUses(d, 'count', project: false);
      expect([for (final u in uses) u.what], containsAll(['样式 width', '存在条件', '派生值 tip', '积木里 1 处']));
      expect(lcStateUses(d, 'keyword', project: false).map((u) => u.what), containsAll(['双向绑定', '文字', '显示条件']));
    });

    test('页面级改名：绑定、双向、派生、积木一起改；别的页不动', () {
      final d = bindSample();
      expect(lcRenameState(d, 'count', 'times', project: false), isTrue);
      final text = _save(d);
      expect(text.contains('"count"'), isFalse);
      expect(d.logic.variable('times'), isNotNull);
      expect(lcEval(lcDataExpr(d.find('tipText')!, 'text'), LcBindEnv.of(d)), '已点 0 次');
      expect(d.logic.handlers.first.body.first.args['name'], 'times');
      expect(lcCheckBindings(d).where((i) => !i.warning), isEmpty);
      expect(lcRenameState(d, 'times', 'keyword', project: false), isFalse, reason: '重名不改');
      expect(lcRenameState(d, 'times', '9x', project: false), isFalse);
    });

    test('项目级改名：扫所有页面和组件定义；自己有同名状态的那一页不动；重复里同名的这一项不动', () {
      final d = bindSample();
      // 组件定义里也用一处
      final def = LcComponentDef(
        id: 'c1',
        name: '卡片',
        root: LcNode(id: 'r', type: 'text', props: {'text': 'x'}),
      );
      lcSetData(def.root, 'text', lcSrcVar('user'));
      d.components.add(def);
      final uses = lcStateUses(d, 'user', project: true);
      expect([for (final u in uses) u.where], ['Home · 文本', '组件「卡片」 · 文本']);
      expect(lcRenameState(d, 'user', 'owner', project: true), isTrue);
      expect(lcProjectStates(d).first.name, 'owner');
      expect(lcDescribeExpr(lcDataExpr(d.find('hello')!, 'text')), '你好，{owner}');
      expect(lcDescribeExpr(lcDataExpr(def.root, 'text')), 'owner');
      d.openPage('cart');
      expect(lcDescribeExpr(lcDataExpr(d.find('who')!, 'text')), 'user', reason: '这一页的 user 是它自己的');
      d.openPage('home');

      expect(lcRenameState(d, 'cart', 'it', project: true), isTrue);
      final rep = lcRepeatOf(d.find('rowItem')!)!;
      expect(lcDescribeExpr(rep.list), 'it', reason: '列表来源在重复外面，跟着改');
      expect(lcDescribeExpr(rep.key), 'it.id', reason: '标识里的 it 是这一项');
      expect(lcProjectStates(d).last.derived, {
        'e': 'len',
        'x': {'e': 'var', 'name': 'it'},
      });
    });

    test('删除：状态没了，用到的地方不动，检查把它们标出来', () {
      final d = bindSample();
      expect(lcRemoveState(d, 'keyword', project: false), isTrue);
      final issues = lcCheckBindings(d);
      expect(issues.where((i) => i.nodeId == 'kw' && i.message.contains('没有这个状态')), isNotEmpty);
      expect(issues.where((i) => i.nodeId == 'echo'), isNotEmpty);
      expect(lcRemoveState(d, 'cart', project: true), isTrue);
      expect(lcRemoveState(d, 'cart', project: true), isFalse);
    });
  });

  group('检查', () {
    test('样例本身没有问题', () {
      final d = bindSample();
      expect([for (final i in lcCheckBindings(d)) i.message], isEmpty);
      d.openPage('cart');
      expect([for (final i in lcCheckBindings(d)) i.message], isEmpty);
    });

    test('重复没标识是错，用序号是警告；要列表的地方绑了不是列表的', () {
      final d = bindSample();
      final row = d.find('rowItem')!;
      lcSetRepeat(row, listSrc: lcSrcVar('cart'), item: 'it', index: 'i');
      expect(lcCheckBindings(d).single.message, contains('还没给每项的标识'));
      lcSetRepeat(row, listSrc: lcSrcVar('cart'), item: 'it', index: 'i', keySrc: lcSrcVar('i'));
      final w = lcCheckBindings(d).single;
      expect(w.warning, isTrue);
      expect(w.message, contains('拿序号当标识'));
      lcSetRepeat(row, listSrc: lcSrcVar('count'), item: 'it', index: 'i', keySrc: lcSrcVar('it', ['id']));
      expect(lcCheckBindings(d).single.message, contains('要一个列表'));
      lcSetData(d.find('nameList')!, 'items', lcSrcVar('user'));
      expect(lcCheckBindings(d).where((i) => i.nodeId == 'nameList').single.message, contains('要一个列表'));
    });

    test('双向：类型对不上、绑到派生值、控件不支持；绑了又被积木直接改', () {
      final d = bindSample();
      lcSetModel(d.find('kw')!, 'agree');
      lcSetModel(d.find('agreeBox')!, 'tip');
      lcSetModel(d.find('hello')!, 'count');
      final msgs = [for (final i in lcCheckBindings(d)) i.message];
      expect(msgs.where((m) => m.contains('要绑一个“文字或数字”的状态')), hasLength(1));
      expect(msgs.where((m) => m.contains('派生值是算出来的')), hasLength(1));
      expect(msgs.where((m) => m.contains('不能双向绑定')), hasLength(1));

      final e = bindSample();
      e.logic.handlers.first.body.add(LcBlock(op: 'setProp', args: {'node': 'hello', 'prop': 'text', 'value': exText('x')}));
      expect(lcCheckBindings(e).single.message, contains('只能留一样'));
    });
  });
}
