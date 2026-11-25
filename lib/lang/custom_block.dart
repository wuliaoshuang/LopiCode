/// “我的积木”的外观（设计稿 docs/blocks-v4-language-design.md 5.1–5.3）：一块自定义积木 ＝ 一个函数定义（[LFuncDecl]）＋ 一个外观。
/// 定义决定它做什么，外观决定它在积木盒里和画布上长什么样。生成代码时它就是一次普通的函数调用。
///
/// 这里只有**纯数据和纯函数**（不依赖界面、不读写文件），编辑器的“新建积木”页、后端宿主、Agent 工具共用：
/// - [CustomBlockLook]、[CustomBlockSlot]：外观本身；
/// - [parseLookTemplate]：把文案模板切成“字”和“槽”；[defaultLookTemplate]：没写模板时的样子；
/// - [customBlockLookFromJson]／[CustomBlockLook.toJson]：存盘（坏数据不崩）；
/// - [validateLook]：外观和参数表对不对得上；
/// - [resolveLookShape]：形状填的是“自动”时按定义选；
/// - 改参数联动在 custom_block_edit.dart（[remapCallArgs]、[remapLook]）。
///
/// **存盘格式**（JSON，键的顺序固定；以后只增字段不改名；读的时候字段先判类型，坏的那一截当默认值）：
///
/// ```json
/// {"name": "问好", "shape": "auto", "template": "向 {名字} 问好 {次数} 次", "colorKey": "custom", "hint": "打几声招呼",
///  "slots": [{"name": "名字", "kind": "value"},
///            {"name": "次数", "kind": "value", "defaultValue": 1},
///            {"name": "语气", "kind": "choice", "options": ["客气", "随便"], "defaultValue": "客气"}]}
/// ```
///
/// `hint` 是空、`options` 是空、`defaultValue` 是空时不写这个键。`slots` 里没有列到的参数按“值槽、没有默认内容”算。
library;

/// 形状（设计稿 5.2）。
enum CustomBlockShape {
  /// 按定义自动选（默认）：函数里有“返回 (值)”就是值型，否则语句型；推得出返回的一定是“是 / 否”就是是否型。
  auto,

  /// 语句型：上凹下凸，能上下拼。
  statement,

  /// 值型：胶囊。
  value,

  /// 是否型：六边形。
  boolean,

  /// 收尾型（下面不能再接积木）。**第 3 阶段（库）才用得上**，这里只占位：校验会报“还不能用”。
  cap,

  /// 帽子型（当一串的开头）。**第 3 阶段（库）才用得上**，这里只占位。
  hat,
}

/// 一个槽的种类（设计稿 5.2）。
enum CustomSlotKind {
  /// 值：能放任何值积木。
  value,

  /// 是否：六边形的槽。
  boolean,

  /// 固定选项：下拉，选项在 [CustomBlockSlot.options] 里；传给函数的是选中的那段文字。
  choice,

  /// 内联口（口里的积木原样放进定义里）。**第 3 阶段才有**，这里只占位。带内联口的定义不许递归（设计稿 5.2）。
  inlineMouth,

  /// 回调口（口里的积木包成一个函数传进去）。**第 3 阶段才有**，这里只占位。
  callbackMouth,
}

/// 每块自定义积木最多几个槽、每个下拉最多几个选项（自定，防坏数据）。
const int kCustomBlockMaxSlots = 32;
const int kCustomBlockMaxOptions = 64;

/// 没选颜色时用的颜色键（编辑器 `lib/blocks/block_colors.dart` 里的 `custom`）。
const String kCustomBlockDefaultColor = 'custom';

/// 一个槽：对应函数的一个参数（[name] 就是参数名）。
class CustomBlockSlot {
  const CustomBlockSlot(this.name, {this.kind = CustomSlotKind.value, this.options = const [], this.defaultValue});

  final String name;
  final CustomSlotKind kind;

  /// 固定选项（只有 [CustomSlotKind.choice] 用）。
  final List<String> options;

  /// 从积木盒拿出来时槽里先放什么：null / bool / num / String。固定选项的槽要是 [options] 里的一项。
  /// 它只管“积木上先显示什么”；函数参数自己的默认值在定义（`LParam.defaultValue`）上，改参数联动时填的也是那个。
  final Object? defaultValue;

  CustomBlockSlot copyWith({String? name, CustomSlotKind? kind, List<String>? options, Object? defaultValue, bool clearDefault = false}) =>
      CustomBlockSlot(name ?? this.name, kind: kind ?? this.kind, options: options ?? this.options, defaultValue: clearDefault ? null : defaultValue ?? this.defaultValue);

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    if (options.isNotEmpty) 'options': [...options],
    if (defaultValue != null) 'defaultValue': defaultValue,
  };

  @override
  bool operator ==(Object other) => other is CustomBlockSlot && other.name == name && other.kind == kind && _sameList(other.options, options) && other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(name, kind, Object.hashAll(options), defaultValue);

  @override
  String toString() => 'CustomBlockSlot($name, ${kind.name})';
}

