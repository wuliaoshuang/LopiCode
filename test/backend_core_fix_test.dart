// 核心 2 的一键修（积木第 5 版·A3）：每一种，点了以后那条标红没了、文档是对的；撤销回来、重做过去都成立。
// 不搭界面：直接用后端积木页的宿主（界面上点小卡里的按钮，走的就是这里的 action）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_model.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';

BeBlockHost hostOf(J doc) => BeBlockHost(doc: parseLangBlocksDocument(doc));

String dump(BeBlockHost h) => [
  for (final i in h.issues) '${i.rule}${i.isError ? '!' : ''} ${i.problem} → ${[for (final a in i.actions) a.label]}',
].join('\n');

/// 找到带这个修法的那条问题，点它；返回点之前那条问题说的话。
String press(BeBlockHost h, Pattern label) {
  for (final i in h.issues) {
    for (final a in i.actions) {
      if (a.label.contains(label)) {
        a.run();
        return i.problem;
      }
    }
  }
  fail('没有找到修法「$label」。现在的问题：\n${dump(h)}');
}

/// 点一种修法：那条问题没了；撤销回来又有了；重做又没了。返回修好以后的文档。
BeDocument fixed(BeBlockHost h, Pattern label, {bool clean = true}) {
  final before = h.doc.encode();
  final said = press(h, label);
  bool still() => h.issues.any((i) => (i.problem) == said);
  expect(still(), isFalse, reason: '点了以后这条应该没了：$said\n${dump(h)}');
  if (clean) {
    expect(
      [
        for (final i in h.issues)
          if (i.isError) i.problem,
      ],
      isEmpty,
      reason: '修完不该还有标红',
    );
  }
  final after = h.doc.encode();
  expect(after, isNot(before));
  h.undo();
  expect(h.doc.encode(), before, reason: '撤销回到点之前');
  expect(still(), isTrue);
  h.redo();
  expect(h.doc.encode(), after, reason: '重做回到点之后');
  return h.doc;
}

final J _color = typeDef('t1', 'enum', '颜色', cases: [kase('红'), kase('绿'), kase('蓝')]);
final J _point = typeDef('t1', 'record', '点', fields: [field('x', tInt), field('y', tInt)]);
J _red() => ex('enumVal', {'type': '颜色', 'case': '红'});

