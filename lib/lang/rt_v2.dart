/// 规矩版本 2 里小库函数的类型（设计 B 第 9 节“类型和库的关系”的第一步）：检查器照它查参数、定结果。
///
/// 名字沿用 rt.dart 的表；[kLangRtV2New] 是版本 2 新加的名字（各语言小库的实现在“带类型的生成路径”那一段做）。
/// 列表和字典上那几个“看被操作的东西是什么再定”的（加一项、取一项、存一项…）不在表里，检查器里单独处理（见 typecheck_rt.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

class LRtSig {
  const LRtSig(this.label, this.params, this.ret, {this.typeVars = const [], this.slots = const [], this.bounds = const {}});

  /// 提示语里怎么叫它（「映射」）。
  final String label;
  final List<LType> params;
  final LType ret;
  final List<String> typeVars;

  /// 类型变量的约束（变量名 → [kBoundComparable] / [kBoundNumeric]…）；没写＝什么都行。
  final Map<String, String> bounds;

  /// 每个参数在提示语里的专门说法（“‘取整’里的数”）；空＝用“「名字」的第 n 个参数”。
  final List<String> slots;
}

const LType _t = LType.variable('T');
const LType _u = LType.variable('U');
const LType _a = LType.variable('A');
const LType _listT = LType.listOf(_t);
const LType _texts = LType.listOf(LType.text);

/// 版本 2 新加的小库名字。
/// 后端积木里早就有、核心 2 的 A5 段才补上版本 2 签名的那 11 个（规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 13 节）。
const Set<String> kLangRtV2Ported = {'abs', 'max', 'min', 'random', 'copy', 'template', 'toBool', 'listInsert', 'listRemove', 'listSort', 'dictPairs'};

const Map<String, String> _numT = {'T': kBoundNumeric};

const Set<String> kLangRtV2New = {'orElse', 'must', 'toInt', 'parseInt', 'codePoints', 'isNumeric', 'urlDecode', 'isType', 'toNumber', 'dictMerge'};

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
  // 整数进整数出、小数进小数出；一个整数一个小数＝都按小数。
  'abs': LRtSig('绝对值', [_t], _t, typeVars: ['T'], bounds: _numT),
  'max': LRtSig('较大的', [_t, _t], _t, typeVars: ['T'], bounds: _numT),
  'min': LRtSig('较小的', [_t, _t], _t, typeVars: ['T'], bounds: _numT),
  // a 到 b 之间（含两头）随便一个整数；a 比 b 大就倒过来。
  'random': LRtSig('随机整数', [LType.integer, LType.integer], LType.integer),
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
  // 数列：从 a 起每次加 step，到 b 为止（含两头）；步长是 0、方向反了＝空列表；最多 10000 项（和版本 1 一样，多出来的不要）。
  'range': LRtSig('数列', [LType.integer, LType.integer, LType.integer], LType.listOf(LType.integer), slots: ['“数列”的起点', '“数列”的终点', '“数列”的步长']),
  // 在第 i 项前面插一项（i＝项数就是加在末尾）；位置不对＝出错。
  'listInsert': LRtSig('插入一项', [_listT, LType.integer, _t], LType.nul, typeVars: ['T']),
  // 删掉第 i 项并把它交回来；没有这一项＝出错。
  'listRemove': LRtSig('删掉一项', [_listT, LType.integer], _t, typeVars: ['T']),
  // 排好序的新列表（原来的不动）：数字按大小、文字按码点。“任意”的列表要全是数字或者全是文字，不然出错。
  'listSort': LRtSig('排序', [_listT], _listT, typeVars: ['T'], bounds: {'T': kBoundComparable}),
  // [键, 值] 一对对排成列表，按键的码点从小到大。
  'dictPairs': LRtSig('一对对', [LType.dictOf(_t)], LType.listOf(LType.listOf(LType.any)), typeVars: ['T']),
  'dictKeys': LRtSig('所有的键', [LType.dictOf(_t)], _texts, typeVars: ['T']),
  'dictValues': LRtSig('所有的值', [LType.dictOf(_t)], _listT, typeVars: ['T']),
  'dictHas': LRtSig('有这个键', [LType.dictOf(_t), LType.text], LType.boolean, typeVars: ['T']),
  // —— 其它 ——
  // 深复制：列表、字典连里面的一层层都另做一份；别的值原样交回。
  'copy': LRtSig('复制', [_t], _t, typeVars: ['T']),
  // 把文字里的 {键} 换成字典里那个键的值（按“变成文字”的规矩）；字典里没有的键、没配上的花括号原样留着。
  'template': LRtSig('套模板', [LType.text, LType.dictOf(_t)], LType.text, typeVars: ['T']),
  // 算不算“是”：空、否、0、空文字＝否；别的都＝是。（严格规矩里条件不会自动这么算，要算就明着用这一块。）
  'toBool': LRtSig('算不算是', [LType.any], LType.boolean),
  'toJson': LRtSig('变成 JSON', [LType.any], LType.text),
  'fromJson': LRtSig('读 JSON', [LType.text], LType.any),
  'now': LRtSig('现在', [], LType.number),
  // 是不是数字：整数、小数是；文字要整段（去掉两头的空白）是一个写得出来、不是无穷大的数（“1.0”“1e3”“ 7 ”都是）；别的都不是。
  'isNumeric': LRtSig('是不是数字', [LType.any], LType.boolean),
  // 把网址里的 %XX 换回原来的字（按 UTF-8）；“+”不动。写坏了的 %、换回来不是 UTF-8 的＝出错。
  'urlDecode': LRtSig('网址解码', [LType.text], LType.text),
  // 这个值是不是某一类。第二个参数是类的名字：null bool number text list dict function object（对象、记录、枚举都算 object）；别的名字＝出错。
  'isType': LRtSig('是不是这一类', [LType.any, LType.text], LType.boolean),
  // 文字变成小数：认的写法和“是不是数字”一样；不是数字的＝出错。
  'toNumber': LRtSig('变成数字', [LType.text], LType.number),
  // 两个字典合成一个新的，后面的盖住前面的；原来的两个不动。
  'dictMerge': LRtSig('合并字典', [LType.dictOf(_t), LType.dictOf(_t)], LType.dictOf(_t), typeVars: ['T']),
};
