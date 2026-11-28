// 设计约束（低代码 · 画布上就地改文字 · 390×844）
// - 对象：文字、按钮（改上面的字）、输入框（改提示文字）、列表（一行一项）、图片（改说明文字）。点一下已经选中的它，原地变成输入框。
// - 列表：整张列表一个框，一行就是一项（回车＝加一项，删空一行＝去掉那一项）；不用先分清点的是第几项。
// - 图片：说明文字平时看不见（读屏念它、图片加载不出来时显示它），所以框贴在图片下沿、带一句灰字说明这是什么。
// - 内容主次：只有这一个输入框——字号、对齐、内边距照组件原样，盖在组件原来的位置上、和组件一样宽（字多了跟着变宽）；
//   一圈强调色的边告诉她“正在改”。
// - 键盘上方不加工具行。点别处、键盘上的“完成”、收键盘＝提交；整次只记一条撤销。没改就不记。
// - 键盘弹出来把它挡住时，画布自己滚到露出来。
// - 取用的 tokens：accent（那一圈边）、Radii.sm。
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 就地改字的框最窄多宽：够放一个光标和一两个字。
const double kInlineEditMinWidth = 32;

/// 图片说明的框大约多高（字 14 + 上下各 8，按画布缩放）。
const double _altHeight = 38;

/// 这种组件点第二下改的是哪个属性；不能就地改返回 null。
String? inlineTextProp(LcNode n) {
  final prop = switch (n.type) {
    'text' || 'button' => 'text',
    'input' => 'placeholder',
    'list' => 'items',
    'image' => 'alt',
    _ => null,
  };
  // 绑了状态的（跟着状态变）不在这里改：改了也看不出来。
  return prop == null || n.bind.containsKey(prop) || lcDataSrc(n, prop) != null ? null : prop;
}

/// 就地改字的框里一开始是什么字（列表＝一行一项）。
String inlineTextInitial(LcNode n) {
  final prop = inlineTextProp(n);
  if (prop == null) return '';
  final v = n.props[prop];
  return prop == 'items' ? (v is List ? v.join('\n') : '') : (v is String ? v : '');
}

/// 把框里的字写回组件。列表：一行一项，空行不算；图片说明删空了就去掉这个属性。
void inlineTextWrite(LcNode n, String text) {
  final prop = inlineTextProp(n);
  if (prop == null) return;
  if (prop == 'items') {
    n.props[prop] = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  } else if (prop == 'alt' && text.trim().isEmpty) {
    n.props.remove(prop);
  } else {
    n.props[prop] = text;
  }
}

/// 图片的说明文字框里没字时的那句灰字。
const String kInlineAltHint = '图片说明（图片出不来时显示）';

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
  late final String _initial = inlineTextInitial(widget.node);
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
    final r = resolvedStyle(lcViewNode(n, widget.canvas.env), widget.parent);
    final multiline = n.type == 'text' || n.type == 'list';
    final isAlt = _prop == 'alt';
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
            // 图片的底色只是“还没图”时的占位色，不拿来当输入框的底。
            final own = isAlt ? null : cssColorToArgb(r['background-color']);
            final fg = Color(cssColorToArgb(n.type == 'input' || isAlt ? null : r['color']) ?? 0xFF222435);
            // 组件自己没有底色时垫一块和字反差够大的底，免得白字落在白底上看不见。
            final bg = own != null && (own >> 24) > 0x40 ? Color(own) : (fg.computeLuminance() > 0.6 ? const Color(0xFF222435) : Colors.white);
            final pad = isAlt
                ? 8.0
                : n.type == 'list'
                ? 20.0
                : n.type == 'input'
                ? 12.0
                : (effectivePx(n, widget.parent, 'padding-left') ?? 0).toDouble();
            final padV = isAlt
                ? 8.0
                : n.type == 'input'
                ? 12.0
                : (effectivePx(n, widget.parent, 'padding-top') ?? 0).toDouble();
            final weight = r['font-weight'];
            // 最窄不小于 [kInlineEditMinWidth]（空文字的组件量出来可能是 0 宽，得有地方放光标）。
            final minWidth = rect.width.clamp(kInlineEditMinWidth, box.maxWidth).toDouble();
            final left = rect.left.clamp(0.0, (box.maxWidth - minWidth).clamp(0.0, double.infinity)).toDouble();
            return Stack(
              children: [
                Positioned(
                  left: left,
                  // 图片：框贴着图片的下沿（不盖住整张图）。
                  top: isAlt ? (rect.bottom - _altHeight * scale).clamp(rect.top, double.infinity).toDouble() : rect.top,
                  // 和组件一样宽；字打多了跟着变宽，最宽到屏幕右边（以前最窄 120，小按钮上的框比按钮还宽）。
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth, maxWidth: (box.maxWidth - left).clamp(minWidth, double.infinity).toDouble()),
                    child: IntrinsicWidth(
                      child: Material(
                        color: bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          side: BorderSide(color: c.accent, width: 2),
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: isAlt ? 0 : rect.height),
                          child: // 字比组件矮（按钮、带内边距的输入框）时上下居中：以前贴着上沿，和画布上原来的字对不上。
                          Align(
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
                                  fontSize: ((isAlt ? 14 : effectivePx(n, widget.parent, 'font-size') ?? 16) * scale).toDouble(),
                                  color: fg,
                                  fontWeight: weight == 'bold' || (int.tryParse(weight ?? '') ?? 400) >= 600 ? FontWeight.w600 : FontWeight.w400,
                                  height: n.type == 'text' ? 1.5 : (n.type == 'list' ? 1.75 : null),
                                ),
                                // 各种状态的边框都明说关掉，不跟着主题里输入框的描边走（外面那圈蓝边是这个编辑框自己的）
                                decoration: InputDecoration(
                                  hintText: isAlt ? kInlineAltHint : null,
                                  hintStyle: isAlt ? TextStyle(fontSize: 14 * scale, color: fg.withValues(alpha: 0.5)) : null,
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
