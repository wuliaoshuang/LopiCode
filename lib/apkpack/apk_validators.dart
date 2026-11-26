// 打包前的输入校验和可勾选的权限表。每个校验函数：通过返回 null，不通过返回直接给用户看的大白话。
// 数值的依据见 docs/apk-format-notes.md。
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';

/// 包名最长 223 个字符：安卓解析安装包时的上限（AOSP ParsingPackageUtils.MAX_FILE_NAME_SIZE）。
const int kMaxPackageNameLength = 223;

/// 应用名最长 50 个字符（自定：桌面图标下面本来也只显示十来个字；Google Play 的上限是 30，这里放宽一些）。
const int kMaxAppNameLength = 50;

/// 版本名最长 50 个字符（自定；安卓本身没有这个限制）。
const int kMaxVersionNameLength = 50;

/// 版本号上限 2100000000：官方文档写明的 Google Play 允许的最大值。
const int kMaxVersionCode = 2100000000;

/// 图标各密度的边长（像素）→ 资源目录名里的密度。
const Map<int, String> kIconDensities = {48: 'mdpi', 72: 'hdpi', 96: 'xhdpi', 144: 'xxhdpi', 192: 'xxxhdpi'};

/// 单张图标 PNG 的大小上限（自定：192×192 的图标正常只有几十 KB）。
const int kMaxIconBytes = 1024 * 1024;

const Set<String> _javaKeywords = {
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', //
  'final', 'finally', 'float', 'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package', 'private', //
  'protected', 'public', 'return', 'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try', 'void', //
  'volatile', 'while', 'true', 'false', 'null',
};

final RegExp _segment = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

String? validatePackageName(String name) {
  if (name.isEmpty) return '包名不能为空。包名像一个倒着写的网址，例如 com.example.myapp';
  if (name != name.trim() || name.contains(RegExp(r'\s'))) return '包名里不能有空格';
  if (name.length > kMaxPackageNameLength) return '包名太长了（${name.length} 个字符），最多 $kMaxPackageNameLength 个';
  final parts = name.split('.');
  if (parts.length < 2) return '包名至少要有两段，用英文句号隔开，例如 com.example.myapp';
  for (final p in parts) {
    if (p.isEmpty) return '包名里不能有连着的句号，开头和结尾也不能是句号';
    if (!_segment.hasMatch(p)) {
      if (RegExp(r'^[0-9_]').hasMatch(p)) return '包名的每一段都要以英文字母开头，“$p”不行';
      return '包名只能用英文字母、数字和下划线，“$p”里有别的字符';
    }
    if (_javaKeywords.contains(p)) return '“$p”是 Java 的保留字，不能当包名的一段，换一个词';
  }
  return null;
}

String? validateAppName(String name) {
  if (name.trim().isEmpty) return '应用名不能为空';
  if (name != name.trim()) return '应用名的开头和结尾不能有空格';
  if (name.contains(RegExp(r'[\u0000-\u001F\u007F]'))) return '应用名里不能有换行或其他控制字符';
  if (_hasLoneSurrogate(name)) return '应用名里有不完整的字符（可能是被截断的表情），删掉重新输入';
  final n = name.runes.length;
  if (n > kMaxAppNameLength) return '应用名太长了（$n 个字），最多 $kMaxAppNameLength 个';
  return null;
}

String? validateVersionName(String name) {
  if (name.trim().isEmpty) return '版本名不能为空，例如 1.0.0';
  if (name != name.trim()) return '版本名的开头和结尾不能有空格';
  if (name.contains(RegExp(r'[\u0000-\u001F\u007F]'))) return '版本名里不能有换行或其他控制字符';
  if (_hasLoneSurrogate(name)) return '版本名里有不完整的字符，删掉重新输入';
  final n = name.runes.length;
  if (n > kMaxVersionNameLength) return '版本名太长了（$n 个字），最多 $kMaxVersionNameLength 个';
  return null;
}

String? validateVersionCode(int code) {
  if (code < 1) return '版本号要是 1 或更大的整数（每发一次新版就加 1）';
  if (code > kMaxVersionCode) return '版本号太大了，最大是 $kMaxVersionCode';
  return null;
}

/// 核对一张图标：确实是 PNG、是 [size]×[size] 的正方形、[size] 是五个密度之一。
String? validateIconPng(int size, Uint8List bytes) {
  if (!kIconDensities.containsKey(size)) return '图标边长只能是 ${kIconDensities.keys.join('、')} 像素，收到的是 $size';
  if (bytes.length > kMaxIconBytes) return '$size 像素的图标文件太大了（超过 1MB）';
  final dims = pngSize(bytes);
  if (dims == null) return '$size 像素的图标不是 PNG 图片（或文件是坏的）';
  if (dims.$1 != size || dims.$2 != size) return '图标尺寸不对：应该是 $size×$size，实际是 ${dims.$1}×${dims.$2}';
  return null;
}

/// 权限名的写法是否正常（不限于下面的表，但必须像个权限名）。
String? validatePermission(String id) => RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$').hasMatch(id) && id.length <= 255 ? null : '权限名“$id”的写法不对';

/// 读 PNG 的宽高：检查 8 字节签名、第一个块是 13 字节的 IHDR、结尾有 IEND。不是 PNG 返回 null。
(int, int)? pngSize(Uint8List b) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 8 + 25 + 12) return null;
  for (var i = 0; i < 8; i++) {
    if (b[i] != sig[i]) return null;
  }
  final d = ByteData.sublistView(b);
  if (d.getUint32(8) != 13 || d.getUint32(12) != 0x49484452) return null; // 'IHDR'
  final w = d.getUint32(16);
  final h = d.getUint32(20);
  if (w == 0 || h == 0) return null;
  if (d.getUint32(b.length - 8) != 0x49454E44) return null; // 结尾的 'IEND'：防被截断的文件
  return (w, h);
}

bool _hasLoneSurrogate(String s) {
  final u = s.codeUnits;
  for (var i = 0; i < u.length; i++) {
    final c = u[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= u.length || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF) return true;
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

/// 可勾选的权限（固定表）。精确定位会自动连带“大概位置”（安卓 12 起只申请精确定位不被允许）。
const List<ApkPermissionOption> kApkPermissionOptions = [
  ApkPermissionOption(id: 'android.permission.INTERNET', label: '联网', hint: '网页要访问网络（加载在线图片、调接口）就得开。一般都开着。', defaultOn: true),
  ApkPermissionOption(id: 'android.permission.ACCESS_NETWORK_STATE', label: '查看网络状态', hint: '让网页知道现在有没有网、是不是 Wi-Fi。'),
  ApkPermissionOption(id: 'android.permission.CAMERA', label: '摄像头', hint: '网页里要拍照、扫码、视频通话时开。用的时候系统还会再问用户一次。'),
  ApkPermissionOption(id: 'android.permission.RECORD_AUDIO', label: '麦克风', hint: '网页里要录音、语音输入、语音通话时开。用的时候系统还会再问用户一次。'),
  ApkPermissionOption(id: 'android.permission.ACCESS_FINE_LOCATION', label: '位置', hint: '网页里要获取用户位置（地图、附近的店）时开。会同时带上“大概位置”权限。'),
  ApkPermissionOption(id: 'android.permission.VIBRATE', label: '震动', hint: '网页里要让手机震一下（提醒、按键反馈）时开。'),
  ApkPermissionOption(id: 'android.permission.WAKE_LOCK', label: '保持屏幕常亮', hint: '看视频、展示页面时不让屏幕自动熄灭。'),
];
