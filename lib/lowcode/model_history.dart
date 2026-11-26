import 'package:lopicode/lowcode/model.dart';

/// 撤销 / 重做：存整份 JSON 快照，简单可靠。
class LcHistory {
  LcHistory(LcDocument initial) : _undo = [initial.encode()];
  final List<String> _undo;
  final List<String> _redo = [];
  static const int limit = 100;

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  /// 每次修改之后调用。
  void record(LcDocument doc) {
    final snap = doc.encode();
    if (snap == _undo.last) return;
    _undo.add(snap);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  LcDocument? undo() {
    if (!canUndo) return null;
    _redo.add(_undo.removeLast());
    return LcDocument.parse(_undo.last);
  }

  LcDocument? redo() {
    if (!canRedo) return null;
    final snap = _redo.removeLast();
    _undo.add(snap);
    return LcDocument.parse(snap);
  }
}
