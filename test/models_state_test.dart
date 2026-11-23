// 渠道与模型的状态（lib/state/models_state.dart）：不可变快照 + Notifier。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  ModelsState state() => box.read(modelsProvider);
  ModelsNotifier ctl() => box.read(modelsProvider.notifier);

  setUp(() async {
    env = await TestEnv.create();
    box = env.services.container;
  });
  tearDown(() => env.dispose());

  test('一开始是空的：没有渠道、没配好', () {
    expect(state().channels, isEmpty);
    expect(state().configured, isFalse);
    expect(state().defaultForNewChat, isNull);
    expect(state().keyRev, 0);
  });

  test('加渠道、改渠道、删渠道：快照每次换一份新的，旧的那份不变', () async {
    final first = state();
    final ch = await ctl().upsert(
      name: '甲',
      protocol: ChatProtocol.openaiChat,
      baseUrl: ' https://example.invalid/v1 ',
      models: [ModelSpec(id: 'm1')],
    );
    expect(first.channels, isEmpty, reason: '旧快照不跟着变');
    final second = state();
    expect(second.channels.single.name, '甲');
    expect(second.channels.single.baseUrl, 'https://example.invalid/v1', reason: '地址两头的空格去掉');
    expect(second.configured, isTrue);

    final edited = await ctl().upsert(id: ch.id, name: '乙', protocol: ChatProtocol.anthropic, baseUrl: 'https://example.invalid/v2');
    expect(edited.id, ch.id);
    expect(ch.name, '甲', reason: '原来那份渠道对象没被改');
    expect(second.channels.single.name, '甲');
    final third = state();
    expect(third.channels.single.name, '乙');
    expect(third.channels.single.protocol, ChatProtocol.anthropic);
    expect(third.channels.single.models.single.id, 'm1', reason: '没传 models＝不动模型');

    await ctl().remove(ch.id);
    expect(state().channels, isEmpty);
    expect(third.channels, hasLength(1));
  });

  test('名字留空用协议名；渠道和模型拿到手改不了', () async {
    final ch = await ctl().upsert(
      name: '  ',
      protocol: ChatProtocol.openaiResponses,
      baseUrl: 'https://example.invalid/v1',
      models: [ModelSpec(id: 'm1')],
    );
    expect(ch.name, ChatProtocol.openaiResponses.label);
    expect(() => state().channels.add(ch), throwsUnsupportedError);
    expect(() => ch.models.add(ModelSpec(id: 'x')), throwsUnsupportedError);
    expect(() => ch.models.first.levels.add('low'), throwsUnsupportedError);
  });

  test('模型 copyWith：只换传了的；单价整组换，可以清空', () {
    final m = ModelSpec(id: 'm1', name: '主力', contextLength: 64000, vision: true, priceHit: 0.5, priceMiss: 2, priceOutput: 8);
    final a = m.copyWith(name: '改名', thinking: true, levels: ['low']);
    expect((a.id, a.name, a.contextLength, a.vision, a.thinking), ('m1', '改名', 64000, true, true));
    expect(a.levels, ['low']);
    expect((a.priceHit, a.priceMiss, a.priceOutput), (0.5, 2.0, 8.0), reason: '没传 prices＝单价不动');
    final b = m.copyWith(prices: (hit: null, miss: 3, output: null));
    expect((b.priceHit, b.priceMiss, b.priceOutput), (null, 3.0, null));
    expect((m.name, m.priceHit), ('主力', 0.5), reason: '原来那份不变');
    // 存一遍再读回来还是一样
    final back = ModelSpec.fromJson(a.toJson())!;
    expect((back.name, back.thinking, back.priceMiss), ('改名', true, 2.0));
    expect(back.levels, ['low']);
  });

  test('Key：存、换、清都让 keyRev 加一；存一样的不加；Key 本身不进状态', () async {
    final ch = await ctl().upsert(name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: 'sk-one');
    expect(state().keyRev, 1);
    await ctl().upsert(id: ch.id, name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: 'sk-one');
    expect(state().keyRev, 1, reason: '同一个 Key 再存一次不算换');
    await ctl().upsert(id: ch.id, name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: '');
    expect(state().keyRev, 1, reason: '留空＝不动 Key');
    expect(await env.services.models.apiKey(ch.id), 'sk-one');
    await ctl().upsert(id: ch.id, name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://example.invalid/v1', apiKey: 'sk-two');
    expect(state().keyRev, 2);
    await ctl().clearKey(ch.id);
    expect(state().keyRev, 3);
    expect(await env.services.models.hasKey(ch.id), isFalse);
    expect(env.services.models.dump(), isNot(contains('sk-')));
  });

  test('新对话默认：沿用上次 / 固定默认；指向的模型被删了就退到第一个能用的', () async {
    final a = await ctl().upsert(
      name: '甲',
      protocol: ChatProtocol.openaiChat,
      baseUrl: 'https://a.invalid/v1',
      models: [
        ModelSpec(id: 'a1'),
        ModelSpec(id: 'a2', thinking: true),
      ],
    );
    final b = await ctl().upsert(
      name: '乙',
      protocol: ChatProtocol.openaiChat,
      baseUrl: 'https://b.invalid/v1',
      models: [ModelSpec(id: 'b1')],
    );
    expect(state().defaultForNewChat!.model.id, 'a1', reason: '什么都没选过：第一个能用的');
    // 不经过 Notifier（发消息时记“上次用的”就是这样）：快照也跟着换
    await env.services.models.setLastSelection(ModelSelection(b.id, 'b1'));
    expect(state().lastSelection, ModelSelection(b.id, 'b1'));
    expect(state().defaultForNewChat!.model.id, 'b1');
    await ctl().setFixedSelection(ModelSelection(a.id, 'a2', 'high'));
    expect(state().defaultForNewChat!.model.id, 'b1', reason: '还没切到固定默认');
    await ctl().setNewChatUsesFixed(true);
    expect(state().newChatUsesFixed, isTrue);
    final fixed = state().defaultForNewChat!;
    expect((fixed.model.id, fixed.level), ('a2', 'high'));
    expect(state().resolve(ModelSelection(a.id, 'a1', 'high'))!.level, 'off', reason: '模型不支持思考，档位收成关闭');
    await ctl().remove(a.id);
    expect(state().resolve(state().fixedSelection), isNull);
    expect(state().defaultForNewChat!.model.id, 'b1', reason: '固定的那个被删了：退到上次用的');
    // 和存储对象算出来的一致
    expect(env.services.models.defaultForNewChat()!.model.id, 'b1');
  });

  test('启动时从盘上读出来的渠道也进快照（那一次不写设置文件）', () async {
    await ctl().upsert(name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://a.invalid/v1');
    var n = 0;
    box.listen(modelsProvider, (_, _) => n++);
    await env.services.models.load();
    expect(state().channels.single.name, '甲');
    expect(n, greaterThan(0), reason: '重新读盘后通知一次');
  });

  test('容器销毁后存储对象上不留监听；之后再改不报错', () async {
    final bare = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    final store = env.services.models;
    final keys = store.keyListeners.length, chans = store.channelListeners.length;
    bare.read(modelsProvider);
    expect(store.keyListeners.length, keys + 1);
    expect(store.channelListeners.length, chans + 1);
    bare.dispose();
    expect(store.keyListeners.length, keys);
    expect(store.channelListeners.length, chans);
    await store.upsert(name: '甲', protocol: ChatProtocol.openaiChat, baseUrl: 'https://a.invalid/v1', apiKey: 'sk-x');
  });
}
