/// 库的导出文件（`.lopilib`）：就是库文件夹打成的一个 zip。这里管打包、拆包、导入前的预览。不碰磁盘、不联网、不执行任何东西。
///
/// 拆包时的防护（设计 C 分册 10.4）：
/// - 整个文件最多 8MB，里面最多 512 个文件，单个文件解出来最多 1MB（清单最多 256KB），解出来的总量最多 16MB；
/// - 文件名里有 `..`、以 `/` 开头、带盘符或反斜杠的，整包不要；
/// - 只留库认识的那几样：清单、积木表、`modules/`、`source/`（画布原件）、`native/`（手写代码，只给看）；
/// - 作者段 `lopi`、`local` 是应用自己留着用的，别的库不许用（读入器里拦）。
///
/// 手写代码（`native/`）：这一版的应用**不会**把它放进生成的工程里。所以带手写代码的库导入时如实显示有哪些文件、
/// 可以点开看，但是不许启用（见 [BeLibPreview.canImport]）。差的是：五种语言各自怎么把手写文件接进工程、怎么声明它的函数
/// 的类型和“要不要等”（清单里的 `native.waits` 已经读进来了，只显示）、以及运行环境里的隔离。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';

/// 导出文件的扩展名。
const String kBeLibFileSuffix = '.lopilib';

const int kBeLibMaxPackBytes = 8 * 1024 * 1024;
const int kBeLibMaxPackFiles = 512;
const int kBeLibMaxFileBytes = 1024 * 1024;
const int kBeLibMaxManifestBytes = 256 * 1024;
const int kBeLibMaxTotalBytes = 16 * 1024 * 1024;

/// 库文件（相对路径 → 内容）→ 一个 zip。文件按名字排好、时间固定，所以同样的库打出来的包一个字节不差。
Uint8List beLibPack(Map<String, String> files) {
  final archive = Archive();
  for (final name in files.keys.toList()..sort()) {
    final bytes = utf8.encode(files[name]!);
    archive.addFile(ArchiveFile(name, bytes.length, bytes)..lastModTime = 0);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive) ?? const []);
}

/// 拆包的结果：成了是文件表；不成是一句原因。
typedef BeLibUnpacked = ({Map<String, String>? files, String? problem});

bool _safeName(String name) =>
    name.isNotEmpty &&
    name.length <= 200 &&
    !name.startsWith('/') &&
    !name.contains('\\') &&
    !name.contains('\u0000') &&
    !RegExp(r'^[A-Za-z]:').hasMatch(name) &&
    !name.split('/').any((part) => part == '..' || part == '.' || part.isEmpty);

bool _known(String name) => name == kLibManifestFile || name.startsWith('modules/') || name.startsWith('source/') || name.startsWith('native/') || (!name.contains('/') && name.endsWith('.json'));

/// 拆一个 `.lopilib`。任何输入都不抛异常。
BeLibUnpacked beLibUnpack(List<int> bytes) {
  if (bytes.length > kBeLibMaxPackBytes) return (files: null, problem: '这个文件太大了（超过 8MB），不像是一个库');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    return (files: null, problem: '这个文件打不开：它不是一个库的导出文件');
  }
  if (archive.files.length > kBeLibMaxPackFiles) return (files: null, problem: '包里的文件太多了（超过 $kBeLibMaxPackFiles 个）');
  final out = <String, String>{};
  var total = 0;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name;
    if (!_safeName(name)) return (files: null, problem: '包里有一个文件的名字不对劲（$name），整包都没有要');
    if (!_known(name)) continue;
    final limit = name == kLibManifestFile ? kBeLibMaxManifestBytes : kBeLibMaxFileBytes;
    if (f.size > limit) return (files: null, problem: '包里的 $name 太大了');
    total += f.size;
    if (total > kBeLibMaxTotalBytes) return (files: null, problem: '包解开以后太大了');
    try {
      out[name] = utf8.decode(f.content as List<int>);
    } on Object {
      return (files: null, problem: '包里的 $name 不是文字，读不了');
    }
  }
  if (!out.containsKey(kLibManifestFile)) return (files: null, problem: '包里没有清单（$kLibManifestFile），它不是一个库');
  return (files: out, problem: null);
}

/// 导入前给人看的东西。
class BeLibPreview {
  const BeLibPreview({
    required this.files,
    required this.lib,
    this.blocks = const [],
    this.needs = const [],
    this.nativeFiles = const [],
    this.problems = const [],
    this.hasSource = false,
    this.nativeBlocked = false,
  });

