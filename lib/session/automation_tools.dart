// Agent 侧的自动化任务工具：查看已有任务、新建 / 修改任务。从 project_session.dart 拆出来的，逻辑没变。
//
// 安全规矩（别改松）：新建 / 修改每次都弹单独的确认卡，不走权限档位，也不吃“本对话都允许”——完全权限也代替不了。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/core/project_store.dart';

/// 手机当前时区相对 UTC 的分钟数。
int get deviceTzOffset => DateTime.now().timeZoneOffset.inMinutes;

String clipText(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

/// [approve]：弹确认卡并等用户点（无人值守的对话里会被自动拒绝）。
List<ExtraTool> automationTools({required AutomationStore store, required Project project, required Future<bool> Function(ApprovalRequest request) approve}) => [
  ExtraTool(
    spec: toolSpec('list_scheduled_tasks', '列出已有的自动化任务（定时 / 周期）。', {}),
    kind: ToolKind.read,
    run: (_) async {
      final items = store.items;
      if (items.isEmpty) return ToolOutcome('还没有自动化任务。');
      return ToolOutcome([for (final a in items) '- ${a.id}｜${a.title}｜${a.rule.describe()}｜${a.enabled ? '开着' : '已停用'}｜指令：${clipText(a.instruction, 120)}'].join('\n'));
    },
  ),
  ExtraTool(
    spec: toolSpec(
      'schedule_task',
      '新建（不给 id）或修改（给 id）一个自动化任务：到时间后在这个工作区里自动开一段对话执行指令。'
          '每次都会弹出单独的确认卡让用户核对完整指令和触发时间，用户点了确认才生效。'
          '注意：只有 App 正在运行时才会触发。',
      {
        'id': {'type': 'string', 'description': '要修改的任务 id；新建时省略'},
        'title': {'type': 'string', 'description': '任务名'},
        'instruction': {'type': 'string', 'description': '到时间后要执行的完整指令（那时没有这段对话的上下文，要写全）'},
        'kind': {
          'type': 'string',
          'enum': ['once', 'daily', 'weekly', 'interval'],
          'description': '只运行一次 / 每天 / 每周 / 每隔一段时间',
        },
        'time': {'type': 'string', 'description': '几点几分，24 小时制，如 08:30（interval 不需要）'},
        'date': {'type': 'string', 'description': 'once 用：日期，如 2026-12-31'},
        'weekdays': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'weekly 用：1＝周一 … 7＝周日',
        },
        'every_minutes': {'type': 'integer', 'description': 'interval 用：间隔分钟数，最短 ${TimeRule.minInterval}'},
        'tz_offset_minutes': {'type': 'integer', 'description': '时区相对 UTC 的分钟数，省略用手机当前时区（北京时间是 480）'},
      },
      ['title', 'instruction', 'kind'],
    ),
    kind: ToolKind.other,
    run: (args) async {
      final rule = TimeRule.fromJson(args, defaultTz: deviceTzOffset);
      if (rule == null) return ToolOutcome('错误：kind 要是 once / daily / weekly / interval 之一', ok: false);
      final existing = args['id'] is String ? store.byId((args['id'] as String).trim()) : null;
      if (args['id'] is String && (args['id'] as String).trim().isNotEmpty && existing == null) {
        return ToolOutcome('错误：没有 id 为 ${args['id']} 的自动化任务', ok: false);
      }
      final title = '${args['title'] ?? ''}', instruction = '${args['instruction'] ?? ''}';
      try {
        AutomationStore.validate(title: title, instruction: instruction, rule: rule);
      } on AutomationException catch (e) {
        return ToolOutcome('错误：${e.message}', ok: false);
      }
      final next = rule.next(DateTime.now());
      if (next == null) return ToolOutcome('错误：这个时间已经过去了，不会再触发', ok: false);
      // 单独的确认卡：不走权限档位，也不吃“本对话都允许”——完全权限也代替不了。
      final ok = await approve(
        ApprovalRequest(
          tool: 'schedule_task',
          title: existing == null ? '新建自动化任务' : '修改自动化任务',
          detail: automationCardText(title: title, instruction: instruction, rule: rule, next: next, workspace: project.name, permission: PermissionLevel.workspace),
          allowAlways: false,
        ),
      );
      if (!ok) return ToolOutcome('用户拒绝了这个自动化任务，没有保存。', ok: false, denied: true);
      final saved = await store.upsert(id: existing?.id, title: title, instruction: instruction, workspaceId: project.id, rule: rule);
      return ToolOutcome('已${existing == null ? '新建' : '修改'}自动化任务 ${saved.id}「${saved.title}」：${rule.describe()}。下一次触发：${formatLocalTime(next, rule.tzOffsetMinutes)}。只有 App 正在运行时才会触发。');
    },
  ),
];

/// 确认卡上的文字：完整指令 + 实际触发时间（界面新建 / 修改时也用它）。
String automationCardText({required String title, required String instruction, required TimeRule rule, required DateTime next, required String workspace, required PermissionLevel permission}) =>
    '任务名：$title\n工作区：$workspace\n时间规则：${rule.describe()}\n下一次触发：${formatLocalTime(next, rule.tzOffsetMinutes)}\n'
    '运行时的权限：${permission.label}（没人在场，需要你确认的操作会被自动拒绝）\n'
    '只有 App 正在运行时才会触发；错过的不会补跑。\n\n完整指令：\n$instruction';

String formatLocalTime(DateTime utc, int tzOffsetMinutes) {
  final t = utc.toUtc().add(Duration(minutes: tzOffsetMinutes));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}（${TimeRule.tzLabel(tzOffsetMinutes)}）';
}
