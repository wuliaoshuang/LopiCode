/// 把应用自带的“接口服务”库“复制一份来改”，和“改库的文字”（积木第 5 版·第四轮）。
///
/// 自带库没有画布上的原样（它是直接用语言核心的文字写法写的，底下直接接宿主接口），所以复制出来的那一份也是文字写法的：
/// 三个文件原样带过去（清单、模块、积木表），换掉标识、名字、模块名和启动时用的变量名，清单里写明
/// “它顶替 lopi/service”“它直接用了哪些宿主接口”。文档指定“用它顶替”以后，接口、返回、数据集合这些积木都走它。
/// 改它＝改这三个文件的文字（[beLibSaveText]）：存之前照读库的规矩查一遍，查不过不存。
/// 为什么这么定见 docs/blocks-v5-parts/library-format.md 第 19 节。
library;

import 'dart:convert';

import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lang/lc_locate.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';

/// 自带库启动时用的那个变量（清单的 init / start / provides 里）。复制件要换一个名字，两个库同时在也不撞。
const String _kRoutesVar = '接口服务的路由表';

/// 复制件的三个文件。标识、名字不合规矩返回原因。
({Map<String, String>? files, String? problem}) beServiceForkFiles({required String id, required String name}) {
  if (!kLibIdPattern.hasMatch(id)) return (files: null, problem: '标识要写成“作者段/库名”：小写字母、数字、连字符，字母开头');
  if (beLibAuthorReserved(id.split('/').first)) return (files: null, problem: '作者段 lopi、local 是应用自己留着用的，换一个');
  final title = name.trim();
  if (title.isEmpty || title.length > 24) return (files: null, problem: '库的名字要 1 到 24 个字');
  // 复制件直接用宿主接口；“自己的库直接用宿主接口”关着时（rules.dart 的 userLibHostEntry）复制出来必然用不了，所以干脆不复制。
  if (!userLibHostEntry) return (files: null, problem: kServiceForkOffNote);
  final base = beServiceLibrary();
  final manifest = jsonDecode(kBeServiceManifest) as Map<String, dynamic>;
  final routes = '路由表_${id.replaceAll(RegExp('[^a-z0-9]'), '_')}';
  String swap(Object? text) => '$text'.replaceAll(_kRoutesVar, routes);
  final out = <String, dynamic>{
    for (final e in manifest.entries)
      if (e.key != 'autoUse') e.key: e.value,
    'id': id,
    'name': title,
    'version': '1.0.0',
    'summary': '从“${base.name}”复制来改的',
    'for': 'backend',
    'replaces': kBeServiceLibId,
    'origin': {'id': kBeServiceLibId, 'version': base.version},
    'hosts': base.hosts,
    'modules': [
      {'file': 'modules/service.lc', 'name': id},
    ],
    'types': [
      for (final t in manifest['types'] as List) {...(t as Map<String, dynamic>), 'module': id},
    ],
    'init': swap(manifest['init']),
    'start': swap(manifest['start']),
    'provides': {for (final e in (manifest['provides'] as Map<String, dynamic>).entries) e.key: swap(e.value)},
  };
  const head = '(模块 接口服务';
  final at = kBeServiceModuleLc.indexOf(head);
  if (at < 0) return (files: null, problem: '自带库的模块文件不是预期的样子，复制不了');
  final module = kBeServiceModuleLc.replaceRange(at, at + head.length, '(模块 $id');
  final files = {kLibManifestFile: '${const JsonEncoder.withIndent('  ').convert(out)}\n', 'modules/service.lc': module, 'blocks.json': kBeServiceBlocks};
  final read = libRead(files, builtin: false);
  if (!read.ok) return (files: null, problem: '复制出来的库读不了：${read.problems.first}');
  return (files: files, problem: null);
}

/// 把“接口服务”复制一份放进项目。成了返回新库的标识。
Future<({String? id, String? problem})> beServiceFork(PathGuard guard, {required String id, required String name}) async {
  final made = beServiceForkFiles(id: id, name: name);
  final files = made.files;
  if (files == null) return (id: null, problem: made.problem);
  final all = await beLibsRead(guard);
  if (all.any((s) => s.id == id)) return (id: null, problem: '项目里已经有标识是 $id 的库了，换一个');
  if (all.length >= kBeMaxProjectLibs) return (id: null, problem: '一个项目最多放 $kBeMaxProjectLibs 个库');
  final bad = await beLibWriteFolder(guard, id, files, from: 'copy');
  return bad == null ? (id: id, problem: null) : (id: null, problem: bad);
}

