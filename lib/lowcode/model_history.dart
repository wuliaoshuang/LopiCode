import 'package:lopicode/lowcode/model.dart';

/// 撤销 / 重做：存整份 JSON 快照，简单可靠。
///
/// 多页面（第 4 期）：整个项目一条撤销线。每份快照另外记着“这一步是在哪一页上做的”——
/// 撤销 / 重做拿回来的文档就开在那一页上，人看得见刚才退掉（重做）的是什么。
/// “当前在看哪一页”本身不算修改：只换页不会多出一步。
class LcHistory {
  LcHistory(LcDocument initial) : _undo = [(initial.encode(), initial.page.id)];
  final List<(String, String)> _undo;
  final List<(String, String)> _redo = [];
  static const int limit = 100;

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  /// 每次修改之后调用。
  void record(LcDocument doc) {
    final snap = doc.encode();
    if (snap == _undo.last.$1) return;
    _undo.add((snap, doc.page.id));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  LcDocument? undo() {
    if (!canUndo) return null;
    final undone = _undo.removeLast();
    _redo.add(undone);
    // 开在“被退掉的那一步”所在的页上；那一页在退回去以后不存在了（那一步就是新建它），就开在上一步所在的页。
    return _open(_undo.last.$1, [undone.$2, _undo.last.$2]);
  }

  LcDocument? redo() {
    if (!canRedo) return null;
    final snap = _redo.removeLast();
    _undo.add(snap);
    return _open(snap.$1, [snap.$2]);
  }

  static LcDocument _open(String source, List<String> pageIds) {
    final doc = LcDocument.parse(source);
    for (final id in pageIds) {
      if (doc.openPage(id)) break;
    }
    return doc;
  }
}
