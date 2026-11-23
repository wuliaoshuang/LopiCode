import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/automation_scheduler.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/secure_secret_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全应用共用的服务：设置、密钥、项目仓库。测试里可以整体替换。
class AppServices extends ChangeNotifier {
  AppServices({required this.settings, required this.secrets, required this.projects, this.chatClientFactory, this.quotaHttp, LinuxRuntime? runtime})
    : runtime = runtime ?? LinuxRuntime(settings: settings, baseDir: p.join(settings.file.parent.path, 'runtime')),
      models = ModelConfigStore(settings, secrets),
      presets = PresetStore(settings),
      skills = SkillStore(settings, p.join(settings.file.parent.path, 'skills')),
      automations = AutomationStore(File(p.join(settings.file.parent.path, 'automations.json'))) {
    projects.linuxRootfs ??= this.runtime.rootfsDir;
    scheduler = AutomationScheduler(this);
    quota = QuotaStore(settings, models, httpClient: quotaHttp);
  }

  /// 测试钩子：查余额用的网络。
  final http.Client? quotaHttp;

  /// DeepSeek 官方渠道的余额和额度上限。
  late final QuotaStore quota;

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

  /// 工作区列表里点了“在这里新建对话”：打开那个工作区后开一段新对话。
  String? newConversationFor;

  /// 这次运行里“没配好模型”的引导是不是已经自动弹过（弹过就只在点发送时再提示）。
  bool modelSetupPrompted = false;

  Future<void>? _ready;

  /// 读渠道配置（含老设置迁移）和自动化任务。可以反复调用，只做一次。
  Future<void> ready() => _ready ??= () async {
    await models.load();
    await automations.load();
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
    final app = AppServices(settings: settings, secrets: secrets, projects: ProjectStore(p.join(docs.path, 'projects')), runtime: runtime);
    await app.ready();
    app.scheduler.start();
    return app;
  }

  ThemeMode get themeMode => switch (settings.getString(SettingKeys.themeMode, 'system')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    await settings.set(SettingKeys.themeMode, mode.name);
    notifyListeners();
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

  /// 设置改动后通知界面刷新。
  void touch() => notifyListeners();
}

class AppScope extends InheritedNotifier<AppServices> {
  const AppScope({super.key, required AppServices services, required super.child}) : super(notifier: services);

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class _UnconfiguredClient implements ChatClient {
  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    throw ChatApiException('还没配置模型：请到“设置 → 模型与渠道”添加渠道和模型');
  }
}
