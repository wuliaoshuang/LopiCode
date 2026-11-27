/// 自定义组件第 6 期加的四样：对外的**事件**、**变体**、组件自己的**状态**、实例上的**绑定 / 接事件 / 选变体**。
/// 字段都是页面格式第 3 版早就留好的（`events` / `variants` / `state`），只加不改；说明见 docs/lowcode-page-format-v3.md
/// “第四轮 B2 之后的补充说明”和 docs/blocks-v5-parts/E-editor-components.md §10.10。
///
/// 存在哪：
/// - 定义上：`events`、`variants`、`state` 三个字段原样待在 [LcComponentDef.more] 里，这里是读写它们的地方（读不懂的项原样留着）。
/// - 定义里的节点上：`emit`——这个控件的哪个事件“往外发”成组件的哪个事件。
/// - 实例节点上：`variant`（每组变体选了哪个）、`on`（组件的事件发生时做什么：一串积木，和页面逻辑同一种存法）、
///   `data`（属性绑到页面的状态上；和普通控件的绑定是同一个字段，键是组件属性的名字）。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

const String kLcEvents = 'events';
const String kLcVariants = 'variants';
const String kLcCompState = 'state';
const String kLcEmit = 'emit';
const String kLcOn = 'on';
const String kLcVariant = 'variant';

/// 一个组件最多几个事件、几组变体、每组几个、几个状态；一个事件最多带几个数据。
const int kLcMaxCompEvents = 12;
const int kLcMaxVariantGroups = 4;
const int kLcMaxVariantsPerGroup = 8;
const int kLcMaxCompStates = 24;
const int kLcMaxEventParams = 6;

/// 没写 `group` 的变体算在这一组里。
const String kLcDefaultVariantGroup = 'variant';

final RegExp kLcEventName = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,23}$');

Object? _copy(Object? v) => v == null ? null : jsonDecode(jsonEncode(v));

String _label(Object? raw, String fallback) {
  final s = raw is String ? LcNode.cleanName(raw) : '';
  return s.isEmpty ? fallback : (s.length > 20 ? s.substring(0, 20) : s);
}

// —— 事件 ——

class LcCompEventParam {
  const LcCompEventParam(this.name, this.type);
  final String name;

  /// text / number / bool。
  final String type;
  Map<String, dynamic> toJson() => {'name': name, 'type': type};
}

class LcCompEvent {
  LcCompEvent({required this.name, String? label, List<LcCompEventParam>? params}) : label = label ?? name, params = params ?? [];
  String name;
  String label;
  final List<LcCompEventParam> params;

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
  };

  static LcCompEvent? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !kLcEventName.hasMatch(name)) return null;
    final raw = json['params'];
    final seen = <String>{};
    final params = <LcCompEventParam>[];
    for (final p in raw is List ? raw : const <Object?>[]) {
      final n = p is Map ? p['name'] : null, t = p is Map ? p['type'] : null;
      if (n is! String || !LcComponentProp.namePattern.hasMatch(n) || !seen.add(n)) return null;
      if (params.length >= kLcMaxEventParams) return null;
      params.add(LcCompEventParam(n, t is String && LcVariable.types.contains(t) ? t : 'text'));
    }
    return LcCompEvent(name: name, label: _label(json['label'], name), params: params);
  }
}

List<T> _readList<T>(Map<String, dynamic> more, String key, T? Function(Object? item) parse, String Function(T) idOf) {
  final raw = more[key];
  final seen = <String>{};
  return [
    if (raw is List)
      for (final item in raw)
        if (parse(item) case final x? when seen.add(idOf(x))) x,
  ];
}

void _writeList<T>(Map<String, dynamic> more, String key, List<T> list, T? Function(Object? item) parse, String Function(T) idOf, Map<String, dynamic> Function(T) json) {
  final raw = more[key];
  // 读不懂的、重名而没被读到的：原样留在后面。
  final old = <String>{};
  final kept = <Object?>[
    if (raw is List)
      for (final item in raw)
        if (parse(item) case final x?) ...[if (!old.add(idOf(x))) item] else item,
  ];
  final seen = <String>{};
  final out = <Object?>[
    for (final x in list)
      if (seen.add(idOf(x))) json(x),
    ...kept,
  ];
  if (out.isEmpty) {
    more.remove(key);
  } else {
    more[key] = out;
  }
}

List<LcCompEvent> lcCompEvents(LcComponentDef def) => _readList(def.more, kLcEvents, LcCompEvent.tryParse, (e) => e.name);

void lcSetCompEvents(LcComponentDef def, List<LcCompEvent> events) => _writeList(def.more, kLcEvents, events, LcCompEvent.tryParse, (e) => e.name, (e) => e.toJson());

LcCompEvent? lcCompEvent(LcComponentDef def, String name) {
  for (final e in lcCompEvents(def)) {
    if (e.name == name) return e;
  }
  return null;
}

