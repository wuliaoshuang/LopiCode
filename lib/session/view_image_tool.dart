// view_image 工具：让模型直接看工作区里的一张图片（png / jpg / gif / webp）。
//
// - 只读工具（ToolKind.read）：所有权限档位、计划模式下都能用；路径照旧过路径守卫（工作区外、.lopicode 里的读不了）。
// - 规矩和用户发图片附件一样（lib/session/attachments.dart）：按扩展名认格式，单张不超过 8MB。
//   另外多查一步文件头：扩展名是图片、内容不是的，不交给模型（否则接口会拒掉整次请求，而且这条记录留在历史里，后面每次都会被拒）。
// - 这里只返回路径和大小；图片内容不进聊天记录，发请求时由 AgentRunner 现读（lib/agent/tool_images.dart）。
// - 只有模型开了“支持看图”才会被加进工具箱（lib/session/toolbox_builder.dart）。
import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/attachments.dart';

const String kViewImageTool = 'view_image';

/// 按文件头认图片类型；认不出返回 null。
String? sniffImageMime(List<int> head) {
  bool starts(List<int> sig, [int at = 0]) {
    if (head.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'image/png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  return null;
}

String _size(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).toStringAsFixed(1)} KB';

ExtraTool viewImageTool(PathGuard guard) => ExtraTool(
  spec: toolSpec(
    kViewImageTool,
    '查看工作区里的一张图片（png、jpg、gif、webp，不超过 8MB）：图片会交给你直接看。用来核对截图、设计稿、素材。只带最近看的几张，较早看过的需要时再看一次。',
    {
      'path': {'type': 'string', 'description': '图片在项目里的相对路径'},
    },
    ['path'],
  ),
  kind: ToolKind.read,
  run: (args) async {
    final rel = AgentToolbox.argString(args, 'path');
    final full = guard.resolve(rel);
    final shown = guard.relative(full);
    if (imageMimeOf(rel) == null) return ToolOutcome('错误：$shown 不是能看的图片。只支持 png、jpg、gif、webp；别的文件用 read_file 读。', ok: false);
    final file = File(full);
    if (!await file.exists()) return ToolOutcome('错误：文件不存在：$shown', ok: false);
    final bytes = await file.length();
    if (bytes == 0) return ToolOutcome('错误：$shown 是空文件。', ok: false);
    if (bytes > kMaxAttachmentBytes) return ToolOutcome('错误：$shown 有 ${_size(bytes)}，超过 ${kMaxAttachmentBytes ~/ 1024 ~/ 1024}MB 的上限，没有交给你。可以先用命令把它缩小再看。', ok: false);
    final handle = await file.open();
    final List<int> head;
    try {
      head = await handle.read(16);
    } finally {
      await handle.close();
    }
    // 以文件头为准（把 jpg 存成 .png 的很常见）；文件头认不出就不交。
    final mime = sniffImageMime(head);
    if (mime == null) return ToolOutcome('错误：$shown 的扩展名是图片，但内容不是 png / jpg / gif / webp，没有交给你。', ok: false);
    return ToolOutcome(
      '已读取图片 $shown（$mime，${_size(bytes)}）。图片内容在紧接着的一条消息里。',
      images: [
        {'path': shown, 'mime': mime, 'bytes': bytes},
      ],
    );
  },
);
