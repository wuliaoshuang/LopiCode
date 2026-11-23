// 自动化任务的状态（lib/state/automations_state.dart）：不可变快照 + Notifier。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/automations_state.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  AutomationsState state() => box.read(automationsProvider);
  AutomationsNotifier ctl() => box.read(automationsProvider.notifier);
  TimeRule daily(int hour) => TimeRule(kind: RuleKind.daily, hour: hour, tzOffsetMinutes: 0);
  final t0 = DateTime.utc(2026, 11, 23);

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
  });
  tearDown(() => env.dispose());

  test('新建、修改、删除：快照每次换新的；旧快照和手里那份任务不变', () async {
    final empty = state();
    expect(empty.items, isEmpty);
    final a = await ctl().upsert(title: ' 晨检 ', instruction: ' 检查依赖 ', workspaceId: 'w1', rule: daily(8));
    expect(empty.items, isEmpty);
    expect((a.title, a.instruction, a.enabled), ('晨检', '检查依赖', true));
    final one = state();
    expect(one.byId(a.id)!.title, '晨检');

    final b = await ctl().upsert(id: a.id, title: '晚检', instruction: '检查依赖', workspaceId: 'w1', rule: daily(20), permission: 'readonly');
    expect(b.id, a.id);
    expect((a.title, a.rule.hour, a.permission), ('晨检', 8, 'workspace'), reason: '原来那份没被改');
    expect(one.byId(a.id)!.title, '晨检');
    expect((state().byId(a.id)!.title, state().byId(a.id)!.rule.hour, state().byId(a.id)!.permission), ('晚检', 20, 'readonly'));
    expect(state().items, hasLength(1));

    await ctl().remove(a.id);
    expect(state().items, isEmpty);
    expect(state().byId(a.id), isNull);
  });

  test('校验不过：报错，什么都不存', () async {
    await expectLater(ctl().upsert(title: '', instruction: 'x', workspaceId: 'w', rule: daily(8)), throwsA(isA<AutomationException>()));
    await expectLater(ctl().upsert(title: 't', instruction: '  ', workspaceId: 'w', rule: daily(8)), throwsA(isA<AutomationException>()));
    expect(state().items, isEmpty);
  });

  test('开关：关了不触发；重新开启从现在起算；任务不在了不报错', () async {
    final a = await env.services.automations.upsert(title: '晨检', instruction: 'x', workspaceId: 'w', rule: daily(8), now: t0);
    await ctl().setEnabled(a.id, false);
    expect(state().byId(a.id)!.enabled, isFalse);
    expect(state().byId(a.id)!.lastRunAt, isNull, reason: '关掉不动时间');
    expect(state().byId(a.id)!.nextRun(t0), isNull);
    expect(a.enabled, isTrue, reason: '手里那份是旧快照');
    await ctl().setEnabled(a.id, true);
    final on = state().byId(a.id)!;
    expect(on.enabled, isTrue);
    expect(on.lastRunAt, isNotNull);
    await ctl().setEnabled('nope', false);
    expect(state().items, hasLength(1));
  });

  test('拿到手的清单、历史、正在跑的集合都改不了', () async {
    final a = await ctl().upsert(title: '晨检', instruction: 'x', workspaceId: 'w', rule: daily(8));
    expect(() => state().items.add(a), throwsUnsupportedError);
    expect(() => state().items.first.history.add(AutomationRun(t0, 'ok', '')), throwsUnsupportedError);
    expect(() => state().running.add('x'), throwsUnsupportedError);
    expect(() => env.services.automations.items.clear(), throwsUnsupportedError);
  });

  test('不经过 Notifier 的改动（调度器记结果、Agent 工具建任务）也进快照；历史新的在前、最多留 30 笔', () async {
    final store = env.services.automations;
    final a = await store.upsert(title: '晨检', instruction: 'x', workspaceId: 'w', rule: daily(8), now: t0);
    expect(state().items.single.id, a.id);
    for (var i = 0; i < AutomationStore.maxHistory + 5; i++) {
      await store.record(a.id, AutomationRun(t0.add(Duration(minutes: i)), 'ok', '第 $i 次'), advance: false);
    }
    final h = state().byId(a.id)!.history;
    expect(h, hasLength(AutomationStore.maxHistory));
    expect(h.first.summary, '第 ${AutomationStore.maxHistory + 4} 次');
    expect(state().byId(a.id)!.lastRunAt, isNull, reason: 'advance: false 不推进时间');
    await store.record(a.id, AutomationRun(t0.add(const Duration(days: 1)), 'missed', '错过'));
    expect(state().byId(a.id)!.lastRunAt, t0.add(const Duration(days: 1)));
    // 存一遍读回来一样
    await store.load();
    expect(state().byId(a.id)!.history.first.status, 'missed');
    expect(state().byId(a.id)!.history, hasLength(AutomationStore.maxHistory));
  });

  test('只运行一次的：一开跑就停用；任务被删后记结果不报错也不复活', () async {
    final store = env.services.automations;
    final once = await store.upsert(
      title: '一次',
      instruction: 'x',
      workspaceId: 'w',
      rule: TimeRule(kind: RuleKind.once, hour: 8, date: '2026-11-24', tzOffsetMinutes: 0),
      now: t0,
    );
    final started = await store.markStarted(once.id, DateTime.utc(2026, 11, 24, 8, 1));
    expect(started!.enabled, isFalse);
    expect(state().byId(once.id)!.enabled, isFalse);
    expect(state().byId(once.id)!.lastRunAt, DateTime.utc(2026, 11, 24, 8, 1));
    await store.remove(once.id);
    expect(await store.record(once.id, AutomationRun(t0, 'ok', '')), isNull);
    expect(await store.markStarted(once.id, t0), isNull);
    expect(state().items, isEmpty);
  });

  test('正在跑：调度器说了才变；任务清单变了不把它冲掉', () async {
    final a = await ctl().upsert(title: '晨检', instruction: 'x', workspaceId: 'w', rule: daily(8));
    expect(state().isRunning(a.id), isFalse);
    final live = {a.id};
    ctl().setRunning(live);
    expect(state().isRunning(a.id), isTrue);
    live.clear();
    expect(state().isRunning(a.id), isTrue, reason: '快照里是拷贝，不跟着外面那个集合变');
    await ctl().setEnabled(a.id, false);
    expect(state().isRunning(a.id), isTrue);
    ctl().setRunning(const {});
    expect(state().isRunning(a.id), isFalse);
  });

  test('容器销毁后：仓库上不留监听；再来通知不报错', () async {
    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    final store = env.services.automations;
    final before = store.changeListeners.length;
    final n = bare.read(automationsProvider.notifier);
    expect(store.changeListeners.length, before + 1);
    bare.dispose();
    expect(store.changeListeners.length, before);
    n.setRunning({'x'});
    await store.upsert(title: '晨检', instruction: 'x', workspaceId: 'w', rule: daily(8));
  });
}