// —— 往外发 ——

/// 定义里一个控件的一个事件往外发成组件的事件 [event]；[args]＝带出去的数据（名字 → 来源，和绑定同一种写法）。
class LcEmit {
  const LcEmit(this.event, [this.args = const {}]);
  final String event;
  final Map<String, Object?> args;
}

/// 这个控件哪些事件往外发（控件的事件名 → 发成什么）。实例节点的“事件名”是它那个组件的事件名（一层层往外转发）。
Map<String, LcEmit> lcEmitsOf(LcNode n) {
  final raw = n.more[kLcEmit];
  final out = <String, LcEmit>{};
  if (raw is! Map) return out;
  raw.forEach((k, v) {
    final e = v is Map ? v['event'] : (v is String ? v : null);
    if (k is! String || e is! String || !kLcEventName.hasMatch(e)) return;
    final args = v is Map && v['args'] is Map ? v['args'] as Map : const <Object?, Object?>{};
    out[k] = LcEmit(e, {
      for (final a in args.entries)
        if (a.key is String && lcIsBoundSrc(a.value)) a.key as String: a.value,
    });
  });
  return out;
}

/// 设 / 去掉（[event] 给 null）一条“往外发”。带出去的数据另用 [lcSetEmitArg]。
void lcSetEmit(LcNode n, String on, String? event) {
  final raw = n.more[kLcEmit];
  final map = <String, dynamic>{if (raw is Map) ...raw.cast<String, dynamic>()};
  if (event == null) {
    map.remove(on);
  } else {
    final old = map[on];
    map[on] = {'event': event, if (old is Map && old['event'] == event && old['args'] != null) 'args': old['args']};
  }
  if (map.isEmpty) {
    n.more.remove(kLcEmit);
  } else {
    n.more[kLcEmit] = map;
  }
}

void lcSetEmitArg(LcNode n, String on, String param, Map<String, dynamic>? src) {
  final raw = n.more[kLcEmit];
  final item = raw is Map ? raw[on] : null;
  if (raw is! Map || item is! Map) return;
  final args = <String, dynamic>{if (item['args'] is Map) ...(item['args'] as Map).cast<String, dynamic>()};
  src == null ? args.remove(param) : args[param] = src;
  n.more[kLcEmit] = {
    ...raw.cast<String, dynamic>(),
    on: {'event': item['event'], if (args.isNotEmpty) 'args': args},
  };
}

// —— 变体 ——

/// 一个变体：属于哪一组（一组里实例只能选一个）、叫什么、选了它以后哪些节点的样式有什么不一样（只存差别）。
class LcVariant {
  LcVariant({required this.group, required this.name, String? label, String? groupLabel, Map<String, Map<String, String>>? styles})
    : label = label ?? name,
      groupLabel = groupLabel ?? (group == kLcDefaultVariantGroup ? '样子' : group),
      styles = styles ?? {};
  String group;
  String name;
  String label;
  String groupLabel;

  /// 定义里的节点 id → 这个变体下多出来 / 换掉的 CSS 声明。
  final Map<String, Map<String, String>> styles;

  String get key => '$group/$name';

  /// [rootId]：定义最外层节点的 id（它的差别写在 `style`，别的节点写在 `nodes`——和第 3 版格式留的写法对上）。
  Map<String, dynamic> toJson(String rootId) {
    final others = {
      for (final e in styles.entries)
        if (e.key != rootId && e.value.isNotEmpty) e.key: {'style': e.value},
    };
    return {
      'name': name,
      'label': label,
      if (group != kLcDefaultVariantGroup) 'group': group,
      if (groupLabel != (group == kLcDefaultVariantGroup ? '样子' : group)) 'groupLabel': groupLabel,
      if (styles[rootId]?.isNotEmpty ?? false) 'style': styles[rootId],
      if (others.isNotEmpty) 'nodes': others,
    };
  }

  static LcVariant? tryParse(Object? json, String rootId) {
    if (json is! Map) return null;
    final name = json['name'], group = json['group'] ?? kLcDefaultVariantGroup;
    if (name is! String || !kLcEventName.hasMatch(name) || group is! String || !kLcEventName.hasMatch(group)) return null;
    final styles = <String, Map<String, String>>{};
    final root = LcNode.cleanStyle(json['style']);
    if (root.isNotEmpty) styles[rootId] = root;
    final nodes = json['nodes'];
    if (nodes is Map) {
      nodes.forEach((id, v) {
        final s = LcNode.cleanStyle(v is Map ? v['style'] : null);
        if (id is String && id != rootId && s.isNotEmpty) styles[id] = s;
      });
    }
    return LcVariant(group: group, name: name, label: _label(json['label'], name), groupLabel: json['groupLabel'] is String ? _label(json['groupLabel'], group) : null, styles: styles);
  }
}

