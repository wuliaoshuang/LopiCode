// 设计约束（裁剪背景 · 390×844，浅色 + 深色）
// 层级（先定这个）：
// - 最重要：图和选框。选框固定在中间，比例＝这台手机的屏幕（竖屏）；框外的图压暗但看得见，知道还能往哪挪。
// - 其次：底部唯一的主操作“用这个区域”（实心、通栏）。
// - 再次：一行缩放（减 · 滑杆 · 加，右上写倍数），一行三个工具（重置 / 旋转 90° / 效果预览）。一行只做一件事。
// 手感（自己定的）：选框不动，**图在选框下面动**——单指拖动挪图，双指捏合缩放（围绕两指中间），和系统设壁纸一样。
//   不做“拖选框的边角”：手机上边角太小不好捏，而且比例是锁死的，拖边角和缩放是一回事。
// - 只记“裁剪区域”（相对图片的 0–1 矩形）和旋转了几个 90°，不改原图；所以下次再进来还是上次的位置，可以接着调。
// - 旋转会把区域重置成居中最大（转过以后原来的区域多半对不上比例）。
// - “效果预览”开着时，选框里按现在的遮罩 / 模糊 / 亮度画，并叠上示例文字和气泡；拖动、缩放照常能用。
import 'dart:ui' as ui;

import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_controls.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 裁剪页交回来的结果。
class BackdropCropResult {
  const BackdropCropResult({required this.crop, required this.turns});
  final CropRect crop;
  final int turns;
}

class BackdropCropScreen extends StatefulWidget {
  const BackdropCropScreen({super.key, required this.path, required this.look, required this.settings, this.fresh = false});

  /// 图片文件的完整路径。
  final String path;

  /// 这张图现在的样子（宽高、上次的裁剪和旋转、效果参数）。
  final BackdropLook look;
  final BackdropSettings settings;

  /// 刚选的新图（还没裁过）：从居中最大开始。否则从上次的区域接着调。
  final bool fresh;

  @override
  State<BackdropCropScreen> createState() => _BackdropCropScreenState();
}

class _BackdropCropScreenState extends State<BackdropCropScreen> {
  ui.Image? _image;
  bool _failed = false;
  late int _turns = widget.look.turns;
  CropRect? _crop;
  bool _preview = false;
  bool _moving = false;
  double _lastScale = 1;

  @override
  void initState() {
    super.initState();
    BackdropImages.instance.load(widget.path).then((img) {
      if (!mounted) return;
      setState(() {
        _image = img;
        _failed = img == null;
      });
    });
  }

  CropMath _math(double aspect) {
    final odd = _turns.isOdd;
    return CropMath(imageWidth: (odd ? widget.look.height : widget.look.width).toDouble(), imageHeight: (odd ? widget.look.width : widget.look.height).toDouble(), aspect: aspect);
  }

