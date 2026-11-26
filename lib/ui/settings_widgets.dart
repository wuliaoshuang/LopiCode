// 设计约束（设置里所有页面共用的“组”和“行” · 390×844）— 2026-11-24 霜霜要求设置页分门别类
// 层级（先定的这个，再定排版，最后才是颜色）：
// - 页 › 组 › 行。组有小标题（弱化的小字），组下面可以有一句脚注；说明文字只放两处：行的副标题、组的脚注。
// - 一行只做一件事，只有七种行：跳转行（右边当前值 + 箭头）、开关行（整行可点）、单选行（右边圆点）、勾选行（左边勾选框）、
//   添加行（强调色的“＋ 新建…”，放在一组的最后）、分段行（名称在上、分段选择独占一行在下）、危险行（红字，点了先确认）。输入框放进“表单组”（组内留 16 的边）。
// 排版（全部取自 lib/theme/tokens.dart，不写表外的数）：
// - 页边 16；组与组相隔 24；组标题到卡片 8；卡片到脚注 8。
// - 行高至少 56（带副标题的自然撑到 64 左右），整行都是点击区域；行内左右 16、上下 12。
// - 图标 22，放在 24 宽的格子里，和名称相隔 12；行间细线从名称的起点画到右边 16，图标下面不画线。
// - 名称 16 / 400；副标题 12 弱色，最多两行；右侧当前值 14 弱色，最多占行宽的一半，超出省略。
// 颜色：图标和名称用正文色，副标题 / 值 / 箭头用弱色；强调色只留给开关和选中态；红色只给危险行。
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:material_ui/material_ui.dart';

/// 设置里一行的尺寸，改这里就全改了。
abstract final class SettingsMetrics {
  static const double rowMinHeight = 56;
  static const double iconSlot = 24;
  static const double iconSize = 22;
  static const double groupGap = Space.x6;

  /// 带图标的行，名称从这里开始（细线也从这里画）。
  static const double textStart = Space.x4 + iconSlot + Space.x3;
}

/// 设置的一页：浅灰底、统一的顶栏、可滚动的一列“组”。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children, this.subtitle, this.actions, this.floatingActionButton, this.listKey, this.bottom = Space.x8});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Key? listKey;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBackdrop(
      area: BackdropArea.pages,
      builder: (context, on) => Scaffold(
        backgroundColor: on ? Colors.transparent : c.canvas,
        extendBodyBehindAppBar: true,
        appBar: PageBar(background: c.canvas, titleText: title, subtitle: subtitle, actions: actions),
        floatingActionButton: floatingActionButton,
        // 不用懒加载的 ListView：设置页都不长，一次排完，滚出屏幕的输入框不会被拆掉重建，底部的“保存”也一直在。
        body: SingleChildScrollView(
          key: listKey,
          padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// 一组：小标题 + 白卡片 + 脚注。[padded] 为真时是“表单组”：卡片里留 16 的边、不画行间线。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, this.footer, required this.children, this.padded = false, this.iconRows});
  final String? title;
  final String? footer;
  final List<Widget> children;
  final bool padded;

  /// 行带不带图标（决定行间细线从哪儿画起）。行被 Consumer / FutureBuilder 包着、从外面看不出来时手动指定。
  final bool? iconRows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && !padded) {
        rows.add(Divider(height: 1, thickness: 1, indent: (iconRows ?? _hasIcon(children)) ? SettingsMetrics.textStart : Space.x4, endIndent: Space.x4, color: c.border));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: SettingsMetrics.groupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: BackdropPlate(
                enabled: BackdropPlates.of(context),
                child: Text(title!, style: t.labelMedium?.copyWith(color: c.textFaint)),
              ),
            ),
          GroupCard(margin: EdgeInsets.zero, dividers: false, padding: padded ? const EdgeInsets.all(Space.x4) : null, children: rows),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
              child: BackdropPlate(
                enabled: BackdropPlates.of(context),
                child: Text(footer!, style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
              ),
            ),
        ],
      ),
    );
  }

  /// 这一组的行是不是都带图标（都带，细线才从名称的起点画起；有一行不带就从卡片的左边 16 画起）。
  static bool _hasIcon(List<Widget> children) =>
      children.every((w) => (w is SettingsRow && (w.icon != null || w.leading != null)) || (w is SettingsSwitchRow && w.icon != null) || w is SettingsCheckRow);
}

