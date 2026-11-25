// 设计约束（主题的实时预览：界面 / 代码 / 积木 / 终端，外加“搭建”（低代码编辑器，在 theme_preview_lowcode.dart）· 宽约 358、高 232）— 2026-11-26
// - 用途：主题编辑器顶上固定的那一块、导入预览页。**用传进来的那份主题渲染**（不是全应用正在用的那份），
//   所以改到一半的主题、还没导入的主题都能看；它不碰全应用的主题。
// - 层级：预览只是“看”，不是操作区——整块不接手指、不进读屏（里面的按钮开关都是样子）。
// - 每种预览尽量把这一节里常用的项都露出来，一眼能看出改了哪里：
//   界面＝顶栏按钮 + 两种气泡 + 卡片（正文 / 次要 / 提示三档字、开关）+ 按钮一行（实心、强调浅底、危险、警告）+ 输入框 + 底部导航；
//   代码＝带行号的一小段（注释、关键字、类名、函数名、参数、数字、字符串、插值）+ 当前行 + 光标 + 选区 / 查找命中 + 改动对比两行；
//   积木＝点阵画布上三块拼在一起的积木（选中描边、报错 / 警告角标、输入框、槽位）+ 20 类主色各一枚小牌；
//   终端＝16 色两排 + 几行带颜色的输出 + 选区 / 查找命中 + 光标。
// - 排版：等宽字 11.5、行高 16；界面预览吃这份主题自己的圆角 / 字号倍率（放大了装不下就裁掉，不报溢出）。
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_langs.dart';
import 'package:lopicode/ui/theme_preview_lowcode.dart';
import 'package:material_ui/material_ui.dart';

enum ThemePreviewKind {
  ui('界面'),
  code('代码'),
  blocks('积木'),
  terminal('终端'),
  lowcode('搭建');

  const ThemePreviewKind(this.label);
  final String label;
}

/// 预览块的高度。
const double kThemePreviewHeight = 232;

class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.spec, required this.kind, this.height = kThemePreviewHeight});
  final ThemeSpec spec;
  final ThemePreviewKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final outer = context.colors;
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final scale = spec.metric(MetricKey.fontScale);
    return Container(
      key: Key('theme-preview-${kind.name}'),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: outer.border, width: outer.hairline),
      ),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Theme(
            data: buildThemeData(spec, fontFamily: font),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: kind == ThemePreviewKind.ui ? TextScaler.linear(scale) : TextScaler.noScaling),
              // 放大字号后可能比这一块高：允许里面比外面长，多出来的裁掉。
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: switch (kind) {
                    ThemePreviewKind.ui => const _UiPreview(),
                    ThemePreviewKind.code => _CodePreview(spec: spec),
                    ThemePreviewKind.blocks => _BlocksPreview(spec: spec),
                    ThemePreviewKind.terminal => _TerminalPreview(spec: spec),
                    ThemePreviewKind.lowcode => ThemeLowcodePreview(spec: spec),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 界面 ─────────────────────────────────────────────
class _UiPreview extends StatelessWidget {
  const _UiPreview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget bubble(String text, Color bg, Color fg) => Container(
      padding: EdgeInsets.symmetric(horizontal: c.space(Space.x3), vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(c.radius(Radii.bubble))),
      child: Text(text, style: t.bodySmall?.copyWith(color: fg)),
    );
    Widget chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(c.radius(Radii.sm))),
      child: Text(text, style: t.labelSmall?.copyWith(color: fg)),
    );
    return ColoredBox(
      color: c.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, 0),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.barButtonBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.border, width: c.hairline),
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: c.text),
                ),
                const SizedBox(width: Space.x2),
                Text('对话', style: t.labelLarge?.copyWith(color: c.text)),
                const SizedBox(width: Space.x2),
                Text('次要文字', style: t.labelSmall?.copyWith(color: c.textMuted)),
                const Spacer(),
                Text('链接', style: t.labelSmall?.copyWith(color: c.link)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x3, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [bubble('Agent 的回复', c.bubbleAgentBg, c.bubbleAgentText), bubble('我发的消息', c.bubbleMineBg, c.bubbleMineText)]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x3, 6),
            color: c.canvas,
            child: Container(
              padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x2, 6),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(c.radius(Radii.md)),
                border: Border.all(color: c.border, width: c.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('卡片里的正文', style: t.bodySmall?.copyWith(color: c.text)),
                        Text('提示文字 · 12:30', style: t.labelSmall?.copyWith(color: c.textFaint)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Switch(value: true, onChanged: (_) {}, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x3, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 5),
                  decoration: BoxDecoration(color: c.accentFill, borderRadius: BorderRadius.circular(c.radius(Radii.md))),
                  child: Text('主按钮', style: t.labelMedium?.copyWith(color: c.onAccent)),
                ),
                const SizedBox(width: Space.x2),
                chip('强调', c.accentSoft, c.accent),
                const SizedBox(width: 6),
                chip('危险', c.dangerSoft, c.danger),
                const SizedBox(width: 6),
                chip('警告', c.warningSoft, c.warning),
                const SizedBox(width: 6),
                chip('成功', c.successSoft, c.success),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x3, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 6),
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: BorderRadius.circular(c.radius(Radii.md)),
                border: Border.all(color: c.border, width: c.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('输入框里的提示字', style: t.bodySmall?.copyWith(color: c.textFaint)),
                  ),
                  Icon(Icons.arrow_upward_rounded, size: 14, color: c.accent),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.navBg,
              border: Border(
                top: BorderSide(color: c.border, width: c.hairline),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (i, (icon, label)) in const [(Icons.chat_bubble_outline, '对话'), (Icons.folder_outlined, '文件'), (Icons.terminal, '终端')].indexed)
                  // 图标和字排成一行：竖着叠会比这块预览高出一截，字被裁掉一半。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: i == 0 ? c.navActive : c.navInactive),
                      const SizedBox(width: 4),
                      Text(label, style: t.labelSmall?.copyWith(color: i == 0 ? c.navActive : c.navInactive, fontSize: 9)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 代码 ─────────────────────────────────────────────
const List<String> _codeLines = [
  '// 注释：算一下总价',
  'class Cart extends Base {',
  '  total(items, rate = 0.08) {',
  '    const sum = items.reduce(add, 0);',
  r'    return `合计 ${sum * (1 + rate)}`;',
  '  }',
  '}',
];
const int _currentLine = 3;

const TextStyle _mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: 11.5, height: 16 / 11.5);