/// 能在应用里改文字的文件：清单、模块、积木表（手写代码、画布原件不在这里改）。
List<String> beLibTextFiles(BeStoredLib s) => [
  for (final f in s.files.keys.toList()..sort())
    if (f == kLibManifestFile || f.startsWith('modules/') || (!f.contains('/') && f.endsWith('.json'))) f,
];

/// 查一遍“把 [rel] 改成 [text] 以后这个库还读不读得了”，不存。没问题返回 null；有问题返回原因，能说出行的带着“第几行”。
/// 有画布原件的库不走这条路（那种库在画布上改，文字是画布出的）。
Future<String?> beLibCheckText(PathGuard guard, String id, String rel, String text) async => (await _checkText(guard, id, rel, text)).problem;

Future<({String? problem, Map<String, String>? files})> _checkText(PathGuard guard, String id, String rel, String text) async {
  ({String? problem, Map<String, String>? files}) no(String why) => (problem: why, files: null);
  final stored = await beLibsRead(guard);
  final s = stored.where((x) => x.id == id).firstOrNull;
  if (s == null) return no('项目里没有库 $id');
  if (s.hasSource) return no('这个库有画布上的原样，请在画布上改');
  if (!beLibTextFiles(s).contains(rel)) return no('这个文件不能在这里改（$rel）');
  if (text.length > kLibMaxFileChars) return no('太长了（最多 $kLibMaxFileChars 个字）');
  // 先看写法本身：括号、引号、JSON 的逗号——这些说得出是第几行。
  final shape = rel.endsWith('.json') ? jsonLocateProblem(text) : lcLocateProblem(text);
  if (shape != null) return no(shape);
  final files = {...s.files, rel: text};
  // 先不管“手写代码许不许用”：这里查的是库本身写得对不对。带手写代码的库改了清单以后，校验值变了，要重新确认才能用。
  final read = libRead(
    {
      for (final e in files.entries)
        if (e.key != kBeLibSourceFile) e.key: e.value,
    },
    builtin: false,
    nativeOk: true,
  );
  if (read.id != id) return no('库的标识不能在这里改（要换标识请“复制一份来改”）');
  if (!read.ok) {
    // 一处写坏常常带出一串连带的问题：只说头一条（那才是根上的），后面有几条说个数。问题里点了名字的，补一句它在这个文件的第几行。
    final first = read.problems.first;
    final line = lcLineOfNamed(text, first);
    final where = line == null ? '' : '（这个文件第 $line 行附近）';
    return no(read.problems.length == 1 ? '$first$where' : '$first$where\n（连带还有 ${read.problems.length - 1} 条，先改好这一条）');
  }
  // 读得进来还不够：模块里的类型对不对，平时是用的时候才和文档一起查的。这里当场和它靠的库放在一起查一遍——
  // 不然“返回类型写错了”这种会被存进去，等到哪份文档用它的时候才冒出来。
  final typed = beLibCheckWith(read, [
    if (read.requires.contains(kBeServiceLibId)) beServiceLibrary(),
    for (final x in stored)
      if (x.ok && x.id != id && read.requires.contains(x.id)) x.lib,
  ]);
  if (typed.isNotEmpty) {
    final line = rel.endsWith('.lc') ? lcLineOfNamed(text, typed.first) : null;
    final where = line == null ? '' : '（这个文件第 $line 行附近）';
    return no(typed.length == 1 ? '${typed.first}$where' : '${typed.first}$where\n（连带还有 ${typed.length - 1} 条，先改好这一条）');
  }
  if (read.natives.isNotEmpty && !LibNativeTrust.instance.enabled) return no(libNativeCodeEntry ? '这个库带手写代码，而“允许库里的手写代码”是关着的' : '这个库带手写代码。$kLibNativeOffNote');
  return (problem: null, files: files);
}

/// 改库里一个文件的文字。存之前照 [beLibCheckText] 查一遍：查不过（或者标识被改了）不存，返回原因。
Future<String?> beLibSaveText(PathGuard guard, String id, String rel, String text) async {
  final checked = await _checkText(guard, id, rel, text);
  final files = checked.files;
  if (files == null) return checked.problem;
  return beLibWriteFolder(guard, id, files);
}
