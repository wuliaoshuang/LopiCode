// 对一条消息能做的事里“纯计算”的那部分：一轮从哪到哪、删一条 / 删一轮之后消息记录长什么样、还合不合法。
// 不读盘、不碰状态；真正动手（换进状态、存盘、通知收藏）在 message_actions.dart。
//
// 名词：
// - “一轮”＝从我的一条消息（含中途插的话）到我的下一条消息之前：我的话 + Agent 的步骤 + 它的回复。
//   压缩留下的摘要和它后面那句承接语不属于任何一轮，删除从不碰它们。
// - “合法”＝发给模型接口不会被拒绝：带工具调用的 assistant 消息后面紧跟着每个调用的结果，工具结果前面有调用它的那条；
//   另外删除不许新造出“开头就是 assistant”“两条 assistant 挨着”这两种本来没有的形状（Anthropic 那边消息要一问一答地排）。
//
// 删除的规矩（2026-11-25 自定，可改）：
// - 只删这一条：我的消息整条拿掉；Agent 的一段回复——那条消息没带工具调用就整条拿掉（思考内容、原始内容块跟着走），
//   带了工具调用就只抹掉文字，工具调用、它的结果、思考内容原样留着（少了它们下一次请求会被接口拒绝）。
//   拿掉后会让记录不合法的（比如只删提问、留下回复顶在最前面）不给删，只能整轮删。
// - 删这一整轮：这一轮里的消息全拿掉，工具调用和结果成对走。
// - 挂在被删消息上的“这一轮用量”“改了哪些文件”：只删一条时挪到同一轮里前一条消息上；整轮删就一起没了。
//   对话累计用量不在消息上（在对话目录里），不受影响。文件改动不回滚。
import 'package:lopicode/agent/agent_events.dart' show kAppNoticeMark;
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/message_ids.dart';

/// 我说的话（不是压缩摘要，也不是应用通知）。
bool isRealUserMessage(Map<String, dynamic> m) => m['role'] == 'user' && m[kCompactMark] != true && m[kAppNoticeMark] is! String;

/// 压缩留下的摘要 / 承接语。
bool isCompactPiece(Map<String, dynamic> m) => m[kCompactMark] == true || m[kCompactAckMark] == true;

List<Object?> _callsOf(Map<String, dynamic> m) {
  final calls = m['tool_calls'];
  return m['role'] == 'assistant' && calls is List ? calls : const [];
}

List<String> _callIdsOf(Map<String, dynamic> m) => [
  for (final c in _callsOf(m))
    if (c is Map) '${c['id']}',
];

bool _hasText(Map<String, dynamic> m) => m['content'] is String && (m['content'] as String).isNotEmpty;

/// [index] 所在那一轮的范围 `[start, end)`。第一条“我的消息”之前的东西算第 0 段。
({int start, int end}) turnRangeAt(List<Map<String, dynamic>> messages, int index) {
  var start = index;
  while (start > 0 && !isRealUserMessage(messages[start])) {
    start--;
  }
  var end = index + 1;
  while (end < messages.length && !isRealUserMessage(messages[end])) {
    end++;
  }
  return (start: start, end: end);
}

/// 每一轮里操作栏挂在哪段话下面（它的 id）：整轮级别的操作（重试……）只在这里出现一次。
/// 有“正式回复”（有文字、后面没跟工具调用）就挂在最后一段正式回复下面；
/// 一段正式回复都没有（被停下、到步数上限，只留下工具调用之间说的话）就挂在最后一段说明下面，不让这一轮没有入口。
Set<String> lastReplyIdsOf(List<Map<String, dynamic>> messages) {
  final out = <String>{};
  String? formal;
  String? note;
  void close() {
    final at = formal ?? note;
    if (at != null) out.add(at);
    formal = null;
    note = null;
  }

  for (final m in messages) {
    if (isRealUserMessage(m)) {
      close();
    } else if (m['role'] == 'assistant' && !isCompactPiece(m) && _hasText(m)) {
      if (_hasCalls(m)) {
        note = messageIdOf(m) ?? note;
      } else {
        formal = messageIdOf(m) ?? formal;
      }
    }
  }
  close();
  return out;
}

