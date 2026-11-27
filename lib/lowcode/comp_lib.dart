/// 用户自己的组件库（第四轮 B2）：把项目里的自定义组件收成一个库，能导出成一个文件、在别的项目导入。
/// 这里只管数据：库长什么样、怎么从文档里收出来、怎么读（带检查）、怎么装进一份文档。不碰磁盘、不联网、不执行任何东西。
///
/// 一个库三个文件（格式见 docs/lowcode-page-format-v3.md“组件库”一节）：
/// - `lib.json`：清单——`kind: lopicode-complib`、`format: 1`、`id`（作者段/库名）、`name`、`version`、`author`、`side: frontend`（和积木库的“给谁用”同一个写法；B2 写的 `front` 也认）、
///   `components`（每个组件的 id 和名字，给预览看）、`images`（用到的图片）、`missing`（太大没带上的图片）；
/// - `components.json`：`components`（组件定义，和页面文件里 `components` 一个写法）、`themeVars`（用到的主题变量和它们的值）；
/// - `images.json`：图片路径 → 内容（base64）；没有图片就没有这个文件。
/// 导出文件用的是积木库同一种 `.lopilib` 包（backend_lib_pack.dart 的打包、拆包和全部防护）。
///
/// 装进文档：库里的组件拷进文档的 `components`，id 换成 `lib_<库标识>_<原 id>`（同一个库再装一次还是这个 id，所以更新时实例不会断），
/// 定义上记一笔 `lib: {id, name, version, component}`。带这一笔的定义在编辑器里是只读的（要改先“复制一份来改”）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lopicode/lang/lib_native.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

const String kCompLibKind = 'lopicode-complib';
const int kCompLibFormat = 1;
const String kCompLibManifest = 'lib.json';
const String kCompLibDefsFile = 'components.json';
const String kCompLibImagesFile = 'images.json';

/// 定义上记“我是从哪个库来的”的字段。
const String kCompLibMark = 'lib';

/// 自定的数：一个库最多几个组件；带进包里的图片一共最多多大（base64 以后要放进一个不超过 1MB 的文件）。
const int kCompLibMaxComponents = 64;
const int kCompLibMaxImageBytes = 700 * 1024;

/// 标识：`作者段/库名`，小写字母、数字、连字符，字母开头（和积木库同一条规矩）。
final RegExp kCompLibId = RegExp(r'^[a-z][a-z0-9-]{0,23}/[a-z][a-z0-9-]{0,31}$');
final RegExp kCompLibVersion = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');

/// 应用自己留着用的作者段。
bool compLibAuthorReserved(String seg) => seg == 'lopi' || seg == 'local';

class CompLib {
  CompLib({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    List<LcComponentDef>? defs,
    Map<String, String>? images,
    Map<String, String>? themeVars,
    List<String>? missingImages,
    List<String>? problems,
  }) : defs = defs ?? [],
       images = images ?? {},
       themeVars = themeVars ?? {},
       missingImages = missingImages ?? [],
       problems = problems ?? [];
  final String id;
  final String name;
  final String version;
  final String author;

  /// 组件定义（id 是库里的原 id）。
  final List<LcComponentDef> defs;

  /// 图片：项目里的相对路径 → base64。
  final Map<String, String> images;
  final Map<String, String> themeVars;

  /// 用到了、但没带进包里的图片（太大，或者项目里找不到）。
  final List<String> missingImages;

  /// 不能导入的原因；空的＝能导入。
  final List<String> problems;

  bool get ok => problems.isEmpty;

  /// 组件里有没有带逻辑的东西（事件、状态、绑定）。预览里如实写。
  bool get hasLogic => defs.any(lcDefIsLive);
}

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

Set<String> _refsOf(LcComponentDef def) {
  final out = <String>{};
  _walk(def.root, (n) {
    final ref = n.props['ref'];
    if (n.type == 'component' && ref is String) out.add(ref);
  });
  return out;
}

bool _isLocalImage(String src) => src.isNotEmpty && !src.contains(':') && !src.startsWith('/') && !src.startsWith('#');

