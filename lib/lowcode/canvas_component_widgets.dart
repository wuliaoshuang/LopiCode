// 设计约束（低代码 · 画布里的自定义组件 · 390×844）
// - 组件实例正常时按“展开后的内容”画（canvas_render_widgets.dart 里复用普通控件的画法），整块只能当一个东西选中 / 拖动。
// - 展开不了（定义被删了，或者组件绕回来用到了自己）时画这里的占位框：一行，图标 + 一句话，颜色用警示色，一眼能看出有问题。
// - 占位框和页面内容一样用固定的浅色，不跟随应用的深色模式。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 画不出来的组件实例的占位。[name] 是组件名（定义还在、只是循环了的时候有）。
class CanvasComponentPlaceholder extends StatelessWidget {
  const CanvasComponentPlaceholder({super.key, this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final label = name == null ? '组件不存在' : '组件「$name」展开不了（它里面又用到了自己）';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: const Color(0xFFD98A0B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off_outlined, size: 18, color: Color(0xFF9A5B00)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFF7A4700)),
            ),
          ),
        ],
      ),
    );
  }
}
