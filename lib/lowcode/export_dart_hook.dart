/// Flutter 导出的“会动的那一路”在生成器里的几个接入点（实现在 export_dart_live_bind.dart）。
///
/// 没用主题变量、绑定、断点、状态样式、网格的项目，[dartLive] 一直是 null，生成器走原来的路，
/// 导出结果和以前逐字节一样。
library;

import 'package:lopicode/lowcode/model.dart';

typedef DartNodeFn = String Function(LcNode n, LcNode? parent, int indent);

abstract class DartLiveHook {
  /// 生成一个节点：重复、条件、绑了的属性、状态样式、网格里的格子都在这儿套上。[core] 是原来的生成函数。
  /// 返回的是列表里的一项（可能带 `for (…)` / `if (…)`，也可能是用逗号隔开的两项）。
  String node(LcNode n, LcNode? parent, int indent, DartNodeFn core);

  /// 页面级的栏（顶部 / 底部导航栏，不在列表里）。[gen] 拿一个节点出它的控件代码。
  String bar(LcNode bar, String Function(LcNode shown) gen);

  /// [n] 是网格时，返回代替 Column / Row 的那段代码；不是网格返回 null。[children] 是已经排好缩进的各项。
  String? grid(LcNode n, int indent, String children);

  /// 双向绑定：现在的值（一句 Dart）；这个控件没有双向绑定返回 null。
  String? modelRead(LcNode n);

  /// 双向绑定：把 [value]（一句 Dart）写回状态的那句代码。
  String modelWrite(LcNode n, String value);

  /// 输入框 / 多行输入框双向绑定时要加的参数（`controller: …`、`onChanged: …`）；没有返回 null。
  List<String>? fieldArgs(LcNode n);

  /// 绑了的文字类属性（图片地址）：一句值是 String 的 Dart；没绑返回 null。
  String? boundText(LcNode n, String prop);

  /// 列表控件绑了“列表内容”：一句值是 List 的 Dart；没绑返回 null。
  String? boundList(LcNode n);
}

/// 现在是不是在走“会动的那一路”（export_dart_live.dart 在生成每一页的前后设上 / 清掉）。
DartLiveHook? dartLive;
