// 记忆的四个工具（memory_read / memory_search / memory_write / memory_delete）和拼进系统提示词的那一段。
//
// 权限怎么拦：
// - 读、查是只读工具（ToolKind.read）：任何权限档、计划模式下都能用；
// - 写、删是 ToolKind.write：“仅可查看”和计划模式下由 AgentToolbox 统一挡掉——工具不出现，硬调也拒绝；
// - 子代理：只给读和查，不给写和删（它只管交给它的那一件事，长期记什么由主对话决定）；
// - 没人在场（自动化任务）：不许动全局记忆，只能写 / 删项目记忆；
// - 写入不出确认卡（和写工作区文件同级），但聊天步骤里写明“记住了：…”，设置页可以撤销最近一次、删除任意一条。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/core/crash_log.dart';

const String kMemoryReadTool = 'memory_read';
const String kMemorySearchTool = 'memory_search';
const String kMemoryWriteTool = 'memory_write';
const String kMemoryDeleteTool = 'memory_delete';

/// 两处记忆的正文加起来不超过这么多字时，系统提示词里直接带全文；超过就只带标题和摘要。
const int kMemoryPromptFullChars = 3000;

/// 只带标题和摘要时，这份清单最多这么多字（再多的不列，提示用 memory_search 查）。
const int kMemoryPromptIndexChars = 4000;

/// memory_search 最多回几条、每条片段多长。
const int kMemorySearchMaxHits = 10;
const int kMemorySnippetChars = 120;

/// 拼进系统提示词的记忆一段。[project] 为 null＝这次没有项目记忆（读不了）。
/// [canWrite]：这段对话现在能不能写记忆（决定说哪句话；真正的拦截在工具那边）。
String memoryPromptSection(List<MemoryEntry> global, List<MemoryEntry>? project, {required bool canWrite}) {
  final out = StringBuffer('记忆（跨对话保留的笔记，是普通的 Markdown 文件，用户看得见也改得了）。');
  out.write(
    canWrite
        ? '用户明确要你记住什么，或者你发现了以后的对话还用得上的东西（用户的偏好和习惯、这个项目定下的约定、踩过并弄清了的坑），用 $kMemoryWriteTool 记一条：'
              '和用户这个人有关的记到全局，只和这个项目有关的记到项目。一条只写一件事；已经有说同一件事的，用它的标题改写，不要另起一条。'
              '一次性的任务细节、很快会过期的状态不要记。绝对不要把密钥、令牌、密码记进记忆。'
        : '你现在只能读记忆，不能写。',
  );
  final all = [...global, ...?project];
  if (all.isEmpty) {
    out.write('\n现在还没有任何记忆。');
    return out.toString();
  }
  final full = all.fold<int>(0, (n, e) => n + e.body.length) <= kMemoryPromptFullChars;
  if (!full) out.write('\n下面只有标题和摘要；用得上哪条，先用 $kMemoryReadTool 读全文再照着做。');
  var budget = kMemoryPromptIndexChars;
  var hidden = 0;
  void section(String label, List<MemoryEntry> list) {
    if (list.isEmpty) return;
    out.write('\n【$label】');
    for (final e in list) {
      if (full) {
        out.write('\n### ${e.title}\n${e.body}');
        continue;
      }
      final line = '\n- ${e.title}${e.summary.isEmpty ? '' : '：${e.summary}'}';
      if (line.length > budget) {
        hidden++;
        continue;
      }
      budget -= line.length;
      out.write(line);
    }
  }

  section('全局记忆（所有项目都适用）', global);
  section('这个项目的记忆', project ?? const []);
  if (hidden > 0) out.write('\n（还有 $hidden 条没列出来，用 $kMemorySearchTool 按关键词查。）');
  return out.toString();
}

/// 在两处记忆里按关键词找：空白隔开的几个词都要出现（不分大小写），在标题或正文里都算。
List<({MemoryEntry entry, String snippet})> searchMemory(Iterable<MemoryEntry> entries, String query) {
  final terms = [
    for (final t in query.toLowerCase().split(RegExp(r'\s+')))
      if (t.isNotEmpty) t,
  ];
  if (terms.isEmpty) return const [];
  final hits = <({MemoryEntry entry, String snippet})>[];
  for (final e in entries) {
    final hay = '${e.title}\n${e.body}'.toLowerCase();
    if (!terms.every(hay.contains)) continue;
    final at = e.body.toLowerCase().indexOf(terms.first);
    final from = at < 0 ? 0 : (at - 30).clamp(0, e.body.length);
    final to = (from + kMemorySnippetChars).clamp(0, e.body.length);
    final piece = e.body.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
    hits.add((entry: e, snippet: '${from > 0 ? '…' : ''}$piece${to < e.body.length ? '…' : ''}'));
    if (hits.length >= kMemorySearchMaxHits) break;
  }
  return hits;
}

String _listing(String label, List<MemoryEntry> list) => list.isEmpty ? '【$label】（空）' : '【$label】\n${list.map((e) => '- ${e.title}${e.summary.isEmpty ? '' : '：${e.summary}'}').join('\n')}';

