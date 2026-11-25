// 设计约束（背景渲染控件）
// - 用法：把页面的 Scaffold 包起来——
//     AppBackdrop(area: BackdropArea.chat, child: Scaffold(…))
//   画着背景时（开着、有图、图已解好）它把下面 Scaffold 的默认底色换成透明；没背景时页面和原来一模一样。
//   Scaffold 自己写死了 backgroundColor 的，改用 builder：
//     AppBackdrop(area: …, builder: (context, on) => Scaffold(backgroundColor: on ? Colors.transparent : c.bg, …))
// - 背景按**整块屏幕**摆：键盘升起、页面变矮时图不跟着缩，只是下面被盖住。
// - 层次从下到上：图片（按裁剪 / 适配方式 / 模糊）→ 亮度 → 遮罩。遮罩默认跟随主题底色，文字直接写在上面也读得清。
// - 页面里的表面（气泡、卡片、输入框、代码块）问 BackdropScope 要颜色：
//     BackdropScope.surface(context, c.surfaceMuted)                           // 有背景时按“表面不透明度”变半透明
//     BackdropScope.surface(context, c.codeBg, seeThrough: BackdropArea.code)  // “透出”开关开着才半透明
//   没背景时原样返回，所以随手包上不会改变现在的样子。
// - 和主题对接的两个取值入口都在这个文件里（合并主题分支后只改这两处）：
//     backdropSurfaceAlpha —— 有背景时表面有多不透明；backdropMaskBase —— “遮罩跟随主题”时用哪个颜色。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:material_ui/material_ui.dart';

/// 有背景时表面（气泡、卡片、输入框）的不透明度，0–1。**全应用只有这一个入口。**
///
/// 现在取背景设置里的“表面不透明度”；合并主题分支后如果要改成主题的 `metrics.surfaceOpacity`，只改这里。
double backdropSurfaceAlpha(BackdropSettings settings) => settings.surfaceOpacity / 100;

/// “遮罩颜色跟随主题”时用的颜色（不带深浅）。现在是主题底色；合并主题分支后可以换成主题的 `backdropScrim`，只改这里。
Color backdropMaskBase(BuildContext context) => context.colors.bg;

/// 告诉下面的控件：这一页有没有背景、表面该多透。
class BackdropScope extends InheritedWidget {
  const BackdropScope({super.key, required this.on, required this.settings, required super.child});

  final bool on;
  final BackdropSettings settings;

  static BackdropScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BackdropScope>();

  /// 这一页现在画着背景吗。
  static bool onOf(BuildContext context) => maybeOf(context)?.on ?? false;

  /// 表面的颜色：有背景时变半透明。[seeThrough] 给了的话，还得那个“透出”开关开着才透。
  static Color surface(BuildContext context, Color color, {BackdropArea? seeThrough}) {
    final scope = maybeOf(context);
    if (scope == null || !scope.on) return color;
    if (seeThrough != null && !scope.settings.area(seeThrough)) return color;
    return color.withValues(alpha: color.a * backdropSurfaceAlpha(scope.settings));
  }

  @override
  bool updateShouldNotify(BackdropScope old) => old.on != on || old.settings != settings;
}

/// 把一页包起来，在它后面画背景。
class AppBackdrop extends ConsumerWidget {
  const AppBackdrop({super.key, required this.area, this.child, this.builder}) : assert((child == null) != (builder == null), 'child 和 builder 给一个');

  /// 这一页算哪个范围（聊天页 / 其它页面）。
  final BackdropArea area;

  /// 被包起来的页面。画着背景时，它里面 Scaffold 的默认底色会变成透明。
  final Widget? child;

  /// 要自己决定底色的用这个：[on]＝现在画着背景，页面把自己的底色改成透明。
  final Widget Function(BuildContext context, bool on)? builder;

  Widget _page(BuildContext context, bool on) {
    final b = builder;
    if (b != null) return b(context, on);
    if (!on) return child!;
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.transparent),
      child: child!,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backdropProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!settings.showsOn(area, dark: dark)) {
      return BackdropScope(
        on: false,
        settings: settings,
        child: Builder(builder: (context) => _page(context, false)),
      );
    }
    final look = settings.lookFor(dark: dark);
    final path = ref.watch(backdropStoreProvider).imageFile(look.file!).path;
    return BackdropPicture(
      look: look,
      path: path,
      fullScreen: true,
      builder: (context, ready) => BackdropScope(
        on: ready,
        settings: settings,
        child: Builder(builder: (context) => _page(context, ready)),
      ),
    );
  }
}

/// 画一张背景（图片 + 亮度 + 遮罩），上面叠 [builder] 给的内容。图没解好时只有内容。
class BackdropPicture extends StatefulWidget {
  const BackdropPicture({super.key, required this.look, required this.path, required this.builder, this.fullScreen = false});

