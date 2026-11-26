// 主题的“界面字号”倍率怎么生效：在应用最外层把系统的文字缩放再乘一个倍率（[ThemeTextScale]），
// 所以全应用的字一起变大变小，不用逐处改。代码区域（编辑器、看代码、改动对比、终端）的字号是另一个
// 独立设置，不该跟着变：它们在自己外面包一层 [SystemTextScale]，把倍率拿掉、只留系统自己的缩放。
// 倍率是 1（默认主题）时两个控件都原样返回孩子，什么都不包。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 系统的文字缩放，再乘上主题给的倍率。
class ThemeTextScaler extends TextScaler {
  const ThemeTextScaler(this.system, this.factor);

  /// 系统自己的缩放（手机设置里的字体大小）。
  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use 这个旧属性是基类要求实现的，只能照着转一下
  double get textScaleFactor => system.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is ThemeTextScaler && other.system == system && other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);
}

/// 放在应用最外层：按当前主题的“界面字号”倍率放大 / 缩小全部文字。
class ThemeTextScale extends StatelessWidget {
  const ThemeTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final factor = context.themeSpec.metric(MetricKey.fontScale);
    if (factor == 1) return child;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: ThemeTextScaler(mq.textScaler, factor)),
      child: child,
    );
  }
}

/// 包在代码区域外面：里面的字不吃主题的字号倍率（代码字号有自己的设置），系统的缩放照旧。
class SystemTextScale extends StatelessWidget {
  const SystemTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler is! ThemeTextScaler) return child;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler.system),
      child: child,
    );
  }
}
