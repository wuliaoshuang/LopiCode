// 打包的核心流程：纯函数、同步读写盘，整个放在后台 isolate 里跑（见 apk_packer.dart 的门面）。
//
// 流程：核对输入和模板 → 收集网页文件 → 改清单 → 换图标 → 组装条目 → 签名（v1 文件 + 对齐写 ZIP + v2）→ 先写临时文件再改名。
// 同样的输入（模板、网页文件、参数）在签名前一定产出同样的字节：条目顺序固定、时间戳固定、不写任何“当前时间”。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_signer.dart';
import 'package:lopicode/apkpack/apk_validators.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/manifest_editor.dart';
import 'package:lopicode/apkpack/web_project.dart';
import 'package:lopicode/apkpack/zip/zip_model.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:lopicode/apkpack/zip/zip_writer.dart';
import 'package:path/path.dart' as p;

const String kApkManifestEntry = 'AndroidManifest.xml';
const String kApkArscEntry = 'resources.arsc';
const String kApkWebPrefix = 'assets/www/';
const String kApkShellConfigEntry = 'assets/lopi_shell.json';

/// 模板里各密度图标的路径。aapt2 会给密度目录补上 `-v4` 这样的版本后缀，所以后缀可有可无。
final RegExp _iconPath = RegExp(r'^res/mipmap-(mdpi|hdpi|xhdpi|xxhdpi|xxxhdpi)(-v\d+)?/ic_launcher\.png$');

/// 本身已经压缩过的格式：再压一遍白费时间，直接存；媒体文件不压缩还能让网页边读边播。
const Set<String> kNoCompressExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'heic', 'mp3', 'mp4', 'm4a', 'm4v', 'aac', 'ogg', 'oga', 'ogv', 'opus', 'webm', 'mov', 'flac', //
  'woff', 'woff2', 'zip', 'gz', 'br', 'zst', '7z', 'rar', 'apk', 'jar',
};

bool _isSignatureFile(String name) {
  if (!name.startsWith('META-INF/')) return false;
  final up = name.toUpperCase();
  return up == 'META-INF/MANIFEST.MF' || up.endsWith('.SF') || up.endsWith('.RSA') || up.endsWith('.DSA') || up.endsWith('.EC');
}

ApkPackException _templateError(Object e) {
  final detail = switch (e) {
    AxmlFormatException() => e.message,
    ZipFormatException() => e.message,
    _ => '$e',
  };
  return ApkPackException('安装包模板损坏或不匹配：$detail。这是 LopiCode 自己的问题，不是你的项目的问题，请把这句话反馈给开发者。', field: 'template');
}

/// 模板解析后的结果。
class ShellTemplate {
  ShellTemplate._(this.entries, this.manifest, this.info, this.iconPaths, this.shellConfig);
  final List<ZipEntry> entries;
  final Uint8List manifest;
  final ManifestInfo info;

  /// 密度（mdpi…）→ 模板里的图标条目名。
  final Map<String, String> iconPaths;
  final Map<String, Object?> shellConfig;
}

/// 解析并核对模板：是合法 ZIP、有清单 / 资源表 / 代码 / 五个密度的图标、清单符合约定。不符合抛 [ApkPackException]（field: template）。
ShellTemplate parseShellTemplate(Uint8List template) {
  try {
    final entries = readZip(template);
    ZipEntry? find(String name) {
      for (final e in entries) {
        if (e.name == name) return e;
      }
      return null;
    }

    final m = find(kApkManifestEntry);
    if (m == null) throw const ZipFormatException('里面没有 AndroidManifest.xml');
    if (find(kApkArscEntry) == null) throw const ZipFormatException('里面没有 resources.arsc');
    if (find('classes.dex') == null) throw const ZipFormatException('里面没有 classes.dex');
    final manifest = m.content();
    final info = readManifestInfo(manifest);
    if (info.packageName != kShellDefaultPackage) throw AxmlFormatException('模板的包名应该是 $kShellDefaultPackage，实际是 ${info.packageName}');
    final icons = <String, String>{};
    for (final e in entries) {
      final hit = _iconPath.firstMatch(e.name);
      if (hit != null) {
        if (icons.containsKey(hit[1])) throw ZipFormatException('${hit[1]} 密度的图标有两份');
        icons[hit[1]!] = e.name;
      }
    }
    final lost = kIconDensities.values.where((d) => !icons.containsKey(d)).toList();
    if (lost.isNotEmpty) throw ZipFormatException('缺少这些密度的图标（res/mipmap-密度/ic_launcher.png）：${lost.join('、')}');
    var config = <String, Object?>{};
    final c = find(kApkShellConfigEntry);
    if (c != null) {
      try {
        final j = jsonDecode(utf8.decode(c.content()));
        if (j is Map<String, Object?>) config = j;
      } on FormatException {
        throw const ZipFormatException('assets/lopi_shell.json 不是合法的 JSON');
      }
    }
    return ShellTemplate._(entries, manifest, info, icons, config);
  } on AxmlFormatException catch (e) {
    throw _templateError(e);
  } on ZipFormatException catch (e) {
    throw _templateError(e);
  }
}

