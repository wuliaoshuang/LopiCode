// 后台整理记忆：一轮对话正常结束后，另发**一次**模型请求，从这段对话里提炼值得长期记住的东西，合并进记忆文件。
//
// 这件事每次都多花一次模型调用，所以：
// - 设置里有开关，**默认关**（设置 › 能力 › 记忆 ›“每轮结束后自动整理”）；
// - 客户端从 AppServices.createChatClient 拿，额度到顶照样被拦（不发请求）；
// - 用量记进刚结束的那一轮（轨迹里标成“整理记忆”），也累计进这段对话；
// - 只在主对话、有人在场、这一轮正常结束时做：出错 / 被停止的轮次、还挂着确认卡或提问卡时、子代理、自动化任务都不做；
// - 离上次整理不到 [kConsolidateMinInterval]、或者新消息不到 [kConsolidateMinMessages] 条，不做（攒着下次一起）；
// - 同一个工作区同一时间只做一个；应用或工作区关掉以后回来的结果一律丢掉；
// - 发出去的对话内容先脱敏；只增改、不删除；失败只记一笔日志，不打扰。
import 'dart:convert';

import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/memory_tools.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/workspace_chat.dart';

/// 两次整理至少隔多久（按工作区算）。
const Duration kConsolidateMinInterval = Duration(minutes: 10);

/// 上次整理之后，这段对话至少新增多少条“用户 / 助手说的话”才值得整理（大约三个来回）。
const int kConsolidateMinMessages = 6;

/// 交给模型的对话记录最多多少字（太长留结尾：最近的更要紧）；每条消息最多多少字。
const int kConsolidateMaxTranscriptChars = 24000;
const int kConsolidateMaxMessageChars = 2000;

/// 一次整理最多写几条。
const int kConsolidateMaxItems = 5;

/// 这条消息算不算“说的话”（用户 / 助手的文字；摘要、承接语、已归档的不算）。
bool _spoken(Map<String, dynamic> m) {
  final content = m['content'];
  return (m['role'] == 'user' || m['role'] == 'assistant') && content is String && content.trim().isNotEmpty && m[kCompactMark] != true && m[kCompactAckMark] != true && !isArchived(m);
}

/// 把要整理的消息写成一段脱敏过的纯文字。
String consolidationTranscript(List<Map<String, dynamic>> messages) {
  final out = StringBuffer();
  for (final m in messages.where(_spoken)) {
    final text = '${m['content']}'.trim();
    final who = m['role'] == 'user' ? '用户' : '助手';
    out.writeln('【$who】${text.length > kConsolidateMaxMessageChars ? '${text.substring(0, kConsolidateMaxMessageChars)}…' : text}');
  }
  final all = redactSecrets(out.toString());
  return all.length <= kConsolidateMaxTranscriptChars ? all : '…（前面省略）\n${all.substring(all.length - kConsolidateMaxTranscriptChars)}';
}

String _existing(String label, List<MemoryEntry> list) => '【$label】\n${list.isEmpty ? '（空）' : list.map((e) => '### ${e.title}\n${redactSecrets(e.body)}').join('\n')}';

/// 发给模型的整理请求。
List<Map<String, dynamic>> consolidationRequest(List<MemoryEntry> global, List<MemoryEntry>? project, String transcript) => [
  {'role': 'system', 'content': '你是记忆整理员：从一段对话里挑出以后还用得上的东西，整理进长期记忆。你只输出 JSON。'},
  {
    'role': 'user',
    'content':
        '现有的记忆：\n${_existing('全局记忆（global：和用户这个人有关，所有项目都适用）', global)}\n'
        '${project == null ? '（这次不能写项目记忆，只考虑 global）' : _existing('项目记忆（project：只和这个项目有关）', project)}\n\n'
        '下面是刚结束的一段编程助手和用户的对话（密钥之类已经抹掉）：\n<<<\n$transcript>>>\n\n'
        '请判断这段对话里有没有值得长期记住的内容。规矩：\n'
        '- 只记以后的对话还用得上的：用户明确说出的偏好和习惯、给这个项目定下的约定、踩过并且已经弄清楚的坑。'
        '一次性的任务细节、很快会过期的状态、看代码就能知道的东西都不记。拿不准就不记。\n'
        '- 和现有的某一条说的是同一件事：沿用那一条的标题，把新旧内容合并成一份完整的正文（不是只写新增的部分）。不要另起一条重复的。\n'
        '- 只增加和改写，不删除。最多 $kConsolidateMaxItems 条；标题不超过 $kMemoryMaxTitleChars 字，正文不超过 $kMemoryMaxBodyChars 字，一条只写一件事。\n'
        '- 绝对不要记密钥、令牌、密码。\n'
        '- 没有值得记的就返回空列表。\n'
        '只输出一个 JSON 对象，不要任何解释：\n'
        '{"items":[{"scope":"global 或 project","title":"标题","content":"正文"}]}',
  },
];

