// 设计约束（参数小卡，390 宽，浅色 + 深色）— 2026-11-25
// - 点一下参数小块，贴着它弹出一张小卡（宽 280），不是整页；点卡片外面＝不改就关。
// - 层级：名字输入框是主角（一打开光标就在里面、全选，直接打字就是改名）；下面的都是次要的，用小字和中性色。
// - 一行只做一件事，从上到下：名字 → 默认值（这种参数能给才有；填了“剩下的全收”就没有）→ “剩下的全收”开关（只有最后一个参数有）
//   → 最底下一行：左边“删除”（危险色的字，不是大红按钮），右边“好”。
// - 名字不合适（空的、重名、带花括号）就在输入框下面用危险色说清原因，“好”按不动；不弹对话框。
// - 键盘弹起时小卡整个挪到键盘上面，不被挡住。
import 'dart:math' as math;

import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 小卡的结果：`param == null`＝删掉这个参数；否则是改好的参数。
typedef BkParamChoice = ({BlockParam? param});

Future<BkParamChoice?> showBlockParamCard(BuildContext context, {required Rect anchor, required BlockParam param, required List<String> others, bool canDefault = false, bool canRest = false}) {
  return showGeneralDialog<BkParamChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: context.colors.scrimOf(0.18),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) => BlockParamCardView(anchor: anchor, param: param, others: others, canDefault: canDefault, canRest: canRest),
  );
}

/// 默认值输入框里的字 → 值：空＝没有默认值；像数字的是数字；“是 / 否”是布尔；别的是文字。
Object? bkParseDefault(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final n = num.tryParse(t);
  if (n != null && n.isFinite) return n;
  if (t == '是') return true;
  if (t == '否') return false;
  return t;
}

String bkDefaultText(Object? v) => v == null ? '' : (v is bool ? (v ? '是' : '否') : (v is num ? bkLookNumber(v) : '$v'));

class BlockParamCardView extends StatefulWidget {
  const BlockParamCardView({super.key, required this.anchor, required this.param, required this.others, this.canDefault = false, this.canRest = false});

  final Rect anchor;
  final BlockParam param;
  final List<String> others;
  final bool canDefault;
  final bool canRest;

  @override
  State<BlockParamCardView> createState() => _BlockParamCardViewState();
}

class _BlockParamCardViewState extends State<BlockParamCardView> {
  late final TextEditingController _name = TextEditingController(text: widget.param.name)..selection = TextSelection(baseOffset: 0, extentOffset: widget.param.name.length);
  late final TextEditingController _default = TextEditingController(text: bkDefaultText(widget.param.defaultValue));
  late bool _rest = widget.param.rest;

  @override
  void dispose() {
    _name.dispose();
    _default.dispose();
    super.dispose();
  }

  String? get _problem => bkParamNameProblem(_name.text, widget.others);

  void _done() {
    if (_problem != null) return;
    final d = widget.canDefault && !_rest ? bkParseDefault(_default.text) : null;
    Navigator.pop<BkParamChoice>(context, (param: BlockParam(_name.text.trim(), defaultValue: d, rest: _rest)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final width = math.min(280.0, screen.width - 24);
    final a = widget.anchor;
    final safeTop = media.padding.top + 8, safeBottom = screen.height - media.viewInsets.bottom - 8;
    final left = (a.left - 8).clamp(12.0, math.max(12.0, screen.width - width - 12)).toDouble();
    final problem = _problem;
    final showDefault = widget.canDefault && !_rest;
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: c.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
    Widget caption(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        s,
        style: t.labelMedium?.copyWith(color: c.textMuted, fontWeight: FontWeight.w600),
      ),
    );
    final card = Material(
      key: const ValueKey('bk-param-card'),
      color: c.surface,
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            caption('参数的名字'),
            TextField(
              key: const ValueKey('bk-param-name'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: field('名字'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  problem,
                  key: const ValueKey('bk-param-problem'),
                  style: t.bodySmall?.copyWith(color: c.danger),
                ),
              ),
            if (showDefault) ...[
              const SizedBox(height: 14),
              caption('默认值（不填＝调用时必须给）'),
              TextField(key: const ValueKey('bk-param-default'), controller: _default, textInputAction: TextInputAction.done, decoration: field('没有默认值'), onSubmitted: (_) => _done()),
            ],
            if (widget.canRest) ...[
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('bk-param-rest'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _rest = !_rest),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('剩下的全收', style: t.bodyMedium),
                            Text('调用时多给的值都装进它里面（一个列表）', style: t.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IgnorePointer(
                        child: Switch(value: _rest, onChanged: (_) {}),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('bk-param-delete'),
                  onPressed: () => Navigator.pop<BkParamChoice>(context, (param: null)),
                  style: TextButton.styleFrom(foregroundColor: c.danger, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text('删除这个参数'),
                ),
                const Spacer(),
                TextButton(key: const ValueKey('bk-param-ok'), onPressed: problem == null ? _done : null, child: const Text('好')),
              ],
            ),
          ],
        ),
      ),
    );
    // 放在小块下面；下面（键盘上面）放不下就贴着键盘上沿往上放。
    return Stack(
      children: [
        Positioned(
          left: left,
          width: width,
          top: 0,
          bottom: 0,
          child: CustomSingleChildLayout(
            delegate: _Placed(top: a.bottom + 6, minTop: safeTop, maxBottom: safeBottom),
            child: card,
          ),
        ),
      ],
    );
  }
}

/// 把小卡放在 `top`；放不下（超过 `maxBottom`）就往上挪到刚好放下，但不高过 `minTop`。
class _Placed extends SingleChildLayoutDelegate {
  const _Placed({required this.top, required this.minTop, required this.maxBottom});
  final double top, minTop, maxBottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth, maxHeight: math.max(120, maxBottom - minTop));

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(0, math.max(minTop, math.min(top, maxBottom - childSize.height)));

  @override
  bool shouldRelayout(_Placed old) => old.top != top || old.minTop != minTop || old.maxBottom != maxBottom;
}
