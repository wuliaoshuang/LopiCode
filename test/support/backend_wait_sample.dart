// “要等的事”十块积木的样例文档（核心 3）：一个接口里都用一遍，结果拼成一行字回出去。
// backend_wait_blocks_test.dart（五种语言开服务真跑）和 theme_wait_smoke_test.dart（十套主题摆一遍）共用。
import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';

J sleep(num ms) => blk('sleep', {'ms': nm(ms)});
J spawnOf(J x) => ex('spawnOf', {'x': x});
J await_(J x) => ex('await', {'x': x});
J slow(num n, num ms) => call('f1', {'n': nm(n), 'ms': nm(ms)});

J waitSlowFn() => tfn(
  'f1',
  '慢慢翻倍',
  [tpar('n', tInt), tpar('ms', tInt)],
  [
    sleep(1),
    blk('sleep', {'ms': pm('ms')}),
    ret(op2('*', pm('n'), nm(2))),
  ],
  returns: tInt,
);

/// 一个接口里把十块都用一遍，结果拼成一行字回出去（开着服务，五种语言回的要一个字不差）。
J waitSampleDoc() => {
  ...coreDoc('要等的事', functions: [waitSlowFn()], main: [sleep(1)]),
  'routes': [
    route('r1', 'GET', '/go', [
      konst('t', spawnOf(slow(21, 300))),
      blk('spawn', {'name': 'b'}, [sleep(60)]),
      konst('a', await_(vr('t'))),
      blk('do', {'value': await_(vr('b'))}),
      let('m', tx('没超时')),
      tryB(
        [
          blk('do', {
            'value': ex('awaitMax', {'x': spawnOf(slow(5, 900)), 'ms': nm(100)}),
          }),
        ],
        [
          catchArm('超时', 'e', [setv('m', getF(vr('e'), '消息'))]),
        ],
      ),
      konst(
        'all',
        ex('awaitAll', {
          'list': ls([spawnOf(slow(1, 120)), spawnOf(slow(2, 20))]),
        }),
      ),
      konst(
        'any',
        ex('awaitAny', {
          'list': ls([spawnOf(slow(3, 700)), spawnOf(slow(4, 30))]),
        }),
      ),
      konst('c', spawnOf(slow(9, 2000))),
      sleep(50),
      blk('cancel', {'x': vr('c')}),
      let('k', tx('没取消')),
      tryB(
        [
          blk('do', {'value': await_(vr('c'))}),
        ],
        [
          catchArm('取消了', 'e', [setv('k', getF(vr('e'), '消息'))]),
        ],
      ),
      let('in', tx('没进去')),
      blk('critical', {'name': tx('账')}, [setv('in', tx('在里面'))]),
      blk('spawn', {'name': ''}, [sleep(5)]),
      text(cat([vr('a'), tx('｜'), vr('m'), tx('｜'), vr('all'), tx('｜'), vr('any'), tx('｜'), vr('k'), tx('｜'), ex('cancelled'), tx('｜'), vr('in')])),
    ]),
  ],
};

const String kWaitSampleWant = '42｜等了 100 毫秒还没做完｜[2,4]｜8｜这件事被取消了｜false｜在里面';