/// 从模型的回答里取出要写的几条（回答外面包了代码块、前后带了话也认）。读不懂返回 null。
List<({MemoryScope scope, String title, String content})>? parseConsolidation(String answer) {
  final from = answer.indexOf('{'), to = answer.lastIndexOf('}');
  if (from < 0 || to <= from) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(answer.substring(from, to + 1));
  } on FormatException {
    return null;
  }
  final items = decoded is Map ? decoded['items'] : null;
  if (items is! List) return null;
  final out = <({MemoryScope scope, String title, String content})>[];
  for (final i in items) {
    if (i is! Map) continue;
    final scope = MemoryScope.byId(i['scope']);
    final title = i['title'], content = i['content'];
    if (scope == null || title is! String || content is! String || title.trim().isEmpty || content.trim().isEmpty) continue;
    out.add((scope: scope, title: title, content: content));
    if (out.length >= kConsolidateMaxItems) break;
  }
  return out;
}

class MemoryConsolidator {
  MemoryConsolidator(this.core);
  final SessionCore core;

  bool _running = false;
  bool _stateLoaded = false;
  DateTime? _lastAt;

  /// 每段对话已经整理到第几条消息。
  final Map<String, int> _seen = {};

  // 上次什么时候整理的、每段对话整理到哪：存在工作区的内部目录里。
  late final _stateFile = core.reserved('memory-state.json');

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    _stateLoaded = true;
    // 文件坏了：备份后当作从没整理过。
    final j = await readJsonFile(_stateFile, accept: (j) => j is Map, label: '记忆整理进度');
    if (j is! Map) return;
    final at = j['at'];
    if (at is int) _lastAt = DateTime.fromMillisecondsSinceEpoch(at);
    final seen = j['seen'];
    if (seen is Map) {
      for (final e in seen.entries) {
        final n = e.value;
        if (e.key is String && n is int && n >= 0) _seen[e.key as String] = n;
      }
    }
  }

  Future<void> _saveState() async {
    try {
      await writeJsonAtomic(_stateFile, {'at': _lastAt?.millisecondsSinceEpoch, 'seen': _seen});
    } on Exception {
      // 记不下进度：最多是下次多整理一遍
    }
  }

  bool get _gone => core.disposed || core.app.disposed;

  /// 一轮收尾之后调一次。不等它：整理在后台做，做不做、做没做成都不影响对话。
  /// [failed]＝这一轮出错了或被停止了。[turn]＝这一轮的用量本子（整理那一次请求记在它上面）。
  void afterTurn(ChatRunNotifier run, {required bool failed, required TurnUsage turn, required ResolvedModel? resolved}) {
    final memory = core.app.memory;
    if (!memory.autoConsolidate || failed || run.unattended || run.conv.parentId != null || _running || _gone) return;
    // 还挂着确认卡 / 提问卡：这一轮其实还没完，不整理。
    final cards = core.cards.current;
    if (cards.approvals.any((a) => a.conversationId == run.convId) || cards.questions.any((q) => q.conversationId == run.convId)) return;
    _running = true;
    // 这一轮的用量挂在哪条消息上（之后要把整理那一次补记进去）
    final holder = run.messages.isNotEmpty && run.messages.last.containsKey('_usage') ? run.messages.last : null;
    memory.track(
      _consolidate(run, turn, holder, resolved)
          .catchError((Object e, StackTrace st) {
            // 整理出了没想到的错：只记日志
            CrashLog.instance.record(e, st, source: '整理记忆', fatal: false);
          })
          .whenComplete(() => _running = false),
    );
  }

  Future<void> _consolidate(ChatRunNotifier run, TurnUsage turn, Map<String, dynamic>? holder, ResolvedModel? resolved) async {
    final app = core.app;
    final memory = app.memory;
    await _loadState();
    final now = memory.now();
    final last = _lastAt;
    if (last != null && now.difference(last) < kConsolidateMinInterval) return;
    // 对话被压缩过（消息变少了）：进度作废，从头算。
    final total = run.messages.length;
    var from = _seen[run.convId] ?? 0;
    if (from > total) from = 0;
    final fresh = run.messages.sublist(from);
    if (fresh.where(_spoken).length < kConsolidateMinMessages) return;

    await memory.global.load();
    MemoryStore? project;
    try {
      project = memory.project(core.project);
      await project.load();
    } on PathGuardException {
      project = null;
    }
    final request = consolidationRequest(memory.global.entries, project?.entries, consolidationTranscript(fresh));
    if (_gone) return;

    // 不管成没成，都从现在起再隔一段时间才试下一次（接口坏着的时候不会每轮都去撞）。
    _lastAt = now;
    final client = await app.createChatClient(resolved); // 额度到顶在这里面被拦
    final text = StringBuffer();
    TokenUsage? usage;
    var requested = false;
    String? error;
    final startedAt = DateTime.now();
    final clock = Stopwatch()..start();
    try {
      await for (final d in client.streamChat(messages: request)) {
        requested = true;
        if (d.usage != null) usage = d.usage;
        if (d.content != null) text.write(d.content);
      }
    } on ChatApiException catch (e) {
      error = e.message;
    } on Exception catch (e) {
      error = '和模型的连接中断了：${shortError(e)}';
    }
    if (requested) {
      final cost = usage == null || resolved == null ? null : ModelPrice.of(resolved.model)?.cost(usage);
      await _recordUsage(run, turn, holder, RequestUsage(usage: usage, ms: clock.elapsedMilliseconds, startedAt: startedAt, cost: cost, memory: true));
    }
    if (error != null) {
      noteMemory('这次没整理成：$error');
      await _saveState();
      return;
    }
    final items = parseConsolidation(text.toString());
    if (items == null) {
      noteMemory('这次没整理成：模型的回答不是约定的格式');
      await _saveState();
      return;
    }
    final written = <String>[];
    if (!_gone) {
      for (final item in items) {
        final store = item.scope == MemoryScope.global ? memory.global : project;
        if (store == null) continue;
        try {
          final r = await store.write(item.title, item.content, by: 'auto');
          written.add(r.entry.title);
        } on MemoryException catch (e) {
          noteMemory('自动整理有一条没记下：${e.message}');
        }
      }
    }
    _seen[run.convId] = total;
    await _saveState();
    if (written.isNotEmpty && !_gone && core.dir.byId(run.convId) != null) {
      run.add(NoticeItem('整理记忆：记住了 ${written.length} 条（${written.join('、')}）。在“设置 › 能力 › 记忆”里可以查看、撤销或删除。'));
    }
  }

  /// 把整理那一次请求记进刚结束的那一轮：轨迹里多一步“整理记忆”，对话累计也加上，然后存盘。
  Future<void> _recordUsage(ChatRunNotifier run, TurnUsage turn, Map<String, dynamic>? holder, RequestUsage request) async {
    turn.steps.add(RequestStep(request));
    if (_gone || core.dir.byId(run.convId) == null) return; // 工作区已经关了 / 对话已经删掉了：没地方记
    core.convs?.update(
      run.convId,
      (c) => c.copyWith(
        usage: UsageTotals()
          ..add(c.usage)
          ..addRequest(request),
      ),
    );
    // 那条消息还在记录里（没被压缩掉）才改它；不在了就只留对话累计。
    if (holder != null && run.messages.any((m) => identical(m, holder))) holder['_usage'] = turn.toJson();
    final shown = run.items.whereType<UsageItem>().where((u) => identical(u.turn, turn)).lastOrNull;
    if (shown != null) run.replace(shown, UsageItem(turn));
    run.bumpRev();
    if (run.busy) {
      // 下一轮已经开始了：跟着它的中途存盘走
      core.saveMessagesLater(run);
    } else {
      await core.saveRun(run);
    }
  }
}
