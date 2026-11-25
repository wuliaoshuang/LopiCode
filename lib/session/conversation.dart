// 工作区里的一段对话（目录里的一条）。不可变：要改就 [Conversation.copyWith] 出一个新的，
// 交给 `ConversationsNotifier` 换进列表里。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';

/// 这段对话是从哪分出来的（“从这里分支”、重试 / 编辑时另存的旧版本）。只是一个出处的记号：
/// 两段对话各有各的记录文件，互不影响；原对话后来被删了，这里的名字还在。
class BranchOrigin {
  const BranchOrigin({required this.convId, required this.title, this.messageId, this.old = false});

  /// 原对话的 id。
  final String convId;

  /// 从原对话的哪条消息分出来的（跳回去时滚到它）；原对话在那之前没有消息时是 null。
  final String? messageId;

  /// 分出来那一刻原对话的名字。
  final String title;

  /// true＝重试 / 编辑时另存下来的旧版本；false＝她自己点的“从这里分支”。
  final bool old;

  /// 列表里跟在名字后面的小标签。
  String get tag => old ? '旧版本' : '分支';

  Map<String, dynamic> toJson() => {'conv': convId, 'msg': ?messageId, 'title': title, if (old) 'old': true};

  /// 形状不对（没有合法的原对话 id）返回 null：当成普通对话，不影响打开。
  static BranchOrigin? fromJson(Object? j) {
    if (j is! Map) return null;
    final conv = j['conv'], msg = j['msg'], title = j['title'];
    if (conv is! String || !RegExp(r'^[a-z0-9]{1,24}$').hasMatch(conv)) return null;
    return BranchOrigin(convId: conv, messageId: msg is String && msg.isNotEmpty ? msg : null, title: title is String ? title : '', old: j['old'] == true);
  }
}

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
    this.origin,
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

  /// 从别的对话分出来的（分支 / 旧版本）才有；旧的目录文件里没有这一项，就是 null。
  final BranchOrigin? origin;

  /// 换个上级（重试 / 编辑时，被移走的那几轮派出的子代理跟着旧版本走）。别的都不变。
  Conversation movedUnder(String parent) => Conversation(
    id,
    title,
    updatedAt,
    parentId: parent,
    depth: depth,
    agentName: agentName,
    selection: selection,
    permission: permission,
    planMode: planMode,
    presetId: presetId,
    auto: auto,
    usage: usage,
    lastInput: lastInput,
    origin: origin,
  );

  /// [clearLastInput]：消息记录被删改过，“上次请求的输入 token 数”不再作数（上下文占用改回按字数估）。
  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    ModelSelection? selection,
    String? permission,
    bool? planMode,
    String? presetId,
    UsageTotals? usage,
    int? lastInput,
    bool clearLastInput = false,
  }) => Conversation(
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
    lastInput: clearLastInput ? null : lastInput ?? this.lastInput,
    origin: origin,
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
    'from': ?origin?.toJson(),
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
      origin: BranchOrigin.fromJson(m['from']),
    );
  }
}
