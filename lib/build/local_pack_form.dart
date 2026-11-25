// 本地打包表单：每个工作区各记各的（应用名、包名、版本、权限、自己选的图标），以及默认值和文件名规则。纯逻辑。
//
// 存盘：`<工作区>/.lopicode/local-pack.json`（原子写；读到坏文件留备份、回默认，不崩）。
//       自己选的图标缩好的五张 PNG 放在 `<工作区>/.lopicode/local-pack-icon/<边长>.png`。
// 钥匙和口令不在这里（钥匙只进 SecretStore，口令哪儿都不存）。
//
// 自定的规则（2026-11-26）：
// - 默认应用名＝工作区名字（去掉首尾空白，最多 [kAppNameDefaultMax] 个字）。
// - 默认包名＝`com.lopicode.app.` + 工作区目录名变来的一段：转小写，只留 a–z、0–9、下划线；
//   一个能用的字符都没有（比如全中文）就用 `p` + 目录名的 6 位校验码；数字开头的前面补 `p`；最长 [kPackageTailMax]。
// - 默认版本名 1.0.0、版本号 1；每成功打包一次，存下来的版本号自动加 1（可以改回去）。
// - 产物文件名＝`应用名-版本名-版本号.apk`，放在工作区的 `build/` 下；名字里不能当文件名的字符换成 `_`；
//   同名文件直接覆盖（同一个版本号重打一次，就是要换掉它）。
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

const int kAppNameDefaultMax = 30;
const int kPackageTailMax = 30;
const String kPackagePrefix = 'com.lopicode.app.';
const String kDefaultVersionName = '1.0.0';
const List<int> kApkIconSizes = [48, 72, 96, 144, 192];
const String kLocalPackFile = 'local-pack.json';
const String kLocalPackIconDir = 'local-pack-icon';

/// 表单的值（不可变）。四个文字项存的是输入框里的原文，校验在点“开始打包”时做。
class LocalPackForm {
  const LocalPackForm({required this.appName, required this.packageName, required this.versionName, required this.versionCode, required this.permissions, this.customIcon = false});

  final String appName;
  final String packageName;
  final String versionName;
  final String versionCode;

  /// 勾上的权限（完整权限名）。
  final Set<String> permissions;

  /// 用的是不是自己选的图标（图在 [kLocalPackIconDir] 里）。
  final bool customIcon;

  LocalPackForm copyWith({String? appName, String? packageName, String? versionName, String? versionCode, Set<String>? permissions, bool? customIcon}) => LocalPackForm(
    appName: appName ?? this.appName,
    packageName: packageName ?? this.packageName,
    versionName: versionName ?? this.versionName,
    versionCode: versionCode ?? this.versionCode,
    permissions: permissions ?? this.permissions,
    customIcon: customIcon ?? this.customIcon,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'appName': appName,
    'packageName': packageName,
    'versionName': versionName,
    'versionCode': versionCode,
    'permissions': permissions.toList()..sort(),
    'customIcon': customIcon,
  };

  /// 默认值。[options] 是权限表（默认勾哪些由它说了算）。
  static LocalPackForm defaults({required String projectId, required String projectName, required List<ApkPermissionOption> options}) => LocalPackForm(
    appName: defaultAppName(projectName),
    packageName: defaultPackageName(projectId),
    versionName: kDefaultVersionName,
    versionCode: '1',
    permissions: {
      for (final o in options)
        if (o.defaultOn) o.id,
    },
  );

  /// 从存盘内容还原；每个字段都先看类型，不对的用 [fallback] 的。权限只留表里有的。
  static LocalPackForm fromJson(Object? json, {required LocalPackForm fallback, required List<ApkPermissionOption> options}) {
    if (json is! Map) return fallback;
    String text(String key, String or) {
      final v = json[key];
      return v is String ? v : or;
    }

    final known = {for (final o in options) o.id};
    final perms = json['permissions'];
    final code = json['versionCode'];
    return LocalPackForm(
      appName: text('appName', fallback.appName),
      packageName: text('packageName', fallback.packageName),
      versionName: text('versionName', fallback.versionName),
      versionCode: code is int ? '$code' : text('versionCode', fallback.versionCode),
      permissions: perms is List
          ? {
              for (final x in perms)
                if (x is String && known.contains(x)) x,
            }
          : fallback.permissions,
      customIcon: json['customIcon'] == true,
    );
  }
}

