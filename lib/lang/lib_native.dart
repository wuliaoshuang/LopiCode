/// 库的三样“边上的事”（积木第 5 版·第四轮）：给谁用（后端 / 前端 / 都行）、顶替哪个自带库、库里带的手写函数。
/// 都是纯数据和纯函数，[libRead] 读清单时调；格式说明见 docs/blocks-v5-parts/library-format.md 第 18–20 节。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

// ———————————————————————— 给谁用 ————————————————————————

/// 库是给哪一边的文档用的。清单里的 `for`；没写＝后端（这个字段之前的库都是后端的）。
enum LibSide {
  backend('后端'),
  frontend('前端'),
  both('后端和前端都行');

  const LibSide(this.label);
  final String label;

  static LibSide read(Object? raw) => values.where((s) => s.name == raw).firstOrNull ?? backend;
}

/// [lib] 能不能用在 [side] 这一边的文档里：能＝null，不能＝一句原因。[side] 只会是后端或前端。
String? libSideProblemOf(LibSide lib, String name, LibSide side) {
  if (lib == LibSide.both || lib == side) return null;
  return '「$name」是只给${lib.label}用的库，${side.label}的文档里用不了';
}

// ———————————————————————— 手写函数 ————————————————————————

/// 模块里手写函数的声明叫 `手写.<库标识>.<函数名>`（和宿主接口的声明同一种写法，名字以这个开头的就是手写函数）。
const String kLibNativePrefix = '手写.';

/// 手写函数的名字：英文字母开头，字母、数字、下划线，最多 32 个。
final RegExp kLibNativeName = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,31}$');

/// 一个库最多带几个手写函数（自定，防坏数据）。
const int kLibMaxNatives = 32;

/// 生成的工程里，手写函数的文件名和代码里的名字都用这个占位写法；应用放文件的时候换成真名字。
const String kLibNativePlaceholder = '__NAME__';

/// 五种语言各自的文件后缀，和那个文件里必须出现的写法（只是防写错文件，不是安全检查）。
const Map<String, ({String ext, String must, String shape})> kLibNativeLangs = {
  'node': (ext: 'js', must: 'module.exports', shape: 'module.exports = function (参数…) { … };'),
  'python': (ext: 'py', must: 'def run(', shape: 'def run(参数…):'),
  'php': (ext: 'php', must: 'return ', shape: '<?php return function (参数…) { … };'),
  'go': (ext: 'go', must: kLibNativePlaceholder, shape: 'package main ⏎ func __NAME__(参数…) 返回类型 { … }'),
  'java': (ext: 'java', must: kLibNativePlaceholder, shape: 'final class __NAME__ { static 返回类型 run(参数…) { … } }'),
};

/// 清单里声明的一个手写函数。
class LibNative {
  const LibNative({required this.name, required this.ident, required this.params, required this.returns, required this.waits, required this.files});
  final String name;

  /// 在生成的代码里叫什么（也是文件名，不带后缀）。
  final String ident;
  final List<LType> params;
  final LType returns;
  final bool waits;

  /// 语言 → 库里那个文件的相对路径。没有的语言＝这个函数在那种语言里用不了。
  final Map<String, String> files;

  /// 模块里的声明应该叫什么。
  String declName(String libId) => '$kLibNativePrefix$libId.$name';
}

/// 库标识 + 函数名 → 代码里的名字（`shuang/todo` 的 `reverse` → `LcN_shuang__todo_reverse`）。
String libNativeIdent(String libId, String name) => 'LcN_${libId.replaceAll('-', '_').replaceAll('/', '__')}_$name';

bool _simple(LType t) => !t.nullable && (t.kind == LKind.text || t.kind == LKind.integer || t.kind == LKind.number || t.kind == LKind.bool);