  final BackdropLook look;

  /// 图片文件的完整路径。
  final String path;

  /// true＝按整块屏幕摆（给整页用）；false＝按自己这一块的大小摆（预览用）。
  final bool fullScreen;
  final Widget Function(BuildContext context, bool ready) builder;

  @override
  State<BackdropPicture> createState() => _BackdropPictureState();
}

class _BackdropPictureState extends State<BackdropPicture> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(BackdropPicture old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    _image = BackdropImages.instance.peek(path);
    if (_image != null) return;
    BackdropImages.instance.load(path).then((img) {
      if (mounted && widget.path == path && img != null) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final content = widget.builder(context, image != null);
    if (image == null) return content;
    final c = context.colors;
    final look = widget.look;
    final screen = MediaQueryData.fromView(View.of(context)).size;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('app-backdrop-paint'),
              painter: BackdropPainter(
                image: image,
                path: widget.path,
                look: look,
                letterbox: c.bg,
                mask: (look.maskFollowsTheme ? backdropMaskBase(context) : Color(look.maskColor | 0xFF000000)).withValues(alpha: look.maskOpacity / 100),
                screenHeight: widget.fullScreen ? screen.height : null,
              ),
            ),
          ),
        ),
        content,
      ],
    );
  }
}

class BackdropPainter extends CustomPainter {
  BackdropPainter({required this.image, required this.path, required this.look, required this.letterbox, required this.mask, this.screenHeight});

  final ui.Image image;
  final String path;
  final BackdropLook look;

  /// “完整显示”时四周空的地方的颜色。
  final Color letterbox;

  /// 遮罩（已经带上深浅）。
  final Color mask;

  /// 给了就按这个高度摆图（整页用：键盘升起、页面变矮时图不跟着缩）。
  final double? screenHeight;

  /// 图片在 [box] 里摆成多大、摆在哪（铺满 / 完整显示；平铺时是左上角第一格）。
  static Rect place(BackdropFit fit, Size region, Rect box, {int tilePercent = kBackdropTileDefault}) {
    switch (fit) {
      case BackdropFit.cover:
      case BackdropFit.contain:
        final sx = box.width / region.width, sy = box.height / region.height;
        final s = fit == BackdropFit.cover ? math.max(sx, sy) : math.min(sx, sy);
        final w = region.width * s, h = region.height * s;
        return Rect.fromLTWH(box.left + (box.width - w) / 2, box.top + (box.height - h) / 2, w, h);
      case BackdropFit.tile:
        final w = box.width * tilePercent / 100;
        return Rect.fromLTWH(box.left, box.top, w, w * region.height / region.width);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final visible = Offset.zero & size;
    final box = Rect.fromLTWH(0, 0, size.width, math.max(size.height, screenHeight ?? 0));
    canvas.save();
    canvas.clipRect(visible);
    final rw = look.turns.isOdd ? image.height : image.width;
    final rh = look.turns.isOdd ? image.width : image.height;
    // “完整显示”不看裁剪区域：整张图都露出来
    final region = look.fit == BackdropFit.contain ? Rect.fromLTWH(0, 0, rw.toDouble(), rh.toDouble()) : cropPixels(look.crop, rotatedWidth: rw, rotatedHeight: rh);
    final first = place(look.fit, region.size, box, tilePercent: look.tilePercent);
    if (look.fit == BackdropFit.contain) canvas.drawRect(visible, Paint()..color = letterbox);

    // 要模糊：换成预先糊好的小图（整张就是那一块，不用再转、再裁）
    var src = image;
    var srcTurns = look.turns;
    var srcRegion = region;
    if (look.blur > 0) {
      src = BackdropImages.instance.blurred(path: path, source: image, turns: look.turns, region: region, sigma: look.blur.toDouble(), shownWidth: first.width);
      srcTurns = 0;
      srcRegion = Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
    }
    if (look.fit == BackdropFit.tile) {
      for (var y = first.top; y < visible.bottom; y += first.height) {
        for (var x = first.left; x < visible.right; x += first.width) {
          paintBackdropRegion(canvas, src, turns: srcTurns, region: srcRegion, dst: Rect.fromLTWH(x, y, first.width, first.height));
        }
      }
    } else {
      paintBackdropRegion(canvas, src, turns: srcTurns, region: srcRegion, dst: first);
    }
    if (look.brightness != 0) {
      final base = look.brightness < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
      canvas.drawRect(visible, Paint()..color = base.withValues(alpha: look.brightness.abs() / 100));
    }
    if (mask.a > 0) canvas.drawRect(visible, Paint()..color = mask);
    canvas.restore();
  }

  @override
  bool shouldRepaint(BackdropPainter old) => old.image != image || old.look != look || old.letterbox != letterbox || old.mask != mask || old.screenHeight != screenHeight || old.path != path;
}
