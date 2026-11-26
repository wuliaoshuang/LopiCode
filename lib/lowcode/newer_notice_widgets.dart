// 设计约束（低代码 · “这个页面是新版做的”那一条 · 390×844）
// - 什么时候有：打开的页面文件版本号比这一版认识的大。贴在悬浮顶栏下面，一行字 + 右边一个“知道了”。
//   它不盖在页面上：画布会把页面顶边往下让出它的高度（由 canvas_banner_widgets.dart 摆、量高度）。
// - 内容主次：只有一句话——这是新版做的、看不懂的部分会原样留着。没有主操作；“知道了”是文字按钮，点了这次不再显示
//   （重新打开页面还会再说一次：不能默默的）。
// - 不拦着她改：能认出来的照常改，存盘时版本号不往回写、看不懂的原样写回（见 docs/lowcode-page-format-v3.md）。
// - 取用的 tokens：Space.x2/x3/x4、Radii.sm、warningSoft（底）、warning（图标）、text。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/newer_notice.dart';
import 'package:lopicode/theme/tokens.dart';
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
