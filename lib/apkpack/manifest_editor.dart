// 改二进制清单里打包要动的那几样：包名、版本号、版本名、应用名、权限。只做这些，别的原样留着。
//
// 约定（见 apk_pack_contract.dart 和 docs/apk-format-notes.md）：模板的包名是 [kShellDefaultPackage]，
// 应用名是清单里的字面字符串，版本号是整数、版本名是字符串。对不上就抛 [AxmlFormatException]（门面报“模板不匹配”）。
import 'dart:typed_data';

import 'package:lopicode/apkpack/axml/axml_codec.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';

/// 模板默认包名。
const String kShellDefaultPackage = 'com.lopicode.shell';

const String kPermFineLocation = 'android.permission.ACCESS_FINE_LOCATION';
const String kPermCoarseLocation = 'android.permission.ACCESS_COARSE_LOCATION';

/// 从清单里读出来的、打包关心的几样。
class ManifestInfo {
  const ManifestInfo({required this.packageName, required this.versionCode, required this.versionName, required this.label, required this.permissions});
  final String packageName;
  final int versionCode;
  final String versionName;
  final String label;

  /// 按清单里的出现顺序。
  final List<String> permissions;
}

/// 要改成什么。
class ManifestEdit {
  const ManifestEdit({required this.packageName, required this.appName, required this.versionCode, required this.versionName, required this.permissions});
  final String packageName;
  final String appName;
  final int versionCode;
  final String versionName;
  final Set<String> permissions;
}

/// 一步到位：解析 → 核对约定 → 改 → 清理字符串池 → 写回。
Uint8List editManifestBytes(Uint8List manifest, ManifestEdit edit, {String expectedPackage = kShellDefaultPackage}) {
  final doc = parseAxml(manifest);
  final m = ManifestEditor(doc);
  final info = m.read();
  if (info.packageName != expectedPackage) throw AxmlFormatException('模板的包名应该是 $expectedPackage，实际是 ${info.packageName}');
  m
    ..setPackage(edit.packageName)
    ..setVersionCode(edit.versionCode)
    ..setVersionName(edit.versionName)
    ..setLabel(edit.appName)
    ..setPermissions(edit.permissions);
  compactStringPool(doc);
  return writeAxml(doc);
}

ManifestInfo readManifestInfo(Uint8List manifest) => ManifestEditor(parseAxml(manifest)).read();

/// 请求的权限集合 → 实际写进清单的集合（精确定位连带粗略定位）。
Set<String> expandPermissions(Set<String> wanted) => {...wanted, if (wanted.contains(kPermFineLocation)) kPermCoarseLocation};

class ManifestEditor {
  ManifestEditor(this.doc) {
    final nodes = doc.nodes;
    _manifestAt = nodes.indexWhere((n) => n is AxmlStartElement);
    if (_manifestAt < 0) throw const AxmlFormatException('清单里没有任何元素');
    final root = nodes[_manifestAt] as AxmlStartElement;
    if (doc.str(root.name) != 'manifest' || root.ns != kNoString) throw AxmlFormatException('清单的根元素应该是 manifest，实际是 ${doc.str(root.name)}');
  }

  final AxmlDocument doc;
  late final int _manifestAt;

  AxmlStartElement get _manifest => doc.nodes[_manifestAt] as AxmlStartElement;

  /// manifest 的直接子元素（深度 2）里叫 [name] 的：返回 (开始下标, 结束下标)。
  List<(int, int)> _children(String name) {
    final out = <(int, int)>[];
    var depth = 0;
    int? start;
    for (var i = _manifestAt; i < doc.nodes.length; i++) {
      final n = doc.nodes[i];
      if (n is AxmlStartElement) {
        depth++;
        if (depth == 2 && doc.str(n.name) == name && n.ns == kNoString) start = i;
      } else if (n is AxmlEndElement) {
        if (depth == 2 && start != null) {
          out.add((start, i));
          start = null;
        }
        depth--;
        if (depth == 0) break;
      }
    }
    return out;
  }

  AxmlAttribute? _androidAttr(AxmlStartElement e, int resId) {
    for (final a in e.attributes) {
      if (doc.resIdOf(a) == resId) return a;
    }
    return null;
  }

  AxmlAttribute? _plainAttr(AxmlStartElement e, String name) {
    for (final a in e.attributes) {
      if (a.ns == kNoString && doc.resIdOf(a) == null && doc.str(a.name) == name) return a;
    }
    return null;
  }

  String _stringOf(AxmlAttribute? a, String what) {
    if (a == null) throw AxmlFormatException('清单里缺少 $what');
    if (a.type != kTypeString) throw AxmlFormatException('$what 应该是直接写在清单里的字符串，实际是别的类型（0x${a.type.toRadixString(16)}，比如引用了资源）');
    return doc.str(a.data);
  }

  void _setString(AxmlAttribute a, String value) {
    final i = doc.internValue(value);
    a
      ..type = kTypeString
      ..rawValue = i
      ..data = i;
  }

  AxmlAttribute get _packageAttr {
    final a = _plainAttr(_manifest, 'package');
    _stringOf(a, 'package（包名）');
    return a!;
  }