/// 一块自定义积木的外观。[name] 是它背后那个函数的名字。
class CustomBlockLook {
  const CustomBlockLook(this.name, {this.shape = CustomBlockShape.auto, this.template = '', this.slots = const [], this.colorKey = kCustomBlockDefaultColor, this.hint = ''});

  /// 函数名（也是积木盒里找它用的名字）。
  final String name;
  final CustomBlockShape shape;

  /// 文案模板：`把 {集合} 里编号是 {id} 的那条删掉`。花括号里是参数名；要写花括号本身就写两个（`{{`、`}}`）。
  /// 空的＝“名字 ＋ 每个参数一个槽”（[defaultLookTemplate]）。
  final String template;

  /// 各槽的种类。没列到的参数按“值槽”算（[slotFor]）。
  final List<CustomBlockSlot> slots;

  /// 颜色分类的键（编辑器的颜色表里查；不认识的由编辑器回退到 `custom`）。
  final String colorKey;

  /// 说明：积木盒里按住显示的一句话。
  final String hint;

  /// 某个参数的槽；没列就是一个默认的值槽。
  CustomBlockSlot slotFor(String param) {
    for (final s in slots) {
      if (s.name == param) return s;
    }
    return CustomBlockSlot(param);
  }

  /// 实际用的模板：写了就用写的，没写就按参数表拼一个。
  String templateFor(List<String> params) => template.trim().isEmpty ? defaultLookTemplate(name, params) : template;

  CustomBlockLook copyWith({String? name, CustomBlockShape? shape, String? template, List<CustomBlockSlot>? slots, String? colorKey, String? hint}) =>
      CustomBlockLook(name ?? this.name, shape: shape ?? this.shape, template: template ?? this.template, slots: slots ?? this.slots, colorKey: colorKey ?? this.colorKey, hint: hint ?? this.hint);

