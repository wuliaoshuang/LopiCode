// 一个工作区的对话目录：有哪些对话（含子代理的）、当前是哪一段、项目规则。
//
// 状态不可变：改标题、换模型、累计用量都是“换一条新的 [Conversation] 进列表”。
// 目录存在 chats.json，项目规则存在 rules.md（都在工作区的保留目录里）。
// 每段对话的消息记录不归这里管（见 ProjectSession 的对话运行部分）。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/project_session.dart';
import 'package:riverpod/riverpod.dart';

class ConversationsState {
  ConversationsState({this.all = const [], this.activeId = 'main', this.loaded = false, this.projectRules = '', Conversation? fallback})
    : fallback = fallback ?? Conversation('main', '', DateTime.fromMillisecondsSinceEpoch(0));

  /// 全部对话（列表不可改），最近说过话的在前。
  final List<Conversation> all;
  final String activeId;

  /// 目录从盘上读过了没有。
  final bool loaded;

  /// 项目规则：她写给 Agent 的长期要求，拼在系统提示词后面。
  final String projectRules;

  /// 目录还没读出来时顶替“当前对话”的空对话。
  final Conversation fallback;

  Conversation get active => byId(activeId) ?? fallback;

  Conversation? byId(String? id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 侧边栏里列的对话：不含子代理的。
  List<Conversation> get top => [
    for (final c in all)
      if (c.parentId == null) c,
  ];

  /// 这段对话的“根”：子代理的权限、计划模式、预设都跟着最上面那段主对话走。
  Conversation rootOf(Conversation conv) {
    var c = conv;
    for (var i = 0; i < 8 && c.parentId != null; i++) {
      final parent = byId(c.parentId);
      if (parent == null) break;
      c = parent;
    }
    return c;
  }

  /// 子代理谱系：[rootId] 这段对话派出的全部子代理（含子代理再派出的），按派出顺序。
  List<Conversation> descendantsOf(String rootId) {
    final out = <Conversation>[];
    void walk(String id) {
      final kids = all.where((c) => c.parentId == id).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final k in kids) {
        out.add(k);
        walk(k.id);
      }
    }

    walk(rootId);
    return out;
  }

  ConversationsState copyWith({List<Conversation>? all, String? activeId, bool? loaded, String? projectRules}) => ConversationsState(
    all: all == null ? this.all : List.unmodifiable(all),
    activeId: activeId ?? this.activeId,
    loaded: loaded ?? this.loaded,
    projectRules: projectRules ?? this.projectRules,
    fallback: fallback,
  );
}

class ConversationsNotifier extends Notifier<ConversationsState> {
  ConversationsNotifier(this.session);
  final ProjectSession session;

  /// 最近一份状态。工作区关掉、应用退出以后也能读（跑到一半的那一轮收尾存盘时要用）。
  ConversationsState get current => _snap;
  ConversationsState _snap = ConversationsState();

  void _set(ConversationsState next) {
    _snap = next;
    // 工作区关掉、收完尾以后（released）不再通知任何人
    if (ref.mounted && !session.released) state = next;
  }

  File _reserved(String name) => File(session.guard.resolve('${PathGuard.reservedDir}/$name', allowReserved: true));
  File get _indexFile => _reserved('chats.json');
  File get _rulesFile => _reserved('rules.md');

  @override
  ConversationsState build() => _snap = ConversationsState();

  Future<void>? _loading;

  /// 从盘上读目录和项目规则。只读一次；一段都没有时补一段“主对话”，当前对话定在最近的那段。
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    if (_snap.loaded || session.disposed) return;
    var rules = '';
    try {
      if (await _rulesFile.exists()) rules = (await _rulesFile.readAsString()).trim();
    } on FileSystemException {
      rules = '';
    }
    final list = <Conversation>[];
    try {
      // 目录文件坏了：备份后当只有一段“主对话”（各段对话的记录文件还在盘上）
      final decoded = await readJsonFile(_indexFile, accept: (j) => j is List, label: '对话目录');
      if (decoded is List) {
        for (final m in decoded) {
          final conv = Conversation.fromJson(m);
          if (conv != null) list.add(conv);
        }
      }
    } catch (_) {
      // 某一条的形状不对（老版本）：读到哪算哪
    }
    if (!ref.mounted || session.disposed || _snap.loaded) return; // 读盘期间工作区关了：不往状态里写
    if (!list.any((c) => c.parentId == null)) list.add(Conversation('main', '', DateTime.now()));
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _set(_snap.copyWith(all: list, activeId: list.firstWhere((c) => c.parentId == null).id, loaded: true, projectRules: rules));
  }

  /// 没被占用的新 id。
  String newId() {
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (_snap.all.any((c) => c.id == id)) {
      id = '${id}x';
    }
    return id;
  }

  /// 加一段对话。[front]＝排到最前；[activate]＝同时切过去。
  void add(Conversation conv, {bool front = false, bool activate = false}) {
    if (_snap.byId(conv.id) != null) return;
    _set(_snap.copyWith(all: front ? [conv, ..._snap.all] : [..._snap.all, conv], activeId: activate ? conv.id : null));
  }

  /// 把 [id] 这段换成 [change] 算出来的新的；[toFront]＝同时排到最前。没有这段就什么都不做。
  Conversation? update(String id, Conversation Function(Conversation c) change, {bool toFront = false}) {
    final old = _snap.byId(id);
    if (old == null) return null;
    final next = change(old);
    assert(next.id == id, '不能借 update 换 id');
    _set(
      _snap.copyWith(
        all: toFront
            ? [
                next,
                for (final c in _snap.all)
                  if (c.id != id) c,
              ]
            : [for (final c in _snap.all) c.id == id ? next : c],
      ),
    );
    return next;
  }

  /// 切到另一段（得是有的）。
  void activate(String id) {
    if (id == _snap.activeId || _snap.byId(id) == null) return;
    _set(_snap.copyWith(activeId: id));
  }

  /// 删掉 [ids] 这些段。删到一段主对话都不剩时补一段空的；当前对话定在最前面那段主对话。
  void removeAll(Set<String> ids) {
    final list = [
      for (final c in _snap.all)
        if (!ids.contains(c.id)) c,
    ];
    if (!list.any((c) => c.parentId == null)) list.add(Conversation('main', '', DateTime.now()));
    _set(_snap.copyWith(all: list, activeId: list.firstWhere((c) => c.parentId == null).id));
  }

  /// 把目录写回盘上。存不了就算了（这次打开期间内存里的仍然生效）。
  /// 目录还没从盘上读出来时不写：不然会拿空目录盖掉盘上的。
  Future<void> save() async {
    if (!_snap.loaded) return;
    try {
      await writeJsonAtomic(_indexFile, [for (final c in _snap.all) c.toJson()]);
    } on FileSystemException {
      // 存不了就算了
    }
  }

  Future<void> setProjectRules(String text) async {
    final rules = text.trim();
    _set(_snap.copyWith(projectRules: rules));
    try {
      await _rulesFile.parent.create(recursive: true);
      await _rulesFile.writeAsString(rules);
    } on FileSystemException {
      // 存不了：这次打开期间仍然生效
    }
  }
}

/// 某个工作区的对话目录（按工作区分身）。
final conversationsProvider = NotifierProvider.family<ConversationsNotifier, ConversationsState, ProjectSession>(ConversationsNotifier.new);
