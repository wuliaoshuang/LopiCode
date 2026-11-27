/// “常用”页在平板 / 桌面档上怎么写（第四轮 B1）。
///
/// “常用”页的每一项改的要么是**样子**（内外边距、间距、圆角、字号、颜色、对齐、宽高、换行、阴影…——最后都落到 CSS 上），
/// 要么是**内容**（文字、图片地址、输入框类型、导航项…）。样子可以分屏宽，内容不分。
///
/// 做法：不去一项一项认，而是在一个临时节点上把这次改动原样跑一遍——临时节点的样式是“这一档看到的那份”
/// （手机的 + 更窄各档的 + 这一档的差别）。跑完比较**最终样式**前后差在哪：
/// - 差出来的那几条记进 `responsive.<档>.style`（和“样式”页在这一档改是同一套存法，见 responsive.dart）；
///   手机那份（简写属性和 style）一个字不动。
/// - 改动里不是样子的那部分（别的属性、绑定这些节点上的字段）照旧写到节点上——它们不分屏宽。
/// - 一个“样子”属性改了、最终样式却没变（这种组件的这个属性不落到 CSS 上，比如图标的大小）：当内容处理，写到节点上。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

/// 落到样式上的简写属性（style_resolve.dart 的 legacyStyle 认的那几个）。
const Set<String> kLcStyleProps = {'width', 'height', 'padding', 'margin', 'radius', 'gap', 'bg', 'color', 'fontSize', 'bold', 'textAlign', 'align', 'justify'};

/// 一条样式“回到没设过”时写什么（这一档要盖掉下面那层的值，光删掉不够）。
String _resetValue(String name) {
  if (name == 'width' || name == 'height' || name == 'flex-basis' || name == 'align-self' || name == 'min-width' || name == 'aspect-ratio') return 'auto';
  if (name == 'flex-grow') return '0';
  if (name == 'flex-shrink') return '1';
  if (name.startsWith('padding-') || name.startsWith('margin-') || name.endsWith('-gap') || name.endsWith('-radius')) return '0px';
  if (name == 'font-weight') return '400';
  if (name == 'background-color') return 'transparent';
  if (name == 'box-shadow') return 'none';
  if (name == 'flex-wrap') return 'nowrap';
  if (name == 'flex-direction') return 'column';
  return 'initial';
}

LcNode _seenAt(LcNode n, String bp) {
  var style = canonicalDeclarations(n.style);
  for (final b in kLcBreakpoints) {
    style = mergeDeclarations(style, lcBpStyle(n, b));
    if (b == bp) break;
  }
  return LcNode(id: n.id, type: n.type, props: n.props, children: n.children, style: style, bind: n.bind, name: n.name, locked: n.locked, hidden: n.hidden, keptProps: n.keptProps, more: n.more)
    ..instSlots = n.instSlots;
}

Map<String, dynamic> _deep(Map<String, dynamic> m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

/// 在 [bp] 这一档上做一次“常用”页的改动 [change]（规矩见文件头）。返回这次有没有东西记进了这一档。
bool lcApplyCommonAtBp(LcNode n, LcNode? parent, String bp, void Function(LcNode n, LcNode? parent) change) {
  final seen = _seenAt(n, bp);
  final temp = LcNode(
    id: n.id,
    type: n.type,
    props: _deep(n.props),
    children: n.children,
    style: Map.of(seen.style),
    bind: n.bind,
    name: n.name,
    locked: n.locked,
    hidden: n.hidden,
    keptProps: n.keptProps,
    more: _deep(n.more),
  )..instSlots = n.instSlots;
  final before = resolvedStyle(temp, parent);
  change(temp, parent);
  final after = resolvedStyle(temp, parent);

  final set = <String, String>{
    for (final e in after.entries)
      if (before[e.key] != e.value) e.key: e.value,
  };
  final gone = [
    for (final k in before.keys)
      if (!after.containsKey(k)) k,
  ];
  final styled = set.isNotEmpty || gone.isNotEmpty;

  // 不是样子的那部分：照旧写到节点上。
  for (final k in {...n.props.keys, ...temp.props.keys}) {
    final a = n.props[k], b = temp.props[k];
    if (jsonEncode(a) == jsonEncode(b)) continue;
    if (kLcStyleProps.contains(k) && styled) continue;
    if (temp.props.containsKey(k)) {
      n.props[k] = b;
    } else {
      n.props.remove(k);
    }
  }
  for (final k in {...n.more.keys, ...temp.more.keys}) {
    if (k == 'responsive') continue;
    if (jsonEncode(n.more[k]) == jsonEncode(temp.more[k])) continue;
    if (temp.more.containsKey(k)) {
      n.more[k] = temp.more[k];
    } else {
      n.more.remove(k);
    }
  }
  if (!styled) return false;

  lcEditAtBp(n, bp, (m) {
    m.addAll(set);
    gone.forEach(m.remove);
  });
  // 这一档不再管以后，下面那层的值又冒出来了（比如手机上加粗、平板上要不加粗）：明说回到没设过。
  final now = resolvedStyle(_seenAt(n, bp), parent);
  final back = [
    for (final k in gone)
      if (now.containsKey(k)) k,
  ];
  // 设了固定宽度以后“撑满”那一组由 resolvedStyle 和导出自己收掉，不用在这儿写。
  final fixedWidth = after.containsKey('width');
  back.removeWhere((k) => fixedWidth && const {'flex-grow', 'flex-shrink', 'flex-basis', 'min-width', 'align-self'}.contains(k));
  if (back.isNotEmpty) {
    lcEditAtBp(n, bp, (m) {
      for (final k in back) {
        m[k] = _resetValue(k);
      }
    });
  }
  return true;
}

/// 面板显示用：[n] 在 [bp] 这一档看到的样子（只并断点的差别，变量不换成值）。
LcNode lcSeenAtBp(LcNode n, String bp) => _seenAt(n, bp);
