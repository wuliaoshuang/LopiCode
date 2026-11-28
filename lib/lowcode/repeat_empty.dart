/// “重复”的列表是空的时候显示的**一块内容**（不只是一句话）。
///
/// 做法（设计见 docs/blocks-v5-parts/E-editor-components.md §10.16、格式见 docs/lowcode-page-format-v3.md）：
/// 不给“重复”加新的格式，而是在被重复的组件**后面**放一个普通容器，带一条“存在条件”＝“那张列表有 0 项”，
/// 再在它的 `emptyOf` 里记下它是哪个“重复”的。于是：
/// - 旧文档原样能开；没用这个功能的页面，四种导出一个字节都不变；
/// - 四种导出（普通网页 / Vue / React / Flutter）本来就认“存在条件”，这块内容不用另写导出；
/// - 它就是画布上的一个容器：里面想放图、放按钮、放几行字都行，照常选中、改样式。
/// `emptyOf` 只给编辑器用：在“重复”的设置单里找到它、列表换了时把条件跟着换、不重复了时一起拿掉。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 节点上记“我是哪个‘重复’的空白内容”的那一格（值＝那个组件的 id）。
const String kLcEmptyOf = 'emptyOf';

/// 新加的那一块里默认的一句话。
const String kLcEmptyBlockText = '这里还没有内容';

/// [repeatId] 这个“重复”的空白内容（就在它旁边、同一个容器里）；没有返回 null。
LcNode? lcRepeatEmptyBlock(LcDocument doc, String repeatId) {
  final parent = doc.parentOf(repeatId);
  if (parent == null) return null;
  for (final c in parent.children) {
    if (c.more[kLcEmptyOf] == repeatId) return c;
  }
  return null;
}

/// “列表有 0 项”的条件。
Map<String, dynamic> lcEmptyCond(Map<String, dynamic> listExpr) => lcSrcExpr({
  'e': 'bin',
  'op': '==',
  'l': exLen(listExpr),
  'r': {'e': 'num', 'v': 0},
});

/// 给 [repeatId] 这个“重复”加一块空白内容（已经有了就不再加），返回那一块的 id；它没设重复、或放不进去返回 null。
/// 原来那句“空的时候显示的一句话”搬进这一块里（不然两样会一起出来）。
String? lcAddRepeatEmptyBlock(LcDocument doc, String repeatId) {
  final node = doc.find(repeatId), parent = doc.parentOf(repeatId);
  final rep = node == null ? null : lcRepeatOf(node);
  if (node == null || parent == null || rep == null) return null;
  final had = lcRepeatEmptyBlock(doc, repeatId);
  if (had != null) return had.id;
  final box = doc.newNode('container')..more[kLcEmptyOf] = repeatId;
  box.props['align'] = 'center';
  box.children.add(doc.newNode('text')..props['text'] = rep.empty ?? kLcEmptyBlockText);
  lcSetCond(box, kLcRenderIf, lcEmptyCond(rep.list));
  if (!doc.insert(parent.id, box, parent.children.indexOf(node) + 1)) return null;
  final raw = node.more[kLcRepeat];
  if (rep.empty != null && raw is Map) node.more[kLcRepeat] = <String, dynamic>{...raw.cast<String, dynamic>()}..remove('empty');
  return box.id;
}

/// “重复”的设置改过以后：列表换了，空白内容的条件跟着换；不重复了，空白内容一起拿掉。
void lcSyncRepeatEmptyBlock(LcDocument doc, String repeatId) {
  final node = doc.find(repeatId);
  final box = lcRepeatEmptyBlock(doc, repeatId);
  if (node == null || box == null) return;
  final rep = lcRepeatOf(node);
  if (rep == null) {
    doc.remove(box.id);
  } else {
    lcSetCond(box, kLcRenderIf, lcEmptyCond(rep.list));
  }
}
