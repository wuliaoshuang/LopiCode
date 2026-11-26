// 背景图片测试用的假实现和代码生成的小图（不从网上下、不拉起真的选择器）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:path/path.dart' as p;

/// 假的选图：按脚本依次交回结果，记下被叫了几次。
class FakeBackdropPicker implements BackdropPicker {
  FakeBackdropPicker([List<BackdropPick>? script]) : script = script ?? [];
  final List<BackdropPick> script;
  int calls = 0;

  @override
  Future<BackdropPick> pick() async {
    calls++;
    return script.isEmpty ? const BackdropPickCancelled() : script.removeAt(0);
  }
}

/// 用代码画一张 PNG：左上红、右上绿、左下蓝、右下黄四块，中间一个白圆（裁剪、旋转对不对一眼看得出）。
Future<Uint8List> makePng(int width, int height) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  final w = width.toDouble(), h = height.toDouble();
  void q(double x, double y, int color) => c.drawRect(ui.Rect.fromLTWH(x, y, w / 2, h / 2), ui.Paint()..color = ui.Color(color));
  q(0, 0, 0xFFD23A3A);
  q(w / 2, 0, 0xFF2FA35B);
  q(0, h / 2, 0xFF2E5FD0);
  q(w / 2, h / 2, 0xFFE8B923);
  c.drawCircle(ui.Offset(w / 2, h / 2), (w < h ? w : h) / 6, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final pic = rec.endRecording();
  final img = await pic.toImage(width, height);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  pic.dispose();
  return data!.buffer.asUint8List();
}

/// 一张像风景的 PNG（天空渐变 + 山 + 太阳），截图用：比四色块更像真的背景图。
Future<Uint8List> makeScenePng(int width, int height) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  final w = width.toDouble(), h = height.toDouble();
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h), const [ui.Color(0xFF274B8F), ui.Color(0xFFE08A5B), ui.Color(0xFFF6D69A)], const [0, 0.6, 1]),
  );
  c.drawCircle(ui.Offset(w * 0.68, h * 0.42), w * 0.09, ui.Paint()..color = const ui.Color(0xFFFFF1C2));
  ui.Path hill(double base, double amp, int n, double phase) {
    final path = ui.Path()..moveTo(0, h);
    for (var i = 0; i <= n; i++) {
      final x = w * i / n;
      path.lineTo(x, base + amp * ((i + phase) % 2 == 0 ? -1 : 1) * (0.4 + 0.6 * ((i * 37 + 11) % 10) / 10));
    }
    return path
      ..lineTo(w, h)
      ..close();
  }

  c.drawPath(hill(h * 0.62, h * 0.07, 9, 0), ui.Paint()..color = const ui.Color(0xFF6B4B6E));
  c.drawPath(hill(h * 0.74, h * 0.05, 13, 1), ui.Paint()..color = const ui.Color(0xFF3B2F4F));
  c.drawPath(hill(h * 0.88, h * 0.04, 7, 0), ui.Paint()..color = const ui.Color(0xFF1E1B2E));
  final pic = rec.endRecording();
  final img = await pic.toImage(width, height);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  pic.dispose();
  return data!.buffer.asUint8List();
}

/// 一张 8×6 的 JPG（用 Pillow 生成后贴进来的，不是下载的）。
final Uint8List kTinyJpg = base64Decode(_tinyJpg);

/// 一张 8×6 的 WebP（同上）。
final Uint8List kTinyWebp = base64Decode(_tinyWebp);

/// 只有文件头的假 GIF。
final Uint8List kGifHeader = Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0]);

/// 把字节写进 [dir] 下的一个“缓存副本”，返回路径（模拟原生那头交回来的文件）。
String writePick(Directory dir, String name, List<int> bytes) {
  final f = File(p.join(dir.path, 'cache', name))..parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
  return f.path;
}

const String _tinyJpg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAGAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDHVQucZooor5evXqYio6tV3k+v4H6Fh8PSw1NUqMbRWy/E/9k=';
const String _tinyWebp = 'UklGRlAAAABXRUJQVlA4IEQAAADQAQCdASoIAAYAAUAmJbACdLoB+AADsAD+6NvHr+b2d0R3C4/+Wxze6Bmh8Nv/lyep6f84+n/xAXWrO9B39B3+agAAAA==';
