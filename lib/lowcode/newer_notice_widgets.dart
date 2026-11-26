// 设计约束（低代码 · “这个页面是新版做的”那一条 · 390×844）
// - 什么时候有：打开的页面文件版本号比这一版认识的大。贴在悬浮顶栏下面、盖在画布最上沿，一行字 + 右边一个“知道了”。
// - 内容主次：只有一句话——这是新版做的、看不懂的部分会原样留着。没有主操作；“知道了”是文字按钮，点了这次不再显示
//   （重新打开页面还会再说一次：不能默默的）。
// - 不拦着她改：能认出来的照常改，存盘时版本号不往回写、看不懂的原样写回（见 docs/lowcode-page-format-v3.md）。
// - 取用的 tokens：Space.x2/x3/x4、Radii.sm、warningSoft（底）、warning（图标）、text。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/newer_notice.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

class LcNewerNotice extends StatelessWidget {
  const LcNewerNotice({super.key, required this.doc, required this.onDismiss});
  final LcDocument doc;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      child: Material(
        key: const ValueKey('lc-newer-notice'),
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.x3, top: Space.x2, bottom: Space.x2),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: c.warning),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(lcNewerNoticeText(doc), style: t.bodySmall?.copyWith(color: c.text)),
              ),
              TextButton(key: const ValueKey('lc-newer-notice-ok'), onPressed: onDismiss, child: const Text('知道了')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把那一条摆在搭建台上面（悬浮顶栏的下沿）。页面不是新版做的就只有 [child]。
class LcNewerNoticeHost extends StatefulWidget {
  const LcNewerNoticeHost({super.key, required this.doc, required this.child});
  final LcDocument doc;
  final Widget child;

  @override
  State<LcNewerNoticeHost> createState() => _LcNewerNoticeHostState();
}

class _LcNewerNoticeHostState extends State<LcNewerNoticeHost> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.doc.isFromNewer || _dismissed) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: PageBar.insetOf(context) + Space.x1,
          child: LcNewerNotice(doc: widget.doc, onDismiss: () => setState(() => _dismissed = true)),
        ),
      ],
    );
  }
}
