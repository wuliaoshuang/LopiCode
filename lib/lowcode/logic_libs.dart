/// 页面逻辑和积木库打交道的几样（积木第 5 版·前端 1）：页面逻辑是一份“会用库的文档”（[LibUser]，给谁用＝前端）；
/// 这一页用上了哪些库、有没有用到“新功能”（用到了导出就走语言核心那条新路，没用到的页面导出和以前逐字节一样）。
library;

import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 页面逻辑当“会用库的文档”看。库积木表（[LibTable]）、积木盒分组（`libCategories`）直接拿它用。
class LcLogicUser implements LibUser {
  LcLogicUser(this.logic);
  final LcLogic logic;

  @override
  List<LibUse> get uses => [for (final u in logic.uses) ?LibUse.tryParse(u)];
  @override
  List<LibLibrary> get loaded => logic.loaded;
  @override
  set loaded(List<LibLibrary> value) => logic.loaded = value;
  @override
  LibSide get libSide => LibSide.frontend;
  @override
  String? get libraryId => null;
  @override
  List<String> libMouthsOf(String fnId) => const [];
  @override
  Iterable<List<LcBlock>> get libBodies => [for (final h in logic.handlers) h.body];
  @override
  Iterable<String> get libHatOps => const [];

  LibLibrary? lib(String id) => loaded.where((l) => l.id == id).firstOrNull;
  bool hasUse(String id) => logic.uses.any((u) => u['id'] == id);

  /// 用上一个库（已经用上了就不动）。
  void use(String id) {
    if (!hasUse(id) && logic.uses.length < kMaxLibUses) logic.uses.add({'id': id});
  }
}

/// 这一页用上的库（读好了的、能用在前端的）；[problems] 里记“用了却不在项目里”“库本身有问题”“只给后端用”“它靠的库没用上”。
List<LibLibrary> lcUsedLibs(LcLogic logic, [List<String>? problems]) {
  final user = LcLogicUser(logic);
  final out = <LibLibrary>[];
  for (final u in user.uses) {
    final l = user.lib(u.id);
    if (l == null) {
      problems?.add('这一页用了库「${u.id}」，可是项目里找不到它');
    } else if (!l.ok) {
      problems?.add('库「${l.name}」有问题，用不了：${l.problems.first}');
    } else if (l.sideProblem(LibSide.frontend) case final why?) {
      problems?.add(why);
    } else if (l.replaces.isNotEmpty) {
      problems?.add('库「${l.name}」是用来顶替后端自带库的，页面里用不了');
    } else if (l.natives.isNotEmpty) {
      problems?.add('库「${l.name}」带了手写代码，浏览器里不接手写代码');
    } else {
      out.add(l);
    }
  }
  for (final l in out) {
    for (final r in l.requires) {
      if (!out.any((x) => x.id == r)) problems?.add('库「${l.name}」要靠库「$r」，请把「$r」也用上');
    }
  }
  return out;
}

bool _exprUsesLib(Object? e, int depth) {
  if (depth > 64 || e is! Map) return false;
  if (libOpOf(exprKind(e)) != null) return true;
  for (final v in e.values) {
    if (v is Map && _exprUsesLib(v, depth + 1)) return true;
    if (v is List && v.any((x) => x is Map && _exprUsesLib(x, depth + 1))) return true;
    if (v is List<LcBlock> && _blocksUseLib(v)) return true;
  }
  return false;
}

bool _blocksUseLib(List<LcBlock> list) {
  for (final b in list) {
    if (libOpOf(b.op) != null) return true;
    if (b.args.values.any((v) => _exprUsesLib(v, 0))) return true;
    if (_blocksUseLib(b.body) || _blocksUseLib(b.orElse)) return true;
    for (final a in b.arms) {
      if (a.args.values.any((v) => _exprUsesLib(v, 0)) || _blocksUseLib(a.body)) return true;
    }
  }
  return false;
}

/// 这一页的逻辑有没有用到“新功能”（是新的页面逻辑、用上了积木库，或者哪一串里有库积木）。用到了，导出走语言核心那条新路。
bool lcLogicUsesCore(LcLogic logic) => logic.front != null || logic.uses.isNotEmpty || logic.handlers.any((h) => _blocksUseLib(h.body));

/// 测试用：把这个开关打开，没用新功能的页面也走新路（拿来和老路对比行为）。产品里永远是关的。
bool lcForceCorePath = false;

/// 这份文档（现在这一页）导出时走不走新路。
bool lcDocUsesCore(LcDocument doc) => lcForceCorePath ? !doc.logic.isEmpty : lcLogicUsesCore(doc.logic);
