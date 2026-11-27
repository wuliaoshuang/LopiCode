import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

import 'comp_samples.dart';

/// 项目甲：只有组件定义（项目自己做的），一页空白。
LcDocument projectA(List<Map<String, Object?>> defs) => LcDocument.fromJson({
  'version': 3,
  'title': 'Maker',
  'components': defs,
  'root': {'id': 'page', 'type': 'page', 'children': <Object?>[]},
});

Object? _reref(Object? x, Map<String, String> ids) {
  if (x is List) return [for (final v in x) _reref(v, ids)];
  if (x is! Map) return x;
  return {
    for (final e in x.entries) e.key: e.key == 'props' && e.value is Map && ids[(e.value as Map)['ref']] != null ? {...(e.value as Map), 'ref': ids[(e.value as Map)['ref']]} : _reref(e.value, ids),
  };
}

/// 全流程：项目甲里的组件 → 收成库 → 存进甲 → 导出成文件 → 把文件拷进项目乙 → 打开看（预览）→ 落盘、装进乙的文档
/// → 乙的页面用上它们（放实例、填插槽、选变体、接事件——页面就是 comp_samples 里那一页，只是引用换成库里的组件）。
/// 返回乙的文档、预览时读出来的库、导出文件的路径。
Future<({LcDocument doc, CompLib previewed, String packRel, List<String> notes})> compLibFullFlow(
  Directory tmp,
  List<Map<String, Object?>> defs, {
  String id = 'shuang/shop',
  String version = '1.0.0',
}) async {
  final a = PathGuard(p.join(tmp.path, 'a')), b = PathGuard(p.join(tmp.path, 'b'));
  await Directory(a.root).create(recursive: true);
  await Directory(b.root).create(recursive: true);
  final docA = projectA(defs);
  final lib = compLibFromDoc(docA, [for (final d in defs) d['id']! as String], id: id, name: '商城组件', version: version, author: '霜霜');
  final stored = await compLibStore(a, lib);
  if (stored != null) throw StateError(stored);
  final out = await compLibExport(a, (await compLibsRead(a)).single);
  if (out.rel == null) throw StateError(out.problem ?? '没导出');
  await Directory(p.join(b.root, 'exports')).create(recursive: true);
  await File(a.resolve(out.rel!)).copy(b.resolve(out.rel!));
  final opened = await compLibOpenPack(b, (await compLibPackFiles(b)).single, installed: await compLibsRead(b));
  if (!opened.lib.ok) throw StateError(opened.lib.problems.join('；'));
  final wrote = await compLibStore(b, opened.lib, from: 'file');
  if (wrote != null) throw StateError(wrote);
  final docB = projectA(const []);
  final notes = compLibInstall(docB, opened.lib);
  final ids = {for (final d in defs) d['id']! as String: compLibDefId(id, d['id']! as String)};
  final page = (jsonDecode(jsonEncode(_reref(compUserPageJson(defs), ids))) as Map).cast<String, dynamic>();
  page['components'] = (jsonDecode(jsonEncode(docB.toJson())) as Map)['components'];
  return (doc: LcDocument.fromJson(page), previewed: opened.lib, packRel: out.rel!, notes: notes);
}