final RegExp _varUse = RegExp(r'var\(\s*--([A-Za-z0-9_-]+)');

/// 库的文件（相对路径 → 内容）。同样的库写出来一个字不差。
Map<String, String> compLibFiles(CompLib lib) {
  const enc = JsonEncoder.withIndent('  ');
  return {
    kCompLibManifest: enc.convert({
      'kind': kCompLibKind,
      'format': kCompLibFormat,
      'id': lib.id,
      'name': lib.name,
      'version': lib.version,
      'author': lib.author,
      'side': LibSide.frontend.name,
      'components': [
        for (final d in lib.defs) {'id': d.id, 'name': d.name},
      ],
      if (lib.images.isNotEmpty) 'images': lib.images.keys.toList()..sort(),
      if (lib.missingImages.isNotEmpty) 'missing': lib.missingImages,
    }),
    kCompLibDefsFile: enc.convert({
      'components': [for (final d in lib.defs) d.toJson()],
      if (lib.themeVars.isNotEmpty) 'themeVars': lib.themeVars,
    }),
    if (lib.images.isNotEmpty) kCompLibImagesFile: jsonEncode({for (final k in lib.images.keys.toList()..sort()) k: lib.images[k]}),
  };
}

/// 内容的校验值（判断“同一个标识同一个版本，内容是不是一样”）。
String compLibSum(Map<String, String> files) {
  final keys = files.keys.toList()..sort();
  return sha256.convert(utf8.encode([for (final k in keys) '$k\u0000${files[k]}\u0000'].join())).toString();
}

/// 从文档里收一个库。[ids]：要放进去的组件；它们里面套着的别的组件自动带上。
/// [readImage]：按相对路径读图片的内容，读不到返回 null。从别的库来的组件带进来以后就是这个库自己的了（来源那一笔去掉）。
CompLib compLibFromDoc(LcDocument doc, Iterable<String> ids, {required String id, required String name, required String version, String author = '', List<int>? Function(String rel)? readImage}) {
  final picked = <String>{};
  void take(String cid) {
    final def = doc.component(cid);
    if (def == null || !picked.add(cid)) return;
    _refsOf(def).forEach(take);
  }

  ids.forEach(take);
  final defs = <LcComponentDef>[];
  for (final c in doc.components) {
    if (!picked.contains(c.id)) continue;
    final json = (jsonDecode(jsonEncode(c.toJson())) as Map).cast<String, dynamic>()..remove(kCompLibMark);
    final copy = LcComponentDef.tryParse(json);
    if (copy != null) defs.add(copy);
  }
  final theme = lcThemeOf(doc).values;
  final vars = <String, String>{};
  final images = <String, String>{}, missing = <String>[];
  var bytes = 0;
  void useVars(String text) {
    for (final m in _varUse.allMatches(text)) {
      final v = theme[m[1]!];
      if (v != null && vars[m[1]!] == null) {
        vars[m[1]!] = v;
        useVars(v);
      }
    }
  }

  for (final d in defs) {
    _walk(d.root, (n) {
      useVars(jsonEncode(n.toJson()..remove('children')));
      final src = n.props['src'];
      if (n.type != 'image' || src is! String || !_isLocalImage(src) || images.containsKey(src) || missing.contains(src)) return;
      final data = readImage?.call(src);
      if (data == null || bytes + data.length > kCompLibMaxImageBytes) {
        missing.add(src);
      } else {
        bytes += data.length;
        images[src] = base64Encode(data);
      }
    });
    useVars(jsonEncode(d.more));
  }
  return CompLib(id: id, name: name, version: version, author: author, defs: defs, images: images, themeVars: vars, missingImages: missing);
}

