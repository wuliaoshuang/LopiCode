// 状态层（lib/state/）的小订阅入口：设置键、外观、聊天开关、渠道 / 预设 / 技能 / 自动化的“变了”信号。
// 额度的状态见 test/quota_usage_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/automations_state.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/presets_state.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;

  /// 订阅一个 provider，返回“被通知了几次”的计数器。
  int Function() count<T>(ProviderListenable<T> provider) {
    var n = 0;
    box.listen<T>(provider, (_, _) => n++);
    // 派生的 provider 是“下一拍”才重算的：先读一次让它算完，再看被通知了几次。
    return () {
      box.read(provider);
      return n;
    };
  }

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
  });
  tearDown(() => env.dispose());

  test('没接线就读应用服务：直接报错，不给假对象', () {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    expect(() => bare.read(appServicesProvider), throwsA(anything));
  });

  test('设置键的订阅：只有这个键变了才通知；值没变不通知；别的键不通知', () async {
    final a = count(settingRevProvider('demo.a'));
    final b = count(settingRevProvider('demo.b'));
    final any = count(settingsAnyRevProvider);
    await env.services.settings.set('demo.a', 1);
    expect((a(), b(), any()), (1, 0, 1));
    await env.services.settings.set('demo.b', 'x');
    expect((a(), b(), any()), (1, 1, 2));
    await env.services.settings.set('demo.a', null);
    expect((a(), b(), any()), (2, 1, 3));
  });

  test('订阅取消后设置文件上不留监听', () async {
    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    final before = env.services.settings.keyListenerCount;
    bare.listen(settingRevProvider('demo.a'), (_, _) {});
    expect(env.services.settings.keyListenerCount, before + 1);
    bare.dispose();
    expect(env.services.settings.keyListenerCount, before);
    await env.services.settings.set('demo.a', 2); // 销毁后再写：不报错
  });

  test('外观模式：默认跟随系统；改了写进设置并通知；别处直接改设置也跟着变', () async {
    final n = count(themeModeProvider);
    expect(box.read(themeModeProvider), AppThemeMode.system);
    await box.read(themeModeProvider.notifier).set(AppThemeMode.dark);
    expect(box.read(themeModeProvider), AppThemeMode.dark);
    expect(env.services.settings.getString(SettingKeys.themeMode, 'system'), 'dark');
    expect(n(), 1);
    await env.services.settings.set(SettingKeys.themeMode, 'light');
    expect(box.read(themeModeProvider), AppThemeMode.light);
    await env.services.settings.set(SettingKeys.themeMode, '看不懂的值');
    expect(box.read(themeModeProvider), AppThemeMode.system);
    final before = n();
    await env.services.settings.set(SettingKeys.chatUsage, false);
    expect(n(), before, reason: '别的设置变了，外观不通知（应用外壳不重建）');
  });

  test('聊天开关：开场建议默认关、显示用量默认开；各改各的', () async {
    final n = count(chatPrefsProvider);
    expect(box.read(chatPrefsProvider), const ChatPrefs(suggestions: false, usage: true));
    await box.read(chatPrefsProvider.notifier).setSuggestions(true);
    expect(box.read(chatPrefsProvider), const ChatPrefs(suggestions: true, usage: true));
    await box.read(chatPrefsProvider.notifier).setUsage(false);
    expect(box.read(chatPrefsProvider), const ChatPrefs(suggestions: true, usage: false));
    expect(n(), 2);
    expect(env.services.settings.getBool(SettingKeys.chatSuggestions), isTrue);
    expect(env.services.settings.getBool(SettingKeys.chatUsage, true), isFalse);
  });

  test('渠道与模型：加渠道、换 Key、删渠道都通知；预设那边不受影响', () async {
    final models = count(modelsProvider);
    int keys() => box.read(modelsProvider).keyRev;
    final presets = count(presetsProvider);
    final ch = await env.services.models.upsert(name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: 'sk-1');
    expect(models(), greaterThan(0));
    expect(keys(), 1);
    var before = models();
    await env.services.models.upsert(id: ch.id, name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: 'sk-2');
    expect(keys(), 2);
    expect(models(), greaterThan(before), reason: '只换了 Key（不在设置文件里）也要通知');
    before = models();
    await env.services.models.remove(ch.id);
    expect(models(), greaterThan(before));
    expect(presets(), 0);
  });

  test('预设与个人偏好：改了通知；渠道那边不受影响', () async {
    final presets = count(presetsProvider);
    final models = count(modelsProvider);
    await env.services.presets.upsert(name: '审查', prompt: '只看不改');
    expect(presets(), 1);
    await env.services.settings.set(PresetStore.kPreferences, '说中文');
    expect(presets(), 2);
    expect(models(), 0);
  });

  test('Agent 相关设置（默认权限、子代理、团队）：改了通知', () async {
    final n = count(agentSettingsRevProvider);
    await env.services.settings.set(SettingKeys.teamEnabled, true);
    await env.services.settings.set(SettingKeys.subagentMaxDepth, 3);
    await env.services.settings.set(SettingKeys.defaultPermission, 'readonly');
    expect(n(), 3);
    await env.services.settings.set(SettingKeys.chatUsage, false);
    expect(n(), 3);
  });

  test('技能：新建、停用、删除都通知', () async {
    final n = count(skillsRevProvider);
    final skill = await env.services.skills.create(name: 'demo', description: '演示', body: '照做');
    expect(n(), 1);
    await env.services.skills.setEnabled(skill, false);
    expect(n(), 2);
    await env.services.skills.delete(skill);
    expect(n(), greaterThanOrEqualTo(3));
  });

  test('自动化：任务变了通知；调度器说“谁在跑变了”也通知', () async {
    final n = count(automationsProvider);
    final a = await env.services.automations.upsert(
      title: '晨检',
      instruction: 'x',
      workspaceId: 'w',
      rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
    );
    expect(n(), 1);
    box.read(automationsProvider.notifier).setRunning({a.id});
    expect(n(), 2);
  });

  test('联网搜索：保存 / 清除后说一声才通知', () {
    final n = count(webSearchRevProvider);
    box.read(webSearchRevProvider.notifier).bump();
    expect(n(), 1);
  });

  test('容器销毁后再来通知：不报错、不写状态', () async {
    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    bare.listen(automationsProvider, (_, _) {});
    final rev = bare.read(automationsProvider.notifier);
    final web = bare.read(webSearchRevProvider.notifier);
    final listeners = env.services.automations.changeListeners.length;
    bare.dispose();
    expect(env.services.automations.changeListeners.length, listeners - 1);
    rev.setRunning({'x'});
    web.bump();
    await env.services.automations.upsert(
      title: '晨检',
      instruction: 'x',
      workspaceId: 'w',
      rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
    );
  });

  test('运行环境：它一通知，订阅的人就收到；容器销毁后不再监听', () {
    final n = count(runtimeRevProvider);
    final d = count(runtimeDiagnosticsRevProvider);
    env.services.runtime.lastLaunchError = '上次没起来';
    env.services.runtime.recordLaunchSuccess(); // 清掉失败记录，会通知
    expect(n(), greaterThan(0));
    expect(d(), 0, reason: '诊断没动');

    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    bare.listen(runtimeRevProvider, (_, _) {});
    bare.dispose();
    env.services.runtime.lastLaunchError = '又没起来';
    env.services.runtime.recordLaunchSuccess(); // 销毁后再通知：不报错
  });

  test('应用服务销毁后：调度器不再往状态里写（跑到一半的自动化任务收尾时不报错）', () async {
    final other = await TestEnv.create();
    other.dispose();
    expect(other.services.disposed, isTrue);
    await other.services.scheduler.tick(DateTime.utc(2026, 11, 23, 8)); // 不抛异常就是过
    other.services.dispose(); // 重复销毁也没事
  });
}
