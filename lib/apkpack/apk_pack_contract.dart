// 本地打包 APK（模板套壳）的对外约定。三块代码靠这一个文件对齐，改它要同时告诉另外两边：
// - 打包器（lib/apkpack/ 其余文件）：实现 [LocalApkPacker]、[detectWebProject]、各项校验。
// - 签名（lib/apkpack/sign/）：实现 [ApkSigningKey] 的生成 / 存取 / 导入导出，以及 v1、v2 签名。
// - 界面（lib/build/ 下的本地打包页）：只用这里的类型，不直接碰 ZIP / 清单 / 签名细节。
// 全部纯 Dart（不 import 界面库），开发机上的测试能直接产出 APK 给官方工具验。
import 'dart:typed_data';

/// 钥匙备份文件名的开头（界面把备份存在工作区 `build/` 下，后面跟日期时间）。
/// 放在约定里是因为两边都要认它：界面用它起名字，打包器收集网页文件时见到这个开头的文件一律不收——
/// 网页目录恰好就是 `build/` 的项目（构建产物在 build/ 里），不能把钥匙备份装进安装包发出去。
const String kKeyBackupPrefix = 'lopicode-key-backup-';

/// 这个项目能不能走“网页套壳”。
class WebProjectInfo {
  const WebProjectInfo({required this.applicable, required this.reason, this.webRoot, this.entry, this.kind});

  /// false ＝ 不适用（Flutter / 原生 / 纯后端 / 找不到网页入口）。
  final bool applicable;

  /// 给用户看的大白话：适用时说“会打包哪个目录、入口是哪个文件”，不适用时说为什么、该去哪。
  final String reason;

  /// 要放进安装包的网页目录（绝对路径）。
  final String? webRoot;

  /// 入口文件，相对 [webRoot]，例如 `index.html`。
  final String? entry;

  /// `static`（纯网页）、`lowcode`（低代码导出）、`dist`（构建产物目录）等，界面只拿来显示。
  final String? kind;
}

/// 可勾选的权限表里的一项（固定表，由打包器给出；默认只勾联网）。
class ApkPermissionOption {
  const ApkPermissionOption({required this.id, required this.label, required this.hint, this.defaultOn = false});

  /// 完整权限名，例如 `android.permission.INTERNET`。
  final String id;
  final String label;
  final String hint;
  final bool defaultOn;
}

/// 一次打包要的全部输入。图标已经是各密度的 PNG（界面层负责把用户选的图缩好；为空用模板自带的默认图标）。
class ApkPackRequest {
  const ApkPackRequest({
    required this.webRoot,
    required this.entry,
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.permissions,
    required this.outputPath,
    this.iconPngs = const {},
  });

  final String webRoot;
  final String entry;
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;
  final Set<String> permissions;

  /// 键是边长像素：48、72、96、144、192（对应 mdpi…xxxhdpi）。
  final Map<int, Uint8List> iconPngs;

  /// 输出文件的绝对路径（工作区 `build/` 下）。
  final String outputPath;
}

enum ApkPackStep { check, collect, manifest, icon, zip, sign, write, done }

class ApkPackProgress {
  const ApkPackProgress(this.step, {this.detail = ''});
  final ApkPackStep step;
  final String detail;
}

class ApkPackResult {
  const ApkPackResult({
    required this.path,
    required this.sizeBytes,
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.fileCount,
    required this.sha256Hex,
    required this.certSha256Hex,
  });

  final String path;
  final int sizeBytes;
  final String packageName;
  final String appName;
  final String versionName;
  final int versionCode;

  /// 放进去的网页文件数。
  final int fileCount;
  final String sha256Hex;

  /// 签名证书的 SHA-256（和 apksigner 打印的一致）。
  final String certSha256Hex;
}

/// 能预料的失败：[message] 是直接给用户看的大白话，要写清真正的原因。
class ApkPackException implements Exception {
  const ApkPackException(this.message, {this.field});
  final String message;

  /// 哪一项输入有问题（`packageName`、`appName`、`versionName`、`versionCode`、`icon`、`project`、`template`、`key`），没有就是 null。
  final String? field;

  @override
  String toString() => message;
}

/// 用户自己的打包钥匙（RSA 私钥 + 自签证书）。不可变；内容绝不进日志。
abstract class ApkSigningKey {
  /// 证书 SHA-256，小写十六进制。
  String get certSha256Hex;

  /// 钥匙生成时间（证书起始时间）。
  DateTime get createdAt;

  /// 存进安全存储的形式（不加密，安全存储自己加密）。
  String serialize();
}