/// 核对一次打包的全部输入；有问题抛 [ApkPackException]（带 field）。
void validatePackRequest(ApkPackRequest r) {
  void check(String? problem, String field) {
    if (problem != null) throw ApkPackException(problem, field: field);
  }

  check(validatePackageName(r.packageName), 'packageName');
  check(validateAppName(r.appName), 'appName');
  check(validateVersionName(r.versionName), 'versionName');
  check(validateVersionCode(r.versionCode), 'versionCode');
  for (final perm in r.permissions) {
    check(validatePermission(perm), 'permissions');
  }
  if (r.iconPngs.isNotEmpty) {
    final lost = kIconDensities.keys.where((s) => !r.iconPngs.containsKey(s)).toList();
    if (lost.isNotEmpty) check('图标要五种尺寸都给齐，还缺：${lost.join('、')} 像素', 'icon');
    for (final e in r.iconPngs.entries) {
      check(validateIconPng(e.key, e.value), 'icon');
    }
  }
  final entry = r.entry.replaceAll('\\', '/');
  if (entry.isEmpty || entry.startsWith('/') || entry.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
    check('入口文件的路径不对：${r.entry}', 'project');
  }
  if (r.webRoot.isEmpty || !p.isAbsolute(r.webRoot)) check('网页目录的路径不对', 'project');
  if (r.outputPath.isEmpty || !p.isAbsolute(r.outputPath)) check('输出位置的路径不对', 'project');
}

/// 组装出签名前的全部条目（不含签名文件）。返回 (条目, 网页文件数)。
(List<ZipEntry>, int) buildApkEntries(ShellTemplate shell, ApkPackRequest request, void Function(ApkPackProgress) report) {
  report(const ApkPackProgress(ApkPackStep.collect, detail: '正在找要打包的网页文件'));
  final tmpPath = _tmpPathFor(request.outputPath);
  final files = collectWebFiles(request.webRoot, entry: request.entry, skipPaths: {request.outputPath, tmpPath});
  final total = files.fold<int>(0, (a, f) => a + f.size);
  report(ApkPackProgress(ApkPackStep.collect, detail: '${files.length} 个文件，共 ${_size(total)}'));

  report(const ApkPackProgress(ApkPackStep.manifest, detail: '写入包名、应用名、版本和权限'));
  final Uint8List manifest;
  try {
    manifest = editManifestBytes(
      shell.manifest,
      ManifestEdit(packageName: request.packageName, appName: request.appName, versionCode: request.versionCode, versionName: request.versionName, permissions: request.permissions),
    );
  } on AxmlFormatException catch (e) {
    throw _templateError(e);
  }

  report(ApkPackProgress(ApkPackStep.icon, detail: request.iconPngs.isEmpty ? '用默认图标' : '换上你的图标'));
  final iconByPath = {for (final e in request.iconPngs.entries) shell.iconPaths[kIconDensities[e.key]]!: e.value};

  final out = <ZipEntry>[];
  try {
    for (final e in shell.entries) {
      if (e.name.startsWith(kApkWebPrefix) || e.name == kApkShellConfigEntry || _isSignatureFile(e.name)) continue;
      if (e.name == kApkManifestEntry) {
        out.add(ZipEntry.deflated(e.name, manifest));
      } else if (iconByPath[e.name] case final Uint8List png) {
        out.add(ZipEntry.stored(e.name, png));
      } else if (e.name == kApkArscEntry && e.method != kZipStored) {
        out.add(ZipEntry.stored(e.name, e.content())); // 资源表必须不压缩
      } else {
        out.add(e);
      }
    }
  } on ZipFormatException catch (e) {
    throw _templateError(e);
  }
  final config = {...shell.shellConfig, 'entry': request.entry.replaceAll('\\', '/')};
  out.add(ZipEntry.deflated(kApkShellConfigEntry, Uint8List.fromList(utf8.encode(jsonEncode(config)))));

  var done = 0;
  for (final f in files) {
    final Uint8List data;
    try {
      data = File(f.path).readAsBytesSync();
    } on FileSystemException catch (e) {
      throw ApkPackException('读不了文件 ${f.rel}：${e.osError?.message ?? e.message}', field: 'project');
    }
    final name = '$kApkWebPrefix${f.rel}';
    final ext = p.extension(f.rel).toLowerCase().replaceFirst('.', '');
    out.add(kNoCompressExtensions.contains(ext) ? ZipEntry.stored(name, data) : ZipEntry.deflated(name, data));
    done++;
    if (done % 50 == 0 || done == files.length) report(ApkPackProgress(ApkPackStep.zip, detail: '已压缩 $done / ${files.length} 个文件'));
  }
  return (out, files.length);
}

