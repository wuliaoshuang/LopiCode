// 聊天列表“滚到某条消息”（从收藏页跳回原消息用）。
//
// 列表是按需搭的（ListView.builder），远处的行还没搭出来、高度也不知道，所以分两步：
// 1. 目标行已经搭出来了：直接滚到它；
// 2. 还没搭出来：看现在搭出来的消息行在目标的前面还是后面，朝那个方向翻一屏，再看；
//    一行消息都没搭出来时按“第几行 / 一共几行”估一个位置。最多翻 [_maxHops] 次，还找不到就放弃（返回 false）。
// 聊天页只要：build 里 [sync]，itemBuilder 里 [wrap]，要跳的时候 [jumpTo]。
import 'dart:async';

import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 这一行是哪条消息（不是消息行返回 null）。
String? messageIdOfRow(ChatRow row) => switch (row) {
  ItemRow(item: UserItem(:final id)) => id,
  ItemRow(item: AssistantItem(:final id)) => id,
  _ => null,
};

class ChatJumper {
  ChatJumper(this.scroll);
  final ScrollController scroll;

  static const int _maxHops = 60;

  /// 刚跳到的那条消息（短暂高亮，过一会儿自己清掉）。
  final ValueNotifier<String?> flash = ValueNotifier<String?>(null);
  Timer? _flashOff;

  final Map<String, GlobalKey> _keys = {};
  Map<String, int> _indexOf = const {};
  int _count = 0;

  /// 每次搭界面时告诉它现在有哪些行。
  void sync(List<ChatRow> rows) {
    final next = <String, int>{};
    for (var i = 0; i < rows.length; i++) {
      final id = messageIdOfRow(rows[i]);
      if (id != null) next[id] = i;
    }
    _indexOf = next;
    _count = rows.length;
    _keys.removeWhere((id, _) => !next.containsKey(id));
  }

  /// 给消息行套一个能找到它的钥匙；别的行原样返回。
  Widget wrap(ChatRow row, Widget child) {
    final id = messageIdOfRow(row);
    return id == null ? child : KeyedSubtree(key: _keys.putIfAbsent(id, GlobalKey.new), child: child);
  }

  /// 这条消息在不在当前列表里。
  bool has(String id) => _indexOf.containsKey(id);

  /// 正在往目标滚。这期间聊天页不要做“有新内容就贴到底”的自动滚动，不然两边抢。
  bool get busy => _busy;
  bool _busy = false;

  /// 滚到 [id] 这条并高亮一下。滚到了返回 true。
  Future<bool> jumpTo(String id) async {
    if (_busy) return false;
    _busy = true;
    try {
      // 先等这一帧排完：刚换对话时列表还会自己贴到底一次，等它做完再找
      await WidgetsBinding.instance.endOfFrame;
      return await _seek(id);
    } finally {
      _busy = false;
    }
  }

  Future<bool> _seek(String id) async {
    final index = _indexOf[id];
    if (index == null || !scroll.hasClients) return false;
    for (var hop = 0; hop < _maxHops; hop++) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.2);
        _flash(id);
        return true;
      }
      if (!scroll.hasClients) return false;
      final pos = scroll.position;
      final built = [
        for (final e in _keys.entries)
          if (e.value.currentContext != null && _indexOf[e.key] != null) _indexOf[e.key]!,
      ];
      final double want;
      if (built.isEmpty) {
        want = _count <= 1 ? 0 : pos.maxScrollExtent * index / (_count - 1);
      } else if (built.every((i) => i > index)) {
        want = pos.pixels - pos.viewportDimension * 0.9;
      } else {
        want = pos.pixels + pos.viewportDimension * 0.9;
      }
      final target = want.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (target == pos.pixels && built.isNotEmpty) return false; // 已经到头了还没有
      scroll.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
    return false;
  }

  void _flash(String id) {
    _flashOff?.cancel();
    flash.value = id;
    _flashOff = Timer(const Duration(milliseconds: 1600), () => flash.value = null);
  }

  void dispose() {
    _flashOff?.cancel();
    flash.dispose();
  }
}
