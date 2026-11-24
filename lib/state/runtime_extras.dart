// “运行环境”页上两样要现算的只读信息：环境占了多大、装好的语言是哪个版本。
//
// 都只读文件（见 lib/runtime/runtime_pack_info.dart），没人看就释放；环境装 / 卸、语言装好、一次安装结束时重算。
// 算不出来就是 null / 空，界面不显示，不编数字。
import 'package:lopicode/runtime/runtime_pack_info.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:riverpod/riverpod.dart';

/// 整个运行环境目录（Ubuntu + 里面装的软件 + 下载留下的文件）现在占多少字节。没装返回 null。
final runtimeDiskUsageProvider = FutureProvider.autoDispose<int?>((ref) async {
  final runtime = ref.watch(appServicesProvider).runtime;
  final installed = ref.watch(runtimeProvider.select((v) => v.installed));
  // 装好一样语言、或者一次安装刚结束（不管成没成），占用都会变
  ref.watch(runtimeProvider.select((v) => (v.installedPacks.length, v.runningPack == null)));
  if (!installed) return null;
  return directorySize(runtime.baseDir);
});

/// 已装语言的版本号（id → “24.9.0”）。读不出来的不在里面。
final runtimePackVersionsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final runtime = ref.watch(appServicesProvider).runtime;
  final ids = ref.watch(runtimeProvider.select((v) => (v.installedPacks.toList()..sort()).join(',')));
  if (ids.isEmpty) return const {};
  return readPackVersions(runtime.rootfsDir, ids.split(','));
});
