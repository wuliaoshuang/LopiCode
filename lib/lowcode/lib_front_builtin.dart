/// 应用自带的前端库（积木第 5 版·前端 2·第一批）：除了自动用上的“页面”，还有五个要用才用的——
/// 定时、请求、本地保存、状态仓库、事件总线。
///
/// 它们和“页面”库走同一条自带库的路：同一种格式、同一个读入器（`libRead(…, builtin: true)`），前端这一边的文档
/// （页面逻辑、“给谁用＝前端”的库）永远带着它们（不用项目里有），在“积木库…”里点“在这份文档里用它”才进积木盒。
/// 默认状态（两个安全开关都关）下就能用：直接碰宿主接口的是这些自带库，不是用户的库。
library;

import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_front_bus.dart';
import 'package:lopicode/lowcode/lib_front_http.dart';
import 'package:lopicode/lowcode/lib_front_storage.dart';
import 'package:lopicode/lowcode/lib_front_store.dart';
import 'package:lopicode/lowcode/lib_front_timer.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/lib_page_module.dart';

/// 一个要用才用的自带前端库：标识、库文件夹的内容、模块的文字（只读画布要它）。
class LcFrontBuiltin {
  const LcFrontBuiltin(this.id, this.files, this.moduleText);
  final String id;
  final Map<String, String> files;
  final String moduleText;
}

/// 五个要用才用的（照积木库面板里排的先后）。
const List<LcFrontBuiltin> kLcFrontBuiltins = [
  LcFrontBuiltin(kLcTimerLibId, kLcTimerLibFiles, kLcTimerModuleLc),
  LcFrontBuiltin(kLcHttpLibId, kLcHttpLibFiles, kLcHttpModuleLc),
  LcFrontBuiltin(kLcStorageLibId, kLcStorageLibFiles, kLcStorageModuleLc),
  LcFrontBuiltin(kLcStoreLibId, kLcStoreLibFiles, kLcStoreModuleLc),
  LcFrontBuiltin(kLcBusLibId, kLcBusLibFiles, kLcBusModuleLc),
];

List<LibLibrary>? _cached;

/// 读好的五个库（只读一次）。
List<LibLibrary> lcFrontBuiltinLibs() => _cached ??= [for (final b in kLcFrontBuiltins) libRead(b.files, builtin: true)];

/// 是不是要用才用的自带前端库。
bool lcIsFrontOptional(String id) => kLcFrontBuiltins.any((b) => b.id == id);

/// 是不是自带的前端库（“页面”也算）。
bool lcIsFrontBuiltin(String id) => id == kLcPageLibId || lcIsFrontOptional(id);

/// 按标识找（“页面”也找得到）；不是自带的＝null。
LibLibrary? lcFrontBuiltinLib(String id) => id == kLcPageLibId ? lcPageLibrary() : lcFrontBuiltinLibs().where((l) => l.id == id).firstOrNull;

/// 模块的文字（只读画布用）；不是自带的＝null。
String? lcFrontBuiltinModule(String id) => id == kLcPageLibId ? kLcPageModuleLc : kLcFrontBuiltins.where((b) => b.id == id).firstOrNull?.moduleText;

/// 前端这一边的文档带着的全部自带库：“页面”排第一个，后面是五个要用才用的。
List<LibLibrary> lcFrontBuiltinAll() => [lcPageLibrary(), ...lcFrontBuiltinLibs()];
