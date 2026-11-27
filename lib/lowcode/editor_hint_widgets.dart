import 'package:lopicode/lowcode/editor_selection_bar_widgets.dart';
import 'package:lopicode/lowcode/editor_toolbar_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 搭建台里的一句提示（“已复制…”）：浮在工具条和选中条**上面**。
/// 用全应用那种贴底的提示会把撤销 / 重做盖住好几秒（测试里点撤销点到了提示上才发现）。
void showEditorHint(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, kEditorToolbarHeight + kEditorSelectionBarHeight + Space.x2),
      ),
    );
}