/// 这段对话能用的记忆工具。
///
/// - [project]：这个工作区的项目记忆；null＝读不了（那就只有全局的）。
/// - [canWrite]：给不给写和删（子代理不给）。
/// - [allowGlobalWrite]：能不能动全局记忆（没人在场时不能）。
List<ExtraTool> memoryTools({required MemoryStore global, required MemoryStore? project, required bool canWrite, required bool allowGlobalWrite}) {
  final scopes = [if (allowGlobalWrite) MemoryScope.global.id, if (project != null) MemoryScope.project.id];
  MemoryStore? storeOf(Object? scope) => switch (MemoryScope.byId(scope)) {
    MemoryScope.global => global,
    MemoryScope.project => project,
    null => null,
  };

  /// 写 / 删之前：scope 认不认得、这段对话能不能动它。能动返回 store，不能动返回给模型的错误。
  (MemoryStore?, String?) writable(Map<String, dynamic> args) {
    final scope = MemoryScope.byId(args['scope']);
    if (scope == null) return (null, '缺少参数 scope（global 或 project）');
    if (scope == MemoryScope.global && !allowGlobalWrite) return (null, '这是无人值守的自动化任务，不能改全局记忆（没有人在场看着）。只和这个项目有关的可以记到 project');
    final store = storeOf(scope.id);
    if (store == null) return (null, '这个工作区的项目记忆现在读写不了');
    return (store, null);
  }

  Future<ToolOutcome> guarded(Future<ToolOutcome> Function() body) async {
    try {
      return await body();
    } on MemoryException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    }
  }

  return [
    ExtraTool(
      spec: toolSpec(kMemoryReadTool, '读记忆。给了 title 就读那一条的全文；不给就列出全部记忆的标题和摘要。', {
        'scope': {
          'type': 'string',
          'enum': [MemoryScope.global.id, MemoryScope.project.id],
          'description': '读哪一处：global＝全局记忆，project＝这个项目的记忆；省略＝两处都看',
        },
        'title': {'type': 'string', 'description': '要读的那一条的标题；省略＝只列清单'},
      }),
      kind: ToolKind.read,
      run: (args) => guarded(() async {
        final scope = AgentToolbox.argOptString(args, 'scope');
        final title = AgentToolbox.argOptString(args, 'title')?.trim() ?? '';
        if (scope != null && scope.isNotEmpty && MemoryScope.byId(scope) == null) return ToolOutcome('错误：scope 只能是 global 或 project', ok: false);
        final stores = [
          if (scope == null || scope.isEmpty || scope == MemoryScope.global.id) global,
          if (project != null && (scope == null || scope.isEmpty || scope == MemoryScope.project.id)) project,
        ];
        for (final s in stores) {
          await s.load();
        }
        if (title.isEmpty) return ToolOutcome(stores.isEmpty ? '这个工作区的项目记忆现在读不了。' : stores.map((s) => _listing(s.scope.label, s.entries)).join('\n'));
        for (final s in stores) {
          final e = s.find(title);
          if (e != null) return ToolOutcome('【${s.scope.label}】${e.title}\n\n${e.body}');
        }
        return ToolOutcome('错误：没有叫“$title”的记忆。现有的：\n${stores.map((s) => _listing(s.scope.label, s.entries)).join('\n')}', ok: false);
      }),
    ),
    ExtraTool(
      spec: toolSpec(
        kMemorySearchTool,
        '按关键词在记忆（全局 + 这个项目）里查，返回命中的标题和片段。几个词用空格隔开，都出现才算命中。',
        {
          'query': {'type': 'string', 'description': '关键词'},
        },
        ['query'],
      ),
      kind: ToolKind.read,
      run: (args) => guarded(() async {
        final query = AgentToolbox.argString(args, 'query').trim();
        await global.load();
        await project?.load();
        final hits = searchMemory([...global.entries, ...?project?.entries], query);
        if (hits.isEmpty) return ToolOutcome('记忆里没有提到“$query”的内容。');
        return ToolOutcome('找到 ${hits.length} 条：\n${hits.map((h) => '- 【${h.entry.scope.label}】${h.entry.title}：${h.snippet}').join('\n')}\n要看全文用 $kMemoryReadTool。');
      }),
    ),
    if (canWrite && scopes.isNotEmpty) ...[
      ExtraTool(
        spec: toolSpec(
          kMemoryWriteTool,
          '记一条记忆，或者改写已有的一条（同标题就是改写，正文整条替换）。一条只写一件事，正文不超过 $kMemoryMaxBodyChars 字。不要记密钥、令牌、密码。',
          {
            'scope': {'type': 'string', 'enum': scopes, 'description': 'global＝全局记忆（用户这个人的偏好、习惯，所有项目都适用）；project＝这个项目的记忆（背景、约定、踩过的坑）'},
            'title': {'type': 'string', 'description': '标题，不超过 $kMemoryMaxTitleChars 字，一眼能看出记的是什么'},
            'content': {'type': 'string', 'description': '正文（Markdown）。改写时给完整的新正文，不是只给改动的部分'},
          },
          ['scope', 'title', 'content'],
        ),
        kind: ToolKind.write,
        run: (args) => guarded(() async {
          final (store, error) = writable(args);
          if (store == null) return ToolOutcome('错误：$error', ok: false);
          final r = await store.write(AgentToolbox.argString(args, 'title'), AgentToolbox.argString(args, 'content'));
          return ToolOutcome('记住了：“${r.entry.title}”（${store.scope.label}，${r.created ? '新增' : '改写了原来那条'}）。');
        }),
      ),
      ExtraTool(
        spec: toolSpec(
          kMemoryDeleteTool,
          '删掉一条记忆（已经不对、过时了的）。',
          {
            'scope': {'type': 'string', 'enum': scopes, 'description': 'global 或 project'},
            'title': {'type': 'string', 'description': '要删的那一条的标题'},
          },
          ['scope', 'title'],
        ),
        kind: ToolKind.write,
        run: (args) => guarded(() async {
          final (store, error) = writable(args);
          if (store == null) return ToolOutcome('错误：$error', ok: false);
          final gone = await store.delete(AgentToolbox.argString(args, 'title'));
          return ToolOutcome('已从${store.scope.label}里删掉“${gone.title}”。');
        }),
      ),
    ],
  ];
}

/// 记一笔和记忆有关、不用打扰用户的事。
void noteMemory(String message) => CrashLog.instance.note(message, source: '记忆');
