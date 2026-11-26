// 设计约束（正文里的图片 · 390×844）— 2026-11-26
// - 工作区里的图片、写在消息里的 data: 图片：直接显示。最宽占满这一行，最高 320，等比缩小不裁切；点一下全屏看（可双指放大）。
// - https 图片默认**不自动下**：先是一小块占位（图标 + “点一下加载图片” + 主机名），点了才联网。
//   这样模型写出来的图片地址不会悄悄联网、把“你看了这条消息”告诉别人。设置里可以改成自动加载。
// - 不加载的（http 明文、别的协议、工作区外面的路径、太大、下不下来）：同样一小块占位，写明原因；能重试的点一下重试。
// - 占位块是一行：图标 + 一句话，不抢正文的戏（灰字小字）。
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/markdown/md_image_loader.dart';
import 'package:lopicode/markdown/md_links.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/md_style.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 图片在正文里最高这么多（自己定的）。
const double kMdImageMaxHeight = 320;

class MdImageView extends StatefulWidget {
  const MdImageView({super.key, required this.src, required this.alt});
  final String src;
  final String alt;

  @override
  State<MdImageView> createState() => _MdImageViewState();
}

class _MdImageViewState extends State<MdImageView> {
  MdImageSource? _source;
  String? _resolvedFor;
  Uint8List? _bytes;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = MdScope.of(context);
    final key = '${scope.guard?.root}\n${widget.src}';
    if (_resolvedFor != key) {
      _resolvedFor = key;
      _resolve(scope);
    }
    // 设置改成了自动加载：还没下的这就去下
    if (scope.autoImages && _source is MdNetImage && _bytes == null && !_loading && _error == null) {
      // 推后一拍：现在正在搭界面，不能改状态
      Future.microtask(() {
        if (mounted) _load();
      });
    }
  }

  @override
  void didUpdateWidget(MdImageView old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _resolvedFor = null;
      didChangeDependencies();
    }
  }

  void _resolve(MdScope scope) {
    _bytes = null;
    _error = null;
    _loading = false;
    var source = mdResolveImage(widget.src, scope.guard);
    if (source is MdLocalImage) {
      // 文件小、只看一眼大小：同步读，免得多画一帧占位
      try {
        final f = File(source.path);
        if (!f.existsSync()) {
          source = const MdBlockedImage('工作区里没有这张图片');
        } else if (f.lengthSync() > kMdLocalImageMaxBytes) {
          source = const MdBlockedImage('图片太大（超过 20MB），不显示');
        }
      } on FileSystemException {
        source = const MdBlockedImage('这张图片读不出来');
      }
    }
    if (source is MdNetImage) _bytes = MdImageLoader.instance.cached(source.uri);
    if (source is MdDataImage) _bytes = source.bytes;
    _source = source;
  }

  Future<void> _load() async {
    final source = _source;
    if (source is! MdNetImage || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await MdImageLoader.instance.load(source.uri);
      if (!mounted || !identical(_source, source)) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } on MdImageException catch (e) {
      if (!mounted || !identical(_source, source)) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source!;
    final alt = widget.alt.trim();
    switch (source) {
      case MdBlockedImage(:final reason):
        return _Chip(icon: Icons.image_not_supported_outlined, text: alt.isEmpty ? reason : '$alt（$reason）');
      case MdLocalImage(:final path):
        return _framed(
          context,
          (cacheWidth) => Image.file(
            File(path),
            key: const Key('md-image'),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            semanticLabel: alt.isEmpty ? null : alt,
            errorBuilder: (_, _, _) => _Chip(icon: Icons.broken_image_outlined, text: alt.isEmpty ? '这张图片显示不出来' : '$alt（显示不出来）'),
          ),
        );
      case MdDataImage():
      case MdNetImage():
        final bytes = _bytes;
        if (bytes != null) {
          return _framed(
            context,
            (cacheWidth) => Image.memory(
              bytes,
              key: const Key('md-image'),
              fit: BoxFit.contain,
              cacheWidth: cacheWidth,
              semanticLabel: alt.isEmpty ? null : alt,
              errorBuilder: (_, _, _) => _Chip(icon: Icons.broken_image_outlined, text: alt.isEmpty ? '这张图片显示不出来' : '$alt（显示不出来）'),
            ),
          );
        }
        final host = source is MdNetImage ? source.uri.host : '';
        if (_loading) return _Chip(icon: Icons.downloading_rounded, text: '正在加载图片（$host）…');
        if (_error != null) return _Chip(key: const Key('md-image-retry'), icon: Icons.broken_image_outlined, text: '图片没加载出来：$_error。点一下重试', onTap: _load);
        return _Chip(key: const Key('md-image-load'), icon: Icons.image_outlined, text: '${alt.isEmpty ? '图片' : alt} · 点一下加载（$host）', onTap: _load);
    }
  }

  Widget _framed(BuildContext context, Widget Function(int cacheWidth) image) {
    // 解码时就按屏幕宽度缩小，大图不占满内存
    final mq = MediaQuery.of(context);
    final cacheWidth = (mq.size.width * mq.devicePixelRatio).round().clamp(64, 2048);
    final child = image(cacheWidth);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ImageScreen(image: image(cacheWidth), title: widget.alt.trim()))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: kMdImageMaxHeight),
        child: ClipRRect(borderRadius: BorderRadius.circular(Radii.sm), child: child),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MdScope.of(context).styles;
    final c = s.colors;
    final t = Theme.of(context).textTheme;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
      decoration: BoxDecoration(
        color: s.blockBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: s.tone == MdTone.body ? null : Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: onTap == null ? c.textFaint : c.accent),
          const SizedBox(width: Space.x2),
          Flexible(
            child: Text(text, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      child: InkWell(borderRadius: BorderRadius.circular(Radii.md), onTap: onTap, child: body),
    );
  }
}

class _ImageScreen extends StatelessWidget {
  const _ImageScreen({required this.image, required this.title});
  final Widget image;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: PageBar(titleText: title.isEmpty ? '图片' : title),
    body: BelowBar(
      child: SafeArea(
        top: false,
        child: InteractiveViewer(maxScale: 6, child: Center(child: image)),
      ),
    ),
  );
}
