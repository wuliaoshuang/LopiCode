/// “允许库里的手写代码”：全应用一个开关（默认关），外加“哪个项目的哪个库的哪一份手写代码她看过并确认了”。
///
/// 为什么不放在项目里：项目文件夹是 Agent 能写的地方，确认记在那里等于 Agent 自己就能替她点头。
/// 这里记在应用自己的私有目录（不在任何项目里），界面以外没有别的入口去改它。
/// （Agent 的文件工具被路径守卫挡在项目里；终端命令平时在 Ubuntu 环境里、看不到这个目录。终端退回本机 shell 时理论上摸得到——没挡死，见 library-format.md 20.3。）
/// 记的是手写代码的校验值：库的手写代码或清单变了一个字，校验值就对不上，要重新看、重新确认。
/// 关掉开关时把所有确认一起清掉——再打开要一个库一个库重新确认。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';

/// 一个库的手写代码的校验值：清单 + `native/` 下每个文件（路径和内容）。
String libNativeSum(Map<String, String> files) {
  final keys = [
    for (final k in files.keys)
      if (k.startsWith('native/') || k == kLibManifestFile) k,
  ]..sort();
  return sha256.convert(utf8.encode([for (final k in keys) '$k\u0000${files[k]}\u0000'].join())).toString();
}

class LibNativeTrust {
  LibNativeTrust();

  /// 全应用用的那一份。测试里可以换一份新的（默认关、不落盘）。
  static LibNativeTrust instance = LibNativeTrust();

  File? _file;
  bool _enabled = false;
  final Map<String, String> _confirmed = {};

  /// 开关现在开没开。总开关（rules.dart 的 `libNativeCodeEntry`）关着时一律算没开——存过“开着”也不算数。
  bool get enabled => libNativeCodeEntry && _enabled;

  static String _key(String projectRoot, String libId) => '$projectRoot\u0000$libId';

  /// 启动时读一次。读不了、没有文件＝关着、一个都没确认。
  Future<void> attach(File file) async {
    _file = file;
    _enabled = false;
    _confirmed.clear();
    final json = await readJsonFile(file, accept: (j) => j is Map, label: '手写代码的确认记录');
    if (json is! Map) return;
    _enabled = json['enabled'] == true;
    final raw = json['confirmed'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is String) _confirmed[e.key as String] = e.value as String;
      }
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await writeJsonAtomic(file, {'enabled': _enabled, 'confirmed': _confirmed});
  }

  /// 开 / 关。关的时候把所有确认清掉。总开关关着时打不开（什么都不改）。
  Future<void> setEnabled(bool on) async {
    if (on && !libNativeCodeEntry) return;
    _enabled = on;
    if (!on) _confirmed.clear();
    await _save();
  }

  /// 这个项目里这个库的这一份手写代码许不许用：开关开着，而且确认过的正是这一份。
  bool allows(String projectRoot, String libId, String sum) => enabled && _confirmed[_key(projectRoot, libId)] == sum;

  /// 她看过并确认了这一份。开关关着时不记（返回否）。
  Future<bool> confirm(String projectRoot, String libId, String sum) async {
    if (!enabled) return false;
    _confirmed[_key(projectRoot, libId)] = sum;
    await _save();
    return true;
  }

  Future<void> forget(String projectRoot, String libId) async {
    if (_confirmed.remove(_key(projectRoot, libId)) != null) await _save();
  }
}
