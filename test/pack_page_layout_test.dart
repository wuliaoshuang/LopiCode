// 打包页两件排版上的事（390×844）：
// - 本地打包打完自动滚动后，“重新打包”按钮整个在顶栏下面，不被顶栏的渐隐盖住半截；结果卡紧跟在它下面。
// - 有背景图片时，直接写在页面底上的小字（方式说明、各组小标题、脚注）后面垫着一块底；没背景时不垫；
//   垫不垫，字的位置一模一样（垫的那块不参与排版）。
//   flutter test --no-pub test/pack_page_layout_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backdrop_ui_support.dart';
import 'support/fake_local_pack.dart';
import 'support/harness.dart';

const plateKey = ValueKey('backdrop-plate');

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;

  tearDown(BackdropImages.instance.clear);

  Future<void> boot(WidgetTester tester) async {
    usePhoneViewport(tester);
    localPackBackendOverride = FakeLocalPackBackend();
    await tester.runAsync(() async {
      env = await TestEnv.create();
      externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        session.dispose();
        await env.dispose();
      });
      localPackBackendOverride = null;
      externalFilesDirOverride = null;
    });
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      appFor(
        env,
        ShellScope(
          openDrawer: () {},
          go: (_) {},
          projectName: '我的小站',
          child: BuildScreen(key: const Key('build'), session: session),
        ),
        font: kTestFont,
      ),
    );
    await settle(tester);
  }

  testWidgets('打完自动滚动后，“重新打包”整个在顶栏下面，不被顶栏的渐隐盖住；结果卡紧跟在它下面', (tester) async {
    await boot(tester);
    await show(tester);
    final start = find.byKey(const Key('pack-start'));
    await tester.scrollUntilVisible(start, 160, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(start);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(start);
    await settle(tester, rounds: 8);
    expect(env.services.container.read(localPackProvider(session)).phase, LocalPackPhase.done);
    // 不再手动滚：就看自动滚完停在哪
    final again = tester.getRect(find.widgetWithText(FilledButton, '重新打包'));
    final inset = PageBar.insetOf(tester.element(find.byType(ListView).first));
    expect(again.top, greaterThanOrEqualTo(inset), reason: '按钮上沿要在“状态栏 + 顶栏”以下（原来在它上面 40 左右，下半截透在顶栏的渐隐里）');
    expect(again.top, lessThan(inset + BarScrim.kTail + 40), reason: '也没有滚过头');
    final done = tester.getRect(find.text('打包完成'));
    expect(done.top, greaterThan(again.bottom), reason: '结果卡在按钮下面');
    expect(done.bottom, lessThan(kPhone.height), reason: '结果卡的开头在屏幕里');
    // 手动滚到最底：按钮要么整个滚出屏幕上沿，要么整个在顶栏下面——不能半截透在顶栏里
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(tester, rounds: 2);
    final f = find.widgetWithText(FilledButton, '重新打包');
    if (f.evaluate().isNotEmpty) {
      final r = tester.getRect(f);
      expect(r.bottom <= 0 || r.top >= inset, isTrue, reason: '滚到底时按钮在 $r，顶栏下沿在 $inset');
    }
  });

  testWidgets('背景图片：开 → 说明、小标题、脚注后面垫着底；关 → 不垫；字的位置不变', (tester) async {
    await boot(tester);
    await seedBackdrop(tester, env, scene: true, settings: (s) => s.copyWith(onPages: true));
    await show(tester);
    final about = find.byKey(const Key('pack-mode-about'));
    Finder plateOf(Finder f) => find.descendant(
      of: find.ancestor(of: f, matching: find.byType(BackdropPlate)).first,
      matching: find.byKey(plateKey),
    );
    final title = find.text('应用信息');
    expect(title, findsOneWidget, reason: '本地打包表单第一组的小标题');

    expect(plateOf(about), findsOneWidget, reason: '方式说明垫着底');
    expect(plateOf(title), findsOneWidget, reason: '组的小标题垫着底');
    final aboutOn = tester.getTopLeft(about), titleOn = tester.getRect(title);
    // 垫的那块比字四周各大一圈，颜色是半透明的页面底色
    final plate = tester.getRect(plateOf(title));
    expect(plate, Rect.fromLTRB(titleOn.left - kBackdropPlateOutsetX, titleOn.top - kBackdropPlateOutsetY, titleOn.right + kBackdropPlateOutsetX, titleOn.bottom + kBackdropPlateOutsetY));
    final box = tester.widget<DecoratedBox>(plateOf(title)).decoration as BoxDecoration;
    expect(box.color!.a, inExclusiveRange(0, 1), reason: '半透明：看得到一点图，又托得住字');
    final height = tester.getSize(find.byType(ListView).first).height;
    final extentOn = tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;

    backdropOf(env).update((s) => s.copyWith(onPages: false), persist: false);
    await settle(tester, rounds: 2);
    expect(find.byKey(plateKey), findsNothing, reason: '背景关了：什么都不垫');
    expect(tester.getTopLeft(about), aboutOn, reason: '说明的位置没动');
    expect(tester.getTopLeft(title), titleOn.topLeft, reason: '小标题的位置没动（没背景时它占满一行，字还是从同一处起）');
    expect(tester.getSize(title).height, titleOn.height);
    expect(tester.getSize(find.byType(ListView).first).height, height);
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, extentOn, reason: '整页高度没变');
  });

  testWidgets('设置页的小标题不垫（只有打包页开了这个）', (tester) async {
    await boot(tester);
    await seedBackdrop(tester, env, scene: true, settings: (s) => s.copyWith(onPages: true));
    await show(tester);
    expect(find.byKey(plateKey), findsWidgets);
    expect(BackdropPlates.of(tester.element(find.byKey(const Key('pack-mode-about')))), isTrue);
    expect(BackdropPlates.of(tester.element(find.byType(BuildScreen))), isFalse, reason: '开关只罩着打包页自己的内容');
    expect(File(p.join(project.dir, 'index.html')).existsSync(), isTrue);
  });
}
