// 设计约束（添加事件面板 · 390×844）— 2026-11-24
// - 两步都在同一个面板里：先选“什么时候”（点击 / 输入内容变化 / 页面打开，一行一个，带一句说明），
//   点击和输入变化再选“哪个控件”（按页面层级缩进；输入变化只能选输入框，别的灰掉）。
// - 从某个控件点进来的（[preferTarget]）：点击 / 输入变化直接挂在它上面，不再问第二步（它不是输入框时，输入变化仍然要选）。
// - 第二步左上有“换一种事件”可以退回第一步。
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 选好的事件：`target` 只有 load 是 null。
typedef LcEventPick = ({String event, String? target});

/// 这种事件能不能挂在这个控件上（输入变化只有输入框会触发）。
bool lcEventFitsNode(String event, LcNode node) => event != 'input' || node.type == 'input';

Future<LcEventPick?> showLcAddEvent(BuildContext context, LcDocument doc, {String? preferTarget}) => showLcSheet<LcEventPick>(context, (_) => LcAddEventSheet(doc: doc, preferTarget: preferTarget));

class LcAddEventSheet extends StatefulWidget {
  const LcAddEventSheet({super.key, required this.doc, this.preferTarget});
  final LcDocument doc;
  final String? preferTarget;

  @override
  State<LcAddEventSheet> createState() => _LcAddEventSheetState();
}

class _LcAddEventSheetState extends State<LcAddEventSheet> {
  /// 第一步选了哪种事件；null＝还在第一步。
  String? _event;

  void _choose(String event) {
    if (event == 'load') return Navigator.pop(context, (event: event, target: null));
    final prefer = widget.preferTarget == null ? null : widget.doc.find(widget.preferTarget!);
    if (prefer != null && lcEventFitsNode(event, prefer)) return Navigator.pop(context, (event: event, target: prefer.id));
    setState(() => _event = event);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = widget.doc;
    final event = _event;
    final prefer = widget.preferTarget == null ? null : doc.find(widget.preferTarget!);
    if (event == null) {
      String detail(String e, String normal) => prefer != null && lcEventFitsNode(e, prefer) ? '挂在${describeNode(doc, prefer.id)}上' : normal;
      return LcSheetFrame(
        title: '添加事件',
        note: '先选“什么时候”，再往里放积木。',
        children: [
          LcOptionRow(
            key: const ValueKey('lc-event-click'),
            leading: Icon(Icons.touch_app_outlined, color: c.textMuted),
            label: '点击某个控件时',
            detail: detail('click', '比如点按钮'),
            onTap: () => _choose('click'),
          ),
          LcOptionRow(
            key: const ValueKey('lc-event-input'),
            leading: Icon(Icons.keyboard_alt_outlined, color: c.textMuted),
            label: '输入框的内容变化时',
            detail: detail('input', '每打一个字都会触发'),
            onTap: () => _choose('input'),
          ),
          LcOptionRow(
            key: const ValueKey('lc-event-load'),
            leading: Icon(Icons.play_circle_outline_rounded, color: c.textMuted),
            label: '页面打开时',
            detail: '页面一准备好就做一次',
            onTap: () => _choose('load'),
          ),
        ],
      );
    }
    var any = false;
    final rows = lcNodeRows(
      doc,
      enabled: (n) {
        final ok = lcEventFitsNode(event, n);
        any = any || ok;
        return ok;
      },
      onPick: (n) => Navigator.pop(context, (event: event, target: n.id)),
    );
    return LcSheetFrame(
      title: event == 'click' ? '点击哪个控件？' : '哪个输入框？',
      note: any ? null : '页面里还没有输入框。先回搭建页加一个，再来添加这种事件。',
      header: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: TextButton.icon(
            key: const ValueKey('lc-event-back'),
            onPressed: () => setState(() => _event = null),
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('换一种事件'),
          ),
        ),
      ),
      children: rows,
    );
  }
}
