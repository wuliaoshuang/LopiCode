// 输入区模型按钮上的字：模型名，后面跟一个很小的思考档位标记（“· 高”）。没开思考就只有名字。
//
// 设计约束：按钮最宽 132，名字放不下时省略名字、标记始终完整；标记用小一号的次要色，不抢名字。
// 档位从外层的聊天页拿（这样不用改聊天页传参）；单独拿输入区出来用 / 测时拿不到，就只显示名字。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:material_ui/material_ui.dart';

class ModelButtonLabel extends StatelessWidget {
  const ModelButtonLabel({super.key, required this.name, this.level});
  final String name;

  /// 直接给档位（测试 / 别处复用）；不给就从外层聊天页的当前模型里读。
  final String? level;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final lv = level ?? context.findAncestorWidgetOfExactType<ChatScreen>()?.session.currentModel?.level ?? 'off';
    final title = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodyMedium?.copyWith(color: c.text),
    );
    if (lv == 'off') return title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: title),
        Text(
          ' · ${thinkingLabel(lv)}',
          key: const ValueKey('model-level-mark'),
          maxLines: 1,
          style: t.bodySmall?.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}
