// 背景渲染控件和聊天页带背景的界面测试（390×844，浅色 + 深色）。图片是代码画的；不拉起系统选择器、不联网。
//   LOPI_SHOTS=1 flutter test test/backdrop_ui_test.dart   # 同时写截图到 docs/screenshots/bg-chat-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/backdrop_ui_support.dart';
import 'support/harness.dart';

const paintKey = ValueKey('app-backdrop-paint');

/// 一张空页面，按 [area] 接背景；把拿到的颜色表和“有没有背景”记下来。
class Probe extends StatelessWidget {
  const Probe({super.key, this.area = BackdropArea.chat, required this.seen});
  final BackdropArea area;
  final void Function(BuildContext context, bool on) seen;

  @override
  Widget build(BuildContext context) => AppBackdrop(
    area: area,
    builder: (context, on) {
      seen(context, on);
      return Scaffold(backgroundColor: on ? Colors.transparent : null, body: const SizedBox.expand());
    },
  );
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BackdropImages.instance.clear);

  Future<TestEnv> newEnv(WidgetTester tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    return env;
  }

  group('背景渲染控件', () {
    late bool on;
    late AppColors colors;
    late BuildContext ctx;
    Future<void> show(WidgetTester tester, TestEnv env, {BackdropArea area = BackdropArea.chat, ThemeMode mode = ThemeMode.light}) async {
      await tester.pumpWidget(
        appFor(
          env,
          Probe(
            area: area,
            seen: (context, o) {
              on = o;
              ctx = context;
              colors = context.colors;
            },
          ),
          mode: mode,
        ),
      );
      await settle(tester, rounds: 2);
    }

    testWidgets('没有图：页面和原来一样，不画背景', (tester) async {
      final env = await newEnv(tester);
      await show(tester, env);
      expect(on, isFalse);
      expect(find.byKey(paintKey), findsNothing);
      expect(BackdropScope.surface(ctx, colors.surface), colors.surface, reason: '没背景时表面颜色原样');
    });

    testWidgets('铺满：四个角是图的四个角，边缘像素不透明；同一张图只解一次', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 0));
      await show(tester, env);
      expect(on, isTrue);
      expect(tester.getSize(find.byKey(paintKey)), const Size(390, 844));
      final d = await grab(tester);
      expect(pixel(d, 0, 0), nearColor(kRed));
      expect(pixel(d, 389, 0), nearColor(kGreen));
      expect(pixel(d, 0, 843), nearColor(kBlue));
      expect(pixel(d, 389, 843), nearColor(kYellow));
      expect(pixel(d, 195, 422), nearColor(const Color(0xFFFFFFFF)), reason: '中间的白圆');
      // 换个外观再摆一遍：还是那张解好的图
      await show(tester, env, mode: ThemeMode.dark);
      expect(on, isTrue);
      expect(BackdropImages.instance.decodeCount, 1);
    });

    testWidgets('按裁剪区域画：只裁左上那一块，整屏都是红的', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 0, crop: const CropRect(0, 0, 0.4, 0.4)));
      await show(tester, env);
      final d = await grab(tester);
      for (final (x, y) in [(2, 2), (387, 2), (2, 841), (387, 841), (195, 422)]) {
        expect(pixel(d, x, y), nearColor(kRed), reason: '($x, $y)');
      }
    });

    testWidgets('旋转 90°：原来左下的蓝到了左上，左上的红到了右上', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, width: 844, height: 390, look: (l) => l.copyWith(maskOpacity: 0, turns: 1));
      await show(tester, env);
      final d = await grab(tester);
      expect(pixel(d, 4, 4), nearColor(kBlue));
      expect(pixel(d, 385, 4), nearColor(kRed));
      expect(pixel(d, 385, 839), nearColor(kGreen));
      expect(pixel(d, 4, 839), nearColor(kYellow));
    });

    testWidgets('完整显示：整张图居中，上下空的地方是主题底色', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(
        tester,
        env,
        width: 390,
        height: 390,
        look: (l) => l.copyWith(maskOpacity: 0, fit: BackdropFit.contain, crop: const CropRect(0, 0, 0.3, 0.6)),
      );
      await show(tester, env);
      final d = await grab(tester);
      expect(pixel(d, 195, 20), nearColor(colors.bg));
      expect(pixel(d, 195, 820), nearColor(colors.bg));
      // 图在 y=227…617：裁剪区域不管，四块都在
      expect(pixel(d, 20, 240), nearColor(kRed));
      expect(pixel(d, 370, 240), nearColor(kGreen));
      expect(pixel(d, 20, 600), nearColor(kBlue));
      expect(pixel(d, 370, 600), nearColor(kYellow));
    });

    testWidgets('平铺：一格是屏幕宽的一半，横竖重复', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, width: 390, height: 390, look: (l) => l.copyWith(maskOpacity: 0, fit: BackdropFit.tile, tilePercent: 50));
      await show(tester, env);
      final d = await grab(tester);
      for (final (ox, oy) in [(0, 0), (195, 0), (0, 195), (195, 390), (0, 780)]) {
        expect(pixel(d, ox + 10, oy + 10), nearColor(kRed), reason: '第 ($ox, $oy) 格的左上');
        expect(pixel(d, ox + 185, oy + 10), nearColor(kGreen), reason: '第 ($ox, $oy) 格的右上');
      }
      expect(pixel(d, 10, 185), nearColor(kBlue));
    });

    testWidgets('遮罩和亮度：遮罩 100% 就是主题底色；自选颜色照自选的来；亮度 −100 全黑', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 100));
      await show(tester, env);
      expect(pixel(await grab(tester), 30, 30), nearColor(colors.bg));

      backdropOf(env).updateLook(dark: false, change: (l) => l.copyWith(maskFollowsTheme: false, maskColor: 0x1B2A4A, maskOpacity: 100));
      await settle(tester, rounds: 1);
      expect(pixel(await grab(tester), 30, 30), nearColor(const Color(0xFF1B2A4A)));

      backdropOf(env).updateLook(dark: false, change: (l) => l.copyWith(maskOpacity: 50));
      await settle(tester, rounds: 1);
      final half = pixel(await grab(tester), 30, 30);
      expect(half, nearColor(Color.lerp(kRed, const Color(0xFF1B2A4A), 0.5)!, tolerance: 10), reason: '50% 就是各一半');

      backdropOf(env).updateLook(dark: false, change: (l) => l.copyWith(maskOpacity: 0, brightness: -100));
      await settle(tester, rounds: 1);
      expect(pixel(await grab(tester), 30, 30), nearColor(const Color(0xFF000000)));
      backdropOf(env).updateLook(dark: false, change: (l) => l.copyWith(brightness: 100));
      await settle(tester, rounds: 1);
      expect(pixel(await grab(tester), 30, 30), nearColor(const Color(0xFFFFFFFF)));
    });

    testWidgets('模糊：色块交界处糊开了；边缘不透明、不发黑；多画几帧不重算', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 0, blur: 20));
      await show(tester, env);
      final d = await grab(tester);
      final seam = pixel(d, 195, 60);
      expect(seam, isNot(nearColor(kRed, tolerance: 20)));
      expect(seam, isNot(nearColor(kGreen, tolerance: 20)));
      for (final (x, y) in [(0, 0), (389, 0), (0, 843), (389, 843), (0, 400)]) {
        final p = pixel(d, x, y);
        expect(p.a, 1, reason: '($x, $y) 不透明');
        expect(p.computeLuminance(), greaterThan(0.05), reason: '($x, $y) 不发黑');
      }
      expect(pixel(d, 30, 30), nearColor(kRed, tolerance: 30), reason: '离交界远的地方还是原来的颜色');
      expect(BackdropImages.instance.blurCount, 1);
      // 再画很多帧、换主题、弹键盘：还是那一张糊好的图
      for (var i = 0; i < 5; i++) {
        tester.renderObject(find.byKey(paintKey)).markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await grab(tester);
      expect(BackdropImages.instance.blurCount, 1);
      // 改了模糊程度才重算一次
      backdropOf(env).updateLook(dark: false, change: (l) => l.copyWith(blur: 6));
      await settle(tester, rounds: 1);
      await grab(tester);
      expect(BackdropImages.instance.blurCount, 2);
    });

    testWidgets('键盘升起：图不跟着缩，左下角还是原来那块', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 0));
      await show(tester, env);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.getSize(find.byKey(paintKey)), const Size(390, 844));
      final d = await grab(tester);
      expect(pixel(d, 5, 5), nearColor(kRed));
      expect(pixel(d, 5, 500), nearColor(kBlue), reason: '图缩了的话这里会是别的');
      expect(pixel(d, 195, 422), nearColor(const Color(0xFFFFFFFF)), reason: '白圆还在屏幕正中');
    });

    testWidgets('范围：默认只铺聊天页；“其它页面”开了才铺；总开关关了哪都不铺', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env);
      await show(tester, env, area: BackdropArea.pages);
      expect(on, isFalse);
      expect(find.byKey(paintKey), findsNothing);
      backdropOf(env).update((s) => s.copyWith(onPages: true));
      await settle(tester, rounds: 1);
      expect(on, isTrue);
      expect(find.byKey(paintKey), findsOneWidget);
      backdropOf(env).update((s) => s.copyWith(enabled: false));
      await settle(tester, rounds: 1);
      expect(on, isFalse);
      expect(find.byKey(paintKey), findsNothing);
    });

    testWidgets('表面颜色：有背景时按“表面不透明度”变透；“透出”开关关着的照旧不透', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, settings: (s) => s.copyWith(surfaceOpacity: 70));
      await show(tester, env);
      final got = BackdropScope.surface(ctx, colors.surface);
      expect(got.a, closeTo(0.7, 0.01));
      expect(got.withValues(alpha: 1), colors.surface.withValues(alpha: 1));
      for (final a in [BackdropArea.terminal, BackdropArea.code, BackdropArea.blocks, BackdropArea.lowcode]) {
        expect(BackdropScope.surface(ctx, colors.codeBg, seeThrough: a), colors.codeBg, reason: '${a.name} 默认不透出');
      }
      backdropOf(env).update((s) => s.withArea(BackdropArea.code, true));
      await settle(tester, rounds: 1);
      expect(BackdropScope.surface(ctx, colors.codeBg, seeThrough: BackdropArea.code).a, closeTo(colors.codeBg.a * 0.7, 0.01));
      expect(BackdropScope.surface(ctx, colors.codeBg, seeThrough: BackdropArea.terminal), colors.codeBg);
    });

    testWidgets('深色单独设置：深色那份没图时深色下不画；给了图就画深色那张', (tester) async {
      final env = await newEnv(tester);
      await seedBackdrop(tester, env, look: (l) => l.copyWith(maskOpacity: 0), settings: (s) => s.copyWith(darkSeparate: true));
      await show(tester, env, mode: ThemeMode.dark);
      expect(on, isFalse);
      await show(tester, env);
      expect(on, isTrue);
      // 深色另放一张：只裁右下（黄）
      await seedBackdrop(tester, env, dark: true, width: 400, height: 800, look: (l) => l.copyWith(maskOpacity: 0, crop: const CropRect(0.6, 0.6, 0.4, 0.4)));
      await show(tester, env, mode: ThemeMode.dark);
      expect(on, isTrue);
      expect(pixel(await grab(tester), 20, 20), nearColor(kYellow));
      await show(tester, env);
      expect(pixel(await grab(tester), 20, 20), nearColor(kRed), reason: '浅色还是原来那张');
    });

    testWidgets('图片文件没了：当作没有背景，不崩', (tester) async {
      final env = await newEnv(tester);
      final img = await seedBackdrop(tester, env);
      BackdropImages.instance.clear();
      backdropStoreOf(env).imageFile(img.file).deleteSync();
      await show(tester, env);
      await settle(tester, rounds: 3);
      expect(on, isFalse);
      expect(find.byKey(paintKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('默认遮罩下直接写在背景上的字读得清（最坏的图：纯黑 / 纯白）· ${mode.name}', (tester) async {
        final env = await newEnv(tester);
        await show(tester, env, mode: mode);
        const mask = kBackdropMaskDefault / 100;
        for (final worst in const [Color(0xFF000000), Color(0xFFFFFFFF)]) {
          final behind = Color.lerp(worst, colors.bg, mask)!;
          expect(contrast(colors.text, behind), greaterThanOrEqualTo(4.5), reason: '正文在 $worst 的图上');
          // 气泡 / 输入框：表面按默认不透明度叠在上面
          final surface = Color.lerp(behind, colors.surfaceMuted, kBackdropSurfaceDefault / 100)!;
          expect(contrast(colors.text, surface), greaterThanOrEqualTo(7), reason: '气泡里的字在 $worst 的图上');
        }
      });
    }
  });

  group('聊天页带背景', () {
    for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
      testWidgets('背景铺在聊天页后面，气泡和输入框半透明，导航还在；关掉就和原来一样 ($suffix)', (tester) async {
        usePhoneViewport(tester);
        late TestEnv env;
        late Project project;
        late ProjectSession session;
        await tester.runAsync(() async {
          env = await TestEnv.create(
            chatClient: () => ScriptedChatClient([
              [say('好的。我先看一下现在的页面结构，再加上登录表单和校验。\n\n1. 新建 login.html\n2. 表单：邮箱、密码、登录按钮\n3. 输入不对时在下面给提示'), ChatDelta(finishReason: 'stop')],
            ]),
          );
          await env.services.models.upsert(
            name: '我的中转站',
            protocol: ChatProtocol.openaiChat,
            baseUrl: 'https://relay.example.cn/v1',
            apiKey: 'test',
            models: [ModelSpec(id: 'some-model', contextLength: 128000)],
          );
          project = await env.services.projects.create('我的小站', ProjectTemplate.web);
          session = ProjectSession(env.services, project);
          await session.loadChat();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        addTearDown(() async {
          session.dispose();
          await env.dispose();
        });
        await seedBackdrop(tester, env, width: 780, height: 1688, scene: true);
        await tester.pumpWidget(
          appFor(
            env,
            ProjectShell(project: project, session: session, initial: ShellDest.chat),
            mode: mode,
            font: kTestFont,
          ),
        );
        await settle(tester);
        await tester.runAsync(() => session.sendToAgent('帮我加一个登录页').timeout(const Duration(seconds: 20)));
        await settle(tester, rounds: 3);

        expect(find.byKey(paintKey), findsOneWidget);
        // 背景铺满聊天页这一块：从屏幕顶到底部导航的上沿（导航是实底的，不透）
        final navTop = tester.getRect(find.byType(IconBottomNav)).top;
        expect(tester.getRect(find.byKey(paintKey)), Rect.fromLTRB(0, 0, 390, navTop));
        expect(find.text('帮我加一个登录页'), findsWidgets); // 气泡里一处，顶栏的对话标题也是它
        expect(find.byType(IconBottomNav), findsOneWidget);
        final scope = tester.widget<BackdropScope>(find.byType(BackdropScope).first);
        expect(scope.on, isTrue);
        // 背景真的透出来了：屏幕上同一行的左右两头颜色不一样（纯色底的话是一样的）
        final d = await grab(tester);
        expect(pixel(d, 2, 300), isNot(nearColor(pixel(d, 2, 700), tolerance: 3)), reason: '上下颜色不同＝看得见图');
        await shot(tester, 'bg-chat-$suffix');

        // 键盘升起：导航留在原位，背景不缩
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(find.byType(IconBottomNav)).bottom, 844);
        // 图是按整块屏幕摆的：页面变矮了，同一个位置上还是原来那块图（没跟着缩）
        final up = await grab(tester);
        expect(pixel(up, 2, 150), nearColor(pixel(d, 2, 150), tolerance: 3));
        expect(pixel(up, 2, 300), nearColor(pixel(d, 2, 300), tolerance: 3));
        tester.view.resetViewInsets();
        await tester.pump();

        // 关掉：不画背景，页面底色回来
        backdropOf(env).update((s) => s.copyWith(enabled: false));
        await settle(tester, rounds: 2);
        expect(find.byKey(paintKey), findsNothing);
        final off = await grab(tester);
        expect(pixel(off, 2, 300), nearColor(pixel(off, 2, 700), tolerance: 3));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
