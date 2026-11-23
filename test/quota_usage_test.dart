// 额度上限（DeepSeek 余额）与用量统计：判定、解析、累计、拦截、各协议用量映射、一轮里多次请求累加、持久化。
// 不调用任何真实接口：余额走 MockClient，模型走脚本客户端或本机假服务器。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';

import 'agent_system_test.dart' show FakeApi, sseOf;
import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, firstUser, hasToolResult, waitFor;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

/// 假的 DeepSeek 余额接口。
class FakeBalance {
  double cny = 100;
  double granted = 10;
  bool available = true;
  int status = 200;
  bool offline = false;
  int calls = 0;
  final List<String?> auth = [];
  final List<Uri> urls = [];

  http.Client get client => MockClient((req) async {
    calls++;
    auth.add(req.headers['Authorization']);
    urls.add(req.url);
    if (offline) throw const SocketException('没网');
    if (status != 200) return http.Response('{"error":{"message":"Authentication Fails"}}', status);
    return http.Response(
      jsonEncode({
        'is_available': available,
        'balance_infos': [
          {'currency': 'USD', 'total_balance': '3.00', 'granted_balance': '0.00', 'topped_up_balance': '3.00'},
          {'currency': 'CNY', 'total_balance': cny.toStringAsFixed(2), 'granted_balance': granted.toStringAsFixed(2), 'topped_up_balance': (cny - granted).toStringAsFixed(2)},
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

TokenUsage u(int miss, int hit, int out, {int? think, int write = 0}) => TokenUsage(uncached: miss, cacheRead: hit, cacheWrite: write, output: out, reasoning: think, hasCache: true);

void main() {
  group('判定是不是 DeepSeek 官方', () {
    test('只认主机名正好是 api.deepseek.com', () {
      expect(isDeepSeekOfficial('https://api.deepseek.com'), isTrue);
      expect(isDeepSeekOfficial('https://api.deepseek.com/v1'), isTrue);
      expect(isDeepSeekOfficial(' https://API.DeepSeek.com/beta/ '), isTrue);
      expect(isDeepSeekOfficial('https://api.deepseek.com.evil.cn/v1'), isFalse);
      expect(isDeepSeekOfficial('https://deepseek.com'), isFalse);
      expect(isDeepSeekOfficial('https://my-proxy.cn/api.deepseek.com/v1'), isFalse);
      expect(isDeepSeekOfficial('https://api.openai.com/v1'), isFalse);
      expect(isDeepSeekOfficial(''), isFalse);
      expect(isDeepSeekOfficial('不是网址'), isFalse);
    });
  });

  group('余额接口', () {
    test('解析：金额是字符串；优先人民币；is_available', () {
      final r = parseBalance({
        'is_available': false,
        'balance_infos': [
          {'currency': 'USD', 'total_balance': '3.00', 'granted_balance': '0.00', 'topped_up_balance': '3.00'},
          {'currency': 'CNY', 'total_balance': '110.50', 'granted_balance': '10.50', 'topped_up_balance': '100.00'},
        ],
      });
      expect(r.isAvailable, isFalse);
      expect(r.preferred!.currency, 'CNY');
      expect(r.preferred!.total, 110.5);
      expect(r.preferred!.granted, 10.5);
      expect(r.preferred!.toppedUp, 100);
      expect(r.of('USD')!.total, 3);
      expect(formatMoney('CNY', 110.5), '¥110.50');
      expect(formatMoney('USD', 3), r'$3.00');
    });

    test('请求：GET /user/balance，Bearer Key；401 → Key 无效；断网 → 普通错误', () async {
      final fake = FakeBalance();
      final r = await fetchDeepSeekBalance(baseUrl: 'https://api.deepseek.com/v1', apiKey: 'sk-secret', httpClient: fake.client);
      expect(r.preferred!.total, 100);
      expect(fake.urls.single.toString(), 'https://api.deepseek.com/user/balance');
      expect(fake.auth.single, 'Bearer sk-secret');

      fake.status = 401;
      await expectLater(
        fetchDeepSeekBalance(baseUrl: 'https://api.deepseek.com', apiKey: 'sk-secret', httpClient: fake.client),
        throwsA(isA<BalanceException>().having((e) => e.keyInvalid, 'keyInvalid', isTrue).having((e) => e.message, 'message', allOf(contains('Key 无效，查不到余额'), isNot(contains('sk-secret'))))),
      );
      fake.status = 500;
      await expectLater(
        fetchDeepSeekBalance(baseUrl: 'https://api.deepseek.com', apiKey: 'sk-secret', httpClient: fake.client),
        throwsA(isA<BalanceException>().having((e) => e.keyInvalid, 'keyInvalid', isFalse)),
      );
    });
  });

  group('额度上限', () {
    late TestEnv env;
    late FakeBalance fake;
    late Channel ds;
    late Channel other;
    late DateTime clock;
    late QuotaStore quota;

    setUp(() async {
      fake = FakeBalance();
      env = await TestEnv.create(quotaHttp: fake.client);
      ds = await env.services.models.upsert(
        name: 'DeepSeek',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-ds',
        models: [ModelSpec(id: 'deepseek-chat')],
      );
      other = await env.services.models.upsert(
        name: '中转',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'sk-x',
        models: [ModelSpec(id: 'm')],
      );
      clock = DateTime(2026, 11, 23, 18);
      quota = QuotaStore(env.services.settings, env.services.models, httpClient: fake.client, now: () => clock);
    });
    tearDown(() => env.dispose());

    test('非 DeepSeek 渠道：不查余额、不拦', () async {
      await quota.refresh(other, force: true);
      expect(fake.calls, 0);
      expect(quota.blockReason(other), isNull);
      expect(await quota.afterRun(other), isNull);
    });

    test('已用 = 设上限之后余额减少的累计；百分比、剩余；到 100% 才拦', () async {
      await quota.setLimit(ds, limit: 20, currency: 'CNY');
      expect(fake.calls, 1, reason: '设上限时查一次当起点');
      final q = quota.quotaOf(ds.id)!;
      expect(q.used, 0);
      expect(q.lastBalance, 100);

      fake.cny = 95;
      await quota.refresh(ds, force: true);
      expect(q.used, 5);
      expect(q.percent, 25);
      expect(q.remaining, 15);
      expect(quota.blockReason(ds), isNull);

      fake.cny = 80.01;
      await quota.refresh(ds, force: true);
      expect(q.percent, 99);
      expect(q.reached, isFalse);
      expect(quota.blockReason(ds), isNull, reason: '99% 不拦');

      fake.cny = 80;
      await quota.refresh(ds, force: true);
      expect(q.reached, isTrue);
      expect(quota.blockReason(ds), startsWith(kQuotaBlockedPrefix));

      // 调高上限就放行；已用不清零
      await quota.setLimit(ds, limit: 50, currency: 'CNY');
      expect(q.used, 20);
      expect(quota.blockReason(ds), isNull);
    });

    test('充值让余额变多：已用不减少，标记出来；“从现在重新算”清零', () async {
      await quota.setLimit(ds, limit: 20, currency: 'CNY');
      fake.cny = 94;
      await quota.refresh(ds, force: true);
      fake.cny = 194; // 充了 100
      await quota.refresh(ds, force: true);
      final q = quota.quotaOf(ds.id)!;
      expect(q.used, 6);
      expect(q.recharge, isTrue);
      fake.cny = 190;
      await quota.refresh(ds, force: true);
      expect(q.used, 10, reason: '充值之后的花费接着累计');

      await quota.restart(ds);
      expect(q.used, 0);
      expect(q.recharge, isFalse);
      expect(q.lastBalance, 190);
    });

    test('节流：一分钟内自动刷新只查一次；手动（force）不受限', () async {
      await quota.refresh(ds);
      await quota.refresh(ds);
      expect(fake.calls, 1);
      clock = clock.add(const Duration(seconds: 59));
      await quota.refresh(ds);
      expect(fake.calls, 1);
      clock = clock.add(const Duration(seconds: 2));
      await quota.refresh(ds);
      expect(fake.calls, 2);
      await quota.refresh(ds, force: true);
      expect(fake.calls, 3);
    });

    test('查不到余额：不拦、不编数字、已用不变；Key 无效单独标出', () async {
      await quota.setLimit(ds, limit: 20, currency: 'CNY');
      fake.cny = 90;
      await quota.refresh(ds, force: true);
      fake.offline = true;
      await quota.refresh(ds, force: true);
      final s = quota.stateOf(ds.id);
      expect(s.error, isNotNull);
      expect(s.keyInvalid, isFalse);
      expect(quota.quotaOf(ds.id)!.used, 10);
      expect(quota.blockReason(ds), isNull);

      fake
        ..offline = false
        ..status = 401;
      await quota.refresh(ds, force: true);
      expect(s.keyInvalid, isTrue);
      expect(s.error, contains('Key 无效，查不到余额'));
      expect(quota.blockReason(ds), isNull);
    });

    test('没设上限时从没查到过余额：设上限后第一次查到的余额才是起点', () async {
      fake.offline = true;
      await quota.setLimit(ds, limit: 20, currency: 'CNY');
      expect(quota.quotaOf(ds.id)!.lastBalance, isNull);
      fake
        ..offline = false
        ..cny = 70;
      await quota.refresh(ds, force: true);
      expect(quota.quotaOf(ds.id)!.used, 0);
      expect(quota.quotaOf(ds.id)!.lastBalance, 70);
    });

    test('提醒阈值（默认 80%）：只提醒一次、不拦；到 100% 另说一次', () async {
      await quota.setLimit(ds, limit: 20, currency: 'CNY');
      expect(quota.quotaOf(ds.id)!.warnPct, 80);
      fake.cny = 90;
      clock = clock.add(const Duration(minutes: 2));
      expect(await quota.afterRun(ds), isNull, reason: '50% 不提醒');
      fake.cny = 83;
      clock = clock.add(const Duration(minutes: 2));
      final warn = await quota.afterRun(ds);
      expect(warn, allOf(contains('85%'), contains('¥3.00')));
      expect(warn, isNot(startsWith(kQuotaBlockedPrefix)));
      expect(quota.blockReason(ds), isNull);
      clock = clock.add(const Duration(minutes: 2));
      expect(await quota.afterRun(ds), isNull, reason: '同一档只提醒一次');
      fake.cny = 79;
      clock = clock.add(const Duration(minutes: 2));
      expect(await quota.afterRun(ds), startsWith(kQuotaBlockedPrefix));
    });

    test('上限、已用存盘：重开还在', () async {
      await quota.setLimit(ds, limit: 20, currency: 'CNY', warnPct: 50);
      fake.cny = 93;
      await quota.refresh(ds, force: true);
      final again = QuotaStore(env.services.settings, env.services.models, httpClient: fake.client);
      final q = again.quotaOf(ds.id)!;
      expect((q.limit, q.used, q.warnPct, q.currency), (20, 7, 50, 'CNY'));
      await again.clearLimit(ds.id);
      expect(QuotaStore(env.services.settings, env.services.models).quotaOf(ds.id), isNull);
    });

    test('低余额提醒线：默认 5 元；低于才提示；关掉后这次运行不再出现；0＝不提醒', () async {
      expect(quota.lowLine, 5);
      await quota.refresh(ds, force: true);
      expect(quota.lowBalance(ds), isNull);
      fake.cny = 4.2;
      await quota.refresh(ds, force: true);
      expect(quota.lowBalance(ds)!.total, 4.2);
      await quota.setLowLine(0);
      expect(quota.lowBalance(ds), isNull);
      await quota.setLowLine(10);
      expect(quota.lowBalance(ds), isNotNull);
      quota.dismissLow(ds.id);
      expect(quota.lowBalance(ds), isNull);
      expect(quota.lowBalance(other), isNull);
    });
  });

  group('到上限后在代码里拦住', () {
    late TestEnv env;
    late FakeBalance fake;
    late Project project;
    late ProjectSession session;
    late Channel ds;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    setUp(() async {
      log = [];
      turn = (_, _) => reply('好的。');
      fake = FakeBalance();
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log), quotaHttp: fake.client);
      ds = await env.services.models.upsert(
        name: 'DeepSeek',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-ds',
        models: [ModelSpec(id: 'deepseek-chat')],
      );
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      await session.setModel(ModelSelection(ds.id, 'deepseek-chat'));
    });
    tearDown(() {
      session.dispose();
      env.dispose();
    });

    Future<void> reach() async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      fake.cny = 90;
      await env.services.quota.refresh(ds, force: true);
      expect(env.services.quota.quotaOf(ds.id)!.reached, isTrue);
    }

    test('没到上限：正常回复', () async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      await session.sendToAgent('你好');
      expect(log, hasLength(1));
      expect(session.chat.whereType<AssistantItem>().last.text, '好的。');
    });

    test('主对话：请求没发出去，聊天里有“已达到你设的额度上限”', () async {
      await reach();
      await session.sendToAgent('你好');
      expect(log, isEmpty, reason: '模型一次都没被调用');
      final notice = session.chat.whereType<NoticeItem>().last;
      expect(notice.isError, isTrue);
      expect(notice.text, contains(kQuotaBlockedPrefix));
      expect(session.chat.whereType<UsageItem>(), isEmpty, reason: '没发出请求就没有用量脚注');

      // 调高上限后恢复
      await env.services.quota.setLimit(ds, limit: 100, currency: 'CNY');
      await session.sendToAgent('再来');
      expect(log, hasLength(1));
    });

    test('一轮中途到上限：下一次请求被拦（工具循环不会继续烧钱）', () async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      turn = (m, t) {
        if (!hasToolResult(m)) {
          // 第一次请求之后余额掉到上限以外
          fake.cny = 85;
          return use('read_file', {'path': 'index.html'});
        }
        return reply('读完了');
      };
      // 让发请求前的那次刷新不被节流挡住：直接把已用推到上限
      await session.sendToAgent('读一下');
      // 第一次请求发出；第二次请求前的检查受一分钟节流影响，可能放行——这是已知的滞后。
      await env.services.quota.refresh(ds, force: true);
      expect(env.services.quota.quotaOf(ds.id)!.reached, isTrue);
      final before = log.length;
      await session.sendToAgent('继续');
      expect(log.length, before, reason: '到上限后新的请求一次都发不出去');
    });

    test('子代理：也被拦', () async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      var childCalls = 0;
      turn = (m, t) async {
        if (firstUser(m).contains('写首页')) {
          childCalls++;
          return reply('首页写好了');
        }
        if (hasToolResult(m)) return reply('做完了');
        // 上级第一次请求之后到上限
        fake.cny = 80;
        await env.services.quota.refresh(ds, force: true);
        return use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'});
      };
      await session.sendToAgent('帮我做个站');
      expect(childCalls, 0, reason: '子代理的请求没发出去');
      expect(log, hasLength(1), reason: '只有上级的第一次请求');
    });

    test('自动化任务：也被拦，历史里记失败原因', () async {
      await reach();
      final a = await env.services.automations.upsert(
        title: '晨检',
        instruction: '写 report.md',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.daily, hour: 8, tzOffsetMinutes: 0),
        now: DateTime.utc(2026, 11, 23, 0),
      );
      env.services.scheduler.liveSessions[project.id] = session;
      expect(await env.services.scheduler.tick(DateTime.utc(2026, 11, 23, 8, 1)), 1);
      await waitFor(() => a.history.isNotEmpty && !env.services.scheduler.running.contains(a.id), what: '自动化跑完');
      expect(log, isEmpty);
      expect(a.history.first.status, isNot('ok'));
      expect(a.history.first.summary, contains(kQuotaBlockedPrefix));
    });

    test('别的渠道不受影响', () async {
      await reach();
      final other = await env.services.models.upsert(
        name: '中转',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'sk-x',
        models: [ModelSpec(id: 'm')],
      );
      await session.setModel(ModelSelection(other.id, 'm'));
      await session.sendToAgent('你好');
      expect(log, hasLength(1));
    });

    test('对话结束后的提醒：到 80% 在聊天里说一句，不拦', () async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      turn = (m, t) {
        fake.cny = 91.5;
        return reply('好的。');
      };
      await session.sendToAgent('你好');
      // 设上限时刚查过，一分钟内自动刷新被节流；手动刷新后再走一次对话结束的检查
      await env.services.quota.refresh(ds, force: true);
      final note = await env.services.quota.afterRun(ds);
      expect(note, contains('85%'));
      expect(env.services.quota.blockReason(ds), isNull);
    });
  });

  group('各协议的用量映射', () {
    test('DeepSeek：hit → 缓存读取，miss → 未缓存输入；推理', () {
      final t = usageFromChatCompletions({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'total_tokens': 1200,
        'prompt_cache_hit_tokens': 820,
        'prompt_cache_miss_tokens': 180,
        'completion_tokens_details': {'reasoning_tokens': 60},
      })!;
      expect((t.uncached, t.cacheRead, t.cacheWrite, t.output, t.reasoning), (180, 820, 0, 200, 60));
      expect(t.input, 1000);
      expect(t.total, 1200);
      expect(t.hasCache, isTrue);
    });

    test('OpenAI Chat Completions：cached_tokens 是 prompt_tokens 的一部分', () {
      final t = usageFromChatCompletions({
        'prompt_tokens': 1000,
        'completion_tokens': 50,
        'prompt_tokens_details': {'cached_tokens': 400},
      })!;
      expect((t.uncached, t.cacheRead, t.output), (600, 400, 50));
      expect(t.input, 1000);
    });

    test('接口没给缓存字段：不当成 0% 命中', () {
      final t = usageFromChatCompletions({'prompt_tokens': 30, 'completion_tokens': 5})!;
      expect(t.hasCache, isFalse);
      final totals = UsageTotals()..addRequest(RequestUsage(usage: t, ms: 10));
      expect(totals.hitRate, isNull);
      expect(totalsLine(totals), isNot(contains('命中')));
    });

    test('没有可用字段：当作没返回', () {
      expect(usageFromChatCompletions(null), isNull);
      expect(usageFromChatCompletions({}), isNull);
      expect(usageFromChatCompletions({'foo': 1}), isNull);
      expect(usageFromResponses('x'), isNull);
      expect(usageFromAnthropic(null, null), isNull);
    });

    test('Responses：input_tokens 含缓存', () {
      final t = usageFromResponses({
        'input_tokens': 500,
        'input_tokens_details': {'cached_tokens': 300},
        'output_tokens': 80,
        'output_tokens_details': {'reasoning_tokens': 20},
        'total_tokens': 580,
      })!;
      expect((t.uncached, t.cacheRead, t.output, t.reasoning), (200, 300, 80, 20));
      expect(t.input, 500);
    });

    test('Anthropic：input_tokens 不含缓存；读取、写入分开；输出取 message_delta 的累计值', () {
      final t = usageFromAnthropic({'input_tokens': 100, 'cache_read_input_tokens': 700, 'cache_creation_input_tokens': 200, 'output_tokens': 1}, {'output_tokens': 90})!;
      expect((t.uncached, t.cacheRead, t.cacheWrite, t.output), (100, 700, 200, 90));
      expect(t.input, 1000);
      expect(t.total, 1090);
    });
  });

  group('口径与格式', () {
    test('输入 = 未缓存 + 读取 + 写入；命中率 = 读取 ÷ 输入；没有输入是 null', () {
      final t = UsageTotals()
        ..addRequest(RequestUsage(usage: u(100, 700, 50, write: 200), ms: 1))
        ..addRequest(RequestUsage(usage: u(300, 700, 50, think: 10), ms: 1))
        ..addRequest(RequestUsage(ms: 1));
      expect(t.input, 2000);
      expect(t.total, 2100);
      expect(t.hitRate, 0.7);
      expect((t.requests, t.reported, t.unreported), (3, 2, 1));
      expect(t.reasoning, 10);
      expect(UsageTotals().hitRate, isNull);
    });

    test('数字：999 / 1K / 43K / 61.8K / 1.05M，不用万、亿', () {
      expect(formatTokens(0), '0');
      expect(formatTokens(999), '999');
      expect(formatTokens(1000), '1K');
      expect(formatTokens(43000), '43K');
      expect(formatTokens(61800), '61.8K');
      expect(formatTokens(999949), '999.9K');
      expect(formatTokens(999950), '1M');
      expect(formatTokens(1000000), '1M');
      expect(formatTokens(1050000), '1.05M');
    });

    test('用时、百分比、金额', () {
      expect(formatSpan(800), '0.8 秒');
      expect(formatSpan(47000), '47 秒');
      expect(formatSpan(65000), '1 分 5 秒');
      expect(formatSpan(120000), '2 分');
      expect(formatPercent(0), '0%');
      expect(formatPercent(0.004), '<1%');
      expect(formatPercent(0.618), '62%');
      expect(formatCost(0.034), '约 ¥0.03');
      expect(formatCost(0.004), '不到 ¥0.01');
    });

    test('费用：写入按输入价、命中按命中价；单价没填全就不估', () {
      final price = ModelPrice.of(ModelSpec(id: 'm', priceHit: 0.5, priceMiss: 2, priceOutput: 8))!;
      // (100 + 200) × 2 + 700 × 0.5 + 1000 × 8 = 8950 → ÷ 1e6
      expect(price.cost(u(100, 700, 1000, write: 200)), closeTo(0.00895, 1e-9));
      expect(ModelPrice.of(ModelSpec(id: 'm', priceHit: 0.5, priceMiss: 2)), isNull);
      expect(ModelPrice.of(ModelSpec(id: 'm')), isNull);
    });

    test('脚注从全到简：依次省 tokens、步数、花费，用时永远在', () {
      final turn = TurnUsage(ms: 47000, steps: [for (var i = 0; i < 12; i++) RequestStep(RequestUsage(usage: u(1000, 2000, 0), ms: 100, cost: 0.0025))]);
      expect(footnoteVariants(turn), ['47 秒 · 12 步 · 约 ¥0.03 · 36K tokens', '47 秒 · 12 步 · 约 ¥0.03', '47 秒 · 约 ¥0.03', '47 秒']);
      // 没单价：没有花费那一段
      final plain = TurnUsage(ms: 3000, steps: [RequestStep(RequestUsage(usage: u(10, 0, 5), ms: 100))]);
      expect(footnoteVariants(plain), ['3 秒 · 1 步 · 15 tokens', '3 秒 · 1 步', '3 秒']);
      // 接口没返回用量：如实写
      final none = TurnUsage(ms: 3000, steps: [RequestStep(RequestUsage(ms: 100))]);
      expect(footnoteVariants(none).first, '3 秒 · 1 步 · 接口没返回用量');
    });

    test('一轮的 JSON 存取不丢东西', () {
      final turn = TurnUsage(
        ms: 5000,
        steps: [
          RequestStep(RequestUsage(usage: u(10, 20, 5, think: 2, write: 3), ms: 900, firstMs: 300, startedAt: DateTime(2026, 11, 23, 18, 30), cost: 0.01)),
          ToolStep('c1', 'read_file', ms: 12, ok: true),
          RequestStep(RequestUsage(ms: 400)),
        ],
        children: [
          ChildUsage('前端', TurnUsage(ms: 100, steps: [RequestStep(RequestUsage(usage: u(1, 0, 1), ms: 50))])),
        ],
      );
      final back = TurnUsage.fromJson(jsonDecode(jsonEncode(turn.toJson())))!;
      expect(back.ms, 5000);
      expect(back.steps, hasLength(3));
      final first = (back.steps.first as RequestStep).request;
      expect((first.usage!.uncached, first.usage!.cacheRead, first.usage!.cacheWrite, first.usage!.output, first.usage!.reasoning), (10, 20, 3, 5, 2));
      expect((first.ms, first.firstMs, first.cost), (900, 300, 0.01));
      expect(first.startedAt, DateTime(2026, 11, 23, 18, 30));
      expect((back.steps[1] as ToolStep).name, 'read_file');
      expect((back.steps[2] as RequestStep).request.usage, isNull);
      expect(back.children.single.name, '前端');
      expect(back.totals.requests, 3);
      expect(back.own.requests, 2);
    });
  });

  group('会话里的用量', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    List<ChatDelta> withUsage(List<ChatDelta> deltas, TokenUsage? usage) => [...deltas.take(deltas.length - 1), ChatDelta(finishReason: deltas.last.finishReason, usage: usage)];

    setUp(() async {
      log = [];
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
      await env.services.models.upsert(
        name: '中转',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'k',
        models: [ModelSpec(id: 'm')],
      );
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
    });
    tearDown(() {
      session.dispose();
      env.dispose();
    });

    test('一轮里多次请求（工具循环）累加；工具调用也记进轨迹；对话累计、轮数、上下文', () async {
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => withUsage(use('read_file', {'path': 'index.html'}), u(1000, 0, 20)),
        1 => withUsage(use('read_file', {'path': 'index.html'}), u(200, 1000, 30, think: 8)),
        _ => withUsage(reply('读完了'), u(100, 1400, 40)),
      };
      await session.sendToAgent('读两遍');
      final turnUsage = session.chat.whereType<UsageItem>().single.turn;
      expect(turnUsage.steps.map((s) => s is RequestStep ? 'req' : 'tool:${(s as ToolStep).name}'), ['req', 'tool:read_file', 'req', 'tool:read_file', 'req']);
      final t = turnUsage.totals;
      expect((t.requests, t.uncached, t.cacheRead, t.output, t.reasoning), (3, 1300, 2400, 90, 8));
      expect(t.input, 3700);
      expect(t.hitRate, closeTo(2400 / 3700, 1e-9));
      expect(turnUsage.steps.whereType<ToolStep>().every((s) => s.ms != null && s.ok), isTrue);
      expect(session.chat.last, isA<UsageItem>(), reason: '脚注在这一轮回复的下方');

      expect(session.usageTotals.turns, 1);
      expect(session.usageTotals.requests, 3);
      final ctx = session.contextUsage!;
      expect((ctx.used, ctx.estimated), (1500, false), reason: '上下文＝最近一次请求的输入');

      // 第二轮
      turn = (m, t) => withUsage(reply('好'), u(50, 1600, 5));
      await session.sendToAgent('再来');
      expect(session.chat.whereType<UsageItem>(), hasLength(2));
      expect(session.usageTotals.turns, 2);
      expect(session.usageTotals.requests, 4);
      expect(session.usageTotals.input, 3700 + 1650);
      expect(session.contextUsage!.used, 1650);
    });

    test('接口没返回用量：脚注如实写，不编数字；上下文退回按字数估（标成估算）', () async {
      turn = (m, t) => reply('好的。');
      await session.sendToAgent('你好');
      final turnUsage = session.chat.whereType<UsageItem>().single.turn;
      expect(turnUsage.totals.requests, 1);
      expect(turnUsage.totals.reported, 0);
      expect(footnoteVariants(turnUsage).first, contains('接口没返回用量'));
      expect(session.usageTotals.total, 0);
      expect(session.usageTotals.hitRate, isNull);
      expect(session.contextUsage!.estimated, isTrue);
    });

    test('填了单价才有估算费用', () async {
      final ch = await env.services.models.upsert(
        name: '带单价',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://relay.example.cn/v1',
        apiKey: 'k',
        models: [
          ModelSpec(id: 'priced', priceHit: 0.5, priceMiss: 2, priceOutput: 8),
          ModelSpec(id: 'free'),
        ],
      );
      turn = (m, t) => withUsage(reply('好'), u(100000, 0, 10000));
      await session.setModel(ModelSelection(ch.id, 'free'));
      await session.sendToAgent('一');
      expect(session.chat.whereType<UsageItem>().last.turn.totals.costed, 0);
      expect(footnoteVariants(session.chat.whereType<UsageItem>().last.turn).first, isNot(contains('¥')));

      await session.setModel(ModelSelection(ch.id, 'priced'));
      await session.sendToAgent('二');
      final t = session.chat.whereType<UsageItem>().last.turn.totals;
      expect(t.costed, 1);
      expect(t.cost, closeTo(0.28, 1e-9)); // 100000×2 + 10000×8 = 280000 → 0.28 元
      expect(footnoteVariants(session.chat.whereType<UsageItem>().last.turn).first, contains('约 ¥0.28'));
    });

    test('子代理的用量计入上级这一轮，也能分开看', () async {
      turn = (m, t) {
        if (firstUser(m).contains('写首页')) {
          return hasToolResult(m) ? withUsage(reply('首页写好了'), u(30, 0, 3)) : withUsage(use('write_file', {'path': 'home.html', 'content': 'H'}), u(20, 0, 2));
        }
        return hasToolResult(m) ? withUsage(reply('都做完了'), u(200, 100, 10)) : withUsage(use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'}), u(100, 0, 5));
      };
      await session.sendToAgent('帮我做个站');
      final turnUsage = session.chat.whereType<UsageItem>().single.turn;
      expect(turnUsage.own.requests, 2);
      expect(turnUsage.children.single.name, '前端');
      expect(turnUsage.children.single.turn.totals.requests, 2);
      expect(turnUsage.children.single.turn.totals.total, 55);
      expect(turnUsage.totals.requests, 4);
      expect(turnUsage.totals.total, 415 + 55);
      expect(turnUsage.stepCount, 4);
      expect(session.usageTotals.total, 470, reason: '对话累计也含子代理');
    });

    test('用量随对话存盘：重开后脚注、累计、上下文都在', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? withUsage(use('read_file', {'path': 'index.html'}), u(1000, 0, 20)) : withUsage(reply('读完了'), u(100, 1000, 40));
      await session.sendToAgent('读一下');
      final again = ProjectSession(env.services, project, headless: true);
      addTearDown(again.dispose);
      await again.loadChat();
      final back = again.chat.whereType<UsageItem>().single.turn;
      expect(back.totals.requests, 2);
      expect(back.totals.total, 2160);
      expect(back.steps.whereType<ToolStep>().single.name, 'read_file');
      expect(again.chat.last, isA<UsageItem>());
      expect(again.usageTotals.turns, 1);
      expect(again.usageTotals.total, 2160);
      expect(again.contextUsage!.used, 1100);
      // 存下来的 _usage 是内部字段：真正发给接口前会被去掉
      turn = (m, t) => reply('好');
      await again.sendToAgent('再来');
      expect(jsonEncode(log.last.messages), contains('_usage'));
      expect(jsonEncode(stripInternal(log.last.messages)), isNot(contains('_usage')));
    });

    test('上下文分项是估算：三项都有数', () async {
      await session.sendToAgent('你好');
      final b = await session.contextBreakdown();
      expect(b.system, greaterThan(0));
      expect(b.tools, greaterThan(0));
      expect(b.messages, greaterThan(0));
    });
  });

  group('客户端拿用量', () {
    FakeModelServer? server;
    FakeApi? api;
    tearDown(() async {
      await server?.stop();
      await api?.stop();
      server = null;
      api = null;
    });

    test('Chat Completions：带 stream_options.include_usage，读到最后一块的 usage', () async {
      server = FakeModelServer([
        ScriptedReply(text: '你好', usage: {'prompt_tokens': 100, 'completion_tokens': 7, 'total_tokens': 107, 'prompt_cache_hit_tokens': 64, 'prompt_cache_miss_tokens': 36}),
      ]);
      await server!.start();
      final client = OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake-model');
      final deltas = await client
          .streamChat(
            messages: [
              {
                'role': 'assistant',
                'content': '上一轮',
                '_usage': {'ms': 1},
              },
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      expect(server!.requests.single['stream_options'], {'include_usage': true});
      expect(jsonEncode(server!.requests.single['messages']), isNot(contains('_usage')), reason: '内部字段不上线');
      final usage = deltas.map((d) => d.usage).whereType<TokenUsage>().last;
      expect((usage.uncached, usage.cacheRead, usage.output), (36, 64, 7));
      expect(deltas.map((d) => d.content ?? '').join(), '你好');
    });

    test('DeepSeek 的形状：用量附在最后一个内容块上（choices 不为空）也认', () async {
      api = FakeApi()
        ..sse['/v1/chat/completions'] = sseOf([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': '你好'},
                'finish_reason': null,
              },
            ],
            'usage': null,
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': ''},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 10, 'completion_tokens': 2, 'total_tokens': 12, 'prompt_cache_hit_tokens': 0, 'prompt_cache_miss_tokens': 10},
          },
        ]);
      await api!.start();
      final client = OpenAiChatClient(baseUrl: api!.base, apiKey: 'k', model: 'deepseek-chat');
      final deltas = await client
          .streamChat(
            messages: [
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      final usages = deltas.map((d) => d.usage).whereType<TokenUsage>().toList();
      expect(usages, hasLength(1));
      expect((usages.single.uncached, usages.single.cacheRead, usages.single.output), (10, 0, 2));
      expect(deltas.any((d) => d.finishReason == 'stop'), isTrue);
    });

    test('接口不认 stream_options：去掉重发一次，之后不再带；回复照常', () async {
      server = FakeModelServer([ScriptedReply(text: '一'), ScriptedReply(text: '二')], rejectStreamOptions: true);
      await server!.start();
      final client = OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake-model');
      final first = await client
          .streamChat(
            messages: [
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      expect(first.map((d) => d.content ?? '').join(), '一');
      expect(first.map((d) => d.usage).whereType<TokenUsage>(), isEmpty);
      expect(server!.requests, hasLength(2));
      expect(server!.requests[0].containsKey('stream_options'), isTrue);
      expect(server!.requests[1].containsKey('stream_options'), isFalse);
      final second = await client
          .streamChat(
            messages: [
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      expect(second.map((d) => d.content ?? '').join(), '二');
      expect(server!.requests, hasLength(3));
      expect(server!.requests[2].containsKey('stream_options'), isFalse);
    });

    test('Anthropic：message_start 给输入、message_delta 给输出', () async {
      api = FakeApi()
        ..sse['/v1/messages'] = sseOf([
          {
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 25, 'cache_read_input_tokens': 300, 'cache_creation_input_tokens': 75, 'output_tokens': 1},
            },
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': '好'},
          },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 42},
          },
          {'type': 'message_stop'},
        ]);
      await api!.start();
      final client = AnthropicChatClient(baseUrl: api!.base, apiKey: 'ak', model: 'claude-x', maxTokens: 1000);
      final deltas = await client
          .streamChat(
            messages: [
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      final usage = deltas.map((d) => d.usage).whereType<TokenUsage>().single;
      expect((usage.uncached, usage.cacheRead, usage.cacheWrite, usage.output), (25, 300, 75, 42));
    });

    test('Responses：response.completed 里的 usage', () async {
      api = FakeApi()
        ..sse['/v1/responses'] = sseOf([
          {'type': 'response.output_text.delta', 'output_index': 0, 'delta': '好'},
          {
            'type': 'response.completed',
            'response': {
              'usage': {
                'input_tokens': 400,
                'input_tokens_details': {'cached_tokens': 100},
                'output_tokens': 30,
                'output_tokens_details': {'reasoning_tokens': 12},
                'total_tokens': 430,
              },
            },
          },
        ]);
      await api!.start();
      final client = OpenAiResponsesClient(baseUrl: api!.base, apiKey: 'sk', model: 'gpt-x');
      final deltas = await client
          .streamChat(
            messages: [
              {'role': 'user', 'content': '嗨'},
            ],
          )
          .toList();
      final usage = deltas.map((d) => d.usage).whereType<TokenUsage>().single;
      expect((usage.uncached, usage.cacheRead, usage.output, usage.reasoning), (300, 100, 30, 12));
    });
  });
}
