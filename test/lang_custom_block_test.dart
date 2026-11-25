// “我的积木”的外观模型（lib/lang/custom_block.dart、custom_block_edit.dart）：模板解析、JSON 往返、坏数据不崩、校验、改参数联动。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

const _t = LookSegment.text;
const _s = LookSegment.slot;

void main() {
  group('文案模板', () {
    test('字和槽按顺序切开', () {
      expect(parseLookTemplate('把 {集合} 里编号是 {id} 的那条删掉'), [_t('把 '), _s('集合'), _t(' 里编号是 '), _s('id'), _t(' 的那条删掉')]);
      expect(parseLookTemplate('{a}{b}'), [_s('a'), _s('b')]);
      expect(parseLookTemplate('没有槽'), [_t('没有槽')]);
      expect(parseLookTemplate(''), isEmpty);
    });

    test('槽名两头的空白去掉；两个花括号是花括号本身', () {
      expect(parseLookTemplate('{  名字 }'), [_s('名字')]);
      expect(parseLookTemplate('写 {{x}} 和 {x}'), [_t('写 {x} 和 '), _s('x')]);
    });

    test('没配上的、空的花括号原样当字，不崩', () {
      expect(parseLookTemplate('a { b'), [_t('a { b')]);
      expect(parseLookTemplate('a {} b'), [_t('a {} b')]);
      expect(parseLookTemplate('a } b'), [_t('a } b')]);
      expect(parseLookTemplate('{'), [_t('{')]);
      expect(parseLookTemplate('}'), [_t('}')]);
      expect(parseLookTemplate('{{'), [_t('{')]);
      expect(parseLookTemplate('{a{b}'), [_t('{a'), _s('b')]);
      expect(parseLookTemplate('{a\nb}'), [_t('{a\nb}')]);
      expect(parseLookTemplate('{   }x'), [_t('{   }x')]);
    });

    test('拼回去再切，结果一样', () {
      for (final t in ['把 {a} 给 {b}', '{{}} {x}', 'a { b', '}{', '{a}{a}', '', '   ', '{{{x}}}']) {
        final segs = parseLookTemplate(t);
        expect(parseLookTemplate(formatLookTemplate(segs)), segs, reason: t);
      }
    });

    test('没写模板＝名字加每个参数一个槽', () {
      expect(defaultLookTemplate('问好', ['名字', '次数']), '问好 {名字} {次数}');
      expect(defaultLookTemplate('a{b', []), 'a{{b');
      expect(const CustomBlockLook('问好').templateFor(['x']), '问好 {x}');
      expect(const CustomBlockLook('问好', template: '向 {x} 问好').templateFor(['x']), '向 {x} 问好');
      expect(lookTemplateSlots('{a} 和 {b} 和 {a}'), ['a', 'b', 'a']);
    });
  });

  group('存盘', () {
    const look = CustomBlockLook(
      '问好',
      shape: CustomBlockShape.statement,
      template: '向 {名字} 问好 {次数} 次，{语气}',
      colorKey: 'function',
      hint: '打几声招呼',
      slots: [
        CustomBlockSlot('名字'),
        CustomBlockSlot('次数', defaultValue: 1),
        CustomBlockSlot('语气', kind: CustomSlotKind.choice, options: ['客气', '随便'], defaultValue: '客气'),
        CustomBlockSlot('大声', kind: CustomSlotKind.boolean, defaultValue: false),
      ],
    );

    test('写出去再读回来一样；键的顺序固定', () {
      final text = jsonEncode(look.toJson());
      expect(customBlockLookFromJson(jsonDecode(text)), look);
      expect(jsonEncode(customBlockLookFromJson(jsonDecode(text))!.toJson()), text);
      expect(
        text,
        '{"name":"问好","shape":"statement","template":"向 {名字} 问好 {次数} 次，{语气}","colorKey":"function","hint":"打几声招呼",'
        '"slots":[{"name":"名字","kind":"value"},{"name":"次数","kind":"value","defaultValue":1},'
        '{"name":"语气","kind":"choice","options":["客气","随便"],"defaultValue":"客气"},{"name":"大声","kind":"boolean","defaultValue":false}]}',
      );
      expect(customBlockLookToJson(look), look.toJson());
    });

    test('最少的写法：只有名字', () {
      final l = customBlockLookFromJson({'name': 'f'})!;
      expect(l, const CustomBlockLook('f'));
      expect(l.shape, CustomBlockShape.auto);
      expect(l.colorKey, 'custom');
      expect(jsonEncode(l.toJson()), '{"name":"f","shape":"auto","template":"","colorKey":"custom","slots":[]}');
    });

    test('坏数据不崩：不是对象、没名字的整条不要', () {
      for (final bad in [
        null,
        1,
        'x',
        true,
        <Object?>[],
        <String, Object?>{},
        {'name': 3},
        {'name': ''},
        {'name': '  '},
      ]) {
        expect(customBlockLookFromJson(bad), isNull, reason: '$bad');
      }
    });

    test('坏数据不崩：字段类型不对当默认值，坏的槽逐条跳过', () {
      final l = customBlockLookFromJson({
        'name': 'f',
        'shape': 7,
        'template': ['x'],
        'colorKey': {'a': 1},
        'hint': 3,
        'slots': [
          1,
          null,
          'x',
          {'name': 5},
          {'name': ''},
          {
            'name': 'a',
            'kind': '没有这种',
            'options': 'x',
            'defaultValue': [1],
          },
          {'name': 'a', 'kind': 'boolean'},
          {
            'name': 'b',
            'kind': 'choice',
            'options': ['x', 3, null, 'x', 'y'],
            'defaultValue': double.nan,
          },
          {
            'name': 'c',
            'kind': 9,
            'defaultValue': {'k': 1},
          },
        ],
        '以后加的字段': {'x': 1},
      })!;
      expect(l.shape, CustomBlockShape.auto);
      expect(l.template, '');
      expect(l.colorKey, 'custom');
      expect(l.hint, '');
      expect(l.slots, const [
        CustomBlockSlot('a'),
        CustomBlockSlot('b', kind: CustomSlotKind.choice, options: ['x', 'y']),
        CustomBlockSlot('c'),
      ]);
      expect(customBlockLookFromJson({'name': 'f', 'slots': 'x', 'shape': '没有这种'}), const CustomBlockLook('f'));
    });

    test('一组外观：不是列表得空，坏的跳过，同名只留第一个', () {
      expect(customBlockLooksFromJson(null), isEmpty);
      expect(customBlockLooksFromJson({'name': 'f'}), isEmpty);
      final list = customBlockLooksFromJson([
        {'name': 'f', 'hint': '一'},
        3,
        {'name': 'g'},
        {'name': 'f', 'hint': '二'},
        {'nome': 'x'},
      ]);
      expect([for (final l in list) l.name], ['f', 'g']);
      expect(list.first.hint, '一');
    });

    test('槽太多、选项太多：截掉', () {
      final l = customBlockLookFromJson({
        'name': 'f',
        'slots': [
          for (var i = 0; i < 50; i++) {'name': 'p$i'},
          {
            'name': 'x',
            'kind': 'choice',
            'options': [for (var i = 0; i < 100; i++) 'o$i'],
          },
        ],
      })!;
      expect(l.slots.length, kCustomBlockMaxSlots);
      final one = customBlockLookFromJson({
        'name': 'f',
        'slots': [
          {
            'name': 'x',
            'kind': 'choice',
            'options': [for (var i = 0; i < 100; i++) 'o$i'],
          },
        ],
      })!;
      expect(one.slots.single.options.length, kCustomBlockMaxOptions);
    });

    test('第 3 阶段的形状和口：读得进、写得出（只是校验说还不能用）', () {
      final l = customBlockLookFromJson({
        'name': 'f',
        'shape': 'hat',
        'slots': [
          {'name': 'a', 'kind': 'callbackMouth'},
          {'name': 'b', 'kind': 'inlineMouth'},
        ],
      })!;
      expect(l.shape, CustomBlockShape.hat);
      expect([for (final s in l.slots) s.kind], [CustomSlotKind.callbackMouth, CustomSlotKind.inlineMouth]);
      expect(customBlockLookFromJson(l.toJson()), l);
    });
  });

  group('校验', () {
    List<String> codes(CustomBlockLook l, List<String> params, {bool? hasValue}) => [for (final p in validateLook(l, params, hasValue: hasValue)) p.code];

    test('对得上：没问题', () {
      expect(validateLook(const CustomBlockLook('问好'), ['a', 'b']), isEmpty);
      expect(validateLook(const CustomBlockLook('问好', template: '向 {b} 说 {a}'), ['a', 'b']), isEmpty);
      expect(validateLook(const CustomBlockLook('无参'), []), isEmpty);
      expect(
        validateLook(
          const CustomBlockLook(
            'f',
            template: '{a} 用 {b} 吗 {c}',
            slots: [
              CustomBlockSlot('b', kind: CustomSlotKind.choice, options: ['x', 'y'], defaultValue: 'y'),
              CustomBlockSlot('c', kind: CustomSlotKind.boolean, defaultValue: true),
            ],
          ),
          ['a', 'b', 'c'],
        ),
        isEmpty,
      );
    });

    test('B01 没名字（手搭的对象才会有）', () {
      expect(codes(const CustomBlockLook(' ', template: '做事'), []), ['B01']);
    });

    test('B02 模板里的槽不是参数；B03 参数没有槽；B04 一个参数出现两次', () {
      expect(codes(const CustomBlockLook('f', template: '做 {x}'), []), ['B02']);
      expect(codes(const CustomBlockLook('f', template: '做事'), ['a']), ['B03']);
      expect(codes(const CustomBlockLook('f', template: '{a} 加 {a}'), ['a']), ['B04']);
      final ps = validateLook(const CustomBlockLook('f', template: '做 {x}'), ['a']);
      expect([for (final p in ps) '${p.code}:${p.slot}'], ['B02:x', 'B03:a']);
      expect(ps.every((p) => p.isError), isTrue);
    });

    test('B05 槽表和参数对不上', () {
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('没有的')]), []), ['B05']);
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('a'), CustomBlockSlot('a')]), ['a']), ['B05']);
    });

    test('B06 下拉没有选项 / 选项重复；B07 先放的内容对不上', () {
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('a', kind: CustomSlotKind.choice)]), ['a']), ['B06']);
      expect(
        codes(
          const CustomBlockLook(
            'f',
            slots: [
              CustomBlockSlot('a', kind: CustomSlotKind.choice, options: ['x', 'x']),
            ],
          ),
          ['a'],
        ),
        ['B06'],
      );
      expect(
        codes(
          const CustomBlockLook(
            'f',
            slots: [
              CustomBlockSlot('a', kind: CustomSlotKind.choice, options: ['x'], defaultValue: 'y'),
            ],
          ),
          ['a'],
        ),
        ['B07'],
      );
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('a', kind: CustomSlotKind.boolean, defaultValue: 1)]), ['a']), ['B07']);
    });

    test('B08 第 3 阶段才有的外观', () {
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.cap), []), ['B08']);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.hat), []), ['B08']);
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('a', kind: CustomSlotKind.inlineMouth)]), ['a']), ['B08']);
      expect(codes(const CustomBlockLook('f', slots: [CustomBlockSlot('a', kind: CustomSlotKind.callbackMouth)]), ['a']), ['B08']);
    });

    test('B09 警告：只有槽没有字；形状和定义对不上', () {
      final ps = validateLook(const CustomBlockLook('f', template: '{a} {b}'), ['a', 'b']);
      expect([for (final p in ps) p.code], ['B09']);
      expect(ps.single.isError, isFalse);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.value), [], hasValue: false), ['B09']);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.boolean), [], hasValue: false), ['B09']);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.statement), [], hasValue: true), ['B09']);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.value), [], hasValue: true), isEmpty);
      expect(codes(const CustomBlockLook('f'), [], hasValue: true), isEmpty);
      expect(codes(const CustomBlockLook('f', shape: CustomBlockShape.value), []), isEmpty);
    });

    test('形状“自动”按定义选', () {
      expect(resolveLookShape(CustomBlockShape.auto, hasValue: false), CustomBlockShape.statement);
      expect(resolveLookShape(CustomBlockShape.auto, hasValue: true), CustomBlockShape.value);
      expect(resolveLookShape(CustomBlockShape.auto, hasValue: true, returnsBool: true), CustomBlockShape.boolean);
      expect(resolveLookShape(CustomBlockShape.auto, hasValue: false, returnsBool: true), CustomBlockShape.statement);
      expect(resolveLookShape(CustomBlockShape.value, hasValue: false), CustomBlockShape.value);
    });
  });

  group('改参数联动：按位置的实参', () {
    const a = LParam('a'), b = LParam('b'), c = LParam('c');
    const d1 = LParam('d', defaultValue: LLit(1));
    const e2 = LParam('e', defaultValue: LLit(2));
    const rest = LParam('xs', rest: true);
    String fill(LParam p) => '<${p.name}>';
    RemapResult<String> run(List<LParam> o, List<LParam> n, List<int?> origin, List<String> args) => remapCallArgs(oldParams: o, newParams: n, origin: origin, args: args, fill: fill);
    List<String> dropped(RemapResult<String> r) => [for (final d in r.dropped) '${d.param}=${d.value}'];

    test('什么都没变', () {
      final r = run([a, b], [a, b], [0, 1], ['1', '2']);
      expect(r.args, ['1', '2']);
      expect(r.dropped, isEmpty);
    });

    test('加一个：填默认内容', () {
      expect(run([a], [a, b], [0, null], ['1']).args, ['1', '<b>']);
      expect(run([a], [b, a], [null, 0], ['1']).args, ['<b>', '1']);
    });

    test('删一个：内容进清单', () {
      final r = run([a, b, c], [a, c], [0, 2], ['1', '2', '3']);
      expect(r.args, ['1', '3']);
      expect(dropped(r), ['b=2']);
    });

    test('改名：内容跟着走，不丢', () {
      final r = run([a, b], [const LParam('甲'), b], [0, 1], ['1', '2']);
      expect(r.args, ['1', '2']);
      expect(r.dropped, isEmpty);
    });

    test('换顺序', () {
      final r = run([a, b, c], [c, a, b], [2, 0, 1], ['1', '2', '3']);
      expect(r.args, ['3', '1', '2']);
      expect(r.dropped, isEmpty);
    });

    test('一起来：删 b、加 d、a 和 c 对调并改名', () {
      final r = run([a, b, c], [const LParam('丙'), const LParam('d'), const LParam('甲')], [2, null, 0], ['1', '2', '3']);
      expect(r.args, ['3', '<d>', '1']);
      expect(dropped(r), ['b=2']);
    });

    test('少给的有默认值的参数：还在最后就照旧不给，中间空出来的补上', () {
      expect(run([a, d1, e2], [a, d1, e2], [0, 1, 2], ['1']).args, ['1']);
      expect(run([a, d1, e2], [a, e2, d1], [0, 2, 1], ['1', '9']).args, ['1', '<e>', '9']);
      expect(run([a, d1], [d1, a], [1, 0], ['1']).args, ['<d>', '1']);
      // 少给的那个不再有默认值了：补上
      expect(run([a, d1], [a, const LParam('d')], [0, 1], ['1']).args, ['1', '<d>']);
    });

    test('“剩下的全收”', () {
      expect(run([a, rest], [a, rest], [0, 1], ['1', '2', '3']).args, ['1', '2', '3']);
      expect(run([a, rest], [b, a, rest], [null, 0, 1], ['1', '2', '3']).args, ['<b>', '1', '2', '3']);
      final gone = run([a, rest], [a], [0], ['1', '2', '3']);
      expect(gone.args, ['1']);
      expect(dropped(gone), ['xs=2', 'xs=3']);
      final plain = run([a, rest], [a, const LParam('xs')], [0, 1], ['1', '2', '3']);
      expect(plain.args, ['1', '2']);
      expect(dropped(plain), ['xs=3']);
      expect(run([a, rest], [a, const LParam('xs')], [0, 1], ['1']).args, ['1', '<xs>']);
      expect(run([a, b], [a, const LParam('b', rest: true)], [0, 1], ['1', '2']).args, ['1', '2']);
      expect(run([a], [a, rest], [0, null], ['1']).args, ['1']);
      // 全收的收到了东西：前面靠默认值没给的也要补出来
      expect(run([rest], [d1, rest], [null, 0], ['7', '8']).args, ['<d>', '7', '8']);
      expect(run([d1, rest], [d1, rest], [0, 1], <String>[]).args, isEmpty);
    });

    test('坏输入不崩：origin 短了、越界、重复；实参多了', () {
      expect(run([a], [a, b], [0], ['1']).args, ['1', '<b>']);
      expect(run([a], [a, b], [0, 9], ['1']).args, ['1', '<b>']);
      expect(run([a], [a, b], [0, -1], ['1']).args, ['1', '<b>']);
      expect(run([a], [a, b], [0, 0], ['1']).args, ['1', '<b>']);
      final extra = run([a], [a], [0], ['1', '2']);
      expect(extra.args, ['1']);
      expect(dropped(extra), ['=2']);
      expect(run([], [], [], <String>[]).args, isEmpty);
    });

    test('只按名字认', () {
      expect(paramOriginsByName([a, b, c], [c, const LParam('新'), a]), [2, null, 0]);
      expect(paramOriginsByName([a], [a, a]), [0, null]);
    });
  });

  group('改参数联动：按槽名的实参、外观', () {
    const a = LParam('a'), b = LParam('b'), c = LParam('c');

    test('按槽名：改名、新加、删掉', () {
      final r = remapCallArgsByName<int>(oldParams: [a, b, c], newParams: [const LParam('丙'), const LParam('d'), a], origin: [2, null, 0], args: {'a': 1, 'b': 2, 'c': 3, '多的': 4}, fill: (_) => 0);
      expect({for (final e in r.args) e.key: e.value}, {'丙': 3, 'd': 0, 'a': 1});
      expect([for (final e in r.args) e.key], ['丙', 'd', 'a']);
      expect([for (final d in r.dropped) '${d.param}=${d.value.value}'], ['b=2', '多的=4']);
      // 原来就没填的：补上
      final miss = remapCallArgsByName<int>(oldParams: [a], newParams: [a], origin: [0], args: {}, fill: (_) => 7);
      expect(miss.args.single.value, 7);
    });

    test('外观：改名、删掉、新加、换顺序', () {
      const look = CustomBlockLook(
        '搬',
        template: '把 {a} 从 {b} 搬到 {c}',
        slots: [
          CustomBlockSlot('a', defaultValue: 1),
          CustomBlockSlot('b', kind: CustomSlotKind.choice, options: ['x']),
        ],
      );
      final renamed = remapLook(look, oldParams: [a, b, c], newParams: [const LParam('东西'), b, c], origin: [0, 1, 2]);
      expect(renamed.template, '把 {东西} 从 {b} 搬到 {c}');
      expect(renamed.slots.first, const CustomBlockSlot('东西', defaultValue: 1));
      expect(validateLook(renamed, ['东西', 'b', 'c']), isEmpty);

      final removed = remapLook(look, oldParams: [a, b, c], newParams: [a, c], origin: [0, 2]);
      expect(removed.template, '把 {a} 从 搬到 {c}');
      expect([for (final s in removed.slots) s.name], ['a']);
      expect(validateLook(removed, ['a', 'c']), isEmpty);

      final added = remapLook(look, oldParams: [a, b, c], newParams: [a, b, c, const LParam('d')], origin: [0, 1, 2, null]);
      expect(added.template, '把 {a} 从 {b} 搬到 {c} {d}');
      expect(validateLook(added, ['a', 'b', 'c', 'd']), isEmpty);

      final moved = remapLook(look, oldParams: [a, b, c], newParams: [c, b, a], origin: [2, 1, 0]);
      expect(moved, look);

      // a、b 对调名字
      final swapped = remapLook(look, oldParams: [a, b, c], newParams: [const LParam('b'), const LParam('a'), c], origin: [0, 1, 2]);
      expect(swapped.template, '把 {b} 从 {a} 搬到 {c}');
      expect([for (final s in swapped.slots) '${s.name}:${s.kind.name}'], ['b:value', 'a:choice']);
    });

    test('外观：没写模板的一直不写；本来就对不上的槽不替用户删', () {
      const plain = CustomBlockLook('f');
      expect(remapLook(plain, oldParams: [a], newParams: [a, b], origin: [0, null]).template, '');
      const odd = CustomBlockLook('f', template: '{a} 和 {没有的}');
      expect(remapLook(odd, oldParams: [a], newParams: [b], origin: [0]).template, '{b} 和 {没有的}');
    });
  });
}
