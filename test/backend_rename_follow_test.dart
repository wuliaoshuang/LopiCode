// 改名时用到它的积木跟着改（全量）、“用了几处”和“删积木时删调用”数全（积木第 5 版·库 2 收尾）。
//   flutter test --no-pub test/backend_rename_follow_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_core_edit.dart';
import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/user_libs.dart';

/// 两个记录都有字段“名”，两个类都有方法“叫”（狗继承动物并改写；机器是不相干的类）。
J zoo() => coreDoc(
  '改名',
  types: [
    typeDef('t1', 'record', '人', fields: [field('名', tText), field('岁', tInt)]),
    typeDef('t2', 'record', '城', fields: [field('名', tText)]),
    typeDef(
      't3',
      'class',
      '动物',
      open: true,
      methods: [
        method('m1', '叫', [], [ret(tx('…'))], returns: tText),
      ],
    ),
    typeDef(
      't4',
      'class',
      '狗',
      parent: '动物',
      methods: [
        method('m2', '叫', [], [
          ret(
            cat([
              tx('汪'),
              ex('superCall', {'name': '叫', 'args': <J>[]}),
            ]),
          ),
        ], returns: tText),
      ],
    ),
    typeDef(
      't5',
      'class',
      '机器',
      methods: [
        method('m3', '叫', [], [ret(tx('哔'))], returns: tText),
      ],
    ),
  ],
  globals: [
    {'name': 'total', 'init': nm(0), 'type': tInt},
  ],
  functions: [
    tfn('f1', '加一', [], [setv('total', op2('+', vr('total'), nm(1)))]),
    tfn('f2', '自己的', [], [
      let('total', nm(5)),
      say([vr('total')]),
    ]),
  ],
  main: [
    konst(
      'p',
      ex('recNew', {
        'type': '人',
        'fields': [pair('名', tx('甲')), pair('岁', nm(3))],
      }),
    ),
    konst(
      'c',
      ex('recNew', {
        'type': '城',
        'fields': [pair('名', tx('乙'))],
      }),
    ),
    say([getF(vr('p'), '名'), getF(vr('c'), '名')]),
    konst('d', newObj('狗')),
    konst('r', newObj('机器')),
    say([send(vr('d'), '叫'), send(vr('r'), '叫')]),
    sendS(vr('d'), '叫'),
    callS('f1'),
    say([vr('total')]),
  ],
);

List<String> errors(BeDocument doc) => [
  for (final i in validateBackend(doc))
    if (i.isError) i.message,
];

void main() {
  test('样例本身没有标红', () => expect(errors(parseLangBlocksDocument(zoo())), isEmpty));

  test('字段改名：别的类型有同名字段，只改对象是这个类型的那几处', () {
    final doc = parseLangBlocksDocument(zoo());
    expect(beRenameField(doc, 't1', '名', '姓名'), isNull);
    final text = jsonEncode(doc.toJson());
    expect(text, contains('"of":{"e":"var","name":"p"},"name":"姓名"'), reason: '人的那一处跟着改了');
    expect(text, contains('"of":{"e":"var","name":"c"},"name":"名"'), reason: '城的那一处没动');
    expect(errors(doc), isEmpty, reason: '改完不标红');
  });

  test('方法改名：改写它的子类一起改，“让上一层做”跟着改；不相干的类的同名方法不动', () {
    final doc = parseLangBlocksDocument(zoo());
    expect(beRenameMethod(doc, 'm1', '出声'), isNull);
    expect(doc.core.type('t4')!.methods.single.name, '出声', reason: '子类里改写的那个一起改名');
    expect(doc.core.type('t5')!.methods.single.name, '叫', reason: '不相干的类不动');
    final text = jsonEncode(doc.toJson());
    expect(text, contains('"e":"superCall","name":"出声"'));
    expect(text, contains('"of":{"e":"var","name":"d"},"name":"出声"'));
    expect(text, contains('"of":{"e":"var","name":"r"},"name":"叫"'));
    expect(errors(doc), isEmpty, reason: '改完不标红');
    expect(beRenameMethod(doc, 'm2', '出声'), isNull, reason: '没变');
  });

  test('模块顶上的变量改名：读写它的地方跟着改；自己新建了同名变量的那一串不动', () {
    final doc = parseLangBlocksDocument(zoo());
    expect(beRenameGlobal(doc, 'total', 'sum'), isNull);
    final f1 = jsonEncode(doc.functions[0].toJson()), f2 = jsonEncode(doc.functions[1].toJson());
    expect(f1, isNot(contains('total')));
    expect(f1, contains('"name":"sum"'));
    expect(f2, contains('total'), reason: '这一串里的 total 是它自己新建的');
    expect(f2, isNot(contains('sum')));
    expect(jsonEncode(doc.core.main!.toJson()), contains('"e":"var","name":"sum"'));
    expect(errors(doc), isEmpty, reason: '改完不标红');
  });

  test('“用了几处”和删积木：也数“程序开始时”、方法里、库积木帽子串里的用法', () {
    final doc = parseLangBlocksDocument({
      ...zoo(),
      'core': {
        ...(zoo()['core'] as J),
        'main': {
          'body': [
            callS('f1'),
            say([vr('total')]),
          ],
        },
        'types': [
          typeDef(
            't3',
            'class',
            '动物',
            methods: [
              method('m1', '叫', [], [callS('f1'), ret(tx('…'))], returns: tText),
            ],
          ),
        ],
      },
    });
    expect(beFunctionUses(doc, 'f1'), 2, reason: '“程序开始时”一处、方法里一处');
    expect(beRemoveFunction(doc, 'f1'), isTrue);
    expect(jsonEncode(doc.toJson()), isNot(contains('call:f1')), reason: '两处调用都一起拿掉了');

    final withHat = parseLangBlocksDocument({
      ...flowUserDoc(),
      'functions': [
        tfn('f9', '帮手', [], [
          say([tx('帮')]),
        ]),
      ],
      'hats': [
        hat('h1', kLibFlow, 'onStart', {'名字': '甲'}, [callS('f9')]),
      ],
    });
    expect(beFunctionUses(withHat, 'f9'), 1, reason: '帽子串里的也算');
    expect(beFunctionUsedInCore(withHat, 'f9'), isTrue);
  });

  test('库积木：用的文档记的是库标识＋积木编号，库里改名字、改积木上的字都不用跟着改；换库标识用“换用法”', () {
    final doc = parseLangBlocksDocument(flowUserDoc());
    final before = jsonEncode(doc.toJson());
    final switched = beLibSwitchUses(doc, kLibFlow, 'shuang/flow2');
    expect(switched, isNotNull);
    expect(switched!.count, greaterThan(0));
    final after = jsonEncode(switched.doc.toJson());
    expect(after, isNot(contains('lib:$kLibFlow#')));
    expect(after.replaceAll('shuang/flow2', kLibFlow), before);
  });

  test('类型改名：新建、父类、字段和参数的类型都跟着改；积木改名：调用按编号认，不用动', () {
    final doc = parseLangBlocksDocument(zoo());
    expect(beRenameType(doc, 't3', '生物'), isNull);
    expect(doc.core.type('t4')!.parent, '生物');
    expect(beRenameType(doc, 't1', '住户'), isNull);
    expect(jsonEncode(doc.core.main!.toJson()), contains('"type":"住户"'));
    doc.functions[0].look = doc.functions[0].look.copyWith(name: '多一个');
    expect(beFunctionUses(doc, 'f1'), 1);
    expect(errors(doc), isEmpty, reason: '改完不标红');
  });
}