List<LcVariant> lcVariants(LcComponentDef def) => _readList(def.more, kLcVariants, (x) => LcVariant.tryParse(x, def.root.id), (v) => v.key);

void lcSetVariants(LcComponentDef def, List<LcVariant> list) => _writeList(def.more, kLcVariants, list, (x) => LcVariant.tryParse(x, def.root.id), (v) => v.key, (v) => v.toJson(def.root.id));

/// 变体的组（按出现的先后）：组名 → 给人看的名字。
Map<String, String> lcVariantGroups(LcComponentDef def) {
  final out = <String, String>{};
  for (final v in lcVariants(def)) {
    out.putIfAbsent(v.group, () => v.groupLabel);
  }
  return out;
}

/// 实例每一组选了哪个变体（组名 → 变体名；没选的组不在里面＝用平时的样子）。只留定义里真有的。
Map<String, String> lcInstanceVariants(LcComponentDef def, LcNode instance) {
  final raw = instance.more[kLcVariant];
  if (raw is! Map) return const {};
  final have = {for (final v in lcVariants(def)) v.key};
  return {
    for (final e in raw.entries)
      if (e.key is String && e.value is String && have.contains('${e.key}/${e.value}')) e.key as String: e.value as String,
  };
}

/// 实例选变体；[name] 给 null＝这一组不选。
void lcSetInstanceVariant(LcNode instance, String group, String? name) {
  final raw = instance.more[kLcVariant];
  final map = <String, dynamic>{if (raw is Map) ...raw.cast<String, dynamic>()};
  name == null ? map.remove(group) : map[group] = name;
  if (map.isEmpty) {
    instance.more.remove(kLcVariant);
  } else {
    instance.more[kLcVariant] = map;
  }
}

/// 选了这些变体以后，定义里这个节点多出来的样式（后面的组盖前面的）。
Map<String, String> lcVariantStyleFor(List<LcVariant> variants, Map<String, String> picked, String nodeId) {
  if (picked.isEmpty) return const {};
  final out = <String, String>{};
  for (final v in variants) {
    if (picked[v.group] == v.name) out.addAll(v.styles[nodeId] ?? const {});
  }
  return out;
}

// —— 组件自己的状态（每个实例一份） ——

List<LcVariable> lcCompStates(LcComponentDef def) => _readList(def.more, kLcCompState, (x) => LcVariable.tryParse(x, wide: true), (v) => v.name);

void lcSetCompStates(LcComponentDef def, List<LcVariable> states) => _writeList(def.more, kLcCompState, states, (x) => LcVariable.tryParse(x, wide: true), (v) => v.name, (v) => v.toJson());

// —— 实例上：接事件 ——

/// 实例上给组件的事件接的积木（事件名 → 一串积木）。读不懂的那一串当没有。
Map<String, List<LcBlock>> lcOnOf(LcNode instance) {
  final raw = instance.more[kLcOn];
  final out = <String, List<LcBlock>>{};
  if (raw is! Map) return out;
  raw.forEach((k, v) {
    if (k is! String || !kLcEventName.hasMatch(k) || v is! List) return;
    final body = <LcBlock>[];
    for (final b in v) {
      final x = LcBlock.tryParse(b, 0);
      if (x == null) return;
      body.add(x);
    }
    if (body.isNotEmpty) out[k] = body;
  });
  return out;
}

void lcSetOn(LcNode instance, String event, List<LcBlock>? body) {
  final raw = instance.more[kLcOn];
  final map = <String, dynamic>{if (raw is Map) ...raw.cast<String, dynamic>()};
  if (body == null || body.isEmpty) {
    map.remove(event);
  } else {
    map[event] = [for (final b in body) b.toJson()];
  }
  if (map.isEmpty) {
    instance.more.remove(kLcOn);
  } else {
    instance.more[kLcOn] = map;
  }
}

/// 这个定义用没用第 6 期的新东西（事件、变体、状态、定义里的绑定）。没用的定义四种导出走原来的路、逐字节不变。
bool lcDefIsLive(LcComponentDef def) {
  if (lcCompEvents(def).isNotEmpty || lcVariants(def).isNotEmpty || lcCompStates(def).isNotEmpty) return true;
  var any = false;
  void walk(LcNode n) {
    any = any || lcHasBindings(n) || n.more[kLcEmit] != null;
    for (final c in n.children) {
      if (!any) walk(c);
    }
  }

  walk(def.root);
  return any;
}

/// 这个实例用没用新东西（属性绑了状态、接了事件、选了变体）。
bool lcInstanceIsLive(LcNode instance) => instance.more[kLcOn] != null || instance.more[kLcVariant] != null || instance.more[kLcData] != null;

/// 拷一份定义上的这三个字段（造临时文档、复制组件时用）。
Map<String, dynamic> lcCopyDefMore(Map<String, dynamic> more) => (_copy(more) as Map).cast<String, dynamic>();
