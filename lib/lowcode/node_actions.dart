/// 长按菜单 / “更多操作”里不用再问人的那几项，搭建页和组件编辑页共用。
library;

import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/model.dart';

/// 做一项操作。返回 (做没做, 做完该选中谁)：没做（不认识的项、要先问人的“删除 / 存成组件”等）是 (false, null)。
///
/// 复制只是放进剪贴板，不改文档、不记撤销；其余每项一次修改、一条撤销。
(bool, String?) runLcNodeAction(String action, LcDocument doc, String nodeId, LcEdit apply) {
  String? select;
  switch (action) {
    case 'clip':
      lcClipboardCopy(doc, nodeId);
      return (true, nodeId);
    case 'paste':
      apply((d) => select = lcClipboardPasteAfter(d, nodeId));
    case 'pasteInto':
      apply((d) => select = lcClipboardPaste(d, nodeId));
    case 'dup':
      apply((d) => select = d.duplicate(nodeId));
    case 'wrap':
      apply((d) => select = wrapInContainer(d, nodeId));
    case 'up':
      apply((d) => d.shift(nodeId, -1));
    case 'down':
      apply((d) => d.shift(nodeId, 1));
    default:
      return (false, null);
  }
  return (true, select ?? nodeId);
}
