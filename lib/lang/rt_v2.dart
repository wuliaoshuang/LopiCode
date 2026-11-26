/// 规矩版本 2 里小库函数的类型（设计 B 第 9 节“类型和库的关系”的第一步）：检查器照它查参数、定结果。
///
/// 名字沿用 rt.dart 的表；[kLangRtV2New] 是版本 2 新加的名字（各语言小库的实现在“带类型的生成路径”那一段做）。
/// 列表和字典上那几个“看被操作的东西是什么再定”的（加一项、取一项、存一项…）不在表里，检查器里单独处理（见 typecheck_rt.dart）。
library;

import 'package:lopicode/lang/types.dart';

class LRtSig {
  const LRtSig(this.label, this.params, this.ret, {this.typeVars = const [], this.slots = const []});

  /// 提示语里怎么叫它（「映射」）。
  final String label;
  final List<LType> params;
  final LType ret;
  final List<String> typeVars;

  /// 每个参数在提示语里的专门说法（“‘取整’里的数”）；空＝用“「名字」的第 n 个参数”。
  final List<String> slots;
}

const LType _t = LType.variable('T');
const LType _u = LType.variable('U');
const LType _a = LType.variable('A');
const LType _listT = LType.listOf(_t);
const LType _texts = LType.listOf(LType.text);

/// 版本 2 新加的小库名字。
const Set<String> kLangRtV2New = {'orElse', 'must', 'toInt', 'parseInt', 'codePoints', 'isNumeric', 'urlDecode'};

const Map<String, LRtSig> kLangRtV2 = {
  // —— 高阶 ——
  'listMap': LRtSig(
    '映射',
    [
      _listT,
      LType.func([_t, _u]),
    ],
    LType.listOf(_u),
    typeVars: ['T', 'U'],
  ),
  'listFilter': LRtSig(
    '筛选',
    [
      _listT,
      LType.func([_t, LType.boolean]),
    ],
    _listT,
    typeVars: ['T'],
  ),
  'listReduce': LRtSig(
    '归并',
    [
      _listT,
      LType.func([_a, _t, _a]),
      _a,
    ],
    _a,
    typeVars: ['T', 'A'],
  ),
  'listFind': LRtSig(
    '找第一个',
    [
      _listT,
      LType.func([_t, LType.boolean]),
    ],
    LType(LKind.typeVar, name: 'T', nullable: true),
    typeVars: ['T'],
  ),
  'listEvery': LRtSig(
    '每个都',
    [
      _listT,
      LType.func([_t, LType.boolean]),
    ],
    LType.boolean,
    typeVars: ['T'],
  ),
  'listSome': LRtSig(
    '有一个',
    [
      _listT,
      LType.func([_t, LType.boolean]),
    ],
    LType.boolean,
    typeVars: ['T'],
  ),
  'listEach': LRtSig(
    '每个都做',
    [
      _listT,
      LType.func([_t, LType.nul]),
    ],
    LType.nul,
    typeVars: ['T'],
  ),
  // —— 数 ——
  'toInt': LRtSig('取整', [LType.number], LType.integer, slots: ['“取整”里的数']),
  'parseInt': LRtSig('变成整数', [LType.text], LType(LKind.integer, nullable: true), slots: ['“变成整数”里的文字']),
  'sqrt': LRtSig('开方', [LType.number], LType.number),
  'floor': LRtSig('向下取整', [LType.number], LType.integer),
  'ceil': LRtSig('向上取整', [LType.number], LType.integer),
  'round': LRtSig('四舍五入', [LType.number], LType.integer),
  // —— 文字 ——
  'listJoin': LRtSig('拼起来', [_texts, LType.text], LType.text, slots: ['“拼起来”的列表', '“拼起来”的分隔']),
  'split': LRtSig('切开', [LType.text, LType.text], _texts),
  'substring': LRtSig('截取', [LType.text, LType.integer, LType.integer], LType.text),
  'startsWith': LRtSig('开头是', [LType.text, LType.text], LType.boolean),
  'endsWith': LRtSig('结尾是', [LType.text, LType.text], LType.boolean),
  'contains': LRtSig('包含', [LType.text, LType.text], LType.boolean),
  'indexOf': LRtSig('在第几个字', [LType.text, LType.text], LType.integer),
  'replace': LRtSig('替换', [LType.text, LType.text, LType.text], LType.text),
  'trim': LRtSig('去掉两头空白', [LType.text], LType.text),
  'upper': LRtSig('变大写', [LType.text], LType.text),
  'lower': LRtSig('变小写', [LType.text], LType.text),
  'repeatText': LRtSig('重复文字', [LType.text, LType.integer], LType.text),
  'charAt': LRtSig('第几个字', [LType.text, LType.integer], LType.text),
  'codePoints': LRtSig('每个字的码点', [LType.text], LType.listOf(LType.integer)),
  // —— 列表、字典里不看“被操作的是什么”的 ——
  'listReverse': LRtSig('倒过来', [_listT], _listT, typeVars: ['T']),
  'listConcat': LRtSig('接起来', [_listT, _listT], _listT, typeVars: ['T']),
  'listSlice': LRtSig('取一段', [_listT, LType.integer, LType.integer], _listT, typeVars: ['T']),
  'listContains': LRtSig('列表里有', [_listT, _t], LType.boolean, typeVars: ['T']),
  'listIndexOf': LRtSig('在列表第几项', [_listT, _t], LType.integer, typeVars: ['T']),
  'range': LRtSig('数列', [LType.integer, LType.integer], LType.listOf(LType.integer)),
  'dictKeys': LRtSig('所有的键', [LType.dictOf(_t)], _texts, typeVars: ['T']),
  'dictValues': LRtSig('所有的值', [LType.dictOf(_t)], _listT, typeVars: ['T']),
  'dictHas': LRtSig('有这个键', [LType.dictOf(_t), LType.text], LType.boolean, typeVars: ['T']),
  // —— 其它 ——
  'toJson': LRtSig('变成 JSON', [LType.any], LType.text),
  'fromJson': LRtSig('读 JSON', [LType.text], LType.any),
  'now': LRtSig('现在', [], LType.number),
  // 是不是数字：整数、小数是；文字要整段（去掉两头的空白）是一个写得出来、不是无穷大的数（“1.0”“1e3”“ 7 ”都是）；别的都不是。
  'isNumeric': LRtSig('是不是数字', [LType.any], LType.boolean),
  // 把网址里的 %XX 换回原来的字（按 UTF-8）；“+”不动。写坏了的 %、换回来不是 UTF-8 的＝出错。
  'urlDecode': LRtSig('网址解码', [LType.text], LType.text),
};