  Map<String, Object?> toJson() => {
    'name': name,
    'shape': shape.name,
    'template': template,
    'colorKey': colorKey,
    if (hint.isNotEmpty) 'hint': hint,
    'slots': [for (final s in slots) s.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CustomBlockLook && other.name == name && other.shape == shape && other.template == template && _sameList(other.slots, slots) && other.colorKey == colorKey && other.hint == hint;

  @override
  int get hashCode => Object.hash(name, shape, template, Object.hashAll(slots), colorKey, hint);

  @override
  String toString() => 'CustomBlockLook($name, ${shape.name}, "$template")';
}

bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ———————————————————————— 存盘 ————————————————————————

/// 顶层函数版的 [CustomBlockLook.toJson]（和 [customBlockLookFromJson] 成对）。
Map<String, Object?> customBlockLookToJson(CustomBlockLook look) => look.toJson();

/// 从 JSON 读一个外观。**不抛异常**：不是对象、或没有名字（不是文字 / 是空的）返回 null，调用方跳过这一条；
/// 其余字段类型不对就当默认值；不认识的形状当“自动”、不认识的槽种类当“值”；槽里坏的逐条跳过、重名的只留第一个。
CustomBlockLook? customBlockLookFromJson(Object? json) {
  if (json is! Map) return null;
  final name = json['name'];
  if (name is! String || name.trim().isEmpty) return null;
  final shape = json['shape'];
  final template = json['template'];
  final colorKey = json['colorKey'];
  final hint = json['hint'];
  final rawSlots = json['slots'];
  final slots = <CustomBlockSlot>[];
  if (rawSlots is List) {
    final seen = <String>{};
    for (final raw in rawSlots) {
      if (slots.length >= kCustomBlockMaxSlots) break;
      final s = _slotFromJson(raw);
      if (s != null && seen.add(s.name)) slots.add(s);
    }
  }
  return CustomBlockLook(
    name,
    shape: shape is String ? _byName(CustomBlockShape.values, shape) ?? CustomBlockShape.auto : CustomBlockShape.auto,
    template: template is String ? template : '',
    slots: slots,
    colorKey: colorKey is String && colorKey.isNotEmpty ? colorKey : kCustomBlockDefaultColor,
    hint: hint is String ? hint : '',
  );
}

/// 读一组外观：不是列表得空表；坏的逐条跳过；同名的只留第一个。
List<CustomBlockLook> customBlockLooksFromJson(Object? json) {
  final out = <CustomBlockLook>[];
  if (json is! List) return out;
  final seen = <String>{};
  for (final raw in json) {
    final look = customBlockLookFromJson(raw);
    if (look != null && seen.add(look.name)) out.add(look);
  }
  return out;
}

CustomBlockSlot? _slotFromJson(Object? json) {
  if (json is! Map) return null;
  final name = json['name'];
  if (name is! String || name.isEmpty) return null;
  final kind = json['kind'];
  final rawOptions = json['options'];
  final options = <String>[];
  if (rawOptions is List) {
    for (final o in rawOptions) {
      if (options.length >= kCustomBlockMaxOptions) break;
      if (o is String && !options.contains(o)) options.add(o);
    }
  }
  final d = json['defaultValue'];
  final ok = d is bool || d is String || (d is num && d.isFinite);
  return CustomBlockSlot(name, kind: kind is String ? _byName(CustomSlotKind.values, kind) ?? CustomSlotKind.value : CustomSlotKind.value, options: options, defaultValue: ok ? d : null);
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

// ———————————————————————— 文案模板 ————————————————————————

/// 模板切出来的一段：一段字（[isSlot] 是 false，[text] 是字）或一个槽（[isSlot] 是 true，[text] 是参数名）。
class LookSegment {
  const LookSegment.text(this.text) : isSlot = false;
  const LookSegment.slot(this.text) : isSlot = true;

  final String text;
  final bool isSlot;

  @override
  bool operator ==(Object other) => other is LookSegment && other.isSlot == isSlot && other.text == text;

  @override
  int get hashCode => Object.hash(isSlot, text);

  @override
  String toString() => isSlot ? '{$text}' : '"$text"';
}

/// 把文案模板切成“字”和“槽”，按出现的顺序。**任何输入都不抛异常。**
///
/// - `{名字}` 是一个槽，名字两头的空白去掉；
/// - `{{`、`}}` 是花括号本身；
/// - 没配上的 `{`（后面没有 `}`）、空的 `{}`、名字里又有 `{` 或换行的：原样当字；落单的 `}` 也当字；
/// - 挨着的字合成一段；空模板得空表。
List<LookSegment> parseLookTemplate(String template) {
  final out = <LookSegment>[];
  final text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    out.add(LookSegment.text(text.toString()));
    text.clear();
  }

  var i = 0;
  while (i < template.length) {
    final ch = template[i];
    if (ch == '{') {
      if (i + 1 < template.length && template[i + 1] == '{') {
        text.write('{');
        i += 2;
        continue;
      }
      final close = template.indexOf('}', i + 1);
      final inner = close < 0 ? null : template.substring(i + 1, close);
      if (inner == null || inner.trim().isEmpty || inner.contains('{') || inner.contains('\n')) {
        text.write('{');
        i++;
        continue;
      }
      flush();
      out.add(LookSegment.slot(inner.trim()));
      i = close + 1;
    } else if (ch == '}' && i + 1 < template.length && template[i + 1] == '}') {
      text.write('}');
      i += 2;
    } else {
      text.write(ch);
      i++;
    }
  }
  flush();
  return out;
}

/// 把切好的段拼回模板（[parseLookTemplate] 的反过程；字里的花括号写成两个）。
String formatLookTemplate(List<LookSegment> segments) => [for (final s in segments) s.isSlot ? '{${s.text}}' : s.text.replaceAll('{', '{{').replaceAll('}', '}}')].join();

/// 模板里的槽名，按出现的顺序（重复的照样列出来）。
List<String> lookTemplateSlots(String template) => [
  for (final s in parseLookTemplate(template))
    if (s.isSlot) s.text,
];

/// 没写模板时的样子：“名字 ＋ 每个参数一个槽”，用空格隔开。
String defaultLookTemplate(String name, List<String> params) => formatLookTemplate([
  LookSegment.text(name),
  for (final p in params) ...[const LookSegment.text(' '), LookSegment.slot(p)],
]);

// ———————————————————————— 形状 ————————————————————————

/// 形状填的是“自动”时按定义选（设计稿 5.2）：[hasValue]＝函数里有“返回 (值)”；[returnsBool]＝推得出返回的一定是“是 / 否”。
/// 不是“自动”就原样返回。
CustomBlockShape resolveLookShape(CustomBlockShape shape, {required bool hasValue, bool returnsBool = false}) {
  if (shape != CustomBlockShape.auto) return shape;
  if (!hasValue) return CustomBlockShape.statement;
  return returnsBool ? CustomBlockShape.boolean : CustomBlockShape.value;
}

// ———————————————————————— 校验 ————————————————————————

/// 外观上的一个问题。[code] 是 `B01`–`B09`（B＝积木外观；和 G / P / S / L 规则不重号）。
class LookProblem {
  const LookProblem(this.code, this.message, {this.slot, this.isError = true});
  final String code;
  final String message;

  /// 哪个槽 / 参数的问题（没有就是整块的）。
  final String? slot;
  final bool isError;

  @override
  String toString() => '$code ${isError ? '错误' : '警告'}：$message';
}

/// 检查外观和参数表对不对得上。**纯函数、不抛异常**；没问题返回空表。[params] 是定义的参数名，按顺序。
///
/// - `B01` 错误：积木没有名字。
/// - `B02` 错误：模板里的槽 `{x}` 不是参数。
/// - `B03` 错误：有参数在模板里没有槽（用的人没处填）。
/// - `B04` 错误：同一个参数在模板里出现了两次。
/// - `B05` 错误：槽表里有不是参数的名字，或同一个名字列了两次。
/// - `B06` 错误：固定选项的槽没有选项，或选项重复 / 是空的。
/// - `B07` 错误：槽里先放的内容和槽的种类对不上（是否槽放了不是“是 / 否”的；固定选项槽放了不在选项里的）。
/// - `B08` 错误：用了第 3 阶段才有的外观（收尾型、帽子型、内联口、回调口）。
/// - `B09` 警告：模板里一个字都没有（只有槽，积木上认不出是什么）；[hasValue] 给了、而形状和定义对不上
///   （选了值型 / 是否型但函数没有“返回 (值)”——当值用会得到空；选了语句型但函数有返回值——返回值会被丢掉）。
List<LookProblem> validateLook(CustomBlockLook look, List<String> params, {bool? hasValue}) {
  final out = <LookProblem>[];
  if (look.name.trim().isEmpty) out.add(const LookProblem('B01', '给这块积木起个名字'));

  final segments = parseLookTemplate(look.templateFor(params));
  final used = <String>{};
  for (final s in segments.where((s) => s.isSlot)) {
    if (!params.contains(s.text)) {
      out.add(LookProblem('B02', '文案里的 {${s.text}} 不是这块积木的参数', slot: s.text));
    } else if (!used.add(s.text)) {
      out.add(LookProblem('B04', '参数 ${s.text} 在文案里出现了不止一次，只留一个', slot: s.text));
    }
  }
  for (final p in params) {
    if (!used.contains(p)) out.add(LookProblem('B03', '参数 $p 在文案里没有槽，用的时候没处填；在文案里加上 {$p}', slot: p));
  }

  final listed = <String>{};
  for (final s in look.slots) {
    if (!params.contains(s.name)) {
      out.add(LookProblem('B05', '槽 ${s.name} 对应的参数已经没有了', slot: s.name));
      continue;
    }
    if (!listed.add(s.name)) {
      out.add(LookProblem('B05', '槽 ${s.name} 设置了两次', slot: s.name));
      continue;
    }
    final d = s.defaultValue;
    switch (s.kind) {
      case CustomSlotKind.value:
        break;
      case CustomSlotKind.boolean:
        if (d != null && d is! bool) out.add(LookProblem('B07', '槽 ${s.name} 是“是 / 否”的槽，先放的内容也要是“是”或“否”', slot: s.name));
      case CustomSlotKind.choice:
        if (s.options.isEmpty) {
          out.add(LookProblem('B06', '槽 ${s.name} 是下拉，至少要有一个选项', slot: s.name));
        } else if (s.options.any((o) => o.isEmpty) || s.options.toSet().length != s.options.length) {
          out.add(LookProblem('B06', '槽 ${s.name} 的选项里有空的或重复的', slot: s.name));
        }
        if (d != null && !s.options.contains(d)) out.add(LookProblem('B07', '槽 ${s.name} 先选中的那一项不在选项里', slot: s.name));
      case CustomSlotKind.inlineMouth || CustomSlotKind.callbackMouth:
        out.add(LookProblem('B08', '槽 ${s.name}：能放积木的口（内联口 / 回调口）要到积木第 4 版第 3 阶段才有', slot: s.name));
    }
  }

  if (look.shape == CustomBlockShape.cap || look.shape == CustomBlockShape.hat) {
    out.add(const LookProblem('B08', '收尾型和帽子型的积木要到积木第 4 版第 3 阶段才有，先选语句型、值型或是否型'));
  }
  if (segments.isNotEmpty && segments.every((s) => s.isSlot || s.text.trim().isEmpty)) {
    out.add(const LookProblem('B09', '文案里一个字都没有，积木上认不出它是做什么的', isError: false));
  }
  if (hasValue != null) {
    final wantsValue = look.shape == CustomBlockShape.value || look.shape == CustomBlockShape.boolean;
    if (wantsValue && !hasValue) {
      out.add(const LookProblem('B09', '形状选的是值，但定义里没有“返回 (值)”，用的时候会得到空', isError: false));
    } else if (look.shape == CustomBlockShape.statement && hasValue) {
      out.add(const LookProblem('B09', '定义里有“返回 (值)”，但形状选的是语句，返回的值会被丢掉', isError: false));
    }
  }
  return out;
}
