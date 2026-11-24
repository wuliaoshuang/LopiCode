// 设计约束（编辑器 · 格式化）
// - “格式化”是 ⋮ 菜单里的一项（顶栏一行只做“切文件 + 保存”，挤不下再多一个按钮）；不支持的文件类型这一项是灰的。
// - 点了以后整篇换成排好的内容，算一次编辑：⋮ → 撤销 能一步退回去；光标留在原来那一行（行数变少了就落在最后一行）。
// - 结果只用底部的一句提示说：已格式化 / 已经是整齐的 / 没有格式化：原因。失败时内容一个字都不动。
import 'dart:math';

import 'package:lopicode/format/format.dart';
import 'package:re_editor/re_editor.dart';

/// 这个文件能不能格式化（菜单项据此变灰）。
bool canFormat(String path) => formatLanguageFor(path) != null;

/// 把编辑器里的内容格式化，返回要提示给用户的一句话。
String formatInEditor(CodeLineEditingController controller, String path) {
  final language = formatLanguageFor(path);
  if (language == null) return '这种文件不支持格式化';
  final result = formatCode(controller.text, language);
  final problem = result.problem;
  if (problem != null) return '没有格式化：$problem';
  final note = result.note;
  if (!result.changed) return note == null ? '已经是整齐的' : '没有可以调整的地方（$note）';
  final lines = result.text.codeLines;
  final line = min(controller.selection.extentIndex, lines.length - 1);
  // 和 controller.text = … 一样包成一次可撤销的操作，只是顺手把光标放回原来那一行
  controller.runRevocableOp(() {
    controller.value = CodeLineEditingValue(
      codeLines: lines,
      selection: CodeLineSelection.collapsed(index: line, offset: 0),
    );
  });
  return note == null ? '已格式化' : '已格式化；$note';
}
