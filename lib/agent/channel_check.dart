// 渠道页的两种检查（都必须由用户点了才发）：
// - 读模型列表（protocols.dart 的 listRemoteModels）：只发 GET，不花钱；这里把失败原因翻成分开说的人话。
// - 测一个模型能不能对话（testModelChat）：发一句极短的话，收到第一段回复就断开——会花一点点额度。
//   用的就是平时对话那个客户端和那套参数（不带工具），所以“测试能过”和“对话能用”是一回事；没有新增任何接口用法。
import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';

/// 一次检查的结果：一句结论 + 下一步怎么办 +（失败时）接口原话。都不含 Key。
class CheckResult {
  const CheckResult({required this.ok, required this.title, this.advice, this.detail, this.suggestManual = false});
  final bool ok;
  final String title;
  final String? advice;
  final String? detail;

  /// 下一步是“手动添加模型 ID”（没有模型列表接口、列表是空的）。
  final bool suggestManual;
}

/// 万一服务端把 Key 原样写在报错里：显示前遮掉。
String hideKey(String text, String apiKey) => apiKey.trim().length < 4 ? text : text.replaceAll(apiKey.trim(), '（Key 已隐藏）');

CheckResult modelListOk(int count) => count == 0
    ? const CheckResult(ok: true, title: '连接正常，但接口给的模型列表是空的', advice: '到第 3 步“手动添加模型 ID”，再点模型右边的“测试”确认能对话。', suggestManual: true)
    : CheckResult(ok: true, title: '连接正常，读到 $count 个模型', advice: '地址和 Key 都能用。只读了模型列表，没有产生对话费用。');

/// 读模型列表失败：分开说是哪一种。
CheckResult modelListFailed(ChatApiException e, {required String apiKey, required bool local}) {
  const manual = '地址确认没错的话，到第 3 步“手动添加模型 ID”，再点模型右边的“测试”确认能对话。';
  final (title, advice, suggestManual) = switch (e is ModelListException ? e.kind : null) {
    ModelListFailure.badKey => ('Key 不能用：服务拒绝了这个 API Key', '回第 1 步检查 Key：有没有填错、过期、欠费，粘贴时有没有多带空格。', false),
    ModelListFailure.noListEndpoint => ('这个地址没有模型列表接口', '两种可能：接口地址填错了（比如少了 /v1）；或者这家服务本来就不提供模型列表。$manual', true),
    ModelListFailure.timeout => ('超时：等了 20 秒没有回应', local ? '检查本机 / 局域网的服务有没有启动，地址和端口对不对。' : '检查手机网络；也可能是接口地址填错了，或者这个地址在你的网络里访问不了。', false),
    ModelListFailure.unreachable => ('地址不通：连不上这个接口地址', local ? '检查本机 / 局域网的服务有没有启动，地址和端口对不对。' : '检查接口地址有没有填错，手机有没有联网。', false),
    ModelListFailure.notAList => ('地址有回应，但给的不是模型列表', '多半是接口地址填错了（比如填成了网页地址）。$manual', true),
    ModelListFailure.other => ('服务返回了错误', '原因看下面接口的原话；稍后可以再试一次。', false),
    null => ('接口地址不对', '回第 1 步检查接口地址。', false),
  };
  return CheckResult(ok: false, title: title, advice: advice, detail: hideKey(e.message, apiKey), suggestManual: suggestManual);
}

/// 测 [model] 能不能对话：发一句 “hi”，收到第一段回复（文字或思考）就断开。会花一点点额度，只能由用户点了才调。
/// 超时沿用对话的（连接 60 秒）。
Future<CheckResult> testModelChat({required ChatProtocol protocol, required String baseUrl, required String apiKey, required ModelSpec model, http.Client? httpClient}) async {
  final client = httpClient ?? http.Client();
  try {
    final chat = buildChatClient(
      ResolvedModel(Channel(id: 'check', name: '', protocol: protocol, baseUrl: baseUrl), model, 'off'),
      apiKey,
      httpClient: client,
    );
    var answered = false;
    await for (final d in chat.streamChat(
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
    )) {
      if ((d.content ?? '').isNotEmpty || (d.reasoning ?? '').isNotEmpty || d.toolCalls.isNotEmpty) {
        answered = true;
        break; // 不等它说完：少花一点
      }
    }
    return answered ? const CheckResult(ok: true, title: '能对话：收到了回复') : const CheckResult(ok: false, title: '接口没报错，但没有返回任何内容', advice: '检查模型 ID 是不是和服务商文档里写的一样。');
  } on ChatApiException catch (e) {
    return CheckResult(ok: false, title: '不能对话', detail: hideKey(e.message, apiKey));
  } on Exception catch (e) {
    return CheckResult(ok: false, title: '不能对话', detail: hideKey(shortError(e), apiKey));
  } finally {
    if (httpClient == null) client.close();
  }
}