  AxmlAttribute get _versionCodeAttr {
    final a = _androidAttr(_manifest, kAttrVersionCode);
    if (a == null) throw const AxmlFormatException('清单里缺少 android:versionCode（版本号）');
    if (a.type != kTypeIntDec && a.type != kTypeIntHex) throw AxmlFormatException('android:versionCode 应该是整数，实际类型 0x${a.type.toRadixString(16)}');
    return a;
  }

  AxmlAttribute get _versionNameAttr {
    final a = _androidAttr(_manifest, kAttrVersionName);
    _stringOf(a, 'android:versionName（版本名）');
    return a!;
  }

  AxmlStartElement get _application {
    final apps = _children('application');
    if (apps.length != 1) throw AxmlFormatException('清单里应该正好有一个 application，实际有 ${apps.length} 个');
    return doc.nodes[apps.single.$1] as AxmlStartElement;
  }

  AxmlAttribute get _labelAttr {
    final a = _androidAttr(_application, kAttrLabel);
    _stringOf(a, 'application 的 android:label（应用名）');
    return a!;
  }

  String? _permissionName(int startIndex) {
    final a = _androidAttr(doc.nodes[startIndex] as AxmlStartElement, kAttrName);
    return a != null && a.type == kTypeString ? doc.str(a.data) : null;
  }

  ManifestInfo read() => ManifestInfo(
    packageName: doc.str(_packageAttr.data),
    versionCode: _versionCodeAttr.data,
    versionName: doc.str(_versionNameAttr.data),
    label: doc.str(_labelAttr.data),
    permissions: [
      for (final (s, _) in _children('uses-permission'))
        if (_permissionName(s) case final String name) name,
    ],
  );

  /// 改包名。模板里以旧包名开头的 provider authorities、自定义权限名也跟着换，免得两个打出来的应用互相冲突装不上。
  void setPackage(String name) {
    final old = doc.str(_packageAttr.data);
    _setString(_packageAttr, name);
    if (old == name) return;
    String swap(String s) => s == old ? name : (s.startsWith('$old.') ? '$name${s.substring(old.length)}' : s);
    for (final n in doc.nodes.whereType<AxmlStartElement>()) {
      final el = doc.str(n.name);
      for (final a in n.attributes) {
        if (a.type != kTypeString) continue;
        final id = doc.resIdOf(a);
        final v = doc.str(a.data);
        String? next;
        if (id == kAttrAuthorities) {
          next = v.split(';').map(swap).join(';');
        } else if (id == kAttrName && (el == 'permission' || el == 'uses-permission')) {
          next = swap(v);
        }
        if (next != null && next != v) _setString(a, next);
      }
    }
  }

  void setVersionCode(int code) {
    _versionCodeAttr
      ..type = kTypeIntDec
      ..rawValue = kNoString
      ..data = code;
  }

  void setVersionName(String name) => _setString(_versionNameAttr, name);

  void setLabel(String label) => _setString(_labelAttr, label);

  /// 让清单里的权限正好等于 [wanted]（精确定位会连带粗略定位）。已有且还要的原样留着；多的删掉；缺的加在最后一个权限后面。
  void setPermissions(Set<String> wanted) {
    final target = expandPermissions(wanted);
    final existing = _children('uses-permission');
    final seen = <String>{};
    // 从后往前删，下标不乱
    for (final (s, e) in existing.reversed) {
      final name = _permissionName(s);
      if (name == null) continue; // 看不懂的不动
      if (!target.contains(name) || !seen.add(name)) doc.nodes.removeRange(s, e + 1);
    }
    final missing = target.difference(seen).toList()..sort();
    if (missing.isEmpty) return;

    final left = _children('uses-permission');
    int at;
    if (left.isNotEmpty) {
      at = left.last.$2 + 1;
    } else {
      final sdk = _children('uses-sdk');
      final app = _children('application');
      at = sdk.isNotEmpty ? sdk.last.$2 + 1 : (app.isNotEmpty ? app.first.$1 : _manifestAt + 1);
    }
    final line = doc.nodes[at - 1].line;
    final nameIdx = _attrNameIndex(kAttrName, 'name');
    final nsIdx = _androidNsIndex();
    final element = doc.internValue('uses-permission');
    final added = <AxmlNode>[];
    for (final p in missing) {
      final v = doc.internValue(p);
      added
        ..add(
          AxmlStartElement(
            line: line,
            comment: kNoString,
            ns: kNoString,
            name: element,
            attributes: [AxmlAttribute(ns: nsIdx, name: nameIdx, rawValue: v, type: kTypeString, data: v)],
          ),
        )
        ..add(AxmlEndElement(line: line, comment: kNoString, ns: kNoString, name: element));
    }
    doc.nodes.insertAll(at, added);
  }

  /// 带资源号的属性名在池子前部的下标（必须和资源号表对齐，所以只能用已有的，不能新加）。
  int _attrNameIndex(int resId, String name) {
    for (var i = 0; i < doc.resourceIds.length; i++) {
      if (doc.resourceIds[i] == resId && doc.pool.strings[i] == name) return i;
    }
    throw AxmlFormatException('模板清单里没有用到 android:$name 这个属性，没法新增权限（正常的模板一定有，模板不对）');
  }

  int _androidNsIndex() {
    for (final n in doc.nodes.whereType<AxmlNamespace>()) {
      if (n.uri != kNoString && doc.str(n.uri) == kAndroidNsUri) return n.uri;
    }
    throw const AxmlFormatException('模板清单里没有声明 android 命名空间');
  }
}
