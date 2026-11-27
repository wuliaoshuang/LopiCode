/// 组件事件对接（2026-11-27 中途包）：线 A 的帽子“当〔组件实例〕发出〔事件〕”接上线 B 的真组件事件。
///
/// - 帽子在页面宿主里登记成 `(<实例 id>, "emit:<事件名>")`，数据从事件对象的 `lcData.<数据名>` 里读（lib_page_module.dart）。
/// - 线 B 的组件往外发事件：Vue 3 / React 里是组件文件发 `{ lcEvent, detail: { 数据名: 值 }, target }`（export_comp_files.dart 的 `kLcEvtJs`）；
///   纯网页里实例是摊开的，没有事件对象，带的数据是一个个式子（component_expand_live.dart）。
///
/// 中间差的一步就是这里的“转发记号”：导出前给接了帽子的 (实例, 事件) 各加一条处理，处理里只放一块记号积木 [kLcEmitBridgeOp]；
/// logic_core_js.dart 写处理函数时见到它，写一句 `lcPage.emit("<实例 id>", "emit:<事件名>", { lcData: … })`。
/// 记号只活在“给导出看的文档”里，不进存盘文件，画布上也看不到。旧的页面逻辑（`logic.front` 为空）完全不走这里。
library;

import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOpOf;
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 记号积木的名字（不是给人用的积木，积木盒里没有）。
const String kLcEmitBridgeOp = 'lcEmitBridge';

String? _lit(Object? v) => v is String ? v : (v is Map && v['e'] == 'text' && v['v'] is String ? v['v'] as String : null);

/// 这一页的新逻辑里接了“当〔组件实例〕发出〔事件〕”的：实例 id → 事件名。旧的页面逻辑＝空的。
Map<String, Set<String>> lcFrontEmitHats(LcLogic logic) {
  final out = <String, Set<String>>{};
  final front = lcFrontOf(logic);
  if (front == null) return out;
  for (final h in front.hats) {
    final ref = libOpOf(h.op);
    if (ref == null || ref.lib != kLcPageLibId || ref.block != 'onEmit') continue;
    final node = _lit(h.args['node']), event = _lit(h.args['event']);
    if (node == null || node.isEmpty || event == null || event.isEmpty) continue;
    out.putIfAbsent(node, () => {}).add(event);
  }
  return out;
}

/// 一块转发记号：[instance] 这个实例发出了 [event]。
LcBlock lcEmitBridgeBlock(String instance, String event) => LcBlock(op: kLcEmitBridgeOp, args: {'instance': instance, 'event': event});

/// 页面上这个实例的每个接了帽子的事件各一块记号（交给摊开实例的那一步，当成“这个事件接到的积木”）。
Map<String, List<LcBlock>> lcEmitBridgeHandlers(Map<String, Set<String>> hats, String instance) => {
  for (final e in hats[instance] ?? const <String>{}) e: [lcEmitBridgeBlock(instance, e)],
};

bool lcIsEmitBridge(List<LcBlock> body) => body.length == 1 && body.single.op == kLcEmitBridgeOp;

/// 摊开的实例（纯网页）：没有事件对象，把这次往外发带的数据（数据名 → 式子，已经是页面这一层的写法）记在记号上。
List<LcBlock> lcEmitBridgeWithData(List<LcBlock> body, LcEmit emit) {
  final b = body.single.clone();
  b.args['data'] = <String, dynamic>{for (final a in emit.args.entries) a.key: ?lcSrcExprOf(a.value)};
  return [b];
}

/// 这条处理是不是转发记号；是就交回 (实例, 事件, 数据的式子)。`data` 为 null＝数据在事件对象的 `detail` 里（组件文件发的）。
({String instance, String event, Map<String, dynamic>? data})? lcEmitBridgeOf(LcHandler h) {
  if (!lcIsEmitBridge(h.body)) return null;
  final a = h.body.single.args;
  final instance = a['instance'], event = a['event'], data = a['data'];
  if (instance is! String || event is! String) return null;
  return (instance: instance, event: event, data: data is Map ? data.cast<String, dynamic>() : null);
}
