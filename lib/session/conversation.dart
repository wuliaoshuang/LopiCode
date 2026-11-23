// 工作区里的一段对话（目录里的一条）。不可变：要改就 [Conversation.copyWith] 出一个新的，
// 交给 `ConversationsNotifier` 换进列表里。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';

/// 工作区里的一段对话。子代理的对话也是一段对话，只是有上级（[parentId]）。
class Conversation {
  Conversation(
    this.id,
    this.title,
    this.updatedAt, {
    this.parentId,
    this.depth = 0,
    this.agentName = '',
    this.selection,
    this.permission,
    this.planMode = false,
    this.presetId,
    this.auto = false,
    UsageTotals? usage,
    this.lastInput,
  }) : usage = usage ?? UsageTotals();
  final String id;
  final String title;
  final DateTime updatedAt;

  /// 上级对话；主对话为 null。
  final String? parentId;

  /// 委派层数：主对话 0，它派出的子代理 1……
  final int depth;

  /// 子代理的名字。
  final String agentName;

  /// 这段对话选的模型；null 表示用新对话默认。
  final ModelSelection? selection;

  /// 权限档位；null 表示用新对话默认。
  final String? permission;
  final bool planMode;
  final String? presetId;

  /// 是不是自动化任务跑出来的。
  final bool auto;

  /// 这段对话累计的用量（含它派出去的子代理）。压缩对话不会清掉它。
  /// 别在原对象上加：要累计就用 [withUsage] 换一份新的。
  final UsageTotals usage;

  /// 最近一次请求的输入 token 数（接口给的），用来算上下文占用；还没有是 null。
  final int? lastInput;

  Conversation copyWith({String? title, DateTime? updatedAt, ModelSelection? selection, String? permission, bool? planMode, String? presetId, UsageTotals? usage, int? lastInput}) => Conversation(
    id,
    title ?? this.title,
    updatedAt ?? this.updatedAt,
    parentId: parentId,
    depth: depth,
    agentName: agentName,
    selection: selection ?? this.selection,
    permission: permission ?? this.permission,
    planMode: planMode ?? this.planMode,
    presetId: presetId ?? this.presetId,
    auto: auto,
    usage: usage ?? this.usage,
    lastInput: lastInput ?? this.lastInput,
  );

  /// 把一轮的用量累计进来（轮数加一），得到一份新的。
  Conversation withTurn(UsageTotals turn) => copyWith(
    usage: UsageTotals()
      ..add(usage)
      ..add(turn)
      ..turns += 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'parent': parentId,
    'depth': depth,
    'agent': agentName,
    'model': selection?.toJson(),
    'permission': permission,
    'plan': planMode,
    'preset': presetId,
    'auto': auto,
    if (usage.requests > 0) 'usage': usage.toJson(),
    'lastInput': ?lastInput,
  };

  /// 从目录文件里的一条读回来；形状不对（没有合法 id）返回 null。
  static Conversation? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = '${m['id'] ?? ''}';
    if (!RegExp(r'^[a-z0-9]{1,24}$').hasMatch(id)) return null;
    return Conversation(
      id,
      '${m['title'] ?? ''}',
      DateTime.tryParse('${m['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      parentId: m['parent'] is String ? m['parent'] as String : null,
      depth: m['depth'] is int ? m['depth'] as int : 0,
      agentName: '${m['agent'] ?? ''}',
      selection: ModelSelection.fromJson(m['model']),
      permission: m['permission'] is String ? m['permission'] as String : null,
      planMode: m['plan'] == true,
      presetId: m['preset'] is String ? m['preset'] as String : null,
      auto: m['auto'] == true,
      usage: UsageTotals.fromJson(m['usage']),
      lastInput: m['lastInput'] is int ? m['lastInput'] as int : null,
    );
  }
}
