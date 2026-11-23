// 服务商图标：来自 @lobehub/icons-static-svg（MIT），随安装包走，不联网取。
// 单色图标跟着深浅色换颜色；认不出是哪家就用通用的“渠道”图标。
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class ProviderIcon extends StatelessWidget {
  const ProviderIcon({super.key, required this.preset, this.size = 40});

  /// 按接口地址认图标。
  ProviderIcon.forBaseUrl(String baseUrl, {super.key, this.size = 40}) : preset = presetForBaseUrl(baseUrl);

  final ProviderPreset? preset;

  /// 外框边长；里面的图标是它的 0.6。
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preset;
    final inner = size * 0.6;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p == null ? c.accentSoft : c.surfaceMuted,
        borderRadius: BorderRadius.circular(size >= 36 ? Radii.md : Radii.sm),
      ),
      child: p == null
          ? Icon(Icons.hub_outlined, color: c.accent, size: inner)
          : SvgPicture.asset(
              p.iconAsset,
              key: ValueKey('provider-icon-${p.id}'),
              width: inner,
              height: inner,
              excludeFromSemantics: true,
              colorFilter: p.monoIcon ? ColorFilter.mode(c.text, BlendMode.srcIn) : null,
              // 图标文件万一读不出来：退回通用图标，不留一块空白。
              placeholderBuilder: (_) => SizedBox(width: inner, height: inner),
            ),
    );
  }
}
