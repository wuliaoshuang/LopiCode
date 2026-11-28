// 设计约束（低代码 · 画布顶上的横条 · 390×844）
// - 位置：悬浮顶栏的下沿，一条一行，从上到下最多两条：①“这个页面是新版做的”（newer_notice_widgets.dart）②“正在编辑弹窗”。
// - **不遮挡**：有横条时画布把页面的顶边往下让出横条的高度（搭建台把量到的高度加进画布的 topInset），页面最上面的组件不会被盖住。
//   （第 3 期第 1 段时它是直接盖在画布上的，会挡住顶上的组件。）
// - “正在编辑弹窗”这一条：左边图标 + 一句“正在编辑弹窗：标题”，右边一个实心的“退出”（这是这个状态下唯一的出口，所以给主按钮的分量）。
//   一行只做这一件事；标题太长就省略。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accentSoft（底）、accent（图标）、text。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/newer_notice_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class CanvasBanners extends StatefulWidget {
  const CanvasBanners({super.key, required this.doc, required this.dialog, required this.onExitDialog, required this.onHeight});
  final LcDocument doc;

  /// 正在“只看这个弹层”的那个弹窗；没有是 null。
  final LcNode? dialog;
  final VoidCallback onExitDialog;

  /// 这几条一共多高（没有横条是 0）；变了才通知。
  final void Function(double height) onHeight;

  @override
  State<CanvasBanners> createState() => _CanvasBannersState();
}

class _CanvasBannersState extends State<CanvasBanners> {
  bool _dismissed = false;
  double _height = -1;

  void _measure() {
    if (!mounted) return;
    final h = context.size?.height ?? 0;
    if (h == _height) return;
    _height = h;
    widget.onHeight(h);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final dialog = widget.dialog;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.x1,
      children: [
        if (widget.doc.isFromNewer && !_dismissed) LcNewerNotice(doc: widget.doc, onDismiss: () => setState(() => _dismissed = true)),
        if (dialog != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            child: Material(
              key: const ValueKey('lc-overlay-bar'),
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x1, Space.x1),
                child: Row(
                  children: [
                    Icon(Icons.web_asset_outlined, size: 18, color: c.accent),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        lcIsToast(dialog) ? '正在编辑轻提示：${dialog.strProp('text') ?? ''}' : '正在编辑弹窗：${dialog.name.isNotEmpty ? dialog.name : dialog.strProp('title') ?? '没有标题'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    FilledButton(
                      key: const ValueKey('lc-overlay-exit'),
                      onPressed: widget.onExitDialog,
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('退出'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
