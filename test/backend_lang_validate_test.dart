// 积木第 4 版·第 1 阶段：新积木上的校验——每条相关规则命中与不命中，问题画到哪块积木、哪个槽，
// 规则号、原因、建议三段齐全；错误拦生成、警告不拦。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_rules.dart';
import 'package:path/path.dart' as p;

import 'support/backend_lang_blocks.dart';

BeDocument docOf(List<J> body) => parseLangBlocksDocument(langBlocksDocumentJson([route('r1', 'GET', '/x', body)]));

String _at(LcBlockPath path) => [for (final s in path) '${s.arm >= 0 ? '段${s.arm}:' : (s.inElse ? '否则:' : '')}${s.index}'].join('/');

/// 每条问题写成“规则号 错/警 积木路径 #槽”。
List<String> found(List<J> body) => [
  for (final i in validateBackend(docOf(body))) '${lcRuleId(i.code)} ${i.level == LcIssueLevel.error ? '错' : '警'} ${_at(i.path)}${i.arg == null ? '' : ' #${i.arg}'}',
];

final J ok = json(dc({'ok': yes()}));
J log(String s) => blk('log', {'value': tx(s)});
J logic(String op, J l, J r) => ex('logic', {'l': l, 'op': op, 'r': r});

void main() {
  test('没问题的一串：新建变量 / 常量、循环、跳出、否则如果、分情况——一条都不报', () {
    expect(
      found([
        let('a', nm(1)),
        konst('b', nm(2)),
        setv('a', op2('+', vr('a'), vr('b'))),
        blk('while', {'cond': op2('<', vr('a'), nm(9))}, [setv('a', op2('+', vr('a'), nm(1)))]),
        blk('forever', {}, [blk('break')]),
        blk('repeat', {'times': nm(2)}, [blk('continue')]),
        blk('forCount', {'name': 'i', 'from': nm(1), 'to': nm(3), 'step': nm(1)}, [setv('a', vr('i'))]),
        iff(
          logic('and', yes(), no()),
          [ok],
          arms: [
            arm({'cond': no()}, [ok]),
          ],
          orElse: [ok],
        ),
      ]),
      isEmpty,
    );
    expect(
      found([
        blk('switch', {'value': nm(1)}, [], [ok], [
          arm({'value': nm(1)}, [ok]),
          arm({'value': nm(2)}, [ok]),
        ]),
      ]),
      isEmpty,
    );
  });

  test('G03 看不见的名字：没新建过、先用后建、循环变量拿到循环外面用；看得见的不报', () {
    expect(found([let('a', vr('nope')), ok]), ['G03 错 0 #value']);
    expect(found([setv('later', nm(1)), let('later', nm(2)), ok]), ['G03 错 0 #name']);
    expect(
      found([
        blk('forCount', {'name': 'i', 'from': nm(1), 'to': nm(3), 'step': nm(1)}, [log('x')]),
        json(vr('i')),
      ]),
      ['G03 错 1 #value'],
    );
    // 没有“块级”：如果里新建的，出了如果还在（设计稿 3.2）。
    expect(
      found([
        iff(yes(), [let('inner', nm(1))], noElse: true),
        json(vr('inner')),
      ]),
      isEmpty,
    );
    // 循环变量在循环里看得见。
    expect(
      found([
        blk('forPairs', {'dict': dc({}), 'key': 'k', 'value': 'v'}, [log('x'), setv('saved', vr('k'))]),
        ok,
      ]),
      isEmpty,
    );
  });

  test('L04 “跳出 / 跳过”不在循环里：报在那一块上；在循环里（隔着如果也算）不报', () {
    expect(found([blk('continue'), ok]).first, 'L04 错 0');
    expect(
      found([
        iff(yes(), [blk('continue')], noElse: true),
        ok,
      ]),
      ['L04 错 0/0'],
    );
    expect(
      found([
        iff(
          yes(),
          [ok],
          arms: [
            arm({'cond': no()}, [blk('break')]),
          ],
          orElse: [ok],
        ),
      ]).first,
      'L04 错 0/段0:0',
    );
    expect(
      found([
        blk(
          'while',
          {'cond': op2('<', vr('total'), nm(3))},
          [
            iff(yes(), [blk('break')], noElse: true),
          ],
        ),
        ok,
      ]),
      isEmpty,
    );
  });

  test('L09 名字重复：新建两次、和“变量”里声明的重名、循环的两个变量同名；各建各的不报', () {
    expect(found([let('a', nm(1)), let('a', nm(2)), ok]), ['L09 错 1 #name']);
    expect(found([let('total', nm(1)), ok]), ['L09 错 0 #name']);
    expect(
      found([
        blk('forPairs', {'dict': dc({}), 'key': 'k', 'value': 'k'}, []),
        ok,
      ]),
      ['L09 错 0 #value'],
    );
    // 没有块级：两个分支里各新建一次同名的也算重复（提示改用“把变量设为”）。
    expect(
      found([
        iff(yes(), [let('b', nm(1))], orElse: [let('b', nm(2))]),
        ok,
      ]),
      ['L09 错 0/否则:0 #name'],
    );
    expect(found([let('a', nm(1)), konst('b', nm(2)), ok]), isEmpty);
  });

  test('L11 给常量重新赋值：报在“把变量设为”的名字上；变量不报', () {
    expect(found([konst('c', nm(1)), setv('c', nm(2)), ok]), ['L11 错 1 #name']);
    expect(found([let('c', nm(1)), setv('c', nm(2)), ok]), isEmpty);
  });

  test('L13 可能停不下来（警告）：一直重复没有出口、条件写死成“是”；有跳出 / 返回的不报', () {
    expect(
      found([
        blk('forever', {}, [log('x')]),
      ]),
      ['L13 警 0'],
    );
    expect(
      found([
        blk('while', {'cond': yes()}, [log('x')]),
        ok,
      ]),
      ['L13 警 0'],
    );
    expect(
      found([
        blk('forever', {}, [ok]),
      ]),
      isEmpty,
      reason: '里面有返回：既不是死循环，也算“怎么走都返回”',
    );
    expect(
      found([
        blk('forever', {}, [blk('break')]),
        ok,
      ]),
      isEmpty,
    );
  });

  test('S10 后面的不会执行（警告）：跳出之后、返回之后（新旧积木混着也认）', () {
    expect(
      found([
        blk('forever', {}, [blk('break'), log('x')]),
        ok,
      ]),
      ['S10 警 0/1'],
    );
    expect(found([let('a', nm(1)), ok, let('z', nm(1))]), ['S10 警 2']);
    expect(
      found([
        blk('repeat', {'times': nm(2)}, [blk('continue'), log('x')]),
        ok,
      ]),
      ['S10 警 0/1'],
    );
    expect(
      found([
        blk('forever', {}, [
          iff(yes(), [blk('break')], noElse: true),
          log('x'),
        ]),
        ok,
      ]),
      isEmpty,
    );
  });

  test('G01 必填：名字没填、段的条件没填、“分情况”一段都没有；G02 名字不合规矩', () {
    expect(found([let('', nm(1)), ok]), ['G01 错 0 #name']);
    expect(
      found([
        iff(
          yes(),
          [ok],
          orElse: [ok],
          arms: [
            arm({}, [ok]),
          ],
        ),
      ]),
      ['G01 错 0 #${lcArmArg(0, 'cond')}'],
    );
    expect(
      found([
        blk('switch', {'value': nm(1)}, [], [], [], true),
        ok,
      ]),
      ['G01 错 0'],
    );
    expect(
      found([
        blk('while', {}, [blk('break')]),
        ok,
      ]),
      ['G01 错 0 #cond'],
    );
    expect(found([let('1a', nm(1)), ok]), ['G02 错 0 #name']);
    expect(found([let('我', nm(1)), ok]), ['G02 错 0 #name']);
    expect(
      found([
        json(ex('isType', {'x': nm(1), 'type': 'nope'})),
      ]),
      ['G02 错 0 #value'],
    );
    // 注释的文字、“对每一项”的序号可以空着。
    expect(
      found([
        blk('note', {'text': ''}),
        blk('forEach', {'list': ls([]), 'item': 'item', 'index': ''}, []),
        ok,
      ]),
      isEmpty,
    );
  });

  test('G10 类型对不上：条件槽里放了固定的数字 / 文字（警告，头上的和段上的都查）、要数字的槽里放了固定的文字（错误）；对得上的不报', () {
    expect(
      found([
        iff(
          yes(),
          [ok],
          orElse: [ok],
          arms: [
            arm({'cond': nm(3)}, [ok]),
          ],
        ),
      ]),
      ['G10 警 0 #${lcArmArg(0, 'cond')}'],
    );
    expect(
      found([
        blk('while', {'cond': tx('a')}, [blk('break')]),
        ok,
      ]),
      ['G10 警 0 #cond'],
    );
    expect(
      found([
        json(ex('neg', {'x': tx('abc')})),
      ]),
      ['G10 错 0 #value'],
    );
    expect(
      found([
        blk(
          'while',
          {
            'cond': logic('or', ex('isType', {'x': vr('total'), 'type': 'number'}), no()),
          },
          [blk('break')],
        ),
        ok,
      ]),
      isEmpty,
    );
    expect(
      found([
        json(
          ex('neg', {
            'x': ex('pow', {'a': nm(2), 'b': nm(3)}),
          }),
        ),
      ]),
      isEmpty,
    );
  });

  test('G08 不能加段的积木带了段（警告）；S11 否则如果链 / 分情况有一段没返回（警告），都返回不报', () {
    expect(
      found([
        blk('repeat', {'times': nm(1)}, [], [], [arm({}, [])]),
        ok,
      ]),
      ['G08 警 0'],
    );
    expect(
      found([
        iff(
          yes(),
          [ok],
          arms: [
            arm({'cond': no()}, []),
          ],
          orElse: [ok],
        ),
      ]),
      ['S11 警 '],
    );
    expect(
      found([
        blk(
          'switch',
          {'value': nm(1)},
          [],
          [],
          [
            arm({'value': nm(1)}, [ok]),
          ],
          true,
        ),
      ]),
      ['S11 警 '],
      reason: '“都不是”收起来了：有的走法不返回',
    );
    expect(
      found([
        blk('switch', {'value': nm(1)}, [], [ok], [
          arm({'value': nm(1)}, [ok]),
        ]),
      ]),
      isEmpty,
    );
  });

  test('每一条都带规则号、原因、建议三段；画到积木盒宿主上（接口 + 积木路径 + 槽）', () {
    final doc = docOf([
      let('a', vr('nope')),
      let('a', nm(2)),
      konst('c', nm(1)),
      setv('c', nm(2)),
      blk('break'),
      blk('forever', {}, [log('x')]),
      log('永远到不了'),
    ]);
    final host = BeBlockHost(doc: doc);
    final rules = {for (final i in host.issues) i.rule};
    expect(rules, containsAll(['G03', 'L09', 'L11', 'L04', 'L13', 'S10']));
    for (final i in host.issues) {
      expect(RegExp(r'^[GLS]\d\d$').hasMatch(i.rule), isTrue, reason: i.message);
      expect(i.problem.trim(), isNotEmpty, reason: '${i.rule} 要有原因');
      expect(i.fix.trim(), isNotEmpty, reason: '${i.rule} 要有建议');
      expect(i.message, contains(i.problem));
      expect(i.scriptId, 'r1');
    }
    final g03 = host.issues.firstWhere((i) => i.rule == 'G03');
    expect((g03.path.single.index, g03.arg, g03.isError), (0, 'value', true));
    final l13 = host.issues.firstWhere((i) => i.rule == 'L13');
    expect((l13.path.single.index, l13.isError), (5, false));
    // 四条新规则在规则表里都有名字和默认建议。
    for (final code in ['outsideLoop', 'duplicateName', 'assignConst', 'endlessLoop']) {
      expect(kLcRules[code]!.title, isNotEmpty);
      expect(kLcRules[code]!.fix, isNotEmpty);
    }
  });

  test('变量下拉：列“变量”里声明的＋这个接口里新建的名字（含循环变量）', () {
    final doc = docOf([
      let('mine', nm(1)),
      blk('forCount', {'name': 'i', 'from': nm(1), 'to': nm(3), 'step': nm(1)}, []),
      ok,
    ]);
    expect(beLocalNames(doc.routes.single.body, RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')).keys, containsAll(['mine', 'i']));
  });

  group('错误拦生成、警告不拦', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('lopi-lang-validate'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<BackendRegenResult> regen(List<J> body) {
      final doc = docOf(body);
      File(p.join(dir.path, kBackendFileName)).writeAsStringSync(doc.encode());
      return regenerateBackend(dir.path, doc: doc);
    }

    test('只有警告（L13、S10、G10）：照常生成', () async {
      final r = await regen([
        blk('forever', {}, [blk('break'), log('x')]),
        blk('while', {'cond': tx('a')}, [blk('break')]),
        ok,
      ]);
      expect(r.error, isNull);
      expect(r.errorCount, 0);
      expect(r.written, contains('server.js'));
      expect(File(p.join(dir.path, 'server.js')).readAsStringSync(), contains('while'));
    });

    test('有错误（L04 / L09 / L11 / G03）：一个文件都不写，说有几个错误', () async {
      for (final body in [
        [blk('break'), ok],
        [let('a', nm(1)), let('a', nm(2)), ok],
        [konst('c', nm(1)), setv('c', nm(2)), ok],
        [json(vr('nope'))],
      ]) {
        final r = await regen(body);
        expect(r.errorCount, greaterThan(0));
        expect(r.written, isEmpty);
        expect(File(p.join(dir.path, 'server.js')).existsSync(), isFalse);
      }
    });
  });
}
