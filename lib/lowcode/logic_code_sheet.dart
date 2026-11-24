// 设计约束（看生成的 JavaScript · 390×844）— 2026-11-24
// - 只读：标题 + 一行说明 + 等宽的代码（自动换行，可上下滚、可选中）+ 底下唯一的主操作“复制全部”。
//   面板本身复用搭建页现成的 CodeSheetBody，样子和“看 Flutter 代码”一致。
// - 逻辑是空的时候不显示空白代码框，直接说明为什么是空的、下一步做什么。
import 'package:lopicode/lowcode/builder_screen.dart' show CodeSheetBody;
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 打开“生成的 JavaScript”面板。
Future<void> showLcCodeSheet(BuildContext context, LcDocument doc) => showLcSheet<void>(context, (_) => LcCodeSheet(doc: doc));

class LcCodeSheet extends StatelessWidget {
  const LcCodeSheet({super.key, required this.doc});
  final LcDocument doc;

  @override
  Widget build(BuildContext context) {
    final code = exportLogicJs(doc);
    if (code.isEmpty) {
      return LcSheetFrame(
        title: '生成的 JavaScript',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x6),
            child: Text('还没有任何变量和事件，所以没有代码。\n加一个事件、往里放几块积木，这里就会出现翻出来的脚本。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.textMuted, height: 1.6)),
          ),
        ],
      );
    }
    return CodeSheetBody(title: '生成的 JavaScript', note: '导出网页时存成 logic.js。这里只能看；改积木，它会跟着变。', code: code);
  }
}