  final Map<String, String> files;
  final LibLibrary lib;

  /// 积木清单：每块一句（它的文字样子）。
  final List<String> blocks;

  /// 要用到的宿主能力和别的库（给人看的话）。
  final List<String> needs;

  /// 手写代码的文件名（`native/…`）。内容在 [files] 里，可以点开看。
  final List<String> nativeFiles;

  /// 不能导入的原因。空＝可以导入。
  final List<String> problems;

  /// 带没带画布原件（带了才能回到画布上接着改）。
  final bool hasSource;

  String get name => lib.name;
  String get id => lib.id;
  String get author => lib.author.isEmpty ? '（没写）' : lib.author;
  String get version => lib.version;
  bool get hasNative => nativeFiles.isNotEmpty;

  /// 带了手写代码、而全应用的开关关着：不能导入就是因为这个。
  final bool nativeBlocked;
  bool get canImport => problems.isEmpty;
}

/// 一块积木在清单里怎么写：把槽写成〔名字〕。
String beLibBlockLine(LibBlock b) => b.look.template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) => '〔${m[1]}〕');

/// 宿主能力用人话怎么说（预览页、库的面板都用）。
String beHostWord(String host) => _hostWords[host] ?? langHostSig(host)?.label ?? host;

const Map<String, String> _hostWords = {
  'http.serve': '开一个网络服务（听一个端口）',
  'net.fetch': '请求别的网址',
  'store.read': '读数据集合',
  'store.update': '写数据集合',
  'sys.env': '读环境变量',
  'sys.print': '往日志里写字',
  'time.now': '看现在的时间',
  'time.sleep': '等一会儿',
};

/// 文件表 → 预览。[others]＝项目里已经有的库（查“它靠的库在不在”）。
/// `nativeEnabled`＝全应用“允许库里的手写代码”开没开（不给就问 [LibNativeTrust]）。
BeLibPreview beLibPreview(Map<String, String> files, {List<LibLibrary> others = const [], bool? nativeEnabled}) {
  // 先按“手写代码许用”读一遍：看的是库本身有没有毛病；许不许导入另算。
  final lib = libRead(files, builtin: false, nativeOk: true);
  final native = [
    for (final name in files.keys)
      if (name.startsWith('native/')) name,
  ]..sort();
  final problems = <String>[...lib.problems];
  final blocked = native.isNotEmpty && !(nativeEnabled ?? LibNativeTrust.instance.enabled);
  if (blocked) {
    problems.add(libNativeCodeEntry ? '这个库带了手写代码，而“允许库里的手写代码”是关着的（设置 › 能力 › 积木库的手写代码）。关着的时候带手写代码的库一律不能导入' : '这个库带了手写代码。$kLibNativeOffNote，所以不能导入');
  }
  final service = beServiceLibrary();
  final needs = <String>[];
  for (final r in lib.requires) {
    if (r == kBeServiceLibId) {
      needs.add('要靠应用自带的“${service.name}”库（${[for (final h in service.hosts) _hostWords[h] ?? h].join('、')}）');
    } else {
      final have = others.where((l) => l.id == r).firstOrNull;
      needs.add(have == null ? '要靠库「$r」（项目里还没有，要先把它导进来）' : '要靠库「${have.name}」（$r）');
    }
  }
  for (final h in lib.hosts) {
    needs.add('直接用宿主能力：${beHostWord(h)}');
  }
  if (lib.replaces == kBeServiceLibId) needs.add('它是用来顶替应用自带的“${service.name}”的：要你在文档里指定“用它顶替”才生效，那以后接口、返回、数据集合这些积木都走它');
  if (lib.ok && problems.isEmpty) {
    final deps = [
      if (lib.requires.contains(kBeServiceLibId)) service,
      for (final l in others)
        if (lib.requires.contains(l.id)) l,
    ];
    final missing = lib.requires.where((r) => r != kBeServiceLibId && !others.any((l) => l.id == r));
    if (missing.isEmpty) problems.addAll(beLibCheckWith(lib, deps));
  }
  return BeLibPreview(
    files: files,
    lib: lib,
    blocks: [for (final b in lib.blocks) beLibBlockLine(b)],
    needs: needs,
    nativeFiles: native,
    problems: problems,
    hasSource: files.containsKey(kBeLibSourceFile),
    nativeBlocked: blocked,
  );
}
