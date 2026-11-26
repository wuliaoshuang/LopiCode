// 设计约束（样式面板的通用小控件；390×844，浅色 + 深色）
// - 一行只做一件事：左边是标签（下面可带一句弱化的说明），右边是控件；控件太宽的（五六个选项的按钮组）标签在上、控件占满一行。
// - 所有可点的目标至少 40px 高。
// - 层级靠颜色深浅：自己设的值用正文色，来自“属性”的值用弱化色，非法输入用危险色描边。
// - 这里的控件都不直接改模型，只把新值交给回调；`merge` 为 true 表示“连续操作的一步”（打字、加减），由面板合并成一条撤销记录。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

// 数字框、长度框、数字行原来就定义在这个文件里，别处还从这里引用。
export 'package:lopicode/lowcode/style_number_widgets.dart';

/// 面板交给各分组的“当前样子”和“怎么改”。每次重画换一份，分组自己不存样式。
class StyleEdit {
  const StyleEdit({required this.node, required this.own, required this.resolved, required this.apply, this.parentColumns, this.inheritedHint});

  /// “这个值不是在这儿设的”那句小字换个说法（改某一档屏宽时是“跟手机一样”）；不给用平常那句“来自常用页”。
  final String? inheritedHint;

  /// 它放在网格里：那个网格一共几列；不在网格里是 null。
  final int? parentColumns;

  /// 只用来看类型（是不是容器、是不是行）。样式不要从这里读，读 [own] / [resolved]。
  final LcNode node;

  /// 这个节点自己的 style（已经算上还没提交的预览值）。
  final Map<String, String> own;

  /// 最终样式：简写属性翻出来的被 [own] 盖过之后。控件显示的是这一份。
  final Map<String, String> resolved;

  /// 改样式。[merge] 为 true 时和紧接着的改动合并成一条撤销记录（停 400ms 才提交）。
  final void Function(void Function(LcStyle s) change, {bool merge}) apply;

  LcStyle get shown => LcStyle(resolved);
  bool isOwn(String name) => own.containsKey(name);

  /// 值是从“属性”里来的（自己没设）。
  bool inherited(String name) => !own.containsKey(name) && resolved.containsKey(name);
}

/// 数字写成最短的样子：整数不带小数点，小数最多两位。
String fmtNum(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// 一行：标签在左、控件在右。[stacked] 时标签在上、控件占满一行。
class StyleRow extends StatelessWidget {
  const StyleRow({super.key, required this.label, required this.child, this.hint, this.stacked = false});
  final String label;
  final String? hint;
  final Widget child;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (hint != null)
          Text(
            hint!,
            style: t.labelSmall?.copyWith(color: c.textFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: Space.x2),
            child,
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: Space.x2),
          child,
        ],
      ),
    );
  }
}

/// 40×40 的小图标按钮（加、减、清除）。不可用时变淡。
class StyleIconButton extends StatelessWidget {
  const StyleIconButton({super.key, required this.icon, required this.onTap, this.semantic});
  final IconData icon;
  final VoidCallback? onTap;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 18, color: onTap == null ? c.border : c.textMuted, semanticLabel: semantic),
      ),
    );
  }
}

/// 一个可选项：值、给人看的名字、可选的图标（有图标时按钮上只画图标，名字当无障碍说明）。
class ChoiceOption {
  const ChoiceOption(this.value, this.label, {this.icon});
  final String value;
  final String label;
  final IconData? icon;
}

/// 按钮组：选一个。再点一下已经选中的＝清除（回到默认 / 属性里的值）。
class ChoiceButtons extends StatelessWidget {
  const ChoiceButtons({super.key, required this.id, required this.options, required this.selected, required this.onChanged, this.inherited = false, this.expand = false});
  final String id;
  final List<ChoiceOption> options;
  final String? selected;

  /// 选中的那个不是自己设的（来自属性或默认）：弱化显示，再点它是“明确设成它”而不是清除。
  final bool inherited;

  /// 占满一行、各项等宽（用在标签在上的宽按钮组）。
  final bool expand;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget cell(ChoiceOption o) {
      final on = o.value == selected;
      final strong = on && !inherited;
      final fg = strong ? c.accent : (on ? c.text : c.textMuted);
      final inner = InkWell(
        key: Key('lc-opt-$id-${o.value}'),
        onTap: () => onChanged(strong ? null : o.value),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          alignment: Alignment.center,
          color: strong ? c.accentSoft : (on ? c.surfaceMuted : null),
          child: o.icon != null
              ? Icon(o.icon, size: 20, color: fg, semanticLabel: o.label)
              : Text(
                  o.label,
                  style: t.bodyMedium?.copyWith(color: fg, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                  maxLines: 1,
                  softWrap: false,
                ),
        ),
      );
      return expand ? Expanded(child: inner) : inner;
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[if (i > 0) Container(width: 1, height: 40, color: c.border), cell(options[i])],
          ],
        ),
      ),
    );
  }
}

/// 下拉：一个 40px 高的框，点开是菜单。选项多、或者不常用的用它。
class StyleMenu extends StatelessWidget {
  const StyleMenu({super.key, required this.text, required this.options, required this.onSelected, this.width, this.faint = false});
  final String text;
  final List<ChoiceOption> options;
  final ValueChanged<String> onSelected;
  final double? width;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.value, height: 44, child: Text(o.label))],
      child: Container(
        width: width,
        height: 40,
        padding: const EdgeInsets.only(left: Space.x2, right: 2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (width == null)
              Text(text, style: t.bodyMedium?.copyWith(color: faint ? c.textMuted : c.text), maxLines: 1)
            else
              Expanded(
                child: Text(
                  text,
                  style: t.bodyMedium?.copyWith(color: faint ? c.textMuted : c.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Icon(Icons.arrow_drop_down, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// “更多”：不常用的收在里面，点开才显示。里面已经设过东西时默认展开（不然用户找不到自己设过的）。
class MoreSection extends StatefulWidget {
  const MoreSection({super.key, required this.id, required this.children, this.initiallyOpen = false, this.label = '更多'});
  final String id;
  final List<Widget> children;
  final bool initiallyOpen;
  final String label;

  @override
  State<MoreSection> createState() => _MoreSectionState();
}

class _MoreSectionState extends State<MoreSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('lc-more-${widget.id}'),
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(Radii.md),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Text(widget.label, style: t.labelLarge?.copyWith(color: c.textMuted)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textMuted),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
