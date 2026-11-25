// 工具结果里带的图片（view_image）怎么交给模型。
//
// 三种协议里“工具结果带图片”的合法写法不一样（见 docs/api-notes.md“工具结果带图片”一节）：
// Chat Completions 的 tool 消息只许文字；Anthropic 的 tool_result、Responses 的 function_call_output 可以带图片块。
// 我们的历史统一存成 Chat Completions 的样子，所以用三家都合法的最保守做法：
// 工具结果只回文字（路径、大小），图片放在紧跟在这一批工具结果后面的一条 user 消息里，
// 用的就是用户发图片附件的那条老路（image_url → 各协议自己再转）。
//
// 聊天记录里只存 `_images: [{path, mime, bytes}]`（路径和大小），不存图片内容；每次发请求时现读文件。
import 'dart:convert';

/// 只把最近这么多次“看图”的图片带进请求；更早的不再带（工具结果里的文字还在，模型需要可以再看一次）。
/// 一张图大约 1000 多个 token，每次请求都要重发，所以不能一直攒着。
const int kToolImagesKept = 3;

/// 历史里哪些 tool 消息的图片这次还要带上（按在 [messages] 里的下标）。
Set<int> toolImageMessagesToSend(List<Map<String, dynamic>> messages) {
  final at = <int>[
    for (var i = 0; i < messages.length; i++)
      if (messages[i]['role'] == 'tool' && messages[i]['_archived'] != true && messages[i]['_images'] is List && (messages[i]['_images'] as List).isNotEmpty) i,
  ];
  return at.skip(at.length > kToolImagesKept ? at.length - kToolImagesKept : 0).toSet();
}

/// 把一批工具结果带的图片拼成紧随其后的那条 user 消息。
/// 模型不能看图、或者文件现在读不到了：不带图片，只用文字说清楚。
Future<Map<String, dynamic>> toolImagesMessage(List<Object?> images, {required bool vision, required Future<List<int>?> Function(String path)? loadImage}) async {
  final parts = <Map<String, dynamic>>[];
  final shown = <String>[];
  final failed = <String>[];
  for (final img in images) {
    if (img is! Map) continue;
    final path = '${img['path']}';
    final bytes = vision ? await loadImage?.call(path) : null;
    if (bytes == null) {
      failed.add(path);
      continue;
    }
    shown.add(path);
    parts.add({
      'type': 'image_url',
      'image_url': {'url': 'data:${img['mime'] is String ? img['mime'] : 'image/png'};base64,${base64Encode(bytes)}'},
    });
  }
  final text = [
    if (shown.isNotEmpty) '（这不是用户说的话：下面是你刚才用 view_image 查看的图片，按顺序是 ${shown.join('、')}。）',
    if (failed.isNotEmpty) '（这不是用户说的话：${failed.join('、')} 没能交给你——${vision ? '文件现在读不到了' : '当前模型不能看图'}。）',
  ].join('\n');
  if (parts.isEmpty) return {'role': 'user', 'content': text};
  return {
    'role': 'user',
    'content': [
      {'type': 'text', 'text': text},
      ...parts,
    ],
  };
}