void main() {
  group('第一轮点不了的 5 种', () {
    J matching() => coreDoc(
      '修',
      types: [_color],
      main: [
        match(_red(), [
          caseArm('红', '', [log(tx('红'))]),
        ]),
      ],
    );

    test('补上漏掉的情况', () {
      final d = fixed(hostOf(matching()), '补上');
      expect([for (final a in d.core.main!.body.single.arms) a.args['case']], ['红', '绿', '蓝']);
    });

    test('加“其他情况”', () {
      final d = fixed(hostOf(matching()), '其他情况');
      expect(d.core.main!.body.single.noElse, isFalse);
      expect(d.core.main!.body.single.arms, hasLength(1));
    });

    test('补缺字段', () {
      final h = hostOf(
        coreDoc(
          '修',
          types: [_point],
          main: [
            let(
              'p',
              ex('recNew', {
                'type': '点',
                'fields': [pair('x', nm(1))],
              }),
            ),
            log(getF(vr('p'), 'x')),
          ],
        ),
      );
      final d = fixed(h, '补上');
      final fields = (d.core.main!.body.first.args['value'] as Map)['fields'] as List;
      expect([for (final f in fields) (f as Map)['key']], ['x', 'y']);
    });

    test('去多余字段', () {
      final h = hostOf(
        coreDoc(
          '修',
          types: [_point],
          main: [
            let(
              'p',
              ex('recNew', {
                'type': '点',
                'fields': [pair('x', nm(1)), pair('y', nm(2)), pair('z', nm(3))],
              }),
            ),
            log(getF(vr('p'), 'x')),
          ],
        ),
      );
      final d = fixed(h, '删掉「z」');
      final fields = (d.core.main!.body.first.args['value'] as Map)['fields'] as List;
      expect([for (final f in fields) (f as Map)['key']], ['x', 'y']);
    });

    test('改成“复制并改”', () {
      final h = hostOf(
        coreDoc(
          '修',
          types: [_point],
          main: [
            let(
              'p',
              ex('recNew', {
                'type': '点',
                'fields': [pair('x', nm(1)), pair('y', nm(2))],
              }),
            ),
            setF(vr('p'), 'x', nm(5)),
            log(getF(vr('p'), 'x')),
          ],
        ),
      );
      final d = fixed(h, '复制并改');
      final b = d.core.main!.body[1];
      expect(b.op, 'setVar');
      expect(b.args['name'], 'p');
      expect((b.args['value'] as Map)['e'], 'recCopy');
    });
  });

  group('另加的', () {
    test('把错误当文字用 → 读它的消息', () {
      final h = hostOf(
        coreDoc(
          '修',
          functions: [
            tfn('f1', '喊', [tpar('话', tText)], [ret(pm('话'))], returns: tText),
          ],
          main: [
            tryB(
              [thro(tx('坏了'))],
              [
                catchArm('@any', 'e', [
                  log(call('f1', {'话': vr('e')})),
                ]),
              ],
            ),
          ],
        ),
      );
      final d = fixed(h, '读它的消息');
      final arg = ((d.core.main!.body.single.arms.single.body.single.args['value'] as Map)['话'] as Map);
      expect(arg['e'], 'getField');
      expect(arg['name'], '消息');
    });

    test('数值约束不对（要的是数字，放进来的是文字）→ 变成数字', () {
      final h = hostOf(
        coreDoc(
          '修',
          main: [
            let('s', tx('12')),
            log(ex('math', {'x': vr('s'), 'fn': 'abs'})),
          ],
        ),
      );
      final d = fixed(h, '变成数字', clean: false);
      expect(((d.core.main!.body.last.args['value'] as Map)['x'] as Map)['e'], 'convert');
    });
  });

  group('类', () {
    J animal({bool open = true, List<J> dogCtor = const [], bool withCtor = true, List<String> interfaces = const [], List<J> extra = const []}) => coreDoc(
      '修',
      types: [
        typeDef(
          't1',
          'class',
          '动物',
          open: open,
          fields: [field('名字', tText)],
          ctor: method('m1', '创建时', [tpar('name', tText)], [setF(me(), '名字', pm('name'))]),
          methods: [
            method('m2', '叫', [tpar('times', tInt, def: 1)], [ret(tx('…'))], returns: tText),
          ],
        ),
        typeDef('t2', 'class', '狗', parent: '动物', interfaces: interfaces, ctor: withCtor ? method('m3', '创建时', [tpar('name', tText)], dogCtor) : null),
        ...extra,
      ],
      main: [
        let('d', newObj('狗', [tx('旺财')])),
        log(send(vr('d'), '叫')),
      ],
    );

    test('T27 子类的“创建时”没调父类的 → 在第一句放上', () {
      final d = fixed(hostOf(animal()), '调父类的创建时');
      expect(d.core.typeNamed('狗')!.ctor!.body.first.op, 'superInit');
    });

    test('T27 “调父类的创建时”不在第一句 → 挪到第一句', () {
      final h = hostOf(
        animal(
          dogCtor: [
            log(tx('先说一句')),
            blk('superInit', {
              'args': [pm('name')],
            }),
          ],
        ),
      );
      final d = fixed(h, '挪到第一句');
      expect([for (final b in d.core.typeNamed('狗')!.ctor!.body) b.op], ['superInit', 'log']);
    });

    test('父类没勾“可以被继承” → 勾上', () {
      final h = hostOf(
        animal(
          open: false,
          dogCtor: [
            blk('superInit', {
              'args': [pm('name')],
            }),
          ],
        ),
      );
      final d = fixed(h, '可以被继承');
      expect(d.core.typeNamed('动物')!.isOpen, isTrue);
    });

    test('接口要的方法没有 → 加上这个方法（签名照抄，连默认值）', () {
      final h = hostOf(
        animal(
          interfaces: ['会跑'],
          dogCtor: [
            blk('superInit', {
              'args': [pm('name')],
            }),
          ],
          extra: [
            typeDef(
              't3',
              'interface',
              '会跑',
              methods: [
                method('m9', '跑', [tpar('米', tInt, def: 100)], const [], returns: tText),
              ],
            ),
          ],
        ),
      );
      final d = fixed(h, '加上这个方法', clean: false);
      final m = d.core.typeNamed('狗')!.methods.single;
      expect(m.name, '跑');
      expect(m.params.single.name, '米');
      expect(m.params.single.defaultValue, 100);
      expect(m.returns?.show(), '文字');
    });
  });

  group('错误和模块', () {
    test('T21 这一节永远轮不到 → 删掉这一节', () {
      final h = hostOf(
        coreDoc(
          '修',
          main: [
            tryB(
              [thro(tx('坏了'))],
              [
                catchArm('@any', 'e', [log(tx('甲'))]),
                catchArm('找不到', 'e', [log(tx('乙'))]),
              ],
            ),
          ],
        ),
      );
      final d = fixed(h, '删掉这一节');
      expect(d.core.main!.body.single.arms, hasLength(1));
    });

    J shop({List<String> uses = const ['仓库'], List<String> public = const ['f1']}) => coreDoc(
      '修',
      modules: [
        {
          'name': '仓库',
          'owns': ['f1'],
        },
        {'name': '店', 'uses': uses, 'owns': <String>[]},
      ],
      entry: '店',
      public: public,
      functions: [
        tfn('f1', '有几个', [], [ret(nm(3))], returns: tInt),
      ],
      main: [log(call('f1', const {}))],
    );

    test('M05 没说用到了谁 → 勾上', () {
      final d = fixed(hostOf(shop(uses: const [])), '勾上用到了');
      expect(d.core.module('店')!.uses, ['仓库']);
    });

    test('M06 没有公开 → 设成公开', () {
      final d = fixed(hostOf(shop(public: const [])), '设成公开');
      expect(d.core.publics, contains('f1'));
    });
  });

  test('“看是哪种情况”看可空的值没列全（积木层自己查的）→ 补上少的情况', () {
    final h = hostOf(
      coreDoc(
        '修',
        main: [
          match(ex('parseInt', {'s': tx('12')}), [
            caseArm('@some', 'n', [log(vr('n'))]),
          ]),
        ],
      ),
    );
    final d = fixed(h, '补上少的情况');
    expect([for (final a in d.core.main!.body.single.arms) a.args['case']], ['@some', '@null']);
  });
}
