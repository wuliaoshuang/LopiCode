/// 页面文档和项目里的积木库（积木第 5 版·前端 1·下半）：把项目里的库交给每一页的逻辑，导出、检查才找得到它们。
library;

import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/model.dart';

/// 读一遍项目里的库，交给每一页的逻辑（不存盘的那一格 `loaded`）。读不了就当没有库。
Future<void> lcAttachLibs(PathGuard guard, LcDocument doc) async {
  final all = await beLibsRead(guard);
  final libs = [
    for (final s in all)
      if (s.lib.id == s.id) s.lib,
  ];
  for (final p in doc.pages) {
    p.logic.loaded = libs;
  }
}

/// 存盘用的那份副本（重新读出来的，库没带过来）：把原件每一页挂着的库照样挂上。
void lcCopyLoaded(LcDocument from, LcDocument to) {
  for (final p in to.pages) {
    p.logic.loaded = (from.pageById(p.id) ?? from.pages.first).logic.loaded;
  }
}
