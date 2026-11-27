part of 'lib_model.dart';

// 清单和积木表里一项一项怎么读：从 lib_model.dart 原样挪出来的，那边放不下了。

LibArg? _arg(Object? raw, Set<String> slots) {
  if (raw is String) return slots.contains(raw) ? LibArgSlot(raw) : null;
  if (raw is! Map || raw.length != 1) return null;
  final key = raw.keys.single, value = raw.values.single;
  return switch (key) {
    'context' when value is String && value.isNotEmpty => LibArgContext(value),
    'setting' when value is String && value.isNotEmpty => LibArgSetting(value),
    'preset' when _plain(value) => LibArgPreset(value),
    _ => null,
  };
}

LibBlock? _block(Object? raw, List<String> problems, Set<String> moduleNames) {
  if (raw is! Map) {
    problems.add('积木表里有一项不是积木，读不了');
    return null;
  }
  final id = _text(raw['id'], max: 64);
  if (id == null || !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(id)) {
    problems.add('有一块积木没有编号，或者编号不是字母开头的字母数字');
    return null;
  }
  void bad(String why) => problems.add('积木「$id」：$why');
  final look = customBlockLookFromJson(raw['look']);
  if (look == null) {
    bad('没有外观（look）');
    return null;
  }
  final slotNames = {
    for (final p in parseLookTemplate(look.template))
      if (p.isSlot) p.text,
  };
  final kinds = <String, LibSlotKind>{};
  for (final e in _map(raw['slotKinds']).entries) {
    final kind = LibSlotKind.values.where((k) => k.name == e.value).firstOrNull;
    if (e.key is! String || kind == null) {
      bad('槽的种类写得不对：${e.key}');
    } else if (!slotNames.contains(e.key)) {
      bad('槽的种类里写了外观上没有的槽「${e.key}」');
    } else {
      kinds[e.key as String] = kind;
    }
  }
  final how = LibHow.values.where((h) => h.name == raw['how']).firstOrNull;
  if (how == null) {
    bad('没写清是哪种定义办法（how 要是 call / method / static / expand）');
    return null;
  }
  final module = _text(raw['module'], max: 64) ?? (moduleNames.length == 1 ? moduleNames.single : '');
  if (!moduleNames.contains(module)) bad('它说的模块「$module」库里没有');
  final args = <LibArg>[];
  for (final a in _list(raw['args'])) {
    final arg = _arg(a, slotNames);
    if (arg == null) {
      bad('实参表里有一项读不懂（要是槽名，或者 {"context": 名} / {"setting": 编号} / {"preset": 值}）');
    } else {
      args.add(arg);
    }
  }
  final into = raw['into'];
  if (into != null && (into is! String || kinds[into] != LibSlotKind.assign)) bad('into 要指向一个“放进变量”的槽');
  final provides = <String, String>{};
  for (final e in _map(raw['provides']).entries) {
    if (e.key is String && e.value is String) provides[e.key as String] = e.value as String;
  }
  final legacy = _map(raw['legacy']);
  return LibBlock(
    id: id,
    module: module,
    look: look,
    how: how,
    of: _text(raw['of'], max: 128) ?? '',
    args: args,
    expand: raw['expand'] is String ? raw['expand'] as String : '',
    slotKinds: kinds,
    into: into is String ? into : null,
    needs: [for (final n in _list(raw['needs'])) ?_text(n, max: 64)],
    provides: provides,
    legacyFn: _text(legacy['fn'], max: 64),
    legacyArgs: [for (final a in _list(legacy['args'])) ?_text(a, max: 64)],
    category: _text(raw['category'], max: 64) ?? '',
  );
}

LibSetting? _setting(Object? raw, List<String> problems) {
  if (raw is! Map) return null;
  final id = _text(raw['id'], max: 64);
  final type = libTypeFromText(raw['type']);
  if (id == null || type == null) {
    problems.add('有一个设置项没有编号或类型写得不对');
    return null;
  }
  final d = raw['default'];
  if (!(_plain(d) || (d is List && d.every(_plain)))) {
    problems.add('设置项「$id」的默认值只能是空、是否、数、文字，或者它们的列表');
    return null;
  }
  return LibSetting(
    id: id,
    name: _text(raw['name'], max: 24) ?? id,
    type: type,
    defaultValue: d,
    min: raw['min'] is num ? raw['min'] as num : null,
    max: raw['max'] is num ? raw['max'] as num : null,
    hint: _text(raw['hint'], max: 200) ?? '',
    legacyKey: _text(raw['legacyKey'], max: 64),
  );
}

/// 读一个库。[files]＝相对路径 → 内容；[builtin]＝是不是应用自带的。
