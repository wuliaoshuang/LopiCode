import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/types.dart';

const LType _dictAny = LType.dictOf(LType.any);

/// 宿主接口（规矩版本 2）：语言核心搭不出来、要靠外面给的那几件事。清单和细则在
/// docs/blocks-v5-parts/C-library-system.md §9.1（开服务的细则另见 B-gen-notes.md 第 12 节）。
/// 实现在各语言的小库里（rt2_*.dart 的“宿主”一节 / rt2_*_host.dart）。net.fetch 等核心 3 再加。
///
/// 程序里用之前要先写一句声明（`LNativeDecl`），参数、返回的类型要和这张表一模一样。
const Map<String, LRtSig> kHostV2 = {
  // 写一行，写完马上送出去。通道是 out（和“打印”排在一起）或 err（标准错误）。
  'sys.print': LRtSig('写一行', [LType.text, LType.text], LType.nul),
  // 读环境变量：没有就是空。
  'sys.env': LRtSig('读环境变量', [LType.text], LType(LKind.text, nullable: true)),
  // 从 1970-01-01（UTC）算起的毫秒数。
  'time.now': LRtSig('现在的毫秒数', [], LType.integer),
  // 等一会儿（毫秒；0 和负数＝不等）。要等。
  'time.sleep': LRtSig('等一会儿', [LType.integer], LType.nul),
  // 读格子：没有就是空。读出来的是复制的一份。
  'store.read': LRtSig('读格子', [LType.text], LType.any),
  // 改格子：把旧值（复制的一份）交给函数，把函数返回的新值存回去（存的也是复制的一份），返回新值。
  // 别人同时改同一个格子＝排队；函数里再改这个格子＝出错。
  'store.update': LRtSig('改格子', [
    LType.text,
    LType.func([LType.any, LType.any]),
  ], LType.any),
  // 开服务：一直服务，不返回（要等）。端口 0＝随便挑一个空的。处理函数收请求
  // {method, path, query, headers, body}，返回 {status, headers, body}；处理函数是“要等”的。
  'http.serve': LRtSig('开服务', [
    LType.integer,
    LType.text,
    LType.func([_dictAny, _dictAny], waits: true),
  ], LType.nul),
};

/// 哪几个宿主接口是“要等”的。
const Set<String> kHostV2Waits = {'time.sleep', 'http.serve'};

/// 宿主接口在小库里叫什么（Go 里首字母大写）。
const Map<String, String> kHostV2Code = {
  'sys.print': 'hostPrint',
  'sys.env': 'hostEnv',
  'time.now': 'hostNow',
  'time.sleep': 'hostSleep',
  'store.read': 'storeRead',
  'store.update': 'storeUpdate',
  'http.serve': 'hostServe',
};