/// 行的骨架：图标格 + 名称 / 副标题 + 右侧内容。别的行都用它拼，保证尺寸一致。
class _RowFrame extends StatelessWidget {
  const _RowFrame({required this.title, this.icon, this.leading, this.subtitle, this.trailing, this.onTap, this.danger = false, this.accent = false, this.enabled = true, this.subtitleLines = 2});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool accent;
  final bool enabled;
  final int subtitleLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ink = danger ? c.danger : (accent ? c.accent : (enabled ? c.text : c.textFaint));
    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsMetrics.rowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: Space.x3)],
              if (leading == null && icon != null) ...[
                SizedBox(
                  width: SettingsMetrics.iconSlot,
                  child: Center(
                    child: Icon(icon, size: SettingsMetrics.iconSize, color: ink),
                  ),
                ),
                const SizedBox(width: Space.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.bodyLarge?.copyWith(height: 1.3, color: ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: t.bodySmall?.copyWith(color: c.textFaint),
                          maxLines: subtitleLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: Space.x3), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳转行 / 只读行：名称 +（副标题）+ 右侧当前值 + 箭头。没有 [onTap] 就不画箭头。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    this.valueKey,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.enabled = true,
    this.accent = false,
  });
  final IconData? icon;

  /// 代替图标的控件（服务商图标之类），按它自己的宽度放。
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// 右侧弱化显示的当前状态，要短。
  final String? value;
  final Key? valueKey;
  final VoidCallback? onTap;

  /// 代替箭头的控件。
  final Widget? trailing;
  final bool danger;
  final bool enabled;

  /// “添加一项”这种行：图标和名称用强调色，不画箭头。
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final hasValue = value != null && value!.isNotEmpty;
    final tail = trailing ?? (onTap == null || danger || accent ? null : Icon(Icons.chevron_right, size: 20, color: c.textFaint));
    return _RowFrame(
      icon: icon,
      leading: leading,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      danger: danger,
      accent: accent,
      enabled: enabled,
      trailing: !hasValue && tail == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasValue)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
                    child: Text(
                      value!,
                      key: valueKey,
                      style: t.bodyMedium?.copyWith(color: c.textFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                if (hasValue && tail != null) const SizedBox(width: Space.x1),
                ?tail,
              ],
            ),
    );
  }
}

/// 开关行：整行可点，开关在右。[switchKey] 落在开关本身上（测试读它的值）。
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({super.key, this.icon, required this.title, this.subtitle, required this.value, required this.onChanged, this.switchKey});
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) => _RowFrame(
    icon: icon,
    title: title,
    subtitle: subtitle,
    subtitleLines: 3,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    // 开关自带的 48 点击区会把行撑高，这里收紧：整行已经可点了。
    trailing: SizedBox(
      height: 32,
      child: Switch(key: switchKey, value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ),
  );
}

/// 单选行：几行里只能选一行，选中的右边是实心圆点。
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: _RowFrame(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 22, color: selected ? c.accent : c.textFaint),
      ),
    );
  }
}

/// 勾选行：几行里可以勾多行，勾选框在左（和图标同一个格子），整行可点。
class SettingsCheckRow extends StatelessWidget {
  const SettingsCheckRow({super.key, required this.title, this.subtitle, required this.checked, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: checked,
      child: _RowFrame(
        leading: SizedBox(
          width: SettingsMetrics.iconSlot,
          child: Center(
            child: Icon(checked ? Icons.check_box : Icons.check_box_outline_blank, size: SettingsMetrics.iconSize, color: checked ? c.accent : c.textFaint),
          ),
        ),
        title: title,
        subtitle: subtitle,
        subtitleLines: 1,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!checked),
      ),
    );
  }
}

/// 分段行：名称（和一句说明）在上，分段选择独占一行在下——不和名称挤在同一行。
class SettingsSegmentRow<T> extends StatelessWidget {
  const SettingsSegmentRow({super.key, this.title, this.subtitle, required this.segments, required this.selected, required this.onChanged, this.segmentKey});
  final String? title;
  final String? subtitle;
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final Key? segmentKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) Text(title!, style: t.bodyLarge?.copyWith(height: 1.3)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: t.bodySmall?.copyWith(color: c.textFaint)),
            ),
          if (title != null || subtitle != null) const SizedBox(height: Space.x3),
          SegmentedButton<T>(
            key: segmentKey,
            showSelectedIcon: false,
            segments: [for (final (value, label) in segments) ButtonSegment(value: value, label: Text(label))],
            selected: {selected},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

/// 打开设置里的下一页。
Future<T?> pushSettingsPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