class _CodePreview extends StatelessWidget {
  const _CodePreview({required this.spec});
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    final fg = spec.codeColor(CodeKey.fg);
    final base = _mono.copyWith(color: fg);
    Widget line(int i) {
      final current = i == _currentLine;
      return Container(
        color: current ? spec.codeColor(CodeKey.currentLine) : null,
        padding: const EdgeInsets.only(right: Space.x2),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.end,
                style: _mono.copyWith(color: spec.codeColor(current ? CodeKey.lineNumberActive : CodeKey.lineNumber)),
              ),
            ),
            const SizedBox(width: Space.x2),
            Flexible(
              child: Text.rich(
                highlightCode(_codeLines[i], 'js', theme: spec, base: base),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
            if (current) Container(width: 2, height: 14, color: spec.codeColor(CodeKey.cursor)),
          ],
        ),
      );
    }

    Widget diff(String sign, String text, Color bg, Color ink) => Container(
      color: bg,
      padding: const EdgeInsets.only(left: Space.x3, right: Space.x2),
      child: Text(
        '$sign $text',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: _mono.copyWith(color: ink),
      ),
    );

    return ColoredBox(
      color: spec.codeColor(CodeKey.bg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.x2),
          for (var i = 0; i < _codeLines.length; i++) line(i),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, 6, Space.x2, 6),
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(
                    text: ' 选中的字 ',
                    style: TextStyle(backgroundColor: spec.codeColor(CodeKey.selection)),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: ' 查找命中 ',
                    style: TextStyle(backgroundColor: spec.codeColor(CodeKey.searchHit)),
                  ),
                ],
              ),
            ),
          ),
          diff('-', 'rate = 0.05', spec.codeColor(CodeKey.diffDelBg), spec.codeColor(CodeKey.diffDelFg)),
          diff('+', 'rate = 0.08', spec.codeColor(CodeKey.diffAddBg), spec.codeColor(CodeKey.diffAddFg)),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  }
}

