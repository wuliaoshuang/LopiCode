/// 规矩版本 2 的生成器·模块分文件（库 1 下半）：一个模块一个文件，入口模块在主文件里。
///
/// 模块之间的规矩（公开、用到了谁、不许绕圈、撞名改名、启动顺序）还是 link.dart 先查、先合成一个模块——检查和生成看的是同一份；
/// 这里只记“合并以后每个顶层名字原来是哪个模块的”，生成器照这个把顶层声明分到各自的文件里。
/// 五种语言各自怎么让别的文件看得见，见 docs/blocks-v5-parts/B-gen-notes.md 第 10 节。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/link.dart';

class Gen2Split {
  Gen2Split(this.order, this.entry, this.owner);

  /// 启动顺序里除了入口以外、自己有顶层声明的模块（被用到的在前）。
  final List<String> order;
  final String entry;

  /// 合并以后的顶层名字（类本身的成员是“类.成员”）→ 它原来是哪个模块的。内置的东西（错误种类）不在里面。
  final Map<String, String> owner;

  /// 内置的错误种类和它的配套放在哪一份里（不是谁的模块）。
  static const String kinds = '';

  /// 这个顶层名字归哪一份：模块名，或者 [kinds]。
  String of(String name) => owner[name] ?? kinds;

  /// 模块名 → 文件名里的那一截（不带前缀、后缀）。只有英文字母、数字、下划线、常用汉字的名字原样；
  /// 别的字符写成码点（有的系统会把全角字、带声调的字母悄悄换一种写法存，文件名和代码里写的就对不上了）。
  /// 两个模块收拾完只差大小写（有的系统不分大小写）或者一样的，后一个加上序号。
  late final Map<String, String> ident = () {
    final out = <String, String>{}, taken = <String>{};
    for (final m in order) {
      var id = gen2FileIdent(m);
      for (var i = 2; !taken.add(id.toLowerCase()); i++) {
        id = '${gen2FileIdent(m)}_$i';
      }
      out[m] = id;
    }
    return out;
  }();

  /// [module] 的文件里要先引进来的模块：启动顺序里排在它前面的全部（入口＝全部）。
  /// 不只是它“用到了谁”里写的那几个：它的代码里会出现隔了一层的模块的类型（比如“看是哪种情况”里的各种情况）。
  List<String> before(String module) => module == entry ? order : order.sublist(0, order.indexOf(module).clamp(0, order.length));
}

String gen2FileIdent(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final plain = (r >= 0x30 && r <= 0x39) || (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a) || r == 0x5f || (r >= 0x4e00 && r <= 0x9fff);
    out.write(plain ? String.fromCharCode(r) : '_u${r.toRadixString(16)}_');
  }
  return out.toString();
}

/// 这个程序要不要分文件、怎么分。只有一个模块有东西（或者对不上）＝null，照旧一个文件。
Gen2Split? gen2SplitOf(LProgram program, LLinked linked) {
  final merged = linked.module;
  if (merged == null) return null;
  final byName = {for (final m in program.modules) m.name: m};
  final owner = <String, String>{};
  final order = <String>[];
  var count = 0;
  for (final mn in linked.order) {
    final m = byName[mn];
    if (m == null) return null;
    count += m.decls.length;
    if (m.decls.isEmpty) continue;
    if (mn != program.entry) order.add(mn);
    for (final d in m.decls) {
      final name = linked.names[(mn, d.name)] ?? d.name;
      owner[name] = mn;
      if (d is LClassDecl) {
        for (final f in d.fields.where((f) => f.isStatic)) {
          owner[lStaticName(name, f.name)] = mn;
        }
        for (final f in d.methods.where((f) => f.isStatic)) {
          owner[lStaticName(name, f.fn.name)] = mn;
        }
      }
    }
  }
  if (order.isEmpty || count != merged.decls.length) return null;
  return Gen2Split(order, program.entry, owner);
}

/// 攒各份文件的顶层代码：哪一份（模块名或 [Gen2Split.kinds]）→ 一行行代码；外加每一份里别的文件要用的名字。
class Gen2Parts {
  final Map<String, List<String>> lines = {};
  final Map<String, List<String>> names = {};

  /// 往 [part] 那一份里加一段。[gap]＝段和段之间空一行（不然是每段前面 / 后面各放一个空行，由调用方自己加在 [chunk] 里）。
  void add(String part, List<String> chunk, {bool gap = false}) {
    if (chunk.isEmpty) return;
    final top = lines.putIfAbsent(part, () => []);
    if (gap && top.isNotEmpty) top.add('');
    top.addAll(chunk);
  }

  void name(String part, String code) => names.putIfAbsent(part, () => []).add(code);

  List<String> of(String part) => lines[part] ?? const [];
  List<String> namesOf(String part) => names[part] ?? const [];
}
