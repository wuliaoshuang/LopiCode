// 服务商预设的数据守门，以及“现在能不能发消息”的判断。
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/third_party.dart';
import 'package:path/path.dart' as p;

void main() {
  test('预设：id 唯一、地址格式对、有官方来源、图标文件在', () {
    final ids = <String>{};
    final hosts = <String>{};
    for (final preset in kProviderPresets) {
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(preset.id), isTrue, reason: preset.id);
      expect(ids.add(preset.id), isTrue, reason: '预设 id 重复：${preset.id}');
      expect(preset.name.trim(), isNotEmpty);

      final uri = Uri.parse(preset.baseUrl);
      expect(uri.host, isNotEmpty, reason: preset.id);
      expect(uri.hasQuery || uri.hasFragment, isFalse, reason: preset.id);
      expect(preset.baseUrl.endsWith('/'), isFalse, reason: '${preset.id} 地址末尾不带 /');
      expect(preset.baseUrl, preset.baseUrl.trim());
      // 只有本机服务可以是 http
      expect(uri.scheme, preset.keyOptional ? 'http' : 'https', reason: preset.id);
      expect(isLocalBaseUrl(preset.baseUrl), preset.keyOptional, reason: '${preset.id}：不要 Key 的只能是本机地址');
      for (final suffix in ['/chat/completions', '/messages', '/responses', '/models']) {
        expect(preset.baseUrl.endsWith(suffix), isFalse, reason: '${preset.id} 的地址不该带 $suffix');
      }
      // anthropic 协议的地址必须自己带 /v1（代码拼的是 {base}/messages）
      if (preset.protocol == ChatProtocol.anthropic) expect(preset.baseUrl.endsWith('/v1'), isTrue, reason: preset.id);
      expect(hosts.add(preset.host), isTrue, reason: '两个预设用了同一个主机名：${preset.host}');

      final source = Uri.parse(preset.source);
      expect(source.scheme, 'https', reason: '${preset.id} 要有官方文档来源');
      expect(source.host, isNotEmpty);

      final icon = File(preset.iconAsset);
      expect(icon.existsSync(), isTrue, reason: '${preset.iconAsset} 不在');
      final svg = icon.readAsStringSync();
      expect(svg.trimLeft().startsWith('<svg'), isTrue, reason: preset.iconAsset);
      // 单色图标靠 currentColor 着色；彩色图标自己带颜色
      expect(preset.monoIcon, !preset.icon.endsWith('-color'), reason: '${preset.id}：-color 结尾的是彩色图标');
    }
    expect(kProviderPresets.length, greaterThanOrEqualTo(16));
    expect(kPresetsVerifiedOn, '2026-11-23');
  });

  test('随包的图标正好是预设用到的那些，校验值和 third_party 里记的一致', () {
    final used = {for (final preset in kProviderPresets) '${preset.icon}.svg'};
    final present = {for (final f in Directory('assets/provider_icons').listSync().whereType<File>()) p.basename(f.path)};
    expect(present, used, reason: '只带用得到的图标');
    final sums = {for (final line in File('third_party/lobe-icons/SHA256SUMS').readAsLinesSync().where((l) => l.trim().isNotEmpty)) line.split(RegExp(r'\s+')).last: line.split(RegExp(r'\s+')).first};
    expect(sums.keys.toSet(), present);
    for (final entry in sums.entries) {
      final bytes = File(p.join('assets/provider_icons', entry.key)).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), entry.value, reason: '${entry.key} 和登记的校验值不一样（图标不能改内容）');
    }
    expect(File('third_party/lobe-icons/README.md').readAsStringSync(), contains(providerIconPack.version));
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/provider_icons/'));
    expect(File('assets/licenses/lobe-icons-MIT.txt').readAsStringSync(), contains('Copyright (c) 2023 LobeHub'));
    expect(File('third_party/lobe-icons/LICENSE').readAsStringSync(), File('assets/licenses/lobe-icons-MIT.txt').readAsStringSync());
  });

  test('DeepSeek 预设能被额度那边认出是官方渠道', () {
    final deepseek = presetById('deepseek')!;
    expect(isDeepSeekOfficial(deepseek.baseUrl), isTrue);
    for (final preset in kProviderPresets.where((x) => x.id != 'deepseek')) {
      expect(isDeepSeekOfficial(preset.baseUrl), isFalse, reason: preset.id);
    }
  });

  test('按接口地址认服务商：主机名对上才算，中转站不算', () {
    expect(presetForBaseUrl('https://api.deepseek.com/v1')?.id, 'deepseek');
    expect(presetForBaseUrl('api.deepseek.com')?.id, 'deepseek');
    expect(presetForBaseUrl('https://API.OpenAI.com/v1/')?.id, 'openai');
    expect(presetForBaseUrl('https://api.minimaxi.com/v1')?.id, 'minimax');
    expect(presetForBaseUrl('https://deepseek.my-relay.example.com/v1'), isNull);
    expect(presetForBaseUrl('https://api.deepseek.com.evil.example/v1'), isNull);
    expect(presetForBaseUrl(''), isNull);
    expect(presetForBaseUrl('not a url ::'), isNull);
    // Ollama：本机或局域网，端口 11434
    expect(presetForBaseUrl('http://localhost:11434/v1')?.id, 'ollama');
    expect(presetForBaseUrl('http://192.168.1.20:11434/v1')?.id, 'ollama');
    expect(presetForBaseUrl('http://192.168.1.20:8080/v1'), isNull);
    expect(presetById('nope'), isNull);
    expect(presetById(null), isNull);
  });

  test('本机 / 局域网地址的判断', () {
    for (final url in [
      'http://localhost:11434/v1',
      'http://127.0.0.1:8080',
      'http://10.0.0.5/v1',
      'http://192.168.31.2:1234/v1',
      'http://172.16.0.1',
      'http://172.31.255.1',
      'http://my-pc.local:11434',
    ]) {
      expect(isLocalBaseUrl(url), isTrue, reason: url);
    }
    for (final url in ['https://api.deepseek.com', 'http://172.32.0.1', 'http://11.0.0.1', 'http://192.169.1.1', '', 'http://999.1.1.1', 'https://localhost.example.com']) {
      expect(isLocalBaseUrl(url), isFalse, reason: url);
    }
  });

  group('现在能不能发消息', () {
    late Directory tmp;
    late ModelConfigStore store;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('lopi_ready_');
      final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
      await settings.load();
      store = ModelConfigStore(settings, MemorySecretStore());
      await store.load();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('没有渠道 → 缺渠道', () async {
      final gap = await store.readiness();
      expect(gap?.kind, ModelGapKind.noChannel);
      expect(gap?.channel, isNull);
    });

    test('有渠道没模型 → 缺模型，指到那个渠道', () async {
      final ch = await store.upsert(name: 'DeepSeek', protocol: ChatProtocol.openaiChat, baseUrl: 'https://api.deepseek.com', apiKey: 'sk-x');
      final gap = await store.readiness();
      expect(gap?.kind, ModelGapKind.noModel);
      expect(gap?.channel?.id, ch.id);
      expect(gap!.message, contains('DeepSeek'));
    });

    test('有模型没 Key → 缺 Key；填了 Key → 可以发', () async {
      final ch = await store.upsert(
        name: 'DeepSeek',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://api.deepseek.com',
        models: [ModelSpec(id: 'm1')],
      );
      var gap = await store.readiness();
      expect(gap?.kind, ModelGapKind.noKey);
      expect(gap?.channel?.id, ch.id);
      await store.upsert(id: ch.id, name: 'DeepSeek', protocol: ChatProtocol.openaiChat, baseUrl: 'https://api.deepseek.com', apiKey: 'sk-x');
      gap = await store.readiness();
      expect(gap, isNull);
    });

    test('本机服务不要求 Key', () async {
      await store.upsert(
        name: 'Ollama',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'http://192.168.1.9:11434/v1',
        models: [ModelSpec(id: 'qwen')],
      );
      expect(await store.readiness(), isNull);
    });

    test('对话选的模型缺 Key：即使别的渠道是好的也要提示', () async {
      await store.upsert(
        name: '好的',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://a.example.com/v1',
        apiKey: 'k',
        models: [ModelSpec(id: 'a')],
      );
      final bad = await store.upsert(
        name: '缺 Key',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://b.example.com/v1',
        models: [ModelSpec(id: 'b')],
      );
      expect(await store.readiness(), isNull);
      final gap = await store.readiness(store.resolve(ModelSelection(bad.id, 'b')));
      expect(gap?.kind, ModelGapKind.noKey);
      expect(gap?.channel?.id, bad.id);
    });
  });
}
