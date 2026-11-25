// 一个工作区里收藏的消息（lib/session/favorites.dart 是数据的样子和读写）。
//
// 照“不可变快照 + Notifier”写：状态是不可改的列表，只有 [FavoritesNotifier] 能换；
// 每次变化马上写盘（原子写），写不了只是这次打开期间有效，不让界面出错。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/favorites.dart';
import 'package:riverpod/riverpod.dart';

class FavoritesState {
  const FavoritesState({this.items = const [], this.loaded = false});

  /// 收藏的消息，新收藏的在前（列表不可改）。
  final List<FavoriteMessage> items;

  /// 从盘上读过了没有。
  final bool loaded;

  bool contains(String convId, String messageId) => items.any((f) => f.convId == convId && f.messageId == messageId);
}

class FavoritesNotifier extends Notifier<FavoritesState> {
  FavoritesNotifier(this.session);
  final ProjectSession session;

  FavoritesState _snap = const FavoritesState();

  /// 最近一份状态（工作区关掉以后也能读）。
  FavoritesState get current => _snap;

  File get file => File(session.guard.resolve('${PathGuard.reservedDir}/favorites.json', allowReserved: true));

  @override
  FavoritesState build() => _snap = const FavoritesState();

  void _set(List<FavoriteMessage> items) {
    _snap = FavoritesState(items: List.unmodifiable(items), loaded: true);
    if (ref.mounted && !session.released) state = _snap;
  }

  Future<void>? _loading;

  /// 从盘上读一次。读盘期间点的收藏不会被读回来的旧内容盖掉。
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final onDisk = await readFavorites(file);
    if (session.disposed) return;
    final mine = _snap.items;
    final keys = {for (final f in mine) f.key};
    _set([
      ...mine,
      for (final f in onDisk)
        if (!keys.contains(f.key)) f,
    ]);
  }

  Future<void> _save() async {
    try {
      await writeFavorites(file, _snap.items);
    } on FileSystemException {
      // 盘写不了：这次打开期间内存里的仍然生效
    }
  }

  /// 收藏 / 取消收藏。返回现在是不是收藏着。
  Future<bool> toggle({required String convId, required String messageId, required String role, required String text, required String convTitle, DateTime? now}) async {
    if (!_snap.loaded) await load();
    final had = _snap.contains(convId, messageId);
    if (had) {
      _set([
        for (final f in _snap.items)
          if (f.convId != convId || f.messageId != messageId) f,
      ]);
    } else {
      final clipped = text.length > kFavoriteSnapshotChars ? '${text.substring(0, kFavoriteSnapshotChars)}…' : text;
      _set([FavoriteMessage(convId: convId, messageId: messageId, role: role, text: clipped, convTitle: convTitle, savedAt: now ?? DateTime.now()), ..._snap.items]);
    }
    await _save();
    return !had;
  }

  /// 从收藏里拿掉一条（收藏页里点的）。
  Future<void> remove(String key) async {
    if (!_snap.loaded) await load();
    if (!_snap.items.any((f) => f.key == key)) return;
    _set([
      for (final f in _snap.items)
        if (f.key != key) f,
    ]);
    await _save();
  }

  /// 原消息被删了：收藏留着（文字快照还在），标成“原消息已删除”。
  Future<void> markGone(String convId, Set<String> messageIds) async {
    if (!_snap.loaded) await load();
    if (!_snap.items.any((f) => f.convId == convId && messageIds.contains(f.messageId) && !f.gone)) return;
    _set([for (final f in _snap.items) f.convId == convId && messageIds.contains(f.messageId) ? f.copyWith(gone: true) : f]);
    await _save();
  }
}

/// 某个工作区里收藏的消息（按工作区分身）。
final favoritesProvider = NotifierProvider.family<FavoritesNotifier, FavoritesState, ProjectSession>(FavoritesNotifier.new);

/// “跳回原消息”：收藏页点了一条以后，聊天页要滚到的那条消息的 id（聊天页滚完就清掉）。
class ChatJumpNotifier extends Notifier<String?> {
  ChatJumpNotifier(this.session);
  final ProjectSession session;

  @override
  String? build() => null;

  void request(String messageId) {
    if (ref.mounted && !session.released) state = messageId;
  }

  void clear() {
    if (ref.mounted && state != null) state = null;
  }
}

final chatJumpProvider = NotifierProvider.family<ChatJumpNotifier, String?, ProjectSession>(ChatJumpNotifier.new);
