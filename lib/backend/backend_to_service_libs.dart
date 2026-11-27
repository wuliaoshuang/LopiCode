/// 严格规矩的后端文档和库打交道的几样小东西（从 backend_to_service.dart 分出来的，那边放不下了）：
/// 这份文档用上了哪些库、库的设置项各是什么值、几个库合好以后的全部声明。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/link.dart';

/// 库的定义画布上那两块积木翻出来的记号（只在翻库的时候出现，写出器把它们写成模板里的洞；见 backend_lib_build.dart）。
const String kBeLibMouthMark = '@口';
const String kBeLibPutMark = '@放进';

/// 这份文档里某个库的设置项各是什么值：内置“接口服务”照旧从文档顶层拿；用户的库拿“用上”时填的。
Map<String, Object?> beLibSettingsOf(BeDocument doc, LibLibrary lib) => lib.builtin || lib.id == doc.serviceLib ? beServiceSettings(doc) : (doc.use(lib.id)?.settings ?? const {});

/// 这份文档的“接口服务”是哪个库：没指定＝应用自带的；指定了＝项目里那个顶替它的库。
/// 指定了却用不了（不在项目里、有问题、清单里没写顶替“接口服务”）时把原因记进 [problems]，返回自带的。
LibLibrary beServiceLibOf(BeDocument doc, [List<String>? problems]) {
  final base = beServiceLibrary();
  if (doc.serviceLib.isEmpty) return base;
  final l = doc.lib(doc.serviceLib);
  final why = l == null
      ? '这份文档指定用库「${doc.serviceLib}」顶替“接口服务”，可是项目里找不到它'
      : !l.ok
      ? '顶替“接口服务”的库「${l.name}」有问题，用不了：${l.problems.first}'
      : l.replaces != kBeServiceLibId
      ? '库「${l.name}」的清单里没有写它顶替“接口服务”，不能这样用'
      : null;
  if (why == null) return l!;
  problems?.add(why);
  return base;
}

/// 这份文档用上的库（读好了的）；[problems] 里记“用了却不在项目里”“库本身有问题”“它靠的库没用上”。
List<LibLibrary> beUsedLibs(BeDocument doc, [List<String>? problems]) {
  final out = <LibLibrary>[];
  for (final u in doc.uses) {
    final l = doc.lib(u.id);
    if (l == null) {
      problems?.add('这份文档用了库「${u.id}」，可是项目里找不到它');
    } else if (!l.ok) {
      problems?.add('库「${l.name}」有问题，用不了：${l.problems.first}');
    } else if (l.sideProblem(doc.libSide) case final why?) {
      problems?.add(why);
    } else if (l.replaces.isNotEmpty) {
      problems?.add('库「${l.name}」是用来顶替自带库的，不能当普通的库用上（在它的面板里选“用它顶替”）');
    } else {
      out.add(l);
    }
  }
  for (final l in out) {
    for (final r in l.requires) {
      if (r != kBeServiceLibId && !out.any((x) => x.id == r)) problems?.add('库「${l.name}」要靠库「$r」，请把「$r」也用上');
    }
  }
  return out;
}

/// 这份文档里库的设置项各是什么值（旧文档顶层的键 → 设置项，照库里写的 `legacyKey`）。
Map<String, Object?> beServiceSettings(BeDocument doc) => {
  'port': doc.port,
  'collections': [for (final c in doc.collections) c.name],
};

List<LDecl>? _libDecls;

/// 内置库合好以后的全部声明（类型检查把它们和文档自己的声明放在一起查）。只算一次。
List<LDecl> beServiceLibDecls() => _libDecls ??= beLibDecls([beServiceLibrary()]);

/// 几个库合好以后的全部声明。
List<LDecl> beLibDecls(List<LibLibrary> libs) {
  final linked = linkProgram(
    LProgram([
      for (final l in libs) ...l.modules,
      LModule(name: 'main', uses: [for (final l in libs) ...l.moduleNames]),
    ], entry: 'main'),
  );
  return linked.module?.decls ?? const [];
}
