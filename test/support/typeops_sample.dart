// 类型积木的样例：三块（看是哪一类值、当成某类型用、标上类型）在一个接口 / 一顶帽子里都用一遍，结果拼成一行字。
// backend_typeops_blocks_test.dart（五种后端语言）和 lowcode_front_typeops_test.dart（三种网页）共用，两边要的是同一行字。
import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/lang/types.dart';

import 'backend_core_samples.dart';
import 'backend_lang_blocks.dart';

J castTo(J x, LType to) => ex(kBeCast, {'x': x, 'to': beTypeKey(to)});
J ascribe(J x, LType to) => ex(kBeAscribe, {'x': x, 'to': beTypeKey(to)});
J isType(J x, String type) => ex('isType', {'x': x, 'type': type});

J typeOpsCard() => typeDef('t1', 'record', '名片', fields: [field('名字', tText)]);

/// 那几句积木：最后 `out` 里是要的那一行字。
List<J> typeOpsBody() => [
  konst('v', ascribe(tx('好'), LType.any)),
  konst('s', castTo(vr('v'), LType.text)),
  konst('xs', castTo(ascribe(ls([nm(1), nm(2)]), LType.any), const LType.listOf(LType.integer))),
  konst(
    'c',
    ascribe(
      ex('recNew', {
        'type': '名片',
        'fields': [pair('名字', tx('霜霜'))],
      }),
      const LType.ref('名片'),
    ),
  ),
  let('m', tx('没出错')),
  tryB(
    [
      konst('k', castTo(vr('v'), LType.integer)),
      setv('m', cat([tx('成了 '), vr('k')])),
    ],
    [
      catchArm('类型不对', 'e', [setv('m', tx('当不成整数'))]),
    ],
  ),
  konst('out', cat([vr('s'), tx('｜'), isType(vr('v'), 'text'), tx('｜'), isType(vr('v'), 'number'), tx('｜'), vr('xs'), tx('｜'), getF(vr('c'), '名字'), tx('｜'), vr('m')])),
];

const String kTypeOpsWant = '好｜true｜false｜[1,2]｜霜霜｜当不成整数';

J typeOpsDoc() => {
  ...coreDoc('类型积木', types: [typeOpsCard()], main: const []),
  'routes': [
    route('r1', 'GET', '/go', [...typeOpsBody(), text(vr('out'))]),
  ],
};
