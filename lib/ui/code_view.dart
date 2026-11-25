// 设计约束（代码区域共用的三样东西 · 390×844，浅色 + 深色）— 2026-11-25
// - 所有显示或编辑代码的地方都用这里的东西：文件编辑器套 CodeZoom；只读代码用 CodeView；多行输入框用 CodeTextController。
// - 双指捏合调字号：10–24，一步 1，默认 14；全应用一个值，松手才存盘。捏的时候右上角浮一个小数字，松手就消失。
// - 单指的事（滚动、长按选字、拖光标）一律不拦：只有第二根手指落下以后才接手。
// - 高亮只上色，不改字重；语言不认识就是普通的等宽字。
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_langs.dart';
import 'package:material_ui/material_ui.dart';

/// 给一块代码区域加上“双指捏合调字号”。字号从 [codeFontProvider] 读，孩子自己订阅它来重画。
class CodeZoom extends ConsumerStatefulWidget {
  const CodeZoom({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CodeZoom> createState() => _CodeZoomState();
}

class _CodeZoomState extends ConsumerState<CodeZoom> {
  /// 现在按在这块区域上的手指（指针编号 → 位置）。
  final Map<int, Offset> _points = {};
  double? _startDistance;
  double _startSize = kCodeFontDefault;

  bool get _pinching => _startDistance != null;

  double _distance() {
    final p = _points.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _points[e.pointer] = e.position;
    if (_points.length == 2) {
      // 两指贴得太近时距离很小，比例会乱跳：按至少 24 算。
      setState(() {
        _startDistance = math.max(_distance(), 24);
        _startSize = ref.read(codeFontProvider);
      });
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_points.containsKey(e.pointer)) return;
    _points[e.pointer] = e.position;
    final start = _startDistance;
    if (start == null || _points.length < 2) return;
    ref.read(codeFontProvider.notifier).preview(_startSize * _distance() / start);
  }

  void _up(PointerEvent e) {
    if (_points.remove(e.pointer) == null) return;
    if (_pinching && _points.length < 2) {
      ref.read(codeFontProvider.notifier).commit();
      if (mounted) setState(() => _startDistance = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = ref.watch(codeFontProvider);
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {_PinchClaim: GestureRecognizerFactoryWithHandlers<_PinchClaim>(_PinchClaim.new, (r) => r.fingers = () => _points.length)},
      // 里面这层先收到事件（先数手指），外面的识别器再决定要不要把这次手势抢过来。
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_pinching)
              Positioned(
                top: Space.x2,
                right: Space.x2,
                child: IgnorePointer(
                  child: Container(
                    key: const Key('code-zoom-badge'),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
                    decoration: BoxDecoration(color: c.text.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '字号 ${size.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: FontSize.xs, color: c.surface, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 第二根手指落下时把这次手势抢过来，免得两根手指一边缩放一边带着页面滚。
/// 只有一根手指时它什么都不抢：手指抬起就认输，单指的滚动 / 长按 / 点按照旧。
class _PinchClaim extends OneSequenceGestureRecognizer {
  int Function() fingers = () => 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (fingers() >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (fingers() < 2) resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'code pinch';
}

/// 只读的代码：带高亮、可选中、可捏合缩放。自己不滚动，外面套滚动容器。
class CodeView extends ConsumerStatefulWidget {
  const CodeView({super.key, required this.code, required this.language, this.color});
  final String code;

  /// 语言 id（`CodeHighlighter.languageFor` / `languageForLabel` 的返回值）。
  final String language;

  /// 没上色部分的文字颜色，默认正文色。
  final Color? color;

  @override
  ConsumerState<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends ConsumerState<CodeView> {
  TextSpan? _span;
  Object? _spanFor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = ref.watch(codeFontProvider);
    final base = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: size, height: 1.5, color: widget.color ?? context.colors.text);
    // 上色只跟代码、语言、深浅色有关：字号变了不用重算（字号在外层样式里）。
    final key = (widget.code, widget.language, dark, base.color);
    if (_spanFor != key) {
      // 制表符在普通文字控件里只有一个空格宽，缩进会看不出来：显示时换成 4 个空格（“复制全部”拿的是原文，不受影响）。
      _span = highlightCode(
        widget.code.replaceAll('\t', '    '),
        widget.language,
        dark: dark,
        base: TextStyle(color: base.color),
      );
      _spanFor = key;
    }
    return SelectableText.rich(_span!, key: const Key('code-view-text'), style: base);
  }
}

/// 多行代码输入框用的控制器：边输入边上色。正在用输入法组字时不上色（保留组字下划线）。
class CodeTextController extends TextEditingController {
  CodeTextController({super.text, required this.language});
  final String language;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (withComposing && value.isComposingRangeValid) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final span = highlightCode(
      text,
      language,
      dark: dark,
      base: TextStyle(color: style?.color),
    );
    return TextSpan(style: style, children: [span]);
  }
}