Object? _json(String? text) {
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// 读一个库（文件表 → 库 + 不能导入的原因）。任何输入都不抛异常。
CompLib compLibRead(Map<String, String> files) {
  final problems = <String>[];
  final m = _json(files[kCompLibManifest]);
  String str(String key) => m is Map && m[key] is String ? (m[key] as String).trim() : '';
  if (m is! Map) {
    return CompLib(id: '', name: '', version: '', problems: ['没有清单 $kCompLibManifest，或者它不是合法的 JSON']);
  }
  if (m['kind'] == 'lopicode-lib') {
    return CompLib(id: str('id'), name: str('name'), version: str('version'), author: str('author'), problems: ['这是一个积木库，不是组件库。请到后端积木页的“积木库”里导入']);
  }
  if (m['kind'] != kCompLibKind) problems.add('清单里没写它是组件库（kind 应该是 $kCompLibKind）');
  if (m['format'] is int && (m['format'] as int) > kCompLibFormat) problems.add('这个库是更新版本的应用导出的，这一版读不了');
  final id = str('id'), name = str('name'), version = str('version');
  for (final (key, v) in [('id', id), ('name', name), ('version', version)]) {
    if (v.isEmpty) problems.add('清单缺一项：$key');
  }
  if (id.isNotEmpty && !kCompLibId.hasMatch(id)) problems.add('标识不对（$id）：要写成“作者段/库名”，小写字母、数字、连字符，字母开头');
  if (id.isNotEmpty && kCompLibId.hasMatch(id) && compLibAuthorReserved(id.split('/').first)) problems.add('作者段 lopi、local 是应用自己留着用的');
  if (version.isNotEmpty && !kCompLibVersion.hasMatch(version)) problems.add('版本号不对（$version）：要写成 1.0.0 这样');
  if (m['side'] != LibSide.frontend.name && m['side'] != 'front') problems.add('清单里“给谁用”不是前端（side 应该是 frontend）');
  if (name.length > 40) problems.add('名字太长了（最多 40 个字）');
  if (files.keys.any((k) => k.startsWith('native/')) || m['native'] != null) problems.add('这个库带了手写代码。组件库是只给前端用的，手写代码是照后端的五种语言写的，前端用不了，所以不能导入');

  final body = _json(files[kCompLibDefsFile]);
  final raw = body is Map ? body['components'] : null;
  final defs = <LcComponentDef>[];
  if (raw is! List) {
    problems.add('包里没有组件（$kCompLibDefsFile 不在，或者读不懂）');
  } else {
    if (raw.length > kCompLibMaxComponents) problems.add('组件太多了（最多 $kCompLibMaxComponents 个）');
    final seen = <String>{};
    for (final x in raw.take(kCompLibMaxComponents)) {
      final d = LcComponentDef.tryParse(x is Map ? x.cast<String, dynamic>() : x);
      if (d == null || d.id.isEmpty) {
        problems.add('有一个组件读不懂（${x is Map ? x['name'] ?? x['id'] ?? '没名字' : '不是组件'}）');
      } else if (!seen.add(d.id)) {
        problems.add('有两个组件的 id 一样（${d.id}）');
      } else {
        defs.add(d);
      }
    }
    if (raw.isEmpty) problems.add('这个库里一个组件都没有');
  }
  // 组件之间的引用：只能指向库里的组件，而且不能绕成圈。
  final byId = {for (final d in defs) d.id: d};
  for (final d in defs) {
    for (final r in _refsOf(d)) {
      if (!byId.containsKey(r)) problems.add('组件「${d.name}」里用到了库里没有的组件（$r）');
    }
  }
  final state = <String, int>{};
  bool loops(String cid) {
    if (state[cid] == 1) return true;
    if (state[cid] == 2) return false;
    state[cid] = 1;
    for (final r in _refsOf(byId[cid]!)) {
      if (byId.containsKey(r) && loops(r)) return true;
    }
    state[cid] = 2;
    return false;
  }

  for (final d in defs) {
    if (loops(d.id)) {
      problems.add('组件互相套成了圈（从「${d.name}」出发能绕回它自己），这样的库用不了');
      break;
    }
  }
  final images = <String, String>{};
  final rawImages = _json(files[kCompLibImagesFile]);
  if (rawImages is Map) {
    rawImages.forEach((k, v) {
      if (k is! String || v is! String) return;
      if (!_isLocalImage(k) || k.contains('\\') || k.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
        problems.add('图片的路径不对劲（$k）');
      } else {
        images[k] = v;
      }
    });
  } else if (files.containsKey(kCompLibImagesFile)) {
    problems.add('图片那个文件读不懂');
  }
  final vars = <String, String>{};
  final rawVars = body is Map ? body['themeVars'] : null;
  if (rawVars is Map) {
    rawVars.forEach((k, v) {
      if (k is String && v is String && kLcVarName.hasMatch(k) && lcVarValueOk(v)) vars[k] = v.trim();
    });
  }
  final missing = m['missing'];
  return CompLib(
    id: id,
    name: name,
    version: version,
    author: str('author'),
    defs: defs,
    images: images,
    themeVars: vars,
    missingImages: [
      if (missing is List)
        for (final x in missing.take(64))
          if (x is String) x,
    ],
    problems: problems,
  );
}

// —— 装进文档 ——

/// 库里的组件装进文档以后的 id。
String compLibDefId(String libId, String defId) => 'lib_${libId.replaceAll(RegExp('[^A-Za-z0-9]'), '_')}_$defId';

/// 定义是从哪个库来的；不是库里的返回 null。
({String id, String name, String version, String component})? compLibOf(LcComponentDef def) {
  final m = def.more[kCompLibMark];
  if (m is! Map || m['id'] is! String || !kCompLibId.hasMatch(m['id'] as String)) return null;
  String s(String k) => m[k] is String ? m[k] as String : '';
  return (id: s('id'), name: s('name').isEmpty ? s('id') : s('name'), version: s('version'), component: s('component'));
}

/// 文档里装着哪些库（标识 → 名字、版本），按第一次出现的先后。
Map<String, ({String name, String version})> compLibsInDoc(LcDocument doc) {
  final out = <String, ({String name, String version})>{};
  for (final d in doc.components) {
    final l = compLibOf(d);
    if (l != null) out.putIfAbsent(l.id, () => (name: l.name, version: l.version));
  }
  return out;
}

void _eachPageRoot(LcDocument doc, void Function(LcNode root, String where) visit) {
  for (final p in doc.pages) {
    visit(p.root, '页面「${p.title}」');
  }
  for (final c in doc.components) {
    visit(c.root, '组件「${c.name}」');
  }
}

/// 把库装进文档（已经装过就换成这一版）。返回“重查”发现的问题：用着它的地方有哪些对不上了（一条一句话；空的＝都对得上）。
/// 库有问题（[CompLib.ok] 是 false）时什么都不做，返回那些问题。
List<String> compLibInstall(LcDocument doc, CompLib lib) {
  if (!lib.ok) return lib.problems;
  final newId = {for (final d in lib.defs) d.id: compLibDefId(lib.id, d.id)};
  final fresh = <LcComponentDef>[];
  for (final d in lib.defs) {
    final json = (jsonDecode(jsonEncode(d.toJson())) as Map).cast<String, dynamic>();
    json['id'] = newId[d.id];
    json[kCompLibMark] = {'id': lib.id, 'name': lib.name, 'version': lib.version, 'component': d.id};
    final copy = LcComponentDef.tryParse(json);
    if (copy == null) continue;
    _walk(copy.root, (n) {
      final ref = n.props['ref'];
      if (n.type == 'component' && ref is String && newId[ref] != null) n.props['ref'] = newId[ref];
    });
    fresh.add(copy);
  }
  final freshIds = {for (final d in fresh) d.id};
  // 这个库上一版有、这一版没有的组件：定义留着（用着它的地方不至于坏掉），只是不再算这个库的。
  for (final old in doc.components) {
    if (compLibOf(old)?.id == lib.id && !freshIds.contains(old.id)) old.more.remove(kCompLibMark);
  }
  for (final d in fresh) {
    final at = doc.components.indexWhere((c) => c.id == d.id);
    if (at >= 0) {
      doc.components[at] = d;
    } else {
      doc.components.add(d);
    }
  }
  // 主题变量：项目里没有的补上（已经有的不动——以项目自己的为准）。
  if (lib.themeVars.isNotEmpty) {
    final raw = doc.more['theme'];
    final vars = <String, dynamic>{if (raw is Map && raw['vars'] is Map) ...(raw['vars'] as Map).cast<String, dynamic>()};
    var added = false;
    lib.themeVars.forEach((k, v) {
      if (!vars.containsKey(k)) {
        vars[k] = v;
        added = true;
      }
    });
    if (added) doc.more['theme'] = {if (raw is Map) ...raw.cast<String, dynamic>(), 'vars': vars};
  }
  return compLibRecheck(doc, freshIds);
}

/// 重查：用着这些组件的地方，填的插槽、选的变体、接的事件、绑的属性在新定义里还在不在。
List<String> compLibRecheck(LcDocument doc, Set<String> defIds) {
  final out = <String>[];
  _eachPageRoot(doc, (root, where) {
    _walk(root, (n) {
      final ref = n.props['ref'];
      if (n.type != 'component' || ref is! String || !defIds.contains(ref)) return;
      final def = doc.component(ref);
      if (def == null) return;
      final slots = {for (final s in def.slots) s.name};
      for (final c in n.children) {
        final s = c.slot;
        if (s != null && s.isNotEmpty && !slots.contains(s)) out.add('$where里的「${def.name}」：填在插槽 $s 里的内容没地方放了（新版没有这个插槽）');
      }
      if (slots.isEmpty && n.children.isNotEmpty) out.add('$where里的「${def.name}」：新版没有插槽，原来填进去的内容显示不出来');
      final groups = lcVariants(def);
      final picked = n.more[kLcVariant];
      if (picked is Map) {
        picked.forEach((g, v) {
          if (!groups.any((x) => x.group == g && x.name == v)) out.add('$where里的「${def.name}」：选的变体 $v 新版没有了');
        });
      }
      final events = {for (final e in lcCompEvents(def)) e.name};
      for (final e in lcOnOf(n).keys) {
        if (!events.contains(e)) out.add('$where里的「${def.name}」：接了动作的事件 $e 新版没有了');
      }
      final values = n.props['values'], data = n.more['data'];
      for (final k in {if (values is Map) ...values.keys, if (data is Map) ...data.keys}) {
        if (k is String && def.prop(k) == null) out.add('$where里的「${def.name}」：属性 $k 新版没有了');
      }
    });
  });
  return out;
}

/// “复制一份来改”：把一个库里的组件另存成项目自己的组件（新 id、去掉来源那一笔），返回新组件的 id；找不到返回 null。
/// 它里面套着的别的组件还是指向原来那些。
String? compLibFork(LcDocument doc, String defId) {
  final def = doc.component(defId);
  if (def == null) return null;
  var i = 1;
  while (doc.component('c$i') != null) {
    i++;
  }
  final json = (jsonDecode(jsonEncode(def.toJson())) as Map).cast<String, dynamic>()
    ..remove(kCompLibMark)
    ..['id'] = 'c$i';
  final names = {for (final c in doc.components) c.name};
  var name = '${def.name} 副本', k = 2;
  while (names.contains(name)) {
    name = '${def.name} 副本 ${k++}';
  }
  json['name'] = name;
  final copy = LcComponentDef.tryParse(json);
  if (copy == null) return null;
  doc.components.add(copy);
  return copy.id;
}

/// 把一个库从文档里拿掉：没人用的定义删掉；还有人用的留着、变成项目自己的组件。返回留下了几个。
int compLibRemoveFromDoc(LcDocument doc, String libId) {
  final used = <String>{};
  _eachPageRoot(doc, (root, _) {
    _walk(root, (n) {
      final ref = n.props['ref'];
      if (n.type == 'component' && ref is String) used.add(ref);
    });
  });
  var kept = 0;
  doc.components.removeWhere((c) {
    if (compLibOf(c)?.id != libId) return false;
    if (!used.contains(c.id)) return true;
    c.more.remove(kCompLibMark);
    kept++;
    return false;
  });
  return kept;
}
