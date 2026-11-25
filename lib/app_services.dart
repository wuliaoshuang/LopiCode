import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/keep_alive.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/skill_mirror.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/automation_scheduler.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/secure_secret_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/quota_state.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod/riverpod.dart';

/// 全应用共用的服务：设置、密钥、项目仓库。测试里可以整体替换。
class AppServices {
  AppServices({
    required this.settings,
    required this.secrets,
    required this.projects,
    this.chatClientFactory,
    this.quotaHttp,
    LinuxRuntime? runtime,
    KeepAliveHost keepAliveHost = const NoKeepAliveHost(),
  }) : runtime = runtime ?? LinuxRuntime(settings: settings, baseDir: p.join(settings.file.parent.path, 'runtime')),
       models = ModelConfigStore(settings, secrets),
       presets = PresetStore(settings),
       skills = SkillStore(settings, p.join(settings.file.parent.path, 'skills')),
       memory = AppMemory(settings, p.join(settings.file.parent.path, 'memory')),
       automations = AutomationStore(File(p.join(settings.file.parent.path, 'automations.json'))),
       mcp = McpStore(File(p.join(settings.file.parent.path, 'mcp_servers.json')), secrets) {
    projects.linuxRootfs ??= this.runtime.rootfsDir;
    // 技能镜像：进 Ubuntu 前把开着的技能复制一份挂到 /skills（挂副本，环境里改不到原件）。
    this.runtime.skillsMirror ??= SkillMirror(skills, p.join(this.runtime.baseDir, 'skills-mirror')).sync;
    keepAlive = AgentKeepAlive(keepEnabled: () => settings.getBool(SettingKeys.agentKeepAlive, true), notifyEnabled: () => settings.getBool(SettingKeys.agentNotifyDone, true))..attach(keepAliveHost);
    settings.addKeyListener(_onSettingKey);
    scheduler = AutomationScheduler(this);
    container = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(this)]);
    // 现在就建好：销毁以后还在收尾的对话也能拿到它（那时只读快照、不再写）
    quota = container.read(quotaProvider.notifier);
  }

  /// 全应用的状态容器（Riverpod）。界面最外层用它，逻辑层要读状态也从它读。
  late final ProviderContainer container;

  /// 已经销毁（应用退出 / 测试收尾）。销毁后还没跑完的后台活儿不许再往状态里写。
  bool get disposed => _disposed;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scheduler.stop();
    settings.removeKeyListener(_onSettingKey);
    keepAlive.dispose();
    container.dispose();
  }

  /// Agent 干活时的后台保活和通知（真机上是安卓前台服务；测试、桌面是空实现）。
  late final AgentKeepAlive keepAlive;

  void _onSettingKey(String key) {
    if (key == SettingKeys.agentKeepAlive || key == SettingKeys.agentNotifyDone) keepAlive.refresh();
  }

  /// 测试钩子：查余额用的网络。
  final http.Client? quotaHttp;

  /// DeepSeek 官方渠道的余额和额度上限（状态在 [quotaProvider]，这里给逻辑层一个取用入口）。
  late final QuotaNotifier quota;

  /// 自动化任务的调度（App 开着时才会触发）。
  late final AutomationScheduler scheduler;

  /// 渠道与模型。
  final ModelConfigStore models;

  /// 个人偏好与 Agent 预设。
  final PresetStore presets;

  /// 技能（全局目录在应用文档目录的 skills/ 下）。
  final SkillStore skills;

  /// 自动化任务。
  final AutomationStore automations;

  /// 文件记忆（全局的在应用文档目录的 memory/ 下，项目的在各工作区的 .lopicode/memory/ 下）。
  final AppMemory memory;

  /// MCP 服务器的配置（状态在 mcpProvider）。
  final McpStore mcp;

  /// 工作区列表里点了“在这里新建对话”：打开那个工作区后开一段新对话。
  String? newConversationFor;

  /// 这次运行里“没配好模型”的引导是不是已经自动弹过（弹过就只在点发送时再提示）。
  bool modelSetupPrompted = false;

  Future<void>? _ready;

  /// 读渠道配置（含老设置迁移）和自动化任务。可以反复调用，只做一次。
  Future<void> ready() => _ready ??= () async {
    await models.load();
    await automations.load();
    await mcp.load();
  }();

  final SettingsStore settings;
  final SecretStore secrets;
  final ProjectStore projects;

  /// 本机 Linux 运行环境（PRoot + Ubuntu）。
  final LinuxRuntime runtime;

  /// 测试钩子：替换真实的模型客户端。
  final ChatClient Function()? chatClientFactory;

  static Future<AppServices> boot() async {
    final docs = await getApplicationDocumentsDirectory();
    final settings = SettingsStore(File(p.join(docs.path, 'settings.json')));
    await settings.load();
    final secrets = SecureSecretStore();
    await secrets.probe();
    // 运行环境放在应用私有的 files 目录下（不进文档目录，免得被当成用户文件）。
    final support = await getApplicationSupportDirectory();
    final runtime = LinuxRuntime(settings: settings, baseDir: p.join(support.path, 'runtime'), host: ChannelRuntimeHost());
    await runtime.init();
    final app = AppServices(settings: settings, secrets: secrets, projects: ProjectStore(p.join(docs.path, 'projects')), runtime: runtime, keepAliveHost: ChannelKeepAliveHost());
    await app.ready();
    app.scheduler.start();
    return app;
  }

  bool get agentConfigured => chatClientFactory != null || models.configured;

  /// 按选中的“渠道 + 模型 + 思考档位”造客户端。
  Future<ChatClient> createChatClient([ResolvedModel? model]) async {
    final factory = chatClientFactory;
    await ready();
    final r = model ?? models.defaultForNewChat();
    if (factory != null) return r == null ? factory() : quota.guard(r.channel, factory());
    if (r == null) return _UnconfiguredClient();
    // 额度上限在这里统一把关：主对话、子代理、自动化任务、压缩对话都从这里拿客户端。
    return quota.guard(r.channel, buildChatClient(r, await models.apiKey(r.channel.id)));
  }
}

class _UnconfiguredClient implements ChatClient {
  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    throw ChatApiException('还没配置模型：请到“设置 → 模型与渠道”添加渠道和模型');
  }
}
