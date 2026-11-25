/// 生成器用到的零碎：“未支持”的报错、能力表、宿主接口、字面量的写法。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/names.dart';

/// 生成器碰到这一阶段还不支持的节点。消息是给人看的整句话。
class LangUnsupported implements Exception {
  const LangUnsupported(this.what, {this.stage, this.src});

  /// 是什么：“函数”“类”…，或一整句说明（[stage] 是 null 时）。
  final String what;

  /// 第几阶段才有。
  final int? stage;
  final LSrc? src;

  String get message => stage == null ? what : '还不支持“$what”（积木第 4 版第 $stage 阶段才有）';

  @override
  String toString() => 'LangUnsupported: $message${src == null ? '' : '（$src）'}';
}

/// 一种语言对一项语言特性的支持办法（设计稿 4.4 的“能力表”）。
enum LCap {
  /// 语言自己就有，直接生成。
  native,

  /// 语言没有，改写成别的写法（比如“从…数到…”改成按遍数的循环）。
  lowered,

  /// 交给运行时小库。
  runtime,

  /// 这种语言做不了，校验要拦。
  forbidden,

  /// 以后的阶段才做（现在生成器会抛 [LangUnsupported]）。
  later,
}

/// 能力表里的特性名。
const List<String> kLangFeatures = [
  'operators', // 加减乘除、比较
  'logic', // 并且 / 或者（短路）
  'cond', // 值版的“如果”
  'hoist', // 变量声明提到函数开头
  'const', // 常量
  'while',
  'forCount',
  'forEach',
  'forPairs',
  'repeat',
  'switch', // 按 x 分情况
  'listMutation', // 原地改列表
  'functions', // 第 2 阶段
  'closures', // 第 2 阶段
  'classes', // 第 5 阶段
  'errors', // 第 6 阶段
  'async', // 第 6 阶段
];

/// 五种语言共同的部分；各语言在自己的生成器里改不一样的几项。
const Map<String, LCap> kLangBaseCaps = {
  'operators': LCap.runtime,
  'logic': LCap.native,
  'cond': LCap.native,
  'hoist': LCap.lowered,
  'const': LCap.lowered,
  'while': LCap.native,
  'forCount': LCap.lowered,
  'forEach': LCap.lowered,
  'forPairs': LCap.lowered,
  'repeat': LCap.lowered,
  'switch': LCap.lowered,
  'listMutation': LCap.native,
  'functions': LCap.native,
  'closures': LCap.native,
  'classes': LCap.later,
  'errors': LCap.later,
  'async': LCap.later,
};

/// 宿主（比如后端）接进来的两样东西。都没有也行（纯脚本）。
class LangHost {
  const LangHost({this.call, this.stmt, this.name, this.allowReturn = true, this.inspect});

  /// [LNative]：调宿主的函数，参数已经写好。
  final String Function(String fn, List<String> args)? call;

  /// [LHost]：宿主自己的语句，返回一行行代码（不带缩进）。
  final List<String> Function(Object payload)? stmt;

  /// 宿主的名字（[LNameKind.host]）在这种语言里怎么写；不给就原样写。
  /// 后端的“这次请求”在语法树里统一叫 `req`，PHP 里要写成 `\$req`——靠它换。
  final String Function(String name)? name;

  /// 能不能直接写“返回”（[LReturn]）。后端的接口函数不行：那里要用“返回响应”。只管宿主自己那一层：
  /// 套在里面的匿名函数、模块顶层的函数里总是可以“返回”。
  final bool allowReturn;

  /// [LHost] 那一句用到了哪些名字（闭包要知道：Python 的 nonlocal、Java 的盒子、PHP 的 use）。不给＝当它什么名字都没用。
  final LHostInspect? inspect;
}

/// 一段语句生成出来的结果。
class LangFragment {
  const LangFragment(this.declares, this.lines);

  /// 要在函数开头声明的名字（用户起的原名，没加前缀）：变量、常量、循环变量。宿主负责在函数开头写声明
  /// （[LangGen.declare]），已经声明过的（比如后端文档里的变量）要自己去掉。
  final List<String> declares;

  /// 代码，一行一项，不带这一层的缩进。
  final List<String> lines;
}

/// 双引号字符串字面量：`"`、`\` 和 [escape] 里的字符加反斜杠；换行 / 回车 / 制表写 `\n` `\r` `\t`；其余控制字符、DEL、U+0085、
/// U+2028、U+2029、U+FEFF 交给 [unicode]。不成对的代理项换成 U+FFFD。中文、表情原样保留。
String langQuoted(String s, {String escape = '', String Function(int codePoint)? unicode}) {
  final u = unicode ?? (int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    var r = s.codeUnitAt(i);
    if (r >= 0xD800 && r <= 0xDBFF && i + 1 < s.length && s.codeUnitAt(i + 1) >= 0xDC00 && s.codeUnitAt(i + 1) <= 0xDFFF) {
      out.write(s.substring(i, i + 2));
      i++;
      continue;
    }
    if (r >= 0xD800 && r <= 0xDFFF) r = 0xFFFD;
    final ch = String.fromCharCode(r);
    if (r == 0x22 || r == 0x5c || (escape.isNotEmpty && escape.contains(ch))) {
      out.write('\\$ch');
    } else if (r == 0x0a) {
      out.write(r'\n');
    } else if (r == 0x0d) {
      out.write(r'\r');
    } else if (r == 0x09) {
      out.write(r'\t');
    } else if (r < 0x20 || r == 0x7f || r == 0x85 || r == 0x2028 || r == 0x2029 || r == 0xfeff) {
      out.write(u(r));
    } else {
      out.write(ch);
    }
  }
  out.write('"');
  return out.toString();
}

/// 数字字面量：不是有限的数当 0；整数不带小数点（[dotZero] 时补 `.0`，给整数和小数分家的语言用）；其余用最短写法。
String langNumber(num v, {bool dotZero = false}) {
  if (!v.isFinite) return dotZero ? '0.0' : '0';
  final text = v is int || (v == v.roundToDouble() && v.abs() < 1e15) ? '${v.round()}' : '$v';
  return dotZero && !text.contains(RegExp('[.eE]')) ? '$text.0' : text;
}

/// 收拾成能放进一行注释的内容：去掉换行类 / 控制字符，拆开 `*/` 和 `</`，过长截断。
String langComment(String s, [int limit = 160]) {
  var out = s.replaceAll(RegExp('[\\x00-\\x1f\\x7f\u0085\u2028\u2029\ufeff\ud800-\udfff]+'), ' ').replaceAll('*/', '* /').replaceAll('</', '< /').trim();
  final runes = out.runes.toList();
  if (runes.length > limit) out = '${String.fromCharCodes(runes.take(limit))}…';
  return out.replaceAll('*/', '* /');
}
