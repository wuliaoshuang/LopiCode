// 背景设置页和裁剪页的界面测试（390×844，浅色 + 深色）。选图用假实现，绝不拉起系统选择器；图片是代码画的。
//   LOPI_SHOTS=1 flutter test test/backdrop_pages_test.dart   # 同时写截图到 docs/screenshots/bg-*.png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/ui/backdrop_crop_screen.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/backdrop_settings_groups.dart';
import 'package:lopicode/ui/backdrop_settings_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/backdrop_fakes.dart';
import 'support/backdrop_ui_support.dart';
import 'support/harness.dart';

const double phone = 390 / 844;

/// 区域在（旋转后的）图上的像素宽高比。
double pixelAspect(CropRect r, num w, num h) => (r.width * w) / (r.height * h);

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

  Future<void> tapKey(WidgetTester tester, String key, {int rounds = 2}) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester, rounds: rounds);
  }

  /// 等裁剪页把图解好、进场动画走完（动画没走完就点，会点到还在滑动的按钮外面）。
  Future<void> cropReady(WidgetTester tester) async {
    await pumpUntil(tester, find.byKey(const ValueKey('bg-crop-paint')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  List<String> stored(TestEnv env) {
    final dir = backdropStoreOf(env).imageDir;
    return dir.existsSync() ? [for (final e in dir.listSync()) e.uri.pathSegments.last] : const [];
  }

  for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    group('背景设置页 ($suffix)', () {
      Future<void> open(WidgetTester tester, TestEnv env) async {
        await tester.pumpWidget(appFor(env, const BackdropSettingsScreen(), mode: mode, font: kTestFont));
        await pumpUntil(tester, find.byKey(const Key('bg-settings-list')));
      }

      testWidgets('没有图：只有“选择图片”一个主操作；选图 → 裁剪 → 用上', (tester) async {
        final env = await newEnv(tester);
        await open(tester, env);
        expect(find.byKey(const Key('bg-empty')), findsOneWidget);
        expect(find.byKey(const Key('bg-pick')), findsOneWidget);
        expect(find.byKey(const Key('bg-preview')), findsNothing);
        expect(find.byKey(const Key('bg-enabled')), findsNothing, reason: '没图时不摆一堆调不了的开关');
        expect(find.byKey(const Key('bg-dark-separate')), findsOneWidget);
        expect(backdropSettingsLabel(backdropStateOf(env)), '没有');
        await shot(tester, 'bg-settings-empty-$suffix');

        late FakeBackdropPicker picker;
        await tester.runAsync(() async => picker = useFakePicker(env, [BackdropPicked(writePick(env.tmp, 'a.png', await makeScenePng(600, 900)))]));
        await tester.tap(find.byKey(const Key('bg-pick')));
        await cropReady(tester);
        expect(picker.calls, 1);
        expect(find.text('裁剪背景'), findsOneWidget);
        expect(backdropStateOf(env).light.hasImage, isFalse, reason: '裁剪页没点确认之前不改设置');
        expect(stored(env), hasLength(1));
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await pumpUntil(tester, find.byKey(const Key('bg-preview')));

        final look = backdropStateOf(env).light;
        expect(look.hasImage, isTrue, reason: '裁剪页还在=${find.text('裁剪背景').evaluate().length} 预览=${find.byKey(const Key('bg-preview')).evaluate().length} 文件=${stored(env)}');
        expect((look.width, look.height), (600, 900));
        expect(pixelAspect(look.crop, 600, 900), closeTo(phone, 1e-6), reason: '裁出来是手机屏幕的比例');
        expect(look.crop.centerX, closeTo(0.5, 1e-9));
        expect(find.byKey(const Key('bg-empty')), findsNothing);
        for (final k in [
          'bg-recrop',
          'bg-replace',
          'bg-remove',
          'bg-enabled',
          'bg-fit',
          'bg-mask-minus',
          'bg-blur-plus',
          'bg-brightness-slider',
          'bg-surface-value',
          'bg-area-chat',
          'bg-area-pages',
          'bg-area-terminal',
          'bg-area-code',
          'bg-area-blocks',
          'bg-area-lowcode',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.byKey(const ValueKey('bg-sample-text')), findsOneWidget, reason: '预览里有示例文字');
        expect(backdropSettingsLabel(backdropStateOf(env)), '已开');
        await shot(tester, 'bg-settings-image-$suffix');
        await tester.ensureVisible(find.byKey(const Key('bg-effect-reset')));
        await settle(tester, rounds: 1);
        await shot(tester, 'bg-settings-effects-$suffix');
        await tester.ensureVisible(find.byKey(const Key('bg-dark-separate')));
        await settle(tester, rounds: 1);
        await shot(tester, 'bg-settings-scope-$suffix');
      });

      testWidgets('取消：什么都不变也不提示；读取失败 / 坏文件头 / 超大：提示人话，什么都不留', (tester) async {
        final env = await newEnv(tester);
        await open(tester, env);
        await tester.runAsync(
          () async => useFakePicker(env, [
            const BackdropPickCancelled(),
            const BackdropPickFailed('读不出这张图，请换一张试试。'),
            BackdropPicked(writePick(env.tmp, 'bad.png', 'definitely not an image'.codeUnits)),
            BackdropPicked(writePick(env.tmp, 'anim.gif', kGifHeader)),
          ]),
        );
        await tapKey(tester, 'bg-pick', rounds: 3);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('bg-empty')), findsOneWidget);

        await tapKey(tester, 'bg-pick', rounds: 3);
        expect(find.text('读不出这张图，请换一张试试。'), findsOneWidget);

        await tapKey(tester, 'bg-pick', rounds: 4);
        expect(find.textContaining('不是能用的图片'), findsOneWidget);

        await tapKey(tester, 'bg-pick', rounds: 4);
        expect(find.textContaining('GIF'), findsWidgets);

        expect(find.text('裁剪背景'), findsNothing);
        expect(backdropStateOf(env).light.hasImage, isFalse);
        expect(stored(env), isEmpty);
        expect(Directory('${env.tmp.path}/cache').listSync(), isEmpty, reason: '缓存副本都删了');
      });

      testWidgets('选了图但从裁剪页退出来：不用这张，刚入库的文件删掉', (tester) async {
        final env = await newEnv(tester);
        await open(tester, env);
        await tester.runAsync(() async => useFakePicker(env, [BackdropPicked(writePick(env.tmp, 'a.png', await makePng(300, 300)))]));
        await tester.tap(find.byKey(const Key('bg-pick')));
        await cropReady(tester);
        expect(stored(env), hasLength(1));
        await tester.tap(find.byTooltip('返回'));
        await settle(tester, rounds: 4);
        expect(find.byKey(const Key('bg-empty')), findsOneWidget);
        expect(backdropStateOf(env).light.hasImage, isFalse);
        expect(stored(env), isEmpty);
      });

      testWidgets('有图：步进按钮、适配方式、范围和透出开关都实时改到设置上', (tester) async {
        final env = await newEnv(tester);
        await seedBackdrop(tester, env, width: 600, height: 900, scene: true);
        await open(tester, env);
        BackdropLook look() => backdropStateOf(env).light;

        expect(tester.widget<Text>(find.byKey(const Key('bg-mask-value'))).data, '$kBackdropMaskDefault%');
        await tapKey(tester, 'bg-mask-minus');
        expect(look().maskOpacity, kBackdropMaskDefault - 5);
        await tapKey(tester, 'bg-mask-plus');
        await tapKey(tester, 'bg-mask-plus');
        expect(look().maskOpacity, kBackdropMaskDefault + 5);
        expect(tester.widget<Text>(find.byKey(const Key('bg-mask-value'))).data, contains('${kBackdropMaskDefault + 5}'));

        expect(tester.widget<IconButton>(find.byKey(const Key('bg-blur-minus'))).onPressed, isNull, reason: '已经是 0，减号灰掉');
        await tapKey(tester, 'bg-blur-plus');
        await tapKey(tester, 'bg-blur-plus');
        expect(look().blur, 4);
        await tapKey(tester, 'bg-brightness-minus');
        expect(look().brightness, -5);
        await tapKey(tester, 'bg-surface-minus');
        expect(backdropStateOf(env).surfaceOpacity, kBackdropSurfaceDefault - 5);

        // 滑杆：拖到最右是上限
        final slider = find.byKey(const Key('bg-blur-slider'));
        await tester.ensureVisible(slider);
        await tester.pump();
        await tester.drag(slider, const Offset(400, 0));
        await settle(tester, rounds: 2);
        expect(look().blur, kBackdropBlurMax);

        // 自选遮罩颜色
        await tapKey(tester, 'bg-mask-${kBackdropMaskSwatches[2].toRadixString(16)}');
        expect(look().maskFollowsTheme, isFalse);
        expect(look().maskColor & 0xFFFFFF, kBackdropMaskSwatches[2] & 0xFFFFFF);
        await tapKey(tester, 'bg-mask-theme');
        expect(look().maskFollowsTheme, isTrue);

        // 恢复默认：效果回去，图和裁剪不动
        final before = look();
        await tapKey(tester, 'bg-effect-reset');
        expect((look().maskOpacity, look().blur, look().brightness, backdropStateOf(env).surfaceOpacity), (kBackdropMaskDefault, 0, 0, kBackdropSurfaceDefault));
        expect((look().file, look().crop), (before.file, before.crop));

        // 适配方式
        await tester.ensureVisible(find.byKey(const Key('bg-fit')));
        await tester.pump();
        await tester.tap(find.text('平铺'));
        await settle(tester, rounds: 2);
        expect(look().fit, BackdropFit.tile);
        await tapKey(tester, 'bg-tile-minus');
        expect(look().tilePercent, kBackdropTileDefault - 5);
        await tester.ensureVisible(find.byKey(const Key('bg-fit')));
        await tester.pump();
        await tester.tap(find.text('完整显示'));
        await settle(tester, rounds: 2);
        expect(look().fit, BackdropFit.contain);
        expect(find.byKey(const Key('bg-tile-minus')), findsNothing);

        // 范围和透出
        expect(backdropStateOf(env).onChat, isTrue);
        await tapKey(tester, 'bg-area-pages');
        expect(backdropStateOf(env).onPages, isTrue);
        await tapKey(tester, 'bg-area-chat');
        expect(backdropStateOf(env).onChat, isFalse);
        for (final a in [BackdropArea.terminal, BackdropArea.code, BackdropArea.blocks, BackdropArea.lowcode]) {
          expect(backdropStateOf(env).area(a), isFalse, reason: '${a.name} 默认不透出');
          await tapKey(tester, 'bg-area-${a.name}');
          expect(backdropStateOf(env).area(a), isTrue);
        }
        await tapKey(tester, 'bg-enabled');
        expect(backdropStateOf(env).enabled, isFalse);
        expect(backdropSettingsLabel(backdropStateOf(env)), '已关');

        // 都存盘了：重新读出来一样
        // （界面上触发的写盘是在测试时钟里排的队，不能在 runAsync 里干等它；先让它们走完再读。）
        await settle(tester, rounds: 4);
        final onDisk = await tester.runAsync(() => backdropStoreOf(env).load());
        expect(onDisk, backdropStateOf(env));
        expect(tester.takeException(), isNull);
      });

      testWidgets('重新裁剪回到上次的区域接着调；换一张清掉旧文件；移除要确认并删文件', (tester) async {
        final env = await newEnv(tester);
        final first = await seedBackdrop(tester, env, width: 600, height: 900);
        const saved = CropRect(0.25, 0.3, 0.3466, 0.5);
        await tester.runAsync(() => backdropOf(env).setCrop(dark: false, crop: saved, turns: 0));
        await open(tester, env);

        // 重新裁剪：进去就是上次的位置和倍数
        await tapKey(tester, 'bg-recrop');
        await cropReady(tester);
        expect(tester.widget<Text>(find.byKey(const Key('bg-crop-zoom-value'))).data, '2.00×');
        await tester.drag(find.byKey(const ValueKey('bg-crop-area')), const Offset(-60, 0));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await pumpUntil(tester, find.byKey(const Key('bg-preview')));
        final again = backdropStateOf(env).light;
        expect(again.file, first.file, reason: '图没换');
        expect(again.crop.left, greaterThan(saved.left), reason: '往左拖图＝区域往右');
        expect(again.crop.top, closeTo(saved.top, 0.01));
        expect(again.crop.width, closeTo(saved.width, 1e-3));

        // 换一张
        await tester.runAsync(() async => useFakePicker(env, [BackdropPicked(writePick(env.tmp, 'b.png', await makePng(500, 400)))]));
        await tapKey(tester, 'bg-replace', rounds: 1);
        await cropReady(tester);
        expect(tester.widget<Text>(find.byKey(const Key('bg-crop-zoom-value'))).data, '1.00×', reason: '新图从居中最大开始');
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await pumpUntil(tester, find.byKey(const Key('bg-preview')));
        await settle(tester, rounds: 3);
        final second = backdropStateOf(env).light;
        expect(second.file, isNot(first.file));
        expect((second.width, second.height), (500, 400));
        expect(stored(env), [second.file]);

        // 移除：先问；取消就不动
        await tapKey(tester, 'bg-remove');
        expect(find.text('移除背景图片？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester, rounds: 2);
        expect(backdropStateOf(env).light.hasImage, isTrue);
        await tapKey(tester, 'bg-remove');
        await tester.tap(find.widgetWithText(TextButton, '移除').last);
        await pumpUntil(tester, find.byKey(const Key('bg-empty')));
        await settle(tester, rounds: 3);
        expect(backdropStateOf(env).light.hasImage, isFalse);
        expect(stored(env), isEmpty);
        expect(find.byKey(const Key('bg-pick')), findsOneWidget);
      });

      testWidgets('深色时单独设置：多出“浅色 / 深色”切换；深色那份另选图，不动浅色的', (tester) async {
        final env = await newEnv(tester);
        final light = await seedBackdrop(tester, env, width: 600, height: 900);
        await open(tester, env);
        expect(find.byKey(const Key('bg-slot')), findsNothing);
        await tapKey(tester, 'bg-dark-separate', rounds: 3);
        expect(backdropStateOf(env).darkSeparate, isTrue);
        expect(find.byKey(const Key('bg-slot')), findsOneWidget);
        expect(backdropStateOf(env).dark.file, light.file, reason: '第一次打开先抄浅色那份');

        await tester.ensureVisible(find.byKey(const Key('bg-slot')));
        await tester.pump();
        await tester.tap(find.text('深色外观'));
        await settle(tester, rounds: 2);
        await tapKey(tester, 'bg-brightness-minus');
        await tapKey(tester, 'bg-brightness-minus');
        expect(backdropStateOf(env).dark.brightness, -10);
        expect(backdropStateOf(env).light.brightness, 0);

        await tester.runAsync(() async => useFakePicker(env, [BackdropPicked(writePick(env.tmp, 'night.png', await makePng(400, 800)))]));
        await tapKey(tester, 'bg-replace', rounds: 1);
        await cropReady(tester);
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await pumpUntil(tester, find.byKey(const Key('bg-preview')));
        await settle(tester, rounds: 3);
        expect(backdropStateOf(env).dark.file, isNot(light.file));
        expect(backdropStateOf(env).dark.brightness, -10, reason: '换图不丢效果');
        expect(backdropStateOf(env).light.file, light.file);
        expect(stored(env), hasLength(2));
        await shot(tester, 'bg-settings-dark-separate-$suffix');
      });
    });

    group('裁剪页 ($suffix)', () {
      /// 摆一个“打开裁剪页”的按钮，裁剪页交回来的结果记进 [results]。
      Future<void> launch(WidgetTester tester, TestEnv env, BackdropLook look, List<BackdropCropResult?> results, {bool fresh = true, String? path}) async {
        final file = path ?? backdropStoreOf(env).imageFile(look.file!).path;
        await tester.pumpWidget(
          appFor(
            env,
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async => results.add(
                      await Navigator.of(context).push<BackdropCropResult>(
                        MaterialPageRoute(
                          builder: (_) => BackdropCropScreen(path: file, look: look, settings: backdropStateOf(env), fresh: fresh),
                        ),
                      ),
                    ),
                    child: const Text('打开裁剪'),
                  ),
                ),
              ),
            ),
            mode: mode,
            font: kTestFont,
          ),
        );
        await tester.tap(find.text('打开裁剪'));
        await settle(tester, rounds: 3);
      }

      String zoomText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('bg-crop-zoom-value'))).data!;

      testWidgets('拖动、双指缩放、步进、重置、效果预览、确认回传', (tester) async {
        final env = await newEnv(tester);
        await seedBackdrop(tester, env, width: 600, height: 900, scene: true);
        final look = backdropStateOf(env).light;
        final results = <BackdropCropResult?>[];
        await launch(tester, env, look, results);
        await cropReady(tester);
        expect(find.text('裁剪背景'), findsOneWidget);
        expect(zoomText(tester), '1.00×');
        final area = find.byKey(const ValueKey('bg-crop-area'));
        final areaRect = tester.getRect(area);
        final frame = cropFrame(areaRect.size, phone);
        expect(frame.width / frame.height, closeTo(phone, 1e-6), reason: '选框是手机屏幕的比例');
        expect(frame.left, greaterThanOrEqualTo(16));
        await shot(tester, 'bg-crop-$suffix');

        // 双指捏开：放大
        final center = areaRect.center;
        final a = await tester.createGesture(pointer: 7);
        final b = await tester.createGesture(pointer: 8);
        await a.down(center - const Offset(30, 0));
        await b.down(center + const Offset(30, 0));
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await a.moveBy(const Offset(-10, 0));
          await b.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await tester.pump();
        final zoomed = double.parse(zoomText(tester).replaceAll('×', ''));
        expect(zoomed, greaterThan(1.5));

        // 单指拖到头：停在边上
        await tester.drag(area, const Offset(-3000, -3000), touchSlopX: 0, touchSlopY: 0);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await settle(tester, rounds: 3);
        expect(results, hasLength(1));
        final r = results.single!;
        expect(r.turns, 0);
        expect(r.crop.right, closeTo(1, 1e-9));
        expect(r.crop.bottom, closeTo(1, 1e-9));
        expect(pixelAspect(r.crop, 600, 900), closeTo(phone, 1e-6));

        // 再进来（不是新图）：回到刚才的区域；步进、重置、效果预览
        await launch(tester, env, look.copyWith(crop: r.crop), results, fresh: false);
        await cropReady(tester);
        expect(double.parse(zoomText(tester).replaceAll('×', '')), closeTo(zoomed, 0.13));
        await tester.tap(find.byKey(const ValueKey('bg-crop-reset')));
        await tester.pump();
        expect(zoomText(tester), '1.00×');
        expect(tester.widget<IconButton>(find.byKey(const Key('bg-crop-zoom-minus'))).onPressed, isNull);
        await tester.tap(find.byKey(const Key('bg-crop-zoom-plus')));
        await tester.pump();
        expect(zoomText(tester), '1.25×');
        expect(find.byKey(const ValueKey('bg-crop-preview')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('bg-crop-preview-toggle')));
        await settle(tester, rounds: 2);
        expect(find.byKey(const ValueKey('bg-crop-preview')), findsOneWidget);
        expect(find.byKey(const ValueKey('bg-sample-text')), findsOneWidget);
        expect(find.byKey(const ValueKey('bg-sample-bubble')), findsOneWidget);
        expect(tester.getRect(find.byKey(const ValueKey('bg-crop-preview'))).width, closeTo(frame.width, 0.5), reason: '预览正好盖在选框上');
        await shot(tester, 'bg-crop-preview-$suffix');
        // 预览开着也能拖
        await tester.drag(area, const Offset(40, 0), touchSlopX: 0);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await settle(tester, rounds: 3);
        expect(results, hasLength(2));
        expect(results.last!.crop.width, closeTo(CropMath(imageWidth: 600, imageHeight: 900, aspect: phone).initial().width / 1.25, 1e-6));
        expect(tester.takeException(), isNull);
      });

      testWidgets('旋转 90°：区域重置成居中最大，比例按转过以后的图算；退出不交结果', (tester) async {
        final env = await newEnv(tester);
        await seedBackdrop(tester, env, width: 900, height: 500);
        final look = backdropStateOf(env).light;
        final results = <BackdropCropResult?>[];
        await launch(tester, env, look, results);
        await cropReady(tester);
        await tester.tap(find.byKey(const Key('bg-crop-zoom-plus')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('bg-crop-rotate')));
        await tester.pump();
        expect(zoomText(tester), '1.00×');
        await tester.tap(find.byKey(const ValueKey('bg-crop-done')));
        await settle(tester, rounds: 3);
        final r = results.single!;
        expect(r.turns, 1);
        // 转过以后是 500×900
        expect(pixelAspect(r.crop, 500, 900), closeTo(phone, 1e-6));
        expect(r.crop.centerX, closeTo(0.5, 1e-9));

        // 转四下回到原样
        await launch(tester, env, look, results);
        await cropReady(tester);
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(const ValueKey('bg-crop-rotate')));
          await tester.pump();
        }
        await tester.tap(find.byTooltip('返回'));
        await settle(tester, rounds: 3);
        expect(results, hasLength(2));
        expect(results.last, isNull, reason: '退出来不算确认');
      });

      testWidgets('图读不出来：说清楚，按钮都点不了，不崩', (tester) async {
        final env = await newEnv(tester);
        final results = <BackdropCropResult?>[];
        await launch(tester, env, const BackdropLook(file: 'bg-gone.png', width: 100, height: 100), results, path: '${env.tmp.path}/nowhere/bg-gone.png');
        await pumpUntil(tester, find.byKey(const ValueKey('bg-crop-failed')));
        expect(find.byKey(const ValueKey('bg-crop-failed')), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byKey(const ValueKey('bg-crop-done'))).onPressed, isNull);
        expect(tester.widget<IconButton>(find.byKey(const Key('bg-crop-zoom-plus'))).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
