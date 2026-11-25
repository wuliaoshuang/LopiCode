// 语言核心一致性用例（二）：第 4 版新加的小库函数的全部用例（分在三个文件里）＋ JSON 互转 ＋ 会抛错的操作。
import 'package:lopicode/lang/lang.dart';

import 'lang_cases_rt_basic.dart';
import 'lang_cases_rt_data.dart';
import 'lang_conformance.dart';

export 'lang_cases_rt_basic.dart' show f;

final List<LangCase> kLangRtCases = [
  ...kLangRtBasicCases,
  ...kLangRtDataCases,
  vals('JSON 互转', [
    (
      f('toJson', [
        {
          'b': [1, 2.5, 'x', null, true],
          'a': <String, Object?>{},
        },
      ]),
      r'"{\"a\":{},\"b\":[1,2.5,\"x\",null,true]}"',
    ),
    (
      ls([
        f('toJson', ['带"引号"\n']),
        f('toJson', [null]),
        f('toJson', [1e21]),
        f('toJson', ['😀']),
      ]),
      r'["\"带\\\"引号\\\"\\n\"","null","1e21","\"😀\""]',
    ),
    (f('fromJson', ['{"b":[1,2.50,"x",null,true,{"c":-0.0}],"a":"\\u4e2d\\ud83d\\ude00","b2":1e2}']), '{"a":"中😀","b":[1,2.5,"x",null,true,{"c":0}],"b2":100}'),
    (
      ls([
        f('fromJson', ['']),
        f('fromJson', ['{']),
        f('fromJson', ['[1,]']),
        f('fromJson', ['NaN']),
        f('fromJson', ["{'a':1}"]),
        f('fromJson', ['\ufeff1']),
        f('fromJson', ['01']),
        f('fromJson', ['1 2']),
        f('fromJson', [5]),
        f('fromJson', [' [ 1 ] ']),
        f('fromJson', ['"x"']),
        f('fromJson', ['{"a":1,"a":2}']),
      ]),
      '[null,null,null,null,null,null,null,null,5,[1],"x",{"a":2}]',
    ),
    (
      f('isNull', [
        f('fromJson', [
          f('repeatText', ['[', 70]),
        ]),
      ]),
      'true',
    ),
    (
      f('fromJson', [
        f('toJson', [
          [
            1,
            {'k': '值'},
          ],
        ]),
      ]),
      '[1,{"k":"值"}]',
    ),
    (
      f('size', [
        f('fromJson', ['[1,2,3]']),
      ]),
      '3',
    ),
  ]),
];

/// 会抛错的操作：(名字, 程序, 标准错误里要有的那句话)。每个都单独跑：抛错前的输出要在，抛错后的不在，退出码不是 0。
final List<(String, List<LStmt>, String)> kLangErrorCases = [
  (
    'listSet 越界',
    [
      log(t('前')),
      run(
        f('listSet', [
          [1],
          1,
          'x',
        ]),
      ),
      log(t('后')),
    ],
    kLangErrors['noItem']!,
  ),
  (
    'listSet 负数位置',
    [
      log(t('前')),
      run(
        f('listSet', [
          [1],
          -1,
          'x',
        ]),
      ),
      log(t('后')),
    ],
    kLangErrors['noItem']!,
  ),
  (
    'listRemove 空列表',
    [
      log(t('前')),
      run(f('listRemove', [[], 0])),
      log(t('后')),
    ],
    kLangErrors['noItem']!,
  ),
  (
    'listInsert 越界',
    [
      log(t('前')),
      run(
        f('listInsert', [
          [1],
          3,
          'x',
        ]),
      ),
      log(t('后')),
    ],
    kLangErrors['noItem']!,
  ),
  (
    'listPush 不是列表',
    [
      log(t('前')),
      run(f('listPush', ['abc', 1])),
      log(t('后')),
    ],
    kLangErrors['notList']!,
  ),
  (
    'dictSet 不是字典',
    [
      log(t('前')),
      run(
        f('dictSet', [
          [1],
          'a',
          1,
        ]),
      ),
      log(t('后')),
    ],
    kLangErrors['notDict']!,
  ),
  (
    'dictRemove 不是字典',
    [
      log(t('前')),
      run(f('dictRemove', [null, 'a'])),
      log(t('后')),
    ],
    kLangErrors['notDict']!,
  ),
  (
    'setItem 不是列表也不是字典',
    [
      log(t('前')),
      run(f('setItem', [5, 0, 1])),
      log(t('后')),
    ],
    kLangErrors['notIndexable']!,
  ),
  (
    '下标赋值越界',
    [
      log(t('前')),
      let('xs', ls([1])),
      setAt(v('xs'), n(5), n(1)),
      log(t('后')),
    ],
    kLangErrors['noItem']!,
  ),
];