  CropRect _current(CropMath m) => _crop ??= widget.fresh ? m.initial() : m.refit(widget.look.crop);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final aspect = phoneAspectOf(context);
    final m = _math(aspect);
    final crop = _current(m);
    final zoom = m.zoomOf(crop);
    final image = _image;
    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      appBar: const PageBar(titleText: '裁剪背景'),
      body: BelowBar(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: image == null
                    ? Center(
                        child: _failed
                            ? Text(
                                '这张图读不出来了，请返回重新选一张。',
                                key: const ValueKey('bg-crop-failed'),
                                style: t.bodyMedium?.copyWith(color: c.textMuted),
                              )
                            : const CircularProgressIndicator(),
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          final frame = cropFrame(box.biggest, aspect);
                          return GestureDetector(
                            key: const ValueKey('bg-crop-area'),
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (_) => setState(() {
                              _moving = true;
                              _lastScale = 1;
                            }),
                            onScaleUpdate: (d) {
                              var next = _current(m);
                              if (d.scale != _lastScale && d.pointerCount > 1) {
                                final fx = next.left + (d.localFocalPoint.dx - frame.left) / frame.width * next.width;
                                final fy = next.top + (d.localFocalPoint.dy - frame.top) / frame.height * next.height;
                                next = m.zoomBy(next, d.scale / _lastScale, focalX: fx.clamp(next.left, next.right), focalY: fy.clamp(next.top, next.bottom));
                                _lastScale = d.scale;
                              }
                              // 手指往右拖 ⇒ 图往右走 ⇒ 区域在图上往左
                              next = m.pan(next, -d.focalPointDelta.dx / frame.width * next.width, -d.focalPointDelta.dy / frame.height * next.height);
                              setState(() => _crop = next);
                            },
                            onScaleEnd: (_) => setState(() => _moving = false),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    key: const ValueKey('bg-crop-paint'),
                                    painter: _CropPainter(image: image, turns: _turns, crop: crop, frame: frame, scrim: c.bg.withValues(alpha: 0.72), line: c.onAccent, grid: _moving),
                                  ),
                                ),
                                if (_preview)
                                  Positioned.fromRect(
                                    rect: frame,
                                    child: BackdropPreview(
                                      key: const ValueKey('bg-crop-preview'),
                                      look: widget.look.copyWith(crop: crop, turns: _turns, fit: BackdropFit.cover),
                                      path: widget.path,
                                      settings: widget.settings,
                                      radius: 0,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              BackdropValueRow(
                id: 'bg-crop-zoom',
                title: '缩放',
                // 滑杆按 0.25 倍一档：1.00×–8.00×
                value: (zoom * 4).round(),
                min: 4,
                max: (kCropMaxZoom * 4).round(),
                step: 1,
                enabled: image != null,
                format: (v) => '${(v / 4).toStringAsFixed(2)}×',
                onChanged: (v, {required done}) => setState(() => _crop = m.zoomTo(crop, v / 4)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        key: const ValueKey('bg-crop-reset'),
                        onPressed: image == null ? null : () => setState(() => _crop = m.initial()),
                        icon: const Icon(Icons.restart_alt, size: 20),
                        label: const Text('重置'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        key: const ValueKey('bg-crop-rotate'),
                        onPressed: image == null
                            ? null
                            : () => setState(() {
                                _turns = (_turns + 1) % 4;
                                _crop = _math(aspect).initial();
                              }),
                        icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 20),
                        label: const Text('旋转 90°'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        key: const ValueKey('bg-crop-preview-toggle'),
                        onPressed: image == null ? null : () => setState(() => _preview = !_preview),
                        icon: Icon(_preview ? Icons.visibility : Icons.visibility_outlined, size: 20),
                        label: Text(_preview ? '只看图' : '效果预览'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
                child: FilledButton(
                  key: const ValueKey('bg-crop-done'),
                  onPressed: image == null ? null : () => Navigator.of(context).pop(BackdropCropResult(crop: crop, turns: _turns)),
                  child: const Text('用这个区域'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选框在 [area] 里的位置：比例 [aspect]，四周至少留 16，居中。
Rect cropFrame(Size area, double aspect) {
  const pad = Space.x4;
  final maxW = (area.width - pad * 2).clamp(1.0, double.infinity);
  final maxH = (area.height - pad * 2).clamp(1.0, double.infinity);
  var w = maxW;
  var h = w / aspect;
  if (h > maxH) {
    h = maxH;
    w = h * aspect;
  }
  return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.image, required this.turns, required this.crop, required this.frame, required this.scrim, required this.line, required this.grid});

  final ui.Image image;
  final int turns;
  final CropRect crop;
  final Rect frame;
  final Color scrim;
  final Color line;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    final rw = turns.isOdd ? image.height : image.width;
    final rh = turns.isOdd ? image.width : image.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // 整张图：让裁剪区域正好落在选框上
    final sx = frame.width / (crop.width * rw);
    final sy = frame.height / (crop.height * rh);
    final whole = Rect.fromLTWH(frame.left - crop.left * rw * sx, frame.top - crop.top * rh * sy, rw * sx, rh * sy);
    paintBackdropRegion(canvas, image, turns: turns, region: Rect.fromLTWH(0, 0, rw.toDouble(), rh.toDouble()), dst: whole, clip: false);
    // 框外压暗
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(frame),
      Paint()..color = scrim,
    );
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = line;
    canvas.drawRect(frame, border);
    if (grid) {
      final thin = Paint()
        ..strokeWidth = 1
        ..color = line.withValues(alpha: 0.5);
      for (var i = 1; i < 3; i++) {
        final x = frame.left + frame.width * i / 3;
        final y = frame.top + frame.height * i / 3;
        canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), thin);
        canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), thin);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.turns != turns || old.crop != crop || old.frame != frame || old.scrim != scrim || old.line != line || old.grid != grid;
}
