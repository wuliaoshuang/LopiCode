// 运行环境和一键诊断的状态（lib/state/runtime_state.dart）：不可变快照 + Notifier。
// 安装流程、PRoot 命令、诊断的判定逻辑本身见 test/runtime_test.dart、test/runtime_diagnostics_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  LinuxRuntime engine() => env.services.runtime;
  RuntimeView state() => box.read(runtimeProvider);
  RuntimeNotifier ctl() => box.read(runtimeProvider.notifier);

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
  });
  tearDown(() => env.dispose());

  test('一开始：没装、不忙、进不去；和引擎自己说的一致', () {
    final v = state();
    expect(v.phase, RuntimePhase.notInstalled);
    expect((v.installed, v.busy, v.usable, v.shouldUseLinux), (false, false, false, false));
    expect(v.installError, isNull);
    expect(v.runningPack, isNull);
    expect(v.installedPacks, isEmpty);
    expect(v.packs.map((RuntimePack p) => p.id), engine().packs.map((RuntimePack p) => p.id));
    expect((v.rootfsSourceId, v.aptMirrorId), (engine().rootfsSource.id, engine().aptMirror.id));
    expect(v.imageSize, engine().image.size);
    expect(v.partialBytes, 0);
  });

  test('引擎那边变了（启动失败、记日志）：快照换新的，旧的那份不变', () {
    final before = state();
    engine().recordLaunchFailure('进不去', output: 'proot error');
    final after = state();
    expect((before.launchFailures, before.lastLaunchError), (0, null));
    expect(before.logLines, isEmpty);
    expect((after.launchFailures, after.lastLaunchError), (1, '进不去'));
    expect(after.compatMode, isTrue, reason: '失败过一次，下次用兼容模式');
    expect(after.logLines.join('\n'), allOf(contains('启动失败'), contains('proot error')));
    engine().log('随手记一行');
    expect(after.logLines.join('\n'), isNot(contains('随手记一行')));
    expect(state().logLines.last, contains('随手记一行'));
  });

  test('重新尝试进入 Ubuntu：失败计数清零', () {
    engine()
      ..recordLaunchFailure('一')
      ..recordLaunchFailure('二');
    expect(state().launchFailures, LinuxRuntime.maxLaunchFailures);
    ctl().resetLaunchFailures();
    expect((state().launchFailures, state().lastLaunchError), (0, null));
    expect(engine().launchFailures, 0);
  });

  test('换下载源：写进设置，快照跟着变', () async {
    await ctl().setRootfsSource('official');
    await ctl().setAptMirror('aliyun');
    expect((state().rootfsSourceId, state().aptMirrorId), ('official', 'aliyun'));
    expect(env.services.settings.getString(SettingKeys.runtimeRootfsSource), 'official');
    expect(env.services.settings.getString(SettingKeys.runtimeAptMirror), 'aliyun');
    expect(state().packs.firstWhere((RuntimePack p) => p.id == 'node').script, contains('nodejs.org'), reason: '运行时的安装脚本跟着系统包的下载源走');
  });

  test('拿到手的快照改不了', () {
    engine().log('一行');
    final v = state();
    expect(() => v.logLines.add('x'), throwsUnsupportedError);
    expect(() => v.packOutput.add('x'), throwsUnsupportedError);
    expect(() => v.installedPacks.add('x'), throwsUnsupportedError);
    expect(v.packs.clear, throwsUnsupportedError);
    expect(() => v.missingLauncherFiles.add('x'), throwsUnsupportedError);
  });

  test('没装的时候卸载：不报错，还是没装', () async {
    await ctl().uninstall();
    expect(state().phase, RuntimePhase.notInstalled);
    expect(state().installError, isNull);
  });

  test('诊断：一开始没在跑、没报告；引擎那边一动快照就换', () {
    final d = box.read(runtimeDiagnosticsProvider);
    expect((d.running, d.hasReport, d.stepCount, d.report), (false, false, 0, ''));
    expect(d.conclusions, isEmpty);
    expect(() => d.conclusions.add('x'), throwsUnsupportedError);
    var n = 0;
    box.listen(runtimeDiagnosticsProvider, (_, _) => n++);
    var r = 0;
    box.listen(runtimeProvider, (_, _) => r++);
    engine().log('只动运行环境');
    expect((n, r), (0, 1), reason: '运行环境变了不惊动诊断');
  });

  test('容器销毁后：引擎上不留监听；之后再变不报错', () {
    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    final a = engine().changeListeners.length, b = engine().diagnostics.changeListeners.length;
    bare
      ..read(runtimeProvider)
      ..read(runtimeDiagnosticsProvider);
    expect(engine().changeListeners.length, a + 1);
    expect(engine().diagnostics.changeListeners.length, b + 1);
    bare.dispose();
    expect(engine().changeListeners.length, a);
    expect(engine().diagnostics.changeListeners.length, b);
    engine().recordLaunchFailure('销毁以后');
  });
}