/// 发给模型前会出的问题（只看没被压缩归档的消息）。空＝合法。
/// `head`＝开头就是 assistant；`pair:<i>`＝两条 assistant 挨着；其余是工具调用和结果对不上。
List<String> wireProblems(List<Map<String, dynamic>> messages) {
  final live = [
    for (final m in messages)
      if (!isArchived(m)) m,
  ];
  final out = <String>[];
  if (live.isNotEmpty && live.first['role'] == 'assistant') out.add('head');
  for (var i = 0; i < live.length; i++) {
    final m = live[i];
    if (m['role'] == 'assistant') {
      if (i > 0 && live[i - 1]['role'] == 'assistant') out.add('pair:$i');
      final want = _callIdsOf(m).toSet();
      var j = i + 1;
      final have = <String>{};
      while (j < live.length && live[j]['role'] == 'tool') {
        have.add('${live[j]['tool_call_id']}');
        j++;
      }
      for (final id in want.difference(have)) {
        out.add('工具调用 $id 没有结果');
      }
      for (final id in have.difference(want)) {
        out.add('工具结果 $id 找不到对应的调用');
      }
      if (!_hasText(m) && want.isEmpty && !isCompactPiece(m)) out.add('空的 assistant 消息 $i');
    } else if (m['role'] == 'tool') {
      // 往前越过别的工具结果，必须碰到一条 assistant
      var k = i - 1;
      while (k >= 0 && live[k]['role'] == 'tool') {
        k--;
      }
      if (k < 0 || live[k]['role'] != 'assistant') out.add('工具结果 ${m['tool_call_id']} 前面没有调用它的消息');
    }
  }
  return out;
}

/// 删除会不会新造出问题：[after] 里有、[before] 里没有的那几类。
bool _addsProblems(List<Map<String, dynamic>> before, List<Map<String, dynamic>> after) {
  String kind(String p) => p.startsWith('pair:') ? 'pair' : p;
  final old = <String, int>{};
  for (final p in wireProblems(before)) {
    old[kind(p)] = (old[kind(p)] ?? 0) + 1;
  }
  final now = <String, int>{};
  for (final p in wireProblems(after)) {
    now[kind(p)] = (now[kind(p)] ?? 0) + 1;
  }
  return now.entries.any((e) => e.value > (old[e.key] ?? 0));
}

enum DeleteScope { message, turn }

/// 删完以后的样子。
class DeleteResult {
  const DeleteResult(this.messages, {required this.goneIds, required this.goneCallIds});

  /// 新的消息记录（新列表；改过的消息是新的 Map，没改的还是原来那个对象）。
  final List<Map<String, dynamic>> messages;

  /// 文字不在了的消息 id（整条拿掉的 + 只抹掉文字的）。收藏据此标“原消息已删除”。
  final Set<String> goneIds;

  /// 一起拿掉的工具调用 id（派子代理的那几次，调用方据此把子代理对话一并删掉）。
  final Set<String> goneCallIds;
}

/// 删之前给用户看的：两种删法各自行不行、会带走什么。
class DeletePreview {
  const DeletePreview({
    required this.role,
    required this.archived,
    required this.single,
    required this.singleBlocked,
    required this.turn,
    required this.turnSteps,
    required this.turnReplies,
    required this.turnMine,
  });

  /// `user` / `assistant`。
  final String role;

  /// 这条已经被压缩进摘要了（Agent 本来就看不到原文，摘要里可能还留着它的意思）。
  final bool archived;

  /// “只删这一条”的结果；不能这么删是 null（原因见 [singleBlocked]）。
  final DeleteResult? single;
  final String? singleBlocked;

  /// “删这一整轮”的结果。
  final DeleteResult turn;

  /// 这一轮里有几个步骤（工具调用）、几段 Agent 的话、几条我的消息。
  final int turnSteps;
  final int turnReplies;
  final int turnMine;

  DeleteResult? of(DeleteScope scope) => scope == DeleteScope.message ? single : turn;
}

const List<String> _turnExtras = ['_usage', '_files'];

/// 把 [from] 上挂着的“这一轮用量 / 改过的文件”挪到 [to] 上（[to] 已经有的不盖）。
Map<String, dynamic> _withExtras(Map<String, dynamic> to, Map<String, dynamic> from) {
  final moved = {
    for (final k in _turnExtras)
      if (from.containsKey(k) && !to.containsKey(k)) k: from[k],
  };
  return moved.isEmpty ? to : {...to, ...moved};
}

/// 抹掉一条 assistant 消息的文字，工具调用、思考内容留着。Anthropic 的原始内容块里的文字块也一并拿掉。
Map<String, dynamic> _withoutText(Map<String, dynamic> m) {
  final next = {...m, 'content': null};
  final raw = m['_raw'];
  if (raw is Map && raw['content'] is List) {
    next['_raw'] = {
      ...raw,
      'content': [
        for (final b in raw['content'] as List)
          if (b is! Map || b['type'] != 'text') b,
      ],
    };
  }
  return next;
}

