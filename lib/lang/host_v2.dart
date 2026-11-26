import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/types.dart';

const LType _dictAny = LType.dictOf(LType.any);

/// 宿主接口（规矩版本 2）：语言核心搭不出来、要靠外面给的那几件事。清单和细则在
/// docs/blocks-v5-parts/C-library-system.md §9.1（开服务的细则另见 B-gen-notes.md 第 12 节）。
/// 实现在各语言的小库里（rt2_*.dart 的“宿主”一节 / rt2_*_host.dart）。一共 14 个：第一批 9 个（C 分册 9.1 的 8 行，其中“格子”是读、改两个）＋文件 5 个（9.2）。
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
  // 随机字节：个数 1–1024，每个 0–255，来自系统的安全随机源。个数不对＝出错。
  'random.bytes': LRtSig('随机字节', [LType.integer], LType.listOf(LType.integer)),
  // 请求别的网址（方式, 网址, 请求头, 内容, 超时毫秒）→ {status, headers, body}。要等、会出错。细则见 B-gen-notes.md 第 14 节：
  // 只许 http / https；回来的 headers 名字一律小写（重名的用“, ”连）；body 按 UTF-8 当文字；404、500 不算出错；
  // 网址不对、超时、连不上＝抛错，三句话五种语言一样。
  'net.fetch': LRtSig('请求网址', [LType.text, LType.text, LType.dictOf(LType.text), LType(LKind.text, nullable: true), LType.integer], _dictAny),
  // 文件（路径相对工程文件夹；不许 .. 、不许绝对路径；只读写 UTF-8 文字）。细则见 B-gen-notes.md 第 14 节。
  'file.read': LRtSig('读文件', [LType.text], LType.text),
  // 整个覆盖；先写临时文件再改名；上层文件夹不在就建。
  'file.write': LRtSig('写文件', [LType.text, LType.text], LType.nul),
  'file.exists': LRtSig('有没有这个文件', [LType.text], LType.boolean),
  // 只列这一层，按名字的码点排好序。
  'file.list': LRtSig('列文件夹', [LType.text], LType.listOf(LType.text)),
  // 只删文件，不删文件夹。
  'file.remove': LRtSig('删文件', [LType.text], LType.nul),
};

/// 哪几个宿主接口是“要等”的。
const Set<String> kHostV2Waits = {'time.sleep', 'http.serve', 'net.fetch'};

/// 宿主接口在小库里叫什么（Go 里首字母大写）。
const Map<String, String> kHostV2Code = {
  'sys.print': 'hostPrint',
  'sys.env': 'hostEnv',
  'time.now': 'hostNow',
  'time.sleep': 'hostSleep',
  'store.read': 'storeRead',
  'store.update': 'storeUpdate',
  'http.serve': 'hostServe',
  'random.bytes': 'hostRandomBytes',
  'net.fetch': 'hostFetch',
  'file.read': 'fileRead',
  'file.write': 'fileWrite',
  'file.exists': 'fileExists',
  'file.list': 'fileList',
  'file.remove': 'fileRemove',
};