// ── 积木 ─────────────────────────────────────────────
class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 10.0; y < size.height; y += 20) {
      for (var x = 10.0; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

class _BlocksPreview extends StatelessWidget {
  const _BlocksPreview({required this.spec});
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = BkPalette.fromTheme(spec);
    const style = TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600);

    Widget field(BkTone tone, String text, {bool hint = false}) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.fieldBg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: style.copyWith(color: hint ? tone.fieldHint : tone.fieldText, fontWeight: FontWeight.w400),
      ),
    );
    Widget slot(BkTone tone, String text) => Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.deep, borderRadius: BorderRadius.circular(6)),
      // 下拉的小三角用图标画：自带字体里没有“▾”这个字，会显示成方框。
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: style.copyWith(color: tone.text)),
          Icon(Icons.arrow_drop_down, size: 14, color: tone.text),
        ],
      ),
    );
    Widget block(String key, String label, {List<Widget> parts = const [], bool selected = false, Color? badge, Color? onBadge, String mark = '!', double indent = 0}) {
      final tone = p.tone(key);
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 3),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tone.fillTop, tone.fill]),
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border.all(color: p.selection, width: 2) : Border(bottom: BorderSide(color: tone.edge, width: 2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: style.copyWith(color: tone.text)),
                  ...parts,
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                  child: Text(
                    mark,
                    style: TextStyle(fontSize: 9, height: 1, fontWeight: FontWeight.w700, color: onBadge),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: p.canvas,
      child: CustomPaint(
        painter: _DotsPainter(p.canvasDot),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              block('event', '当 按钮被点击', parts: [slot(p.tone('event'), '按钮1')]),
              block('control', '如果', parts: [field(p.tone('control'), '条件', hint: true)], selected: true),
              block('variable', '设 总价 为', parts: [field(p.tone('variable'), '0')], indent: Space.x4, badge: p.warning, onBadge: p.onWarning),
              block('action', '显示', parts: [field(p.tone('action'), '你好')], indent: Space.x4, badge: p.error, onBadge: p.onError, mark: '×'),
              const SizedBox(height: 5),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final f in kBlockCategoryFields)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: p.tone(f.key).fill, borderRadius: BorderRadius.circular(5)),
                      child: Text(f.label, style: TextStyle(fontSize: 9.5, height: 1.2, color: p.tone(f.key).text)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 终端 ─────────────────────────────────────────────
const List<String> _ansi = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'];
const List<String> _ansiBright = ['brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightMagenta', 'brightCyan', 'brightWhite'];

class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview({required this.spec});
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    Color k(String key) => spec.terminalColor(key);
    final base = _mono.copyWith(color: k('fg'));
    TextSpan s(String text, [String? key]) => TextSpan(
      text: text,
      style: key == null ? null : TextStyle(color: k(key)),
    );
    Widget strip(List<String> keys) => Row(
      children: [
        for (final key in keys)
          Expanded(
            child: Container(key: Key('theme-preview-ansi-$key'), height: 12, margin: const EdgeInsets.only(right: 2), color: k(key)),
          ),
      ],
    );
    Widget line(List<InlineSpan> spans) => Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
    );
    return ColoredBox(
      color: k('bg'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            strip(_ansi),
            const SizedBox(height: 2),
            strip(_ansiBright),
            const SizedBox(height: Space.x2),
            line([s('root@localhost', 'green'), s(':'), s('/workspace', 'blue'), s('# npm run build')]),
            line([s('> vite build', 'brightBlack')]),
            line([s('✓ ', 'brightGreen'), s('128 modules transformed.')]),
            line([s('warning', 'yellow'), s(': chunk is larger than 500 kB')]),
            line([s('error', 'red'), s(': Cannot find module '), s("'./app'", 'magenta')]),
            line([s('dist/index.html', 'cyan'), s('  0.46 kB', 'brightBlue'), s('  done', 'brightMagenta')]),
            const SizedBox(height: 2),
            line([
              TextSpan(
                text: ' 选中的字 ',
                style: TextStyle(backgroundColor: k('selection')),
              ),
              s(' '),
              TextSpan(
                text: ' 查找命中 ',
                style: TextStyle(backgroundColor: k('searchHitBg'), color: k('searchHitFg')),
              ),
              s(' '),
              TextSpan(
                text: ' 当前命中 ',
                style: TextStyle(backgroundColor: k('searchHitBgCurrent'), color: k('searchHitFg')),
              ),
            ]),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('root@localhost:/workspace# ', style: base),
                Container(width: 7, height: 14, color: k('cursor')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
