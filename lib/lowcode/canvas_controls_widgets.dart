// 设计约束（低代码 · 画布里的按钮、输入框和“不认识的组件”占位 · 390×844）
// - 按钮、输入框只是样子，不响应点击（点＝选中，在 canvas_render_widgets.dart 里管）。
// - 没用到第 3 版新属性（图标、禁用、类型、值、标签、必填）的旧页面，画出来和以前一模一样。
// - 禁用＝整体变淡（和导出网页的 opacity .5 一致），不换颜色。
// - 标签在输入框上面，小一号、次要色；必填的星号用警示色。页面内容用固定浅色，不跟随应用深色模式。
// - 不认识的组件（新版应用做的）：一行占位，图标 + 一句话，和“组件不存在”的占位同一套颜色（都是“这里有东西但画不出来”）。
import 'package:lopicode/lowcode/icon_set_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

const Color _labelColor = Color(0xFF5C6479);
const Color _requiredColor = Color(0xFFC62828);

/// 画布上的按钮。
Widget canvasButton(LcNode n, {required ButtonStyle style, TextAlign? textAlign}) {
  final text = Text(n.strProp('text') ?? '', textAlign: textAlign);
  final icon = lcIconData[n.strProp('icon')];
  final Widget button = icon == null
      ? FilledButton(onPressed: () {}, style: style, child: text)
      : (n.strProp('text') == null
            ? FilledButton(onPressed: () {}, style: style, child: Icon(icon, size: 20))
            : FilledButton.icon(onPressed: () {}, style: style, icon: Icon(icon, size: 20), label: text));
  return n.props['disabled'] == true ? Opacity(opacity: 0.5, child: button) : button;
}

/// 画布上的输入框。[field] 是按样式画好的那个框；这里只管标签、禁用这些外面的东西。
Widget canvasInputFrame(LcNode n, Widget field) {
  final label = n.strProp('label');
  Widget out = field;
  if (label != null) {
    out = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            children: [
              if (n.props['required'] == true)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: _requiredColor),
                ),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.4, color: _labelColor),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }
  return n.props['disabled'] == true ? Opacity(opacity: 0.5, child: out) : out;
}

/// 输入框里显示的默认值（密码类型显示成圆点）；没有返回 null。
String? canvasInputValue(LcNode n) {
  final v = n.strProp('value');
  if (v == null) return null;
  return n.strProp('inputType') == 'password' ? '•' * v.length.clamp(1, 12) : v;
}

/// 这一版不认识的组件的占位。
class CanvasUnknownPlaceholder extends StatelessWidget {
  const CanvasUnknownPlaceholder({super.key, required this.typeName});
  final String typeName;

  @override
  Widget build(BuildContext context) {
    final ui = context.themeSpec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ui.lowcodeColor(LowcodeKey.missingBg),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: ui.lowcodeColor(LowcodeKey.missingBorder)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.new_releases_outlined, size: 18, color: ui.lowcodeColor(LowcodeKey.missingIcon)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '新版组件（$typeName），这一版显示不了',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: ui.lowcodeColor(LowcodeKey.missingText)),
            ),
          ),
        ],
      ),
    );
  }
}
