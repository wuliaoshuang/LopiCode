// 设计约束（点开一步看到的详情 · 390×844）— 2026-11-25 按工具分别排
// - 一个浅底的框，限高（先 240，点“显示全部”后 420），里面自己滚；字都是等宽小字，可以长按选中复制。
// - 从上到下一段一段，每段是“淡色小标题一行 + 内容”，一段只说一件事：
//   · 命令 / 后台命令：〔命令〕`$ 命令` →〔输出〕（失败时标题是“报错”、没执行是“没有执行”）→〔退出码〕；
//   · 读文件：〔文件〕路径（读的是其中一段就带“第 a–b 行”）→〔内容〕；
//   · 写文件 / 改文件：最上面是改动对比（step_diff.dart，原样复用）→〔文件〕→〔结果〕；
//   · 其余工具：〔参数〕→〔结果〕。
// - 框底固定一行次要操作，不跟着内容滚：左边“用了多久”，右边“复制结果”；命令输出被转存成文件的多一个“查看完整输出”。
// - 没有主操作；颜色只有两个文字按钮的强调色。
// - 字号跟着“代码字号”走、小一号（默认 12）；在框里双指捏合可以调（和别的代码区域是同一个值）。
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/step_digest.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/step_diff.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 结果先显示这么多字，多的点“显示全部”。
const int kStepResultPreview = 1200;

/// “显示全部”也最多这么多字（再长在手机上也没法看）。
const int kStepResultMax = 20000;

/// 详情框的高度上限：先这么高，点了“显示全部”以后那么高。
const double kStepDetailHeight = 240;
const double kStepDetailFullHeight = 420;

final RegExp _exitStatus = RegExp(r'^退出码 (-?\d+)\s*$');
final RegExp _readHeader = RegExp(r'^（.* 第 (\d+)–(\d+) 行，全文共 (\d+) 行）\n');

/// 一步的参数和结果要显示的几段：（小标题，内容）。
List<(String, String)> stepDetailSections(ToolItem tool) {
  Map<String, dynamic> args = const {};
  try {
    final decoded = jsonDecode(tool.arguments);
    if (decoded is Map<String, dynamic>) args = decoded;
  } on FormatException {
    // 不是合法 JSON：下面按原文显示
  }
  String a(String key) => '${args[key] ?? ''}';
  final result = tool.result;
  final resultTitle = result == null
      ? '结果'
      : tool.denied
      ? '没有执行'
      : tool.ok
      ? '结果'
      : '报错';
  final out = <(String, String)>[];
  switch (tool.name) {
    case 'run_command' || 'start_background_command':
      out.add(('命令', '\$ ${a('command')}'));
      if (result == null) break;
      // 结果是“第一行退出码 + 后面的输出”：拆开排，输出在前、退出码单独一段。认不出这个格式就整段照原样放。
      final nl = result.indexOf('\n');
      final exit = _exitStatus.firstMatch(nl < 0 ? result : result.substring(0, nl))?.group(1);
      if (exit == null) break;
      return out..addAll([(tool.ok ? '输出' : '报错', nl < 0 ? '（没有输出）' : result.substring(nl + 1)), ('退出码', exit)]);
    case 'write_file':
      out
        ..add(('文件', a('path')))
        // 有红绿对比就不再把整份内容重复贴一遍。
        ..addAll([if (!(tool.change?.hasDiff ?? false)) ('写入的内容', a('content'))]);
    case 'edit_file' when tool.change != null || editPreviewOf(tool) != null:
      out.add(('文件', a('path')));
    case 'read_file':
      final header = result == null || !tool.ok ? null : _readHeader.firstMatch(result);
      if (header == null) {
        final from = args['start_line'], to = args['end_line'];
        out.add(('文件', from is int || to is int ? '${a('path')} · 第 ${from is int ? from : 1}–${to is int ? to : '末'} 行' : a('path')));
        break;
      }
      return out..addAll([('文件', '${a('path')} · 第 ${header.group(1)}–${header.group(2)} 行（全文 ${header.group(3)} 行）'), ('内容', result!.substring(header.end))]);
    case 'delete_file' || 'view_image':
      out.add(('文件', a('path')));
    default:
      final raw = tool.arguments.trim();
      if (args.isNotEmpty) {
        out.add(('参数', const JsonEncoder.withIndent('  ').convert(args)));
      } else if (raw.isNotEmpty && raw != '{}') {
        out.add(('参数', raw));
      }
  }
  out.add((tool.name == 'read_file' && result != null && tool.ok && !tool.denied ? '内容' : resultTitle, result ?? '执行中…'));
  return out;
}

class StepDetail extends ConsumerStatefulWidget {
  const StepDetail({super.key, required this.tool});
  final ToolItem tool;

  @override
  ConsumerState<StepDetail> createState() => _StepDetailState();
}

class _StepDetailState extends ConsumerState<StepDetail> {
  bool _full = false;

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '已复制这一步的结果');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tool = widget.tool;
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: ref.watch(compactCodeFontProvider), height: 1.5, color: c.textMuted);
    final sections = stepDetailSections(tool);
    final limit = _full ? kStepResultMax : kStepResultPreview;
    final clipped = sections.any((s) => s.$2.length > kStepResultPreview);
    // 命令输出太长、完整的转存成了文件：给一个整页查看的入口。
    final spilled = spilledOutputPathOf(tool.result);
    final readOutput = ChatRowActions.maybeOf(context)?.readOutput;
    final result = tool.result;
    final ms = tool.ms;
    Widget action(String label, Key key, VoidCallback onTap) => InkWell(
      key: key,
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1, horizontal: Space.x1),
        child: Text(label, style: t.bodySmall?.copyWith(color: c.accent)),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(left: Space.x8, bottom: Space.x2),
      constraints: BoxConstraints(maxHeight: _full ? kStepDetailFullHeight : kStepDetailHeight),
      decoration: BoxDecoration(
        color: BackdropScope.surface(context, c.codeBg, seeThrough: BackdropArea.code),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: CodeZoom(
              child: SingleChildScrollView(
                key: const ValueKey('step-detail-scroll'),
                padding: const EdgeInsets.all(Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StepDiffBlock(tool: tool),
                    for (final (i, (title, body)) in sections.indexed) ...[
                      if (i > 0) const SizedBox(height: Space.x3),
                      Text(title, style: t.bodySmall?.copyWith(color: c.textFaint)),
                      const SizedBox(height: Space.x1),
                      SelectableText(body.length > limit ? '${body.substring(0, limit)}\n…（共 ${body.length} 字，${_full ? '太长，只显示前 $limit 字' : '还有 ${body.length - limit} 字没显示'}）' : body, style: mono),
                    ],
                    if (clipped && !_full)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.x2),
                        child: InkWell(
                          onTap: () => setState(() => _full = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.x1),
                            child: Text('显示全部', style: t.bodySmall?.copyWith(color: c.accent)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 这一行钉在框底，不跟着内容滚走：输出很长时不用先滑到底才看得见。
          if (result != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x2, Space.x2),
              child: Row(
                children: [
                  Expanded(
                    child: ms == null
                        ? const SizedBox.shrink()
                        : Text(
                            '用了 ${formatStepSpan(ms)}',
                            key: const ValueKey('step-detail-span'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: c.textFaint),
                          ),
                  ),
                  if (spilled != null && readOutput != null)
                    action(
                      '查看完整输出',
                      const ValueKey('open-full-output'),
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CommandOutputPage(path: spilled, load: readOutput),
                        ),
                      ),
                    ),
                  const SizedBox(width: Space.x2),
                  action('复制结果', const ValueKey('step-copy'), () => _copy(result)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