/// 工具结果找不到调用它的消息的，拿掉（正常删除不会出现；兜底）。
List<Map<String, dynamic>> _dropOrphanResults(List<Map<String, dynamic>> messages) {
  final out = <Map<String, dynamic>>[];
  var open = <String>{};
  for (final m in messages) {
    if (m['role'] == 'tool') {
      if (open.contains('${m['tool_call_id']}')) out.add(m);
      continue;
    }
    open = _callIdsOf(m).toSet();
    out.add(m);
  }
  return out;
}

/// 兜底收拾：找不到调用的工具结果拿掉，缺结果的工具调用补一条说明。返回新列表（重试 / 编辑 / 分支截断记录后也用它）。
List<Map<String, dynamic>> tidyForWire(List<Map<String, dynamic>> messages) {
  final clean = _dropOrphanResults(messages);
  repairDanglingCalls(clean);
  return clean;
}

DeleteResult _finish(List<Map<String, dynamic>> next, Set<String> goneIds, Set<String> goneCallIds) {
  final clean = _dropOrphanResults(next);
  repairDanglingCalls(clean);
  return DeleteResult(clean, goneIds: goneIds, goneCallIds: goneCallIds);
}

DeleteResult? _deleteSingle(List<Map<String, dynamic>> messages, int index) {
  final m = messages[index];
  final id = messageIdOf(m);
  if (id == null) return null;
  final List<Map<String, dynamic>> next;
  if (_callsOf(m).isNotEmpty) {
    if (!_hasText(m)) return null;
    next = [...messages]..[index] = _withoutText(m);
  } else {
    next = [...messages]..removeAt(index);
    // 这一轮的用量 / 改动清单挂在它上面：挪给同一轮里的前一条
    final range = turnRangeAt(messages, index);
    if (_turnExtras.any(m.containsKey) && index - 1 >= range.start && !isCompactPiece(next[index - 1])) {
      next[index - 1] = _withExtras(next[index - 1], m);
    }
  }
  if (_addsProblems(messages, next)) return null;
  return _finish(next, {id}, const {});
}

DeleteResult _deleteTurn(List<Map<String, dynamic>> messages, int index) {
  final range = turnRangeAt(messages, index);
  final goneIds = <String>{};
  final goneCalls = <String>{};
  final next = <Map<String, dynamic>>[];
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    if (i < range.start || i >= range.end || isCompactPiece(m)) {
      next.add(m);
      continue;
    }
    final id = messageIdOf(m);
    if (id != null) goneIds.add(id);
    goneCalls.addAll(_callIdsOf(m));
  }
  return _finish(next, goneIds, goneCalls);
}

/// 删 [id] 这条之前先算好两种删法。找不到这条（或它是压缩摘要、应用通知）返回 null。
DeletePreview? previewDelete(List<Map<String, dynamic>> messages, String id) {
  final index = indexOfMessage(messages, id);
  if (index < 0) return null;
  final m = messages[index];
  final role = m['role'];
  if (isCompactPiece(m) || m[kAppNoticeMark] is String || (role != 'user' && role != 'assistant')) return null;
  final range = turnRangeAt(messages, index);
  var steps = 0, replies = 0, mine = 0;
  for (var i = range.start; i < range.end; i++) {
    final x = messages[i];
    if (isCompactPiece(x)) continue;
    steps += _callsOf(x).length;
    if (x['role'] == 'assistant' && _hasText(x)) replies++;
    if (isRealUserMessage(x)) mine++;
  }
  final single = _deleteSingle(messages, index);
  return DeletePreview(
    role: '$role',
    archived: isArchived(m),
    single: single,
    singleBlocked: single != null
        ? null
        : role == 'user'
        ? '它后面紧跟着 Agent 的回复，单独删掉提问会让记录对不上，只能整轮删。'
        : '单独删掉这段会让记录对不上，只能整轮删。',
    turn: _deleteTurn(messages, index),
    turnSteps: steps,
    turnReplies: replies,
    turnMine: mine,
  );
}

/// 分享用：只这一条（工具调用不带）。找不到返回 null。
List<Map<String, dynamic>>? messagesForShare(List<Map<String, dynamic>> messages, String id, {required bool wholeTurn}) {
  final index = indexOfMessage(messages, id);
  if (index < 0) return null;
  if (!wholeTurn) {
    return [
      {...messages[index]}..remove('tool_calls'),
    ];
  }
  final range = turnRangeAt(messages, index);
  return [
    for (var i = range.start; i < range.end; i++)
      if (!isCompactPiece(messages[i])) messages[i],
  ];
}

bool _hasCalls(Map<String, dynamic> m) {
  final calls = m['tool_calls'];
  return calls is List && calls.isNotEmpty;
}
