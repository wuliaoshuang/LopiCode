import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';

/// 页面文件里节点 `props` 的读法（格式说明见 docs/lowcode-page-format-v3.md）。
///
/// 读出来分两堆：
/// - `props`：这一版认识、值也合规矩的，界面和导出只看这一堆；
/// - `kept`：不认识的键、或者认识的键但值看不懂的——**不解释，但原样留着**，存盘时再写回去。
///
/// 第 3 版才有的键（[lcV3PropKeys]）在第 1、2 版的文件里不算数：那时候它们没有意义，
/// 要是现在突然生效，旧页面的样子和导出就变了。所以旧文件里的这些键也进 `kept`。
const Set<String> lcV3PropKeys = {'icon', 'disabled', 'alt', 'inputType', 'value', 'label', 'required'};

/// 输入框的类型（`props.inputType`）；不写＝文字。
const List<String> lcInputTypes = ['text', 'password', 'number', 'email', 'tel'];

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _iconName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// 一个值合不合这个键的规矩；合就返回整理好的值，不合（或者键不认识）返回 null。
Object? _clean(String type, String key, Object? value, int version) {
  // 新组件带来的键（第 3 版才有；哪种组件能用哪个键、对象数组的规矩都在 model_v3_components.dart）。
  if (lcIsV3ComponentKey(type, key)) return version < 3 ? null : lcCleanV3(type, key, value);
  if (version < 3 && lcV3PropKeys.contains(key)) return null;
  switch (key) {
    case 'width':
      return value == 'fill' || (value is num && value >= 0) ? value : null;
    case 'height' || 'padding' || 'margin' || 'radius' || 'gap' || 'fontSize' || 'size':
      return value is num && value >= 0 ? value : null;
    case 'bg' || 'color':
      return value is String && _hex.hasMatch(value) ? value.toUpperCase() : null;
    case 'align':
      return const ['start', 'center', 'end', 'stretch'].contains(value) ? value : null;
    case 'justify':
      return const ['start', 'center', 'end', 'between'].contains(value) ? value : null;
    case 'textAlign':
      return const ['left', 'center', 'right'].contains(value) ? value : null;
    case 'text' || 'src' || 'placeholder' || 'alt' || 'value' || 'label':
      return value is String ? value : null;
    case 'bold' || 'disabled' || 'required':
      return value is bool ? value : null;
    case 'icon':
      return value is String && _iconName.hasMatch(value) ? value : null;
    case 'inputType':
      return lcInputTypes.contains(value) ? value : null;
    case 'items':
      return value is List ? [for (final v in value) '$v'] : null;
    case 'name':
      return type == 'slot' && value is String && lcSlotName.hasMatch(value) ? value : null;
    case 'ref':
      return type == 'component' && value is String && LcComponentDef.idPattern.hasMatch(value) ? value : null;
    case 'values':
      if (type != 'component' || value is! Map) return null;
      return <String, dynamic>{
        for (final e in value.entries)
          if (e.key is String && (e.value is String || e.value is num || e.value is bool)) e.key as String: e.value,
      };
  }
  return null;
}

/// 把文件里的 `props` 分成“认识的”和“原样留着的”两堆。[version] 是文件的版本号。
(Map<String, dynamic> props, Map<String, dynamic> kept) lcReadProps(String type, Map<Object?, Object?> raw, int version) {
  final props = <String, dynamic>{}, kept = <String, dynamic>{};
  raw.forEach((key, value) {
    if (key is! String || value == null) return;
    final v = _clean(type, key, value, version);
    if (v != null) {
      props[key] = v;
    } else {
      kept[key] = value;
    }
  });
  return (props, kept);
}
