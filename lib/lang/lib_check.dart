/// 读完一个库以后的检查（积木第 5 版·库 1）：积木和它背后的定义对不对得上、模板读不读得了、旧名对照有没有重复。
/// 只查“库自己内部”的事；库的模块本身的类型检查在用的时候和用户的程序一起查（link + typecheck）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lib_model.dart';

/// 模板里能用的“洞”。
const Set<String> kLibHoles = {'槽', '隐含', '设置', '口', '放进'};

/// 模板里每种洞各提到了哪些名字（按出现的先后，重复的照记）。
Map<String, List<String>> libTemplateHoles(String template) {
  final out = {for (final h in kLibHoles) h: <String>[]};
  void walk(Object node) {
    if (node is! List) return;
    if (node.length >= 2 && node[0] is String && kLibHoles.contains(node[0]) && node[1] is String) out[node[0]]!.add(node[1] as String);
    for (final c in node) {
      walk(c as Object);
    }
  }

  walk(lcParse(template));
  return out;
}

LFuncDecl? _func(LModule? m, String name) => m?.decls.whereType<LFuncDecl>().where((f) => f.name == name).firstOrNull;

/// 一个库有什么问题（给人看的话）；没有问题是空表。
List<String> libCheck(LibLibrary lib) {
  final out = <String>[];
  final legacy = <String>{};
  final provided = {...lib.provides.keys, for (final b in lib.blocks) ...b.provides.keys};
  for (final b in lib.blocks) {
    void bad(String why) => out.add('积木「${b.id}」：$why');
    final module = lib.modules.where((m) => m.name == b.module).firstOrNull;
    final slots = {
      for (final p in parseLookTemplate(b.look.template))
        if (p.isSlot) p.text,
    };
    for (final n in b.needs) {
      // 靠着别的库的：那样东西可能是那个库给的，这里查不了，用的时候再查。
      if (!provided.contains(n) && lib.requires.isEmpty) bad('它要用“$n”，可是库里没有哪块积木（或启动时）给“$n”');
    }
    if (b.shape == CustomBlockShape.hat && b.how != LibHow.expand) bad('帽子型的积木要用模板展开来定义（口里的积木要放进模板里）');
    if (b.how != LibHow.expand && b.slotKinds.values.contains(LibSlotKind.mouth)) bad('带口的积木要用模板展开来定义');
    switch (b.how) {
      case LibHow.call:
        final f = _func(module, b.of);
        if (f == null) {
          bad('它要调的函数「${b.of}」模块「${b.module}」里没有');
        } else {
          if (!f.isPublic) bad('它要调的函数「${b.of}」没有勾“公开”');
          if (b.args.length > f.params.length || b.args.length < f.params.where((p) => p.defaultValue == null && !p.rest).length) {
            bad('实参表有 ${b.args.length} 项，函数「${b.of}」要 ${f.params.length} 个参数');
          }
        }
      case LibHow.static:
        final parts = b.of.split('.');
        final cls = parts.length == 2 ? module?.decls.whereType<LClassDecl>().where((c) => c.name == parts[0]).firstOrNull : null;
        final m = cls?.methods.where((m) => m.isStatic && m.fn.name == parts[1]).firstOrNull;
        if (cls == null || m == null) {
          bad('它要调的「${b.of}」要写成 类名.方法名，而且那个方法得是“类自己的方法”');
        } else {
          if (!cls.isPublic) bad('类「${cls.name}」没有勾“公开”');
          if (b.args.length != m.fn.params.length) bad('实参表有 ${b.args.length} 项，「${b.of}」要 ${m.fn.params.length} 个参数');
        }
      case LibHow.method:
        if (b.of.isEmpty) bad('没写调哪个方法');
        if (b.args.isEmpty) bad('调对象的方法：实参表的第一项要是那个对象');
        final known = module?.decls.whereType<LClassDecl>().any((c) => c.isPublic && c.methods.any((m) => !m.isStatic && m.fn.name == b.of)) ?? false;
        if (b.of.isNotEmpty && !known) bad('模块「${b.module}」里没有哪个公开的类有方法「${b.of}」');
      case LibHow.expand:
        if (b.expand.trim().isEmpty) {
          bad('是模板展开的积木，可是没写模板（expand）');
          break;
        }
        final Map<String, List<String>> holes;
        try {
          holes = libTemplateHoles(b.expand);
        } on Object catch (e) {
          bad('模板读不了：${lcProblemText(e)}');
          break;
        }
        for (final s in holes['槽']!) {
          if (!slots.contains(s)) bad('模板里用了外观上没有的槽「$s」');
          if (b.kindOf(s) == LibSlotKind.mouth || b.kindOf(s) == LibSlotKind.assign) bad('槽「$s」不是值槽，模板里不能写 (槽 $s)');
        }
        // 一个槽在模板里只许出现一次：出现两次，槽里的东西就会被算两遍。要用两次，先 (设 临时 (槽 名)) 存起来。
        final seen = <String>{};
        for (final s in holes['槽']!) {
          if (!seen.add(s)) bad('槽「$s」在模板里出现了不止一次：先用 (设 临时名 (槽 $s)) 存起来，后面用临时名');
        }
        for (final s in holes['口']!) {
          if (b.kindOf(s) != LibSlotKind.mouth) bad('模板里的 (口 $s) 指的不是一个口');
        }
        for (final s in holes['放进']!) {
          if (b.kindOf(s) != LibSlotKind.assign) bad('模板里的 (放进 $s …) 指的不是一个“放进变量”的槽');
        }
        for (final s in holes['隐含']!) {
          if (!b.needs.contains(s) && !b.provides.containsKey(s)) bad('模板里用了“$s”，要在 needs 里写上它');
        }
        for (final s in holes['设置']!) {
          if (lib.setting(s) == null) bad('模板里用了库里没有的设置项「$s」');
        }
    }
    for (final a in b.args) {
      if (a is LibArgContext && !b.needs.contains(a.name)) bad('实参里用了“${a.name}”，要在 needs 里写上它');
      if (a is LibArgSetting && lib.setting(a.id) == null) bad('实参里用了库里没有的设置项「${a.id}」');
    }
    final fn = b.legacyFn;
    if (fn != null) {
      if (!lib.builtin) {
        bad('写了旧名对照（legacy）。只有应用自带的库可以写');
      } else if (!legacy.add(fn)) {
        bad('旧名「$fn」被两块积木同时认领了');
      }
      for (final a in b.legacyArgs) {
        final ok = a.startsWith('@') ? b.needs.contains(a.substring(1)) : slots.contains(a);
        if (!ok) bad('旧名对照的参数「$a」既不是这块积木的槽，也不是它要用的隐含的东西');
      }
    }
  }
  for (final (what, template) in [('init', lib.init), ('start', lib.start)]) {
    if (template.trim().isEmpty) continue;
    try {
      final holes = libTemplateHoles(template);
      for (final s in holes['设置']!) {
        if (lib.setting(s) == null) out.add('清单的 $what 里用了库里没有的设置项「$s」');
      }
      if (holes['槽']!.isNotEmpty || holes['口']!.isNotEmpty || holes['放进']!.isNotEmpty) out.add('清单的 $what 里不能用槽、口、放进（它不是积木）');
    } on Object catch (e) {
      out.add('清单的 $what 读不了：${lcProblemText(e)}');
    }
  }
  for (final t in lib.types) {
    final m = lib.modules.where((m) => m.name == t.module).firstOrNull;
    if (m == null || !m.decls.any((d) => d.name == t.name)) out.add('清单里说公开了类型「${t.name}」，模块「${t.module}」里没有它');
  }
  if (!lib.builtin) {
    if (lib.settings.any((s) => s.legacyKey != null)) out.add('设置项里写了旧文档的键（legacyKey）。只有应用自带的库可以写');
  }
  return out;
}
