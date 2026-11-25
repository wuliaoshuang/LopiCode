// 积木盒里加的星存进应用设置（SettingsStore）：每种宿主一个键，值是一张 token 表（如 ["block:if","expr:bin"]）。
// 读：原样交出去，洗干净是 bkCleanStars 的事（设置文件被改坏了也不崩）。写：不等写盘（按钮回调里用）。
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/core/stores.dart';

class SettingsBlockStars implements BlockStars {
  /// [kind]＝哪一种积木编辑器（`logic` / `backend` …），各存各的。
  SettingsBlockStars(this.settings, this.kind);
  final SettingsStore settings;
  final String kind;

  String get key => '${SettingKeys.blockStarsPrefix}$kind';

  @override
  Object? load() => settings.get<Object>(key);

  @override
  void save(List<String> tokens) => settings.setLater(key, tokens.isEmpty ? null : tokens);
}
