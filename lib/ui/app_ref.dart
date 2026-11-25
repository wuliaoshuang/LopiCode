import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_stars.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/quota_state.dart';
import 'package:material_ui/material_ui.dart';

/// 界面里取“应用服务”（一次性读取，不订阅）。要跟着状态变的地方用 `ref.watch(某个 provider)`。
AppServices appOf(BuildContext context) => ProviderScope.containerOf(context, listen: false).read(appServicesProvider);

/// 同上，但这块界面可能没放在应用外壳里（单独拿一个页面出来用 / 测）：拿不到就返回 null，不崩。
AppServices? maybeAppOf(BuildContext context) {
  if (context.findAncestorWidgetOfExactType<UncontrolledProviderScope>() == null) return null;
  try {
    return appOf(context);
  } on Object {
    return null; // 外壳在，但没有配应用服务
  }
}

/// 积木盒里加的星存进应用设置，按编辑器种类（`logic` / `backend`）分开；拿不到应用服务时返回 null（只在编辑器开着时记着）。
BlockStars? blockStarsOf(BuildContext context, String kind) {
  final app = maybeAppOf(context);
  return app == null ? null : SettingsBlockStars(app.settings, kind);
}

/// 订阅额度 / 余额状态：它一变，[builder] 里的这一小块重画（别处不动）。
class QuotaBuilder extends ConsumerWidget {
  const QuotaBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, QuotaNotifier quota) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(quotaProvider);
    return builder(context, ref.read(quotaProvider.notifier));
  }
}
