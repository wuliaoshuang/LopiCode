// 记忆的订阅入口。记忆的主人是 lib/agent/memory_store.dart 里的存储对象（一条一个 Markdown 文件）；
// 这里只负责“记忆变了，通知正在看它的界面”：界面在 build 里 `ref.watch(memoryRevProvider)`，然后照常从存储对象读。
// 两个开关是普通的设置键，界面用 `settingRevProvider(键)` 订阅。
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 记忆（全局的或某个工作区的）增删改了。
class MemoryRev extends Notifier<int> {
  @override
  int build() {
    final memory = ref.watch(appServicesProvider).memory;
    // 存储对象可能在别人正在搭界面的时候说“变了”（比如页面一打开就重新读盘）：推后一拍再改状态。
    void onChange() => Future.microtask(() {
      if (ref.mounted) state = state + 1;
    });
    memory.changeListeners.add(onChange);
    ref.onDispose(() => memory.changeListeners.remove(onChange));
    return 0;
  }
}

final memoryRevProvider = NotifierProvider<MemoryRev, int>(MemoryRev.new);
