// 切换模型时设思考等级（2026-11-25 霜霜真机反馈第 4 条）。390×844，浅色 + 深色：
// 没标记的模型就地打开“可思考”、档位按模型记住、底部固定区在模型很多时也看得见、
// 只能开关 / 调不了的服务商显示成真实的样子、输入区模型按钮上的档位标记。
// 思考参数没核对过的服务商：面板和模型设置里都只有一句说明，没有开关和档位。
//   LOPI_SHOTS=1 flutter test test/model_picker_thinking_test.dart   # 同时写截图到 docs/screenshots/
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/model_level_mark.dart';
import 'package:lopicode/ui/model_picker_sheet.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_model_sheets.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/harness.dart';

/// 一个只有“选模型”按钮的页面：点了像聊天页那样弹出面板，把结果记下来。
class PickerHost extends StatefulWidget {
  const PickerHost({super.key, this.current, required this.onResult});
  final ModelSelection? current;
  final ValueChanged<Object?> onResult;
  @override
  State<PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<PickerHost> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () async {
          final r = await showModalBottomSheet<Object>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => ModelPickerSheet(current: widget.current),
          );
          widget.onResult(r);
        },
        child: const Text('选模型'),
      ),
    ),
  );
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    Object? result;

    Future<void> boot(WidgetTester tester) async {
      usePhoneViewport(tester);
      result = null;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
    }

    Future<Channel> add(WidgetTester tester, String name, String baseUrl, List<ModelSpec> models, {ChatProtocol protocol = ChatProtocol.openaiChat}) async {
      late Channel ch;
      await tester.runAsync(() async => ch = await env.services.models.upsert(name: name, protocol: protocol, baseUrl: baseUrl, apiKey: 'sk-demo', models: models));
      return ch;
    }

    Future<void> open(WidgetTester tester, {ModelSelection? current}) async {
      await tester.pumpWidget(
        appFor(
          env,
          PickerHost(key: UniqueKey(), current: current, onResult: (r) => result = r),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      await tester.tap(find.text('选模型'));
      await settle(tester, rounds: 4);
    }

    /// 分段按钮上现在有哪些字（按顺序）。
    List<String> segments(WidgetTester tester) {
      final f = find.byKey(const ValueKey('thinking-levels'));
      if (f.evaluate().isEmpty) return const [];
      return [for (final s in tester.widget<SegmentedButton<String>>(f).segments) (s.label! as Text).data!];
    }

    testWidgets('没标记“可思考”的模型：这一段还在，就地打开后立刻出现档位，选的档位按模型记住 ($suffix)', (tester) async {
      await boot(tester);
      final ch = await add(tester, '我的中转站', 'https://api.example.com/v1', [ModelSpec(id: 'gpt-plain', name: '普通模型'), ModelSpec(id: 'gpt-other', name: '另一个模型', thinking: true)]);
      await open(tester, current: ModelSelection(ch.id, 'gpt-plain'));

      expect(find.byKey(const ValueKey('thinking-section')), findsOneWidget, reason: '没标记也不能整段消失');
      expect(find.text('这个模型没有标记为可思考'), findsOneWidget);
      expect(segments(tester), isEmpty, reason: '没打开之前不给档位');
      final row = tester.getSize(find.byKey(const ValueKey('thinking-mark')));
      expect(row.height, greaterThanOrEqualTo(44));
      await shot(tester, 'think-01-unmarked-$suffix');

      // 就地打开
      await tester.tap(find.byKey(const ValueKey('thinking-mark')));
      await settle(tester, rounds: 4);
      expect(env.services.models.channel(ch.id)!.model('gpt-plain')!.thinking, isTrue, reason: '标记存在模型上');
      expect(find.text('这个模型没有标记为可思考'), findsNothing);
      expect(segments(tester), ['默认', '低', '中', '高']);
      expect(find.textContaining('档位越高，思考越久、花的 token 越多'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('thinking-levels'))).height, greaterThanOrEqualTo(44));
      await shot(tester, 'think-02-marked-$suffix');

      await tester.tap(find.text('高'));
      await settle(tester, rounds: 2);
      // 切到别的模型（它自己是“默认”），再切回来：还是“高”
      await tester.tap(find.text('另一个模型'));
      await settle(tester, rounds: 2);
      expect(tester.widget<SegmentedButton<String>>(find.byKey(const ValueKey('thinking-levels'))).selected, {'off'});
      await tester.tap(find.text('普通模型'));
      await settle(tester, rounds: 2);
      expect(tester.widget<SegmentedButton<String>>(find.byKey(const ValueKey('thinking-levels'))).selected, {'high'});

      await tester.tap(find.text('用这个模型'));
      await settle(tester, rounds: 4);
      final picked = (result! as ModelSelectionResult).selection;
      expect((picked.channelId, picked.modelId, picked.level), (ch.id, 'gpt-plain', 'high'));
      expect(env.services.models.thinkingLevelOf(ch.id, 'gpt-plain'), 'high');

      // 聊天换成了别的模型以后再打开面板、切回这个模型：还是上次给它设的“高”
      await open(tester, current: ModelSelection(ch.id, 'gpt-other'));
      await tester.tap(find.text('普通模型'));
      await settle(tester, rounds: 2);
      expect(tester.widget<SegmentedButton<String>>(find.byKey(const ValueKey('thinking-levels'))).selected, {'high'});

      // 标错了可以就地关回去
      await tester.tap(find.byKey(const ValueKey('thinking-mark')));
      await settle(tester, rounds: 4);
      expect(env.services.models.channel(ch.id)!.model('gpt-plain')!.thinking, isFalse);
      expect(segments(tester), isEmpty);
      await tester.tap(find.text('用这个模型'));
      await settle(tester, rounds: 4);
      expect((result! as ModelSelectionResult).selection.level, 'off', reason: '没标记＝不带档位');
    });

    testWidgets('模型很多：“思考深度”和“用这个模型”固定在底部，不用滚就看得见、点得到 ($suffix)', (tester) async {
      await boot(tester);
      final ch = await add(tester, '我的中转站', 'https://api.example.com/v1', [for (var i = 1; i <= 30; i++) ModelSpec(id: 'gpt-model-$i', name: 'model-$i', thinking: true)]);
      await open(tester, current: ModelSelection(ch.id, 'gpt-model-1', 'medium'));
      expect(find.byKey(const ValueKey('thinking-levels')).hitTestable(), findsOneWidget);
      expect(find.text('用这个模型').hitTestable(), findsOneWidget);
      expect(find.text('管理渠道和模型').hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(find.text('管理渠道和模型')).dy, lessThanOrEqualTo(kPhone.height));
      expect(find.text('model-30').hitTestable(), findsNothing, reason: '列表在上面自己滚');
      await shot(tester, 'think-03-many-models-$suffix');
      // 列表滚到底，底部那一截不动
      final before = tester.getTopLeft(find.text('用这个模型'));
      await tester.drag(find.byKey(const ValueKey('model-picker-list')), const Offset(0, -3000));
      await settle(tester, rounds: 2);
      expect(find.text('model-30').hitTestable(), findsOneWidget);
      expect(tester.getTopLeft(find.text('用这个模型')), before);
      await tester.tap(find.text('model-30'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('低'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('用这个模型'));
      await settle(tester, rounds: 4);
      final picked = (result! as ModelSelectionResult).selection;
      expect((picked.modelId, picked.level), ('gpt-model-30', 'low'));
    });

    testWidgets('档位显示成这家真实支持的样子：只有关 / 开、另有“最高”、调不了的写原因 ($suffix)', (tester) async {
      await boot(tester);
      final zhipu = await add(tester, '智谱', 'https://open.bigmodel.cn/api/paas/v4', [ModelSpec(id: 'glm-4.6', thinking: true), ModelSpec(id: 'glm-5.3', thinking: true)]);
      await add(tester, 'DeepSeek', 'https://api.deepseek.com', [ModelSpec(id: 'deepseek-v4-pro', thinking: true)]);
      await add(tester, 'Kimi', 'https://api.moonshot.cn/v1', [ModelSpec(id: 'kimi-k2.7-code', thinking: true)]);
      await open(tester, current: ModelSelection(zhipu.id, 'glm-4.6', 'high'));
      expect(segments(tester), ['关', '开']);
      expect(tester.widget<SegmentedButton<String>>(find.byKey(const ValueKey('thinking-levels'))).selected, {'on'}, reason: '旧存盘里的“高”在只有开关的模型上＝开');
      expect(find.textContaining('只能开或关'), findsOneWidget);
      await shot(tester, 'think-04-on-off-$suffix');

      await tester.tap(find.text('glm-5.3'));
      await settle(tester, rounds: 2);
      expect(segments(tester), ['默认', '低', '高', '最高']);

      await tester.tap(find.text('DeepSeek'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('deepseek-v4-pro'));
      await settle(tester, rounds: 2);
      expect(segments(tester), ['关', '低', '高', '最高']);
      await tester.tap(find.text('最高'));
      await settle(tester, rounds: 2);
      await shot(tester, 'think-05-deepseek-$suffix');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Kimi'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('kimi-k2.7-code'));
      await settle(tester, rounds: 2);
      expect(segments(tester), isEmpty, reason: '调不了就不给点了没用的档位');
      expect(find.textContaining('接口不让调强度'), findsOneWidget);
      await shot(tester, 'think-06-fixed-$suffix');
      await tester.tap(find.text('用这个模型'));
      await settle(tester, rounds: 4);
      expect((result! as ModelSelectionResult).selection.level, 'off');
    });

    testWidgets('思考参数没核对过的服务商：只有一句说明，没有开关、没有档位；旧存盘里标过、记过档位的也一样 ($suffix)', (tester) async {
      await boot(tester);
      // 旧存盘的样子：没核对过的服务商上已经标了“可思考”，还记了“高”
      final ark = await add(tester, '火山方舟', 'https://ark.cn-beijing.volces.com/api/v3', [ModelSpec(id: 'doubao-pro', thinking: true), ModelSpec(id: 'doubao-lite')]);
      final relay = await add(tester, '我的中转站', 'https://api.example.com/v1', [ModelSpec(id: 'my-model', thinking: true), ModelSpec(id: 'deepseek-v4-pro', thinking: true)]);
      await add(tester, '本机', 'http://localhost:11434/v1', [ModelSpec(id: 'qwen3', thinking: true)]);
      await tester.runAsync(() => env.services.models.setThinkingLevel(ark.id, 'doubao-pro', 'high'));
      await open(tester, current: ModelSelection(ark.id, 'doubao-pro', 'high'));

      void expectLocked(String because) {
        expect(find.byKey(const ValueKey('thinking-section')), findsOneWidget, reason: because);
        expect(find.byKey(const ValueKey('thinking-unverified')), findsOneWidget, reason: because);
        expect(find.byKey(const ValueKey('thinking-mark')), findsNothing, reason: '$because：没有就地开关');
        expect(find.byType(Switch), findsNothing, reason: because);
        expect(segments(tester), isEmpty, reason: '$because：没有档位');
        expect(find.byKey(const ValueKey('thinking-note')), findsNothing, reason: because);
        expect(find.textContaining('可思考'), findsNothing, reason: '$because：列表里也不写“可思考”');
      }

      expectLocked('标过的');
      expect(find.textContaining('火山方舟（豆包）的思考参数还没对着官方文档核对过，暂时不能在这里调'), findsOneWidget);
      expect(find.textContaining('请求里不带任何思考参数'), findsOneWidget);
      expect(find.text('用这个模型').hitTestable(), findsOneWidget);
      await shot(tester, 'think2-01-unverified-provider-$suffix');

      // 没标过的模型：同一句话，同样没有开关
      await tester.tap(find.text('doubao-lite'));
      await settle(tester, rounds: 2);
      expectLocked('没标过的');

      // 选它：不带档位；以前记的“高”留着不动
      await tester.tap(find.text('doubao-pro'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('用这个模型'));
      await settle(tester, rounds: 4);
      final picked = (result! as ModelSelectionResult).selection;
      expect((picked.channelId, picked.modelId, picked.level), (ark.id, 'doubao-pro', 'off'));
      expect(env.services.models.thinkingLevelOf(ark.id, 'doubao-pro'), 'high', reason: '记住的档位不清掉，只是不用');
      expect(env.services.models.resolve(picked)!.level, 'off');

      // 自己填的中转站：认不出的模型是说明，认得出的（DeepSeek）照常有档位
      await open(tester, current: ModelSelection(relay.id, 'my-model', 'high'));
      expect(find.byKey(const ValueKey('thinking-unverified')), findsOneWidget);
      expect(find.byKey(const ValueKey('thinking-mark')), findsNothing);
      expect(segments(tester), isEmpty);
      expect(find.textContaining('从模型名认不出是哪家的模型'), findsOneWidget);
      await shot(tester, 'think2-02-unverified-relay-$suffix');
      await tester.tap(find.text('deepseek-v4-pro'));
      await settle(tester, rounds: 2);
      expect(find.byKey(const ValueKey('thinking-unverified')), findsNothing);
      expect(find.byKey(const ValueKey('thinking-mark')), findsOneWidget);
      expect(segments(tester), ['关', '低', '高', '最高']);
      await shot(tester, 'think2-03-relay-known-model-$suffix');

      // 本机服务
      await tester.tap(find.widgetWithText(ChoiceChip, '本机'));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('qwen3'));
      await settle(tester, rounds: 2);
      expectLocked('本机');
    });

    testWidgets('模型设置面板和选模型面板说的是同一句话：没核对过的没有“可以思考”开关，存着的标记不动 ($suffix)', (tester) async {
      await boot(tester);
      Object? saved;
      Future<void> openSpec(ModelSpec m, String baseUrl) async {
        saved = null;
        await tester.pumpWidget(
          appFor(
            env,
            Scaffold(
              key: UniqueKey(),
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async => saved = await showModalBottomSheet<Object>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => ModelSpecSheet(model: m, protocol: ChatProtocol.openaiChat, baseUrl: baseUrl),
                    ),
                    child: const Text('改模型'),
                  ),
                ),
              ),
            ),
            mode: mode,
            font: kTestFont,
          ),
        );
        await settle(tester, rounds: 2);
        await tester.tap(find.text('改模型'));
        await settle(tester, rounds: 4);
      }

      Future<void> confirm() async {
        await tester.scrollUntilVisible(find.text('确定'), 200, scrollable: find.byType(Scrollable).last);
        await tester.ensureVisible(find.text('确定'));
        await settle(tester, rounds: 2);
        await tester.tap(find.text('确定'));
        await settle(tester, rounds: 4);
      }

      // 没核对过：没有开关和档位，只有说明
      final old = ModelSpec(id: 'doubao-pro', thinking: true, levels: const ['high']);
      await openSpec(old, 'https://ark.cn-beijing.volces.com/api/v3');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('spec-thinking-unverified')), 200, scrollable: find.byType(Scrollable).last);
      await settle(tester, rounds: 2);
      expect(find.byKey(const ValueKey('spec-thinking')), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('火山方舟（豆包）的思考参数还没对着官方文档核对过，暂时不能在这里调'), findsOneWidget);
      await shot(tester, 'think2-04-spec-unverified-$suffix');
      await confirm();
      final kept = saved! as ModelSpec;
      expect(kept.thinking, isTrue, reason: '改不了的东西原样交回，不偷偷清掉');
      expect(kept.levels, ['high']);

      // 核对过：开关和档位都在
      await openSpec(ModelSpec(id: 'deepseek-v4-pro', thinking: true), 'https://api.deepseek.com');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('spec-thinking')), 200, scrollable: find.byType(Scrollable).last);
      await settle(tester, rounds: 2);
      expect(find.byKey(const ValueKey('spec-thinking-unverified')), findsNothing);
      expect(find.byType(FilterChip), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('spec-thinking')));
      await settle(tester, rounds: 2);
      await confirm();
      expect((saved! as ModelSpec).thinking, isFalse);
    });

    testWidgets('输入区的模型按钮：开了思考就带一个小标记，没开只有名字 ($suffix)', (tester) async {
      await boot(tester);
      final ch = await add(tester, '我的中转站', 'https://api.example.com/v1', [ModelSpec(id: 'gpt-demo', name: '名字特别特别长的主力模型', thinking: true), ModelSpec(id: 'mini-demo')]);
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await env.services.models.setThinkingLevel(ch.id, 'gpt-demo', 'high');
        await session.setModel(ModelSelection(ch.id, 'gpt-demo', 'high'));
      });
      addTearDown(session.dispose);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 6);
      // 模型按钮在输入框展开（点进去）以后才出现
      await tester.tap(find.byType(TextField));
      await settle(tester, rounds: 3);
      final button = find.byKey(const ValueKey('model-button'));
      expect(find.descendant(of: button, matching: find.text(' · 高')), findsOneWidget);
      expect(tester.getSize(button).width, lessThanOrEqualTo(132), reason: '名字再长也不把按钮撑宽');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await shot(tester, 'think-07-composer-mark-$suffix');

      await tester.runAsync(() => session.setModel(ModelSelection(ch.id, 'mini-demo')));
      await settle(tester, rounds: 4);
      expect(find.descendant(of: button, matching: find.text('mini-demo')), findsOneWidget);
      expect(find.byKey(const ValueKey('model-level-mark')), findsNothing);
    });

    testWidgets('模型按钮上的字单独拿出来用：给了档位就显示，拿不到聊天页就只有名字 ($suffix)', (tester) async {
      await boot(tester);
      await tester.pumpWidget(
        appFor(
          env,
          const Scaffold(
            body: Column(
              children: [
                ModelButtonLabel(name: '甲'),
                ModelButtonLabel(name: '乙', level: 'max'),
                ModelButtonLabel(name: '丙', level: 'on'),
              ],
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 2);
      expect(find.byKey(const ValueKey('model-level-mark')), findsNWidgets(2));
      expect(find.text(' · 最高'), findsOneWidget);
      expect(find.text(' · 开'), findsOneWidget);
    });
  }
}
