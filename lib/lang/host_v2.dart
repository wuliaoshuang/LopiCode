import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/types.dart';

/// 宿主接口（规矩版本 2）：语言核心搭不出来、要靠外面给的那几件事。清单和细则在
/// docs/blocks-v5-parts/C-library-system.md §9.1；这里只有“不用等”的四个（要等的 time.sleep、net.fetch、
/// http.serve 等核心 3 做了“要等的事”再加）。实现在各语言的小库里（rt2_*.dart 的“宿主”一节）。
///
/// 程序里用之前要先写一句声明（`LNativeDecl`），参数、返回的类型要和这张表一模一样。
const Map<String, LRtSig> kHostV2 = {
  // 写一行。通道是 out（和“打印”排在一起）或 err（马上写到标准错误）。
  'sys.print': LRtSig('写一行', [LType.text, LType.text], LType.nul),
  // 从 1970-01-01（UTC）算起的毫秒数。
  'time.now': LRtSig('现在的毫秒数', [], LType.integer),
  // 读格子：没有就是空。读出来的是复制的一份。
  'store.read': LRtSig('读格子', [LType.text], LType.any),
  // 改格子：把旧值（复制的一份）交给函数，把函数返回的新值存回去（存的也是复制的一份），返回新值。
  'store.update': LRtSig('改格子', [
    LType.text,
    LType.func([LType.any, LType.any]),
  ], LType.any),
};

/// 宿主接口在小库里叫什么（Go 里首字母大写）。
const Map<String, String> kHostV2Code = {'sys.print': 'hostPrint', 'time.now': 'hostNow', 'store.read': 'storeRead', 'store.update': 'storeUpdate'};