/// 读清单的 `native.functions`，和模块里的声明逐个对一遍；对得上的声明带上“它是手写函数”的记号。
/// 返回手写函数表和换好声明的模块；问题记进 [problems]。
({List<LibNative> natives, List<LModule> modules}) libNativeRead({
  required String libId,
  required Object? raw,
  required bool allowed,
  required Map<String, String> files,
  required List<LModule> modules,
  required List<String> problems,
  required LType? Function(Object? text) typeOf,
}) {
  final natives = <LibNative>[];
  final listed = raw is List ? raw : const <Object?>[];
  final nativeFiles = {
    for (final f in files.keys)
      if (f.startsWith('native/')) f,
  };
  final used = <String>{};
  for (final item in listed.take(kLibMaxNatives)) {
    if (item is! Map) continue;
    final name = item['name'];
    if (name is! String || !kLibNativeName.hasMatch(name)) {
      problems.add('手写函数的名字要是英文字母开头的字母、数字、下划线（清单里写的是「$name」）');
      continue;
    }
    if (natives.any((n) => n.name == name)) {
      problems.add('手写函数「$name」在清单里写了两次');
      continue;
    }
    final params = <LType>[];
    var bad = false;
    for (final p in item['params'] is List ? item['params'] as List : const <Object?>[]) {
      final t = typeOf(p);
      if (t == null || !_simple(t)) bad = true;
      if (t != null) params.add(t);
    }
    final returns = typeOf(item['returns']);
    if (bad || returns == null || !_simple(returns) || params.length > 8) {
      problems.add('手写函数「$name」的参数和返回只能是 文字、整数、小数、是否（最多 8 个参数）；别的东西请先变成文字（比如 JSON）再交过去');
      continue;
    }
    final byLang = <String, String>{};
    final rawFiles = item['files'];
    if (rawFiles is Map) {
      for (final e in rawFiles.entries) {
        final lang = e.key, path = e.value;
        final spec = kLibNativeLangs[lang];
        if (spec == null || path is! String) {
          problems.add('手写函数「$name」写了不认识的语言「$lang」');
          continue;
        }
        final src = files[path];
        if (!path.startsWith('native/') || src == null) {
          problems.add('手写函数「$name」的 $lang 文件 $path 不在库的 native/ 里');
          continue;
        }
        if (!src.contains(spec.must)) problems.add('手写函数「$name」的 $lang 文件 $path 不是规定的样子（要写成：${spec.shape}）');
        if (!used.add(path)) problems.add('文件 $path 被两个手写函数用了');
        byLang[lang as String] = path;
      }
    }
    if (byLang.isEmpty) problems.add('手写函数「$name」一种语言的文件都没有');
    natives.add(LibNative(name: name, ident: libNativeIdent(libId, name), params: params, returns: returns, waits: item['waits'] == true, files: byLang));
  }
  for (final f in nativeFiles.difference(used)) {
    problems.add('库里的手写代码文件 $f 清单里没有登记（native.functions 里每个文件都要写明是哪个函数的）');
  }
  if ((natives.isNotEmpty || nativeFiles.isNotEmpty) && !allowed) problems.add('库里带了手写代码，可是清单里没有写 native.allowed＝是');

  // 模块里的声明：名字以“手写.”开头的每一个都要在清单里有，类型要一样；清单里有的每一个都要有声明。
  final declared = <String>{};
  final out = <LModule>[];
  for (final m in modules) {
    var changed = false;
    final decls = <LDecl>[];
    for (final d in m.decls) {
      if (d is! LNativeDecl || !d.name.startsWith(kLibNativePrefix)) {
        decls.add(d);
        continue;
      }
      final n = natives.where((n) => n.declName(libId) == d.name).firstOrNull;
      if (n == null) {
        problems.add('模块「${m.name}」里声明了手写函数「${d.name}」，可是清单里没有它（名字要写成 $kLibNativePrefix$libId.函数名）');
        decls.add(d);
        continue;
      }
      declared.add(n.name);
      final same = d.params.length == n.params.length && d.type == n.returns && [for (var i = 0; i < n.params.length; i++) d.params[i].type == n.params[i]].every((ok) => ok);
      if (!same) {
        problems.add('手写函数「${n.name}」：模块里的声明和清单里写的对不上（清单：(${n.params.map((p) => p.show()).join(', ')}) → ${n.returns.show()}）');
      }
      decls.add(
        LNativeDecl(
          d.name,
          d.params,
          src: d.src,
          type: d.type,
          user: LNativeUser(n.ident, waits: n.waits),
        ),
      );
      changed = true;
    }
    out.add(changed ? LModule(name: m.name, uses: m.uses, decls: decls, body: m.body, src: m.src) : m);
  }
  for (final n in natives) {
    if (!declared.contains(n.name)) problems.add('手写函数「${n.name}」清单里有，模块里却没有声明（要写一句：(宿主 ${n.declName(libId)} (参数…) -> 返回类型)）');
  }
  return (natives: natives, modules: out);
}

/// 这些手写函数在 [language] 的工程里是哪些文件（文件名 → 内容，占位的名字已经换好）。
/// 哪个函数没有这种语言的文件，记进 [missing]。
Map<String, String> libNativeProjectFiles(List<LibNative> natives, Map<String, String> files, String language, {List<String>? missing}) {
  final spec = kLibNativeLangs[language];
  final out = <String, String>{};
  if (spec == null) return out;
  for (final n in natives) {
    final src = files[n.files[language]];
    if (src == null) {
      missing?.add(n.name);
      continue;
    }
    out['${n.ident}.${spec.ext}'] = src.replaceAll(kLibNativePlaceholder, n.ident);
  }
  return out;
}
