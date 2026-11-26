// 设计约束（低代码 · 画布上就地改文字 · 390×844）
// - 对象：文字、按钮（改上面的字）、输入框（改提示文字）。点一下已经选中的它，原地变成输入框。
// - 内容主次：只有这一个输入框——字号、对齐、内边距照组件原样，盖在组件原来的位置上；一圈强调色的边告诉她“正在改”。
// - 键盘上方不加工具行。点别处、键盘上的“完成”、收键盘＝提交；整次只记一条撤销。没改就不记。
// - 键盘弹出来把它挡住时，画布自己滚到露出来。
// - 取用的 tokens：accent（那一圈边）、Radii.sm。
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 这种组件点第二下改的是哪个属性；不能就地改返回 null。
String? inlineTextProp(LcNode n) => switch (n.type) {
  'text' || 'button' => n.bind.containsKey('text') ? null : 'text',
  'input' => n.bind.containsKey('placeholder') ? null : 'placeholder',
  _ => null,
};

class InlineTextEditor extends StatefulWidget {
  const InlineTextEditor({super.key, required this.canvas, required this.node, required this.parent, required this.origin, required this.onDone});
  final CanvasViewState canvas;
  final LcNode node;
  final LcNode? parent;

  /// 搭建台左上角在屏幕上的位置（把画布给的屏幕坐标换成这一层自己的坐标用）。
  final Offset Function() origin;

  /// 改完了：[text] 是新的字；没改是 null。
  final void Function(String? text) onDone;

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late final String _prop = inlineTextProp(widget.node)!;
  late final String _initial = widget.node.strProp(_prop) ?? '';
  late final TextEditingController _text = TextEditingController(text: _initial)..selection = TextSelection(baseOffset: 0, extentOffset: _initial.length);
  final FocusNode _focus = FocusNode();
  bool _done = false;
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    final v = _text.text;
    widget.onDone(v == _initial ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = widget.node;
    final r = resolvedStyle(n, widget.parent);
    final multiline = n.type == 'text';
    return LayoutBuilder(
      builder: (context, box) {
        // 这一层的大小变了（键盘弹出来把画布挤矮了）：等排完版让画布把它滚到露出来。
        if (_lastSize != box.biggest) {
          _lastSize = box.biggest;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.canvas.revealNode(n.id);
          });
        }
        return ValueListenableBuilder<CanvasViewport>(
          valueListenable: widget.canvas.view,
          builder: (context, _, _) {
            final screen = widget.canvas.nodeScreenRect(n.id);
            if (screen == null) return const SizedBox.shrink();
            final rect = screen.shift(-widget.origin());
            final scale = widget.canvas.scale;
            final own = cssColorToArgb(r['background-color']);
            final fg = Color(cssColorToArgb(n.type == 'input' ? null : r['color']) ?? 0xFF222435);
            // 组件自己没有底色时垫一块和字反差够大的底，免得白字落在白底上看不见。
            final bg = own != null && (own >> 24) > 0x40 ? Color(own) : (fg.computeLuminance() > 0.6 ? const Color(0xFF222435) : Colors.white);
            final pad = n.type == 'input' ? 12.0 : (effectivePx(n, widget.parent, 'padding-left') ?? 0).toDouble();
            final padV = n.type == 'input' ? 12.0 : (effectivePx(n, widget.parent, 'padding-top') ?? 0).toDouble();
            final weight = r['font-weight'];
            return Stack(
              children: [
                Positioned(
                  left: rect.left.clamp(0.0, (box.maxWidth - 120).clamp(0.0, double.infinity)).toDouble(),
                  top: rect.top,
                  width: rect.width.clamp(120.0, box.maxWidth).toDouble(),
                  child: Material(
                    color: bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      side: BorderSide(color: c.accent, width: 2),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: rect.height),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: pad * scale, vertical: padV * scale),
                        child: TextField(
                          key: const Key('lc-inline-edit'),
                          controller: _text,
                          focusNode: _focus,
                          autofocus: true,
                          maxLines: multiline ? null : 1,
                          textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
                          textAlign: switch (n.type == 'button' ? 'center' : r['text-align']) {
                            'center' => TextAlign.center,
                            'right' => TextAlign.right,
                            _ => TextAlign.left,
                          },
                          cursorColor: fg,
                          style: TextStyle(
                            fontSize: ((effectivePx(n, widget.parent, 'font-size') ?? 16) * scale).toDouble(),
                            color: fg,
                            fontWeight: weight == 'bold' || (int.tryParse(weight ?? '') ?? 400) >= 600 ? FontWeight.w600 : FontWeight.w400,
                            height: n.type == 'text' ? 1.5 : null,
                          ),
                          // 各种状态的边框都明说关掉，不跟着主题里输入框的描边走（外面那圈蓝边是这个编辑框自己的）
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _finish(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
