// “后台与通知”设置页要现问系统的一件事：通知权限给没给。
// 问不到（不是安卓、通道出错）就是 null，界面按“不知道”显示，不编。
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 通知权限：true＝允许，false＝没允许，null＝问不到。从系统设置回来后 `ref.invalidate` 重新问。
final notificationsAllowedProvider = FutureProvider.autoDispose<bool?>((ref) async {
  final host = ref.watch(appServicesProvider).keepAlive.host;
  try {
    return await host.notificationsAllowed();
  } on Exception {
    return null; // 通道出错：当作问不到
  }
});
