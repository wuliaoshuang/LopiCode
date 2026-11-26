// 设计约束（聊天正文的排版样式 · 390×844）— 2026-11-26
// - 正文三种“底”：Agent 的话（通栏、页面底色）、我的消息（强调色浅底的气泡）、思考全文（灰底小字）。
//   三种底上代码块 / 引用 / 表格 / 链接都要看得清：代码块和表格在页面底色上用代码底色，在气泡和思考的灰底上换成卡片色。
// - 层级：正文最重；标题只比正文大一点、加粗（聊天里不需要报纸那样的大标题）；引用、说明是次要内容用灰字。
// - 代码字号跟“代码字号”设置走：正文里的代码用正式那一档，思考里的用小一号那一档；不写死。
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

enum MdTone { body, bubble, muted }

class MdStyles {
  const MdStyles({required this.tone, required this.base, required this.codeSize, required this.colors, required this.dark});
  final MdTone tone;

  /// 正文的字。
  final TextStyle base;

  /// 代码块 / 行内代码的字号。
  final double codeSize;
  final AppColors colors;
  final bool dark;

  /// 代码块、表格、行内代码的底色。
  Color get blockBg => tone == MdTone.body ? colors.codeBg : colors.surface;
  Color get text => base.color ?? colors.text;
  Color get subtle => tone == MdTone.muted ? colors.textFaint : colors.textMuted;
  double get gap => tone == MdTone.muted ? Space.x2 : Space.x3;

  TextStyle get mono => TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: codeSize, height: 1.5, color: text);

  TextStyle heading(int level) {
    final size = base.fontSize ?? 16;
    // 正文 16 时：一级 20、二级 18（都在字号阶上），往下和正文一样大只加粗；思考里的标题不放大
    final add = tone == MdTone.muted
        ? 0.0
        : switch (level) {
            1 => 4.0,
            2 => 2.0,
            _ => 0.0,
          };
    return base.copyWith(fontSize: size + add, fontWeight: FontWeight.w600, height: 1.35);
  }

  @override
  bool operator ==(Object other) => other is MdStyles && other.tone == tone && other.base == base && other.codeSize == codeSize && identical(other.colors, colors) && other.dark == dark;

  @override
  int get hashCode => Object.hash(tone, base, codeSize, colors, dark);
}

/// 一条正文里各个小控件共用的东西：样式、工作区的路径守卫（找本机图片用）、要不要自动加载网络图片、点链接怎么办。
class MdScope extends InheritedWidget {
  const MdScope({super.key, required this.styles, required this.guard, required this.autoImages, required this.onLink, required super.child});
  final MdStyles styles;
  final PathGuard? guard;
  final bool autoImages;
  final void Function(BuildContext context, String href) onLink;

  static MdScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MdScope>()!;

  @override
  bool updateShouldNotify(MdScope old) => old.styles != styles || old.guard?.root != guard?.root || old.autoImages != autoImages;
}
