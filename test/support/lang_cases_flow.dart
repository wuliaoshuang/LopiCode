// 语言核心一致性用例（一）：语法树的每一种节点——变量、常量、如果、各种循环、跳出 / 跳过、短路、值版如果、按 x 分情况、下标。
import 'package:lopicode/lang/lang.dart';

import 'lang_conformance.dart';

LExpr _join(List<LExpr> xs) => rt('join', xs);
LExpr _and(LExpr a, LExpr b) => LLogic('and', a, b);
LExpr _or(LExpr a, LExpr b) => LLogic('or', a, b);

final List<LangCase> kLangFlowCases = [
  LangCase(
    '变量、赋值、常量',
    [
      let('x', n(1)),
      set('x', bin('+', v('x'), n(1))),
      log(v('x')),
      let('c', t('常量'), isConst: true),
      log(v('c')),
      // 关键字当名字：加了 v_ 前缀，哪种语言都不撞
      let('class', n(7)),
      let('func', n(8)),
      let('def', n(9)),
      log(_join([v('class'), v('func'), v('def')])),
    ],
    ['2', '常量', '789'],
  ),
  LangCase(
    '没有块级作用域：在“如果”里新建的出来还在，没走到就是空',
    [
      iff(no, [let('y', n(1))]),
      log(rt('isNull', [v('y')])),
      iff(yes, [let('z', n(5))]),
      log(v('z')),
    ],
    ['true', '5'],
  ),
  LangCase(
    '如果 / 否则如果 / 否则',
    [
      LForEach(list([n(1), n(2), n(3), n(4)]), 'i', [
        LIf(
          [
            LIfArm(bin('==', v('i'), n(1)), [log(t('一'))]),
            LIfArm(bin('==', v('i'), n(2)), [log(t('二'))]),
            LIfArm(bin('==', v('i'), n(3)), []),
          ],
          orElse: [log(t('别的'))],
        ),
      ]),
      // 条件不是“是 / 否”：按“算不算是”
      iff(t(''), [log(t('空文字算是？'))], [log(t('空文字算否'))]),
      iff(list(), [log(t('空列表算是'))]),
      iff(n(0), [log(t('0 算是？'))]),
      // 只有注释的一段（Python 要补 pass）
      iff(yes, [const LNote('这里什么都不做')], [const LNote('这里也是')]),
      const LIf([], orElse: [LNote('没有任何一段的如果')]),
      log(t('完')),
    ],
    ['一', '二', '别的', '空文字算否', '空列表算是', '完'],
  ),
  LangCase(
    '当…时重复、一直重复＋跳出',
    [
      let('i', n(0)),
      LWhile(bin('<', v('i'), n(3)), [log(v('i')), set('i', bin('+', v('i'), n(1)))]),
      LWhile(null, [
        set('i', bin('+', v('i'), n(1))),
        iff(bin('>=', v('i'), n(6)), [const LBreak()]),
      ]),
      log(v('i')),
      // 条件一开始就不成立：一遍都不做
      LWhile(no, [log(t('不该出现'))]),
      // 条件是个值（不是比较）：按“算不算是”
      let('left', n(2)),
      LWhile(v('left'), [set('left', bin('-', v('left'), n(1)))]),
      log(v('left')),
    ],
    ['0', '1', '2', '6', '0'],
  ),
  LangCase(
    '从…数到…：含两头、负步长、步长 0、方向不对、小数步长',
    [
      LForCount('i', n(1), n(3), n(1), [log(v('i'))]),
      LForCount('i2', n(3), n(1), n(-1), [log(v('i2'))]),
      LForCount('i3', n(1), n(3), n(0), [log(t('步长 0 不该出现'))]),
      LForCount('i4', n(1), n(3), n(-1), [log(t('方向不对不该出现'))]),
      LForCount('i5', n(3), n(1), n(1), [log(t('方向不对不该出现'))]),
      LForCount('i6', n(0), n(1), n(0.25), [log(v('i6'))]),
      let('count', n(0)),
      LForCount('i7', n(0), n(1), n(0.1), [set('count', bin('+', v('count'), n(1)))]),
      log(_join([t('0 到 1 每次 0.1：'), v('count'), t(' 遍，最后是 '), v('i7')])),
      LForCount('i8', n(1), n(10), n(4), [log(v('i8'))]),
      LForCount('i9', n(5), n(5), n(1), [log(v('i9'))]),
      LForCount('i10', t('2'), t(' 4 '), t('1'), [log(v('i10'))]),
      // 三个数进循环前算好一次：循环里改了也不影响
      let('to', n(3)),
      LForCount('i11', n(1), v('to'), n(1), [set('to', n(10)), log(v('i11'))]),
      LForCount('i12', n(-1), n(-2.5), n(-0.5), [log(v('i12'))]),
    ],
    ['1', '2', '3', '3', '2', '1', '0', '0.25', '0.5', '0.75', '1', '0 到 1 每次 0.1：11 遍，最后是 1', '1', '5', '9', '5', '2', '3', '4', '1', '2', '3', '-1', '-1.5', '-2', '-2.5'],
  ),
  LangCase(
    '对列表的每一项：序号、空列表、不是列表、循环中途改列表',
    [
      LForEach(list([n(10), t('二'), nul]), 'x', index: 'k', [
        log(_join([v('k'), t(':'), v('x')])),
      ]),
      LForEach(list(), 'x2', [log(t('空列表不该出现'))]),
      LForEach(n(5), 'x3', [log(t('不是列表不该出现'))]),
      LForEach(t('abc'), 'x4', [log(t('文字不是列表'))]),
      let('xs', list([n(1), n(2), n(3)])),
      let('seen', n(0)),
      LForEach(v('xs'), 'x5', [
        run(rt('listPush', [v('xs'), v('x5')])),
        set('seen', bin('+', v('seen'), n(1))),
      ]),
      log(
        _join([
          v('seen'),
          t(' 遍，现在 '),
          rt('size', [v('xs')]),
          t(' 项'),
        ]),
      ),
      // 第 3 版后端的做法：每一项赋给一个已有的变量
      let('item', t('起先')),
      LForEach(list([n(1), n(2)]), 'item', reuse: true, []),
      log(v('item')),
    ],
    ['0:10', '1:二', '2:', '3 遍，现在 6 项', '2'],
  ),
  LangCase(
    '对字典的每一对：键按 Unicode 码点从小到大；循环中途改字典',
    [
      LForPairs(dict({'b': n(1), 'a': n(2), '😀': n(3), 'Ａ': n(4), '中': n(5), 'Z': n(6), '10': n(7), '9': n(8)}), 'k', 'val', [
        log(_join([v('k'), t('='), v('val')])),
      ]),
      LForPairs(list([n(1)]), 'k2', 'v2', [log(t('不是字典不该出现'))]),
      LForPairs(dict(), 'k3', 'v3', [log(t('空字典不该出现'))]),
      let('d', dict({'a': n(1), 'b': n(2)})),
      LForPairs(v('d'), 'k4', 'v4', [
        log(_join([v('k4'), t('='), v('v4')])),
        run(rt('dictRemove', [v('d'), t('b')])),
        run(rt('dictSet', [v('d'), t('c'), n(3)])),
      ]),
      logJson(v('d')),
    ],
    ['10=7', '9=8', 'Z=6', 'a=2', 'b=1', '中=5', 'Ａ=4', '😀=3', 'a=1', 'b=', '{"a":1,"c":3}'],
  ),
  LangCase(
    '重复 N 次：小数、负数、文字、封顶 10000',
    [
      let('c', n(0)),
      LRepeat(n(3), [set('c', bin('+', v('c'), n(1)))]),
      log(v('c')),
      LRepeat(n(2.9), [set('c', bin('+', v('c'), n(1)))]),
      log(v('c')),
      LRepeat(n(-1), [log(t('负数不该出现'))]),
      LRepeat(t('2'), [set('c', bin('+', v('c'), n(1)))]),
      log(v('c')),
      set('c', n(0)),
      LRepeat(n(20000), [set('c', bin('+', v('c'), n(1)))]),
      log(v('c')),
    ],
    ['3', '5', '7', '10000'],
  ),
  LangCase(
    '跳出 / 跳过：套着的循环里只管最里面那一层',
    [
      LForCount('i', n(1), n(3), n(1), [
        LForCount('j', n(1), n(3), n(1), [
          iff(bin('==', v('j'), n(2)), [const LContinue()]),
          iff(bin('==', v('i'), n(2)), [const LBreak()]),
          log(_join([v('i'), t('-'), v('j')])),
        ]),
      ]),
      let('w', n(0)),
      LWhile(bin('<', v('w'), n(5)), [
        set('w', bin('+', v('w'), n(1))),
        iff(bin('==', bin('%', v('w'), n(2)), n(0)), [const LContinue()]),
        log(v('w')),
      ]),
      LRepeat(n(5), [log(t('重复里跳出')), const LBreak()]),
      LForEach(list([n(1), n(2), n(3)]), 'e', [
        iff(bin('==', v('e'), n(2)), [const LBreak()]),
        log(v('e')),
      ]),
      LForPairs(dict({'a': n(1), 'b': n(2), 'c': n(3)}), 'k', 'val', [
        iff(bin('==', v('k'), t('b')), [const LContinue()]),
        log(v('k')),
      ]),
      // 跳出后面的语句不会执行，也不会生成（Java 不许有执行不到的语句）
      LWhile(yes, [const LBreak(), log(t('不该出现'))]),
      log(t('完')),
    ],
    ['1-1', '1-3', '3-1', '3-3', '1', '3', '5', '重复里跳出', '1', 'a', 'c', '完'],
  ),
  LangCase(
    '并且 / 或者：短路，结果是“是 / 否”',
    [
      let('ys', list([n(1), n(2)])),
      log(_and(no, rt('listPop', [v('ys')]))),
      log(rt('size', [v('ys')])),
      log(_or(yes, rt('listPop', [v('ys')]))),
      log(rt('size', [v('ys')])),
      log(_and(yes, rt('listPop', [v('ys')]))),
      log(rt('size', [v('ys')])),
      log(_or(no, n(0))),
      log(_and(t('a'), t(''))),
      log(_or(t(''), t('a'))),
      log(_and(_or(no, yes), const LUnary('not', no))),
      // 当条件用：最外面是并且 / 或者、里面套着括号和带括号的文字
      iff(_and(_or(no, t(')(')), const LUnary('not', no)), [log(t('条件成立'))]),
      let('w', n(0)),
      LWhile(_and(bin('<', v('w'), n(2)), _or(yes, no)), [set('w', bin('+', v('w'), n(1)))]),
      LWhile(_or(_and(no, yes), _and(no, t('"('))), [log(t('不该出现'))]),
      // 短路也保护了会抛错的操作
      log(_and(no, rt('listRemove', [v('ys'), n(99)]))),
      logJson(list([_and(yes, yes), _or(no, no)])),
    ],
    ['false', '2', 'true', '2', 'true', '1', 'false', 'false', 'true', 'true', '条件成立', 'false', '[true,false]'],
  ),
  LangCase(
    '值版的“如果”：只算选中的那一边',
    [
      let('ys', list([n(1), n(2)])),
      log(LCond(yes, t('甲'), rt('listPop', [v('ys')]))),
      log(LCond(no, rt('listPop', [v('ys')]), t('乙'))),
      log(rt('size', [v('ys')])),
      log(LCond(n(0), n(1), n(2))),
      log(LCond(t('x'), LCond(no, n(1), n(2)), n(3))),
      log(LCond(bin('>', n(3), n(2)), nul, t('不是'))),
      logJson(LCond(yes, list([n(1)]), dict())),
    ],
    ['甲', '乙', '2', '2', '2', '', '[1]'],
  ),
  LangCase(
    '一元运算：不是、取负',
    [
      log(LUnary('not', n(0))),
      log(LUnary('not', t('x'))),
      log(LUnary('neg', n(5))),
      log(LUnary('neg', n(0))),
      log(LUnary('neg', t('3'))),
      log(LUnary('neg', t('abc'))),
      log(LUnary('neg', LUnary('neg', n(2.5)))),
    ],
    ['true', 'false', '-5', '0', '-3', '0', '2.5'],
  ),
  vals('二元运算：加减乘除余乘方、比较', [
    (bin('+', n(1), n(2)), '3'),
    (bin('+', t('3'), n(4)), '7'),
    (bin('+', n(0.1), n(0.2)), '0.3'),
    (bin('-', n(7), n(10)), '-3'),
    (bin('*', n(3), t('x')), '0'),
    (bin('/', n(7), n(2)), '3.5'),
    (bin('/', n(1), n(0)), '0'),
    (bin('%', n(7), n(3)), '1'),
    (bin('%', n(-7), n(3)), '-1'),
    (bin('%', n(5), n(0)), '0'),
    (bin('**', n(2), n(10)), '1024'),
    (bin('**', n(2), n(0.5)), '1.41421356237'),
    (bin('**', n(-8), n(0.5)), '0'),
    (bin('**', n(0), n(-1)), '0'),
    (bin('**', n(10), n(400)), '0'),
    (bin('==', n(1), t('1')), 'true'),
    (bin('==', nul, t('')), 'true'),
    (bin('==', list([n(1), n(2)]), list([n(1), n(2)])), 'true'),
    (bin('==', dict({'a': n(1), 'b': n(2)}), dict({'b': n(2), 'a': n(1)})), 'true'),
    (bin('!=', n(1), n(2)), 'true'),
    (bin('<', n(2), n(10)), 'true'),
    (bin('<', t('2'), t('10')), 'true'),
    (bin('<', t('abc'), n(1)), 'true'),
    (bin('<=', n(2), n(2)), 'true'),
    (bin('>', n(2), n(2)), 'false'),
    (bin('>=', n(2), n(2)), 'true'),
  ]),
  LangCase(
    '字面量：空、是否、数字、各种刁钻的文字',
    [
      log(nul),
      log(yes),
      log(no),
      log(n(1.5)),
      log(n(-3)),
      log(n(100)),
      log(n(1e21)),
      log(n(0.000001)),
      log(n(1e-7)),
      log(n(123456789012345680000.0)),
      log(n(double.nan)),
      log(n(double.infinity)),
      log(t('带"引号"和\\反斜杠')),
      log(t('多字节 😀 ß é 中文')),
      log(t('第一行\n第二行\t制表')),
      log(t(r'$dollar ${x} #{y} %s {0}')),
      log(t("</script><!-- '单引号' `反引号`")),
      logJson(t('\u0001\u007f\u2028\ufeff')),
      log(rt('size', [t('\ud83d')])),
    ],
    [
      '',
      'true',
      'false',
      '1.5',
      '-3',
      '100',
      '1e21',
      '0.000001',
      '0.0000001',
      '1.23456789012e20',
      '0',
      '0',
      '带"引号"和\\反斜杠',
      '多字节 😀 ß é 中文',
      '第一行',
      '第二行\t制表',
      r'$dollar ${x} #{y} %s {0}',
      "</script><!-- '单引号' `反引号`",
      '"\\u0001\u007f\u2028\ufeff"',
      '1',
    ],
  ),
  LangCase(
    '按 (x) 分情况：一串“如果”，x 只算一次，比法是“等于”',
    [
      LForEach(list([n(1), n(2), t('2'), n(3)]), 'x', [
        ...lSwitch(
          's1',
          v('x'),
          [
            LIfArm(n(1), [log(t('一'))]),
            LIfArm(t('2'), [log(t('二'))]),
          ],
          orElse: [log(t('别的'))],
        ),
      ]),
      let('ys', list([n(1), n(2), n(3)])),
      ...lSwitch('s2', rt('listPop', [v('ys')]), [
        LIfArm(n(1), [log(t('是 1'))]),
        LIfArm(n(3), [log(t('是 3'))]),
      ]),
      log(rt('size', [v('ys')])),
      // 一种情况都没有：主体还是要算一次
      ...lSwitch('s3', rt('listPop', [v('ys')]), [], orElse: [log(t('都不是'))]),
      log(rt('size', [v('ys')])),
    ],
    ['一', '二', '二', '别的', '是 3', '2', '都不是', '1'],
  ),
  LangCase(
    '下标：读列表 / 字典 / 文字，写列表 / 字典；列表和字典是“同一个”，不是复制',
    [
      let('xs', list([n(10), n(20), n(30)])),
      let('d', dict({'k': t('值')})),
      logJson(
        list([
          at(v('xs'), n(1)),
          at(v('d'), t('k')),
          at(t('héllo😀'), n(5)),
          at(v('xs'), n(9)),
          at(n(5), n(0)),
          at(v('d'), t('没有')),
          at(list([n(7)]), t('x')),
        ]),
      ),
      setAt(v('xs'), n(0), t('改了')),
      setAt(v('d'), t('新'), n(1)),
      setAt(v('d'), n(2), t('数字键')),
      logJson(list([v('xs'), v('d')])),
      let(
        'm',
        dict({
          'xs': list([n(1), n(2)]),
        }),
      ),
      setAt(at(v('m'), t('xs')), n(0), n(9)),
      run(rt('listPush', [at(v('m'), t('xs')), n(3)])),
      logJson(v('m')),
      let('a', list([n(1)])),
      let('b', v('a')),
      run(rt('listPush', [v('b'), n(2)])),
      logJson(v('a')),
      let('c', rt('copy', [v('m')])),
      run(rt('listPush', [at(v('c'), t('xs')), n(4)])),
      logJson(
        list([
          v('m'),
          v('c'),
          rt('copy', [n(5)]),
        ]),
      ),
    ],
    ['[20,"值","😀",null,null,null,7]', '[["改了",20,30],{"2":"数字键","k":"值","新":1}]', '{"xs":[9,2,3]}', '[1,2]', '[{"xs":[9,2,3]},{"xs":[9,2,3,4]},5]'],
  ),
  LangCase(
    '列表 / 字典字面量：套着的、空的、键重复、键不是文字',
    [
      logJson(
        list([
          list([
            n(1),
            list([n(2)]),
          ]),
          dict(),
          list(),
        ]),
      ),
      logJson(LDictLit([LDictEntry(t('a'), n(1)), LDictEntry(t('a'), n(2)), LDictEntry(n(1), t('x')), LDictEntry(n(1.5), yes), const LDictEntry(nul, nul)])),
      logJson(list([nul])),
    ],
    ['[[1,[2]],{},[]]', '{"":null,"1":"x","1.5":true,"a":2}', '[null]'],
  ),
  LangCase(
    '只为效果算一个式子、注释、返回后面的不执行',
    [
      run(n(1)),
      let('x', n(2)),
      run(v('x')),
      run(_and(yes, no)),
      run(LCond(yes, n(1), n(2))),
      run(bin('+', n(1), n(2))),
      run(const LUnary('not', yes)),
      run(at(list(), n(0))),
      run(list([n(1)])),
      run(dict()),
      const LNote('注释里的 */ 和\n换行 \\u000a 都不会变成代码'),
      log(t('到这里')),
      const LReturn(null),
      log(t('不该出现')),
    ],
    ['到这里'],
  ),
];
