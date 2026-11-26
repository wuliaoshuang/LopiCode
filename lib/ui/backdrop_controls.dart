// 设计约束（背景设置里的小控件 · 390×844）
// - 数值行（BackdropValueRow）：第一行“名称 …… 当前数值”，第二行“减 · 滑杆 · 加”。滑杆在手机上不好拖准，
//   所以两头各有一个 44×44 的步进按钮，数值一直写在右上（等宽数字，不跳动）。到头的按钮灰掉。
// - 效果预览（BackdropPreview）：手机屏幕比例的一小块，里面是背景 + 几行示例文字 + 一个气泡 + 一条输入框，
//   只为了回答“字还读得清吗”。不能点。
// - 颜色全部取自 context.colors；气泡 / 输入框的底色走 BackdropScope.surface（和真页面同一个入口）。
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:material_ui/material_ui.dart';

/// 一个带步进按钮的数值行。拖动过程中 [onChanged]（done＝false）只改内存，松手 / 点步进时 done＝true 才存盘。
class BackdropValueRow extends StatelessWidget {
  const BackdropValueRow({
    super.key,
    required this.id,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.format,
    this.enabled = true,
  });

  /// 测试用的键前缀：`$id-minus` / `$id-plus` / `$id-slider` / `$id-value`。
  final String id;
  final String title;
  final int value;
  final int min;
  final int max;
  final int step;
  final void Function(int value, {required bool done}) onChanged;
  final String Function(int value)? format;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = value.clamp(min, max);
    Widget stepper(String key, IconData icon, String tip, int delta) {
      final next = (v + delta).clamp(min, max);
      return IconButton(
        key: Key('$id-$key'),
        tooltip: tip,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Icon(icon, size: 20),
        onPressed: enabled && next != v ? () => onChanged(next, done: true) : null,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x1, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: Space.x3),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: t.bodyLarge?.copyWith(color: enabled ? c.text : c.textFaint)),
                ),
                Text(
                  format?.call(v) ?? '$v',
                  key: Key('$id-value'),
                  style: t.bodyMedium?.copyWith(color: c.textMuted, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          Row(
            children: [
              // 行本身左边留了 16，按钮图标要和名称左对齐：往左收 12
              Transform.translate(offset: const Offset(-Space.x3, 0), child: stepper('minus', Icons.remove, '减一档', -step)),
              Expanded(
                child: Slider(
                  key: Key('$id-slider'),
                  value: v.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: ((max - min) / step).round(),
                  padding: EdgeInsets.zero,
                  onChanged: enabled ? (x) => onChanged(x.round(), done: false) : null,
                  onChangeEnd: enabled ? (x) => onChanged(x.round(), done: true) : null,
                ),
              ),
              stepper('plus', Icons.add, '加一档', step),
            ],
          ),
        ],
      ),
    );
  }
}

/// 效果预览：按 [look] 画背景，上面叠示例内容。[path] 是图片文件的完整路径。
class BackdropPreview extends StatelessWidget {
  const BackdropPreview({super.key, required this.look, required this.path, required this.settings, this.radius = Radii.lg});

  final BackdropLook look;
  final String path;
  final BackdropSettings settings;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: c.bg,
        child: BackdropPicture(
          look: look,
          path: path,
          builder: (context, ready) => BackdropScope(
            on: ready,
            settings: settings,
            surfaceAlpha: backdropSurfaceAlpha(context, settings),
            child: const IgnorePointer(child: BackdropSample()),
          ),
        ),
      ),
    );
  }
}

/// 预览里的示例内容：一个自己发的气泡、几行回复、一条输入框。字号按这一块的宽度等比缩小。
class BackdropSample extends StatelessWidget {
  const BackdropSample({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        // 按 390 宽的真页面等比缩：预览里看到的字和背景的大小关系和真页面一样
        final k = (box.maxWidth / 390).clamp(0.3, 1.0);
        final body = TextStyle(fontSize: FontSize.base * k, height: 1.5, color: c.text);
        final faint = TextStyle(fontSize: FontSize.xs * k, color: c.textFaint);
        return Padding(
          padding: EdgeInsets.fromLTRB(Space.x4 * k, Space.x12 * k, Space.x4 * k, Space.x3 * k),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  key: const ValueKey('bg-sample-bubble'),
                  padding: EdgeInsets.symmetric(horizontal: Space.x4 * k, vertical: Space.x2 * k),
                  decoration: BoxDecoration(color: BackdropScope.surface(context, c.surfaceMuted), borderRadius: BorderRadius.circular(Radii.bubble * k)),
                  child: Text('帮我加一个登录页', style: body),
                ),
              ),
              SizedBox(height: Space.x4 * k),
              Text('好的。我先看一下现在的页面结构，再加上登录表单和校验。', key: const ValueKey('bg-sample-text'), style: body),
              SizedBox(height: Space.x2 * k),
              Text('示例文字：用来看背景上的字读不读得清', style: faint),
              const Spacer(),
              Container(
                height: 44 * k,
                padding: EdgeInsets.symmetric(horizontal: Space.x4 * k),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: BackdropScope.surface(context, c.surface),
                  borderRadius: BorderRadius.circular(22 * k),
                  border: Border.all(color: c.border),
                ),
                child: Text('说点什么…', style: body.copyWith(color: c.textFaint)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 手机屏幕的宽高比（竖屏：宽 ÷ 高）。裁剪选框和预览都用它。
double phoneAspectOf(BuildContext context) {
  final s = MediaQueryData.fromView(View.of(context)).size;
  if (s.width <= 0 || s.height <= 0) return 9 / 19.5;
  return s.width < s.height ? s.width / s.height : s.height / s.width;
}
