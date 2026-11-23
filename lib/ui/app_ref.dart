import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/quota_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;

/// 界面里取“应用服务”（一次性读取，不订阅）。要跟着状态变的地方用 `ref.watch(某个 provider)`。
AppServices appOf(BuildContext context) => ProviderScope.containerOf(context, listen: false).read(appServicesProvider);

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

/// 订阅一个“变了”计数（见 lib/state/ 里各个 xxxRevProvider）：它一变，[builder] 里的这一小块重画。
class RevBuilder extends ConsumerWidget {
  const RevBuilder({super.key, required this.rev, required this.builder});
  final ProviderListenable<int> rev;
  final Widget Function(BuildContext context, Widget? child) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(rev);
    return builder(context, null);
  }
}