/// 整个打包。能预料的失败都抛 [ApkPackException]。
ApkPackResult packApkSync(Uint8List template, ApkSigner signer, ApkPackRequest request, void Function(ApkPackProgress) report) {
  report(const ApkPackProgress(ApkPackStep.check, detail: '核对填写的信息和安装包模板'));
  validatePackRequest(request);
  final shell = parseShellTemplate(template);
  final (entries, fileCount) = buildApkEntries(shell, request, report);

  report(const ApkPackProgress(ApkPackStep.sign, detail: '正在签名'));
  // 签名要每个条目解压后的内容。这里解不开的只可能是模板里原样带过来的条目（网页文件是刚压的），所以算模板坏了
  final Map<String, Uint8List> contents;
  try {
    contents = {for (final e in entries) e.name: e.content()};
  } on ZipFormatException catch (e) {
    throw _templateError(e);
  }
  final Uint8List signed;
  try {
    final v1 = signer.v1Files(contents);
    final names = v1.keys.toList()..sort();
    for (final name in names) {
      if (!name.startsWith('META-INF/')) throw ApkPackException('签名出了问题：签名文件的位置不对（$name）。', field: 'key');
      entries.add(ZipEntry.deflated(name, v1[name]!));
    }
    signed = signer.v2(writeZip(entries));
  } on ZipFormatException catch (e) {
    throw ApkPackException('安装包装不下：${e.message}。', field: 'project');
  }

  report(const ApkPackProgress(ApkPackStep.write, detail: '保存安装包'));
  final tmp = File(_tmpPathFor(request.outputPath));
  try {
    tmp.parent.createSync(recursive: true);
    tmp.writeAsBytesSync(signed, flush: true);
    tmp.renameSync(request.outputPath);
  } on FileSystemException catch (e) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on FileSystemException {
      // 临时文件删不掉就算了，下次打包会覆盖它
    }
    throw ApkPackException('安装包保存不了：${e.osError?.message ?? e.message}（可能是存储空间不够，或者没有写入权限）。');
  }
  final result = ApkPackResult(
    path: request.outputPath,
    sizeBytes: signed.length,
    packageName: request.packageName,
    appName: request.appName,
    versionName: request.versionName,
    versionCode: request.versionCode,
    fileCount: fileCount,
    sha256Hex: sha256.convert(signed).toString(),
    certSha256Hex: signer.certSha256Hex,
  );
  report(ApkPackProgress(ApkPackStep.done, detail: '打包完成，${_size(signed.length)}'));
  return result;
}

String _tmpPathFor(String outputPath) => '$outputPath.part';

String _size(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB' : '${(bytes / 1024).ceil()}KB';