String defaultAppName(String projectName) {
  final name = projectName.trim();
  if (name.isEmpty) return '我的应用';
  final runes = name.runes.toList();
  return runes.length <= kAppNameDefaultMax ? name : String.fromCharCodes(runes.take(kAppNameDefaultMax));
}

String defaultPackageName(String projectId) {
  var tail = projectId.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '');
  if (tail.isEmpty) {
    // 稳定的小校验码（FNV-1a 32 位），同一个目录名每次算出来一样。
    var h = 0x811c9dc5;
    for (final unit in projectId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    tail = 'p${h.toRadixString(16).padLeft(8, '0').substring(0, 6)}';
  } else if (RegExp('^[0-9_]').hasMatch(tail)) {
    tail = 'p$tail';
  }
  if (tail.length > kPackageTailMax) tail = tail.substring(0, kPackageTailMax);
  return '$kPackagePrefix$tail';
}

/// 产物文件名（不带目录）。
String apkFileName({required String appName, required String versionName, required int versionCode}) {
  String clean(String s) => s.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').replaceAll(RegExp(r'\s+'), '_');
  final name = clean(appName);
  final version = clean(versionName);
  return '${name.isEmpty ? 'app' : name}-${version.isEmpty ? '0' : version}-$versionCode.apk';
}

/// 钥匙备份文件名的开头（放在工作区 `build/` 下，后面跟日期时间）。
const String kKeyBackupPrefix = 'lopicode-key-backup-';

/// 本地打包留在工作区 `build/` 下的东西（安装包、钥匙备份）：远程打包推送 / 上传项目文件时跳过它们。
bool isLocalPackOutput(String relativePath) {
  final parts = relativePath.split('/');
  if (parts.length != 2 || parts.first != 'build') return false;
  return parts.last.endsWith('.apk') || parts.last.startsWith(kKeyBackupPrefix);
}

/// 一个工作区的表单存取。
class LocalPackFormStore {
  LocalPackFormStore(this.guard);
  final PathGuard guard;

  File get file => File(guard.resolve('${PathGuard.reservedDir}/$kLocalPackFile', allowReserved: true));
  Directory get iconDir => Directory(guard.resolve('${PathGuard.reservedDir}/$kLocalPackIconDir', allowReserved: true));

  Future<LocalPackForm> read({required LocalPackForm fallback, required List<ApkPermissionOption> options}) async {
    final json = await readJsonFile(file, accept: (j) => j is Map, label: '本地打包表单');
    return LocalPackForm.fromJson(json, fallback: fallback, options: options);
  }

  Future<void> write(LocalPackForm form) => writeJsonAtomic(file, form.toJson());

  /// 读回自己选的图标；缺任何一张 / 读不了就当没有（用默认图标）。
  Future<Map<int, Uint8List>> readIcons() async {
    final out = <int, Uint8List>{};
    try {
      for (final size in kApkIconSizes) {
        final f = File(p.join(iconDir.path, '$size.png'));
        if (!await f.exists()) return const {};
        out[size] = await f.readAsBytes();
      }
    } on FileSystemException {
      return const {};
    }
    return out;
  }

  Future<void> writeIcons(Map<int, Uint8List> icons) async {
    await iconDir.create(recursive: true);
    for (final entry in icons.entries) {
      await File(p.join(iconDir.path, '${entry.key}.png')).writeAsBytes(entry.value, flush: true);
    }
  }

  Future<void> clearIcons() async {
    try {
      if (await iconDir.exists()) await iconDir.delete(recursive: true);
    } on FileSystemException {
      // 删不掉也无所谓：表单里 customIcon 已经是 false，这些文件不会再被读。
    }
  }
}
