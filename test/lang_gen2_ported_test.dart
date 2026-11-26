// 接通后端文档生成的前置（核心 2·A5 段的第 3、4 步）：后端积木里早就有、版本 2 的表里原来没有的 11 个小库函数
// （绝对值、较大、较小、随机整数、复制、套模板、算不算是、插入一项、删掉一项、排序、一对对）补上签名，
// “数列”改成三个参数（从、到、步长），五种语言真跑、输出逐字节一样。A4 段已经做的三个（是不是这一类、变成数字、合并字典）
// 和原来就有的三个（变成文字、每一项都做、删掉键）在这里一起核对一遍——任务点名的 17 个都在。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/rt.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _program = '''
(主
  ; 绝对值、较大、较小：整数进整数出、小数进小数出；一个整数一个小数＝按小数
  (设 i 整数 (库 abs -7))
  (设 f 小数 (库 abs -2.5))
  (打印 (连 "abs：" i " " f " " (库 abs 0)))
  (设 m 整数 (库 max 3 9))
  (设 n 小数 (库 min 1.5 -4.25))
  (打印 (连 "max/min：" m " " n " " (库 max 2 2.5) " " (库 min 2 2.5) " " (库 max -1 -1)))
  (打印 (连 "整数还是整数：" (+ (库 abs -3) (库 max 1 2) (库 min 5 4))))
  ; 放进“任意”的：运行时再查
  (设 a 任意 -4)
  (设 b 任意 2.5)
  (打印 (连 "任意：" (库 abs a) " " (库 max a b) " " (库 min a b)))
  (试 (做 (打印 (连 "不该到这里" (库 abs (标 任意 "七")))))
      (出错时 类型不对 e (打印 (连 "abs 文字：" (. e 消息) "｜类型不对"))))
  ; 随机整数：含两头；两头一样就是它；倒着给也行
  (打印 (连 "random：" (库 random 5 5) " " (库 random -2 -2)))
  (设 都在 是)
  (数 k 0 200
    (设 r (库 random 3 1))
    (如果 (或 (< r 1) (> r 3)) (那么 (改 都在 否))))
  (打印 (连 "random 都在 1 到 3：" 都在))
  ; 复制：一层层都另做一份
  (设 原 (列表 (列表 整数)) (列 (列 1 2) (列 3)))
  (设 份 (库 copy 原))
  (加项 (项 份 0) 99)
  (加项 份 (列 7))
  (打印 (连 "copy：" 原 " " 份))
  (设 典原 (字典 (列表 文字)) (典 ("a" (列 "x"))))
  (设 典份 (库 copy 典原))
  (加项 (必有 (取 典份 "a")) "y")
  (存 典份 "b" (列 "z"))
  (打印 (连 "copy 字典：" 典原 " " 典份))
  (设 任原 任意 (典 ("k" (列 1 (典 ("m" 2))))))
  (设 任份 (库 copy 任原))
  (存 任份 "k" "换了")
  (打印 (连 "copy 任意：" 任原 " " 任份 " " (库 copy 5) " " (库 copy "字") " " (库 copy 空)))
  ; 套模板
  (打印 (库 template "你好 {name}，{n} 岁，{没有} {{name}} {a{name}b} 剩 {" (典 ("name" "小明") ("n" "3"))))
  (打印 (库 template "{x}+{y}＝{z}{}" (典 ("x" 1) ("y" 2) ("z" 3))))
  (打印 (库 template "{a} {b} {c} {d}" (标 (字典 任意) (典 ("a" 1.5) ("b" 是) ("c" 空) ("d" (列 1 "二"))))))
  ; 算不算是
  (打印 (连 "toBool：" (库 toBool 空) (库 toBool 否) (库 toBool 0) (库 toBool 0.0) (库 toBool "") "｜"
    (库 toBool 是) (库 toBool 1) (库 toBool -0.5) (库 toBool "0") (库 toBool " ") (库 toBool (列)) (库 toBool (典))))
  ; 插入、删掉一项
  (设 xs (列表 文字) (列 "b" "d"))
  (库 listInsert xs 0 "a")
  (库 listInsert xs 2 "c")
  (库 listInsert xs 4 "e")
  (打印 (连 "insert：" xs))
  (设 走了 文字 (库 listRemove xs 1))
  (打印 (连 "remove：" 走了 " " xs " " (库 listRemove xs 3) " " xs))
  (试 (做 (库 listInsert xs 5 "z")) (出错时 找不到 e (打印 (连 "insert 越界：" (. e 消息) "｜找不到"))))
  (试 (做 (库 listInsert xs -1 "z")) (出错时 错误 e (打印 (连 "insert 负数：" (. e 消息)))))
  (试 (做 (打印 (库 listRemove xs 3))) (出错时 错误 e (打印 (连 "remove 越界：" (. e 消息)))))
  (设 任列 任意 (列 1 2))
  (库 listInsert (转 (列表 任意) 任列) 1 "夹")
  (打印 (连 "insert 任意：" 任列))
  ; 排序：新列表，原来的不动
  (设 数们 (列 3 -1 20 3 0))
  (打印 (连 "sort 整数：" (库 listSort 数们) " 原：" 数们))
  (打印 (连 "sort 小数：" (库 listSort (列 2.5 -0.5 10.0 1e3 2.25))))
  (打印 (连 "sort 文字：" (库 listSort (列 "b" "a" "B" "10" "9" "中" "一" "😀" "ｚ" ""))))
  (打印 (连 "sort 空：" (库 listSort (标 (列表 整数) (列)))))
  (设 任数 (列表 任意) (列 3 1.5 -2))
  (打印 (连 "sort 任意：" (库 listSort 任数) " " (库 listSort (标 (列表 任意) (列 "乙" "甲")))))
  (试 (做 (打印 (库 listSort (标 (列表 任意) (列 1 "a")))))
      (出错时 类型不对 e (打印 (连 "sort 混着：" (. e 消息) "｜类型不对"))))
  ; 一对对
  (设 d (字典 整数) (典 ("b" 2) ("a" 1) ("中" 3)))
  (打印 (连 "pairs：" (库 dictPairs d) " " (库 dictPairs (标 (字典 文字) (典)))))
  (每个 对 (库 dictPairs d) (打印 (连 (项 对 0) "＝" (项 对 1))))
  ; 数列：三个参数
  (打印 (连 "range：" (库 range 1 5 1) (库 range 1 5 2) (库 range 3 1 -1) (库 range 1 3 0) (库 range 1 3 -1) (库 range 5 5 3) (库 range 0 -6 -4)))
  (打印 (连 "range 最多一万项：" (长 (库 range 1 20000 1)) " " (项 (库 range 1 20000 1) 9999)))
  ; 原来就有的六个，一起核对
  (打印 (连 "toText：" (文 12) (文 1.50) (文 是) (文 空) (文 (列 1 "a"))))
  (设 总 0)
  (库 listEach (列 1 2 3) (λ块 ((v 整数)) (改 总 (+ 总 v))))
  (打印 (连 "each：" 总))
  (删键 d "a")
  (打印 (连 "dictRemove：" d))
  (打印 (连 "isType：" (是类 1 "number") (是类 "1" "number") (是类 (列) "list")))
  (打印 (连 "toNumber：" (转数 "12.5") " " (转数 " 7 ")))
  (打印 (连 "dictMerge：" (合并 (典 ("a" 1) ("b" 2)) (典 ("b" 3) ("c" 4))))))
''';

const String _want =
    'abs：7 2.5 0\n'
    'max/min：9 -4.25 2.5 2 -1\n'
    '整数还是整数：9\n'
    '任意：4 2.5 -4\n'
    'abs 文字：「绝对值」要数字，拿到的是文字｜类型不对\n'
    'random：5 -2\n'
    'random 都在 1 到 3：true\n'
    'copy：[[1,2],[3]] [[1,2,99],[3],[7]]\n'
    'copy 字典：{"a":["x"]} {"a":["x","y"],"b":["z"]}\n'
    'copy 任意：{"k":[1,{"m":2}]} {"k":"换了"} 5 字 \n'
    '你好 小明，3 岁，{没有} {小明} {a小明b} 剩 {\n'
    '1+2＝3{}\n'
    '1.5 true  [1,"二"]\n'
    'toBool：falsefalsefalsefalsefalse｜truetruetruetruetruetruetrue\n'
    'insert：["a","b","c","d","e"]\n'
    'remove：b ["a","c","d","e"] e ["a","c","d"]\n'
    'insert 越界：位置 5 超出了列表的范围（共 3 项）｜找不到\n'
    'insert 负数：位置 -1 超出了列表的范围（共 3 项）\n'
    'remove 越界：位置 3 超出了列表的范围（共 3 项）\n'
    'insert 任意：[1,"夹",2]\n'
    'sort 整数：[-1,0,3,3,20] 原：[3,-1,20,3,0]\n'
    'sort 小数：[-0.5,2.25,2.5,10,1000]\n'
    'sort 文字：["","10","9","B","a","b","一","中","ｚ","😀"]\n'
    'sort 空：[]\n'
    'sort 任意：[-2,1.5,3] ["乙","甲"]\n'
    'sort 混着：排序要全是数字或者全是文字的列表，拿到的是混着的｜类型不对\n'
    'pairs：[["a",1],["b",2],["中",3]] []\n'
    'a＝1\n'
    'b＝2\n'
    '中＝3\n'
    'range：[1,2,3,4,5][1,3,5][3,2,1][][][5][0,-4]\n'
    'range 最多一万项：10000 10000\n'
    'toText：121.5true[1,"a"]\n'
    'each：6\n'
    'dictRemove：{"b":2,"中":3}\n'
    'isType：truefalsetrue\n'
    'toNumber：12.5 7\n'
    'dictMerge：{"a":1,"b":3,"c":4}\n';

void main() {
  test('任务点名的 17 个旧函数在版本 2 的表里都有签名（或者是检查器单独处理的那几个）', () {
    const special = {'toText', 'dictRemove'}; // 检查器、生成器里单独处理，不走表
    const names = ['abs', 'max', 'min', 'random', 'copy', 'template', 'toNumber', 'toText', 'toBool', 'isType', 'listInsert', 'listRemove', 'listSort', 'listEach', 'dictMerge', 'dictPairs', 'dictRemove'];
    expect(names, hasLength(17));
    for (final n in names) {
      expect((kLangCoreFns.containsKey(n) || kLangRtFns.containsKey(n)), isTrue, reason: '$n 是版本 1 小库里的名字');
      expect(special.contains(n) || kLangRtV2.containsKey(n), isTrue, reason: '$n 要有版本 2 的签名');
    }
    expect(kLangRtV2Ported, hasLength(11));
    expect(kLangRtV2Ported.every(kLangRtV2.containsKey), isTrue);
    expect(kLangRtV2['range']!.params, hasLength(3));
  });

  test('整数进整数出、小数进小数出；不是数字的在检查的时候就拦下', () {
    String errs(String body) => checkModuleTypes(lcModule('(主 $body)')).errors.map((i) => '${i.code} ${i.message}').join('\n');
    expect(errs('(设 a 整数 (库 abs -1)) (设 b 小数 (库 abs -1.5)) (设 c 整数 (库 max 1 2)) (设 d 小数 (库 min 1 2.5))'), isEmpty);
    expect(errs('(设 a 整数 (库 abs -1.5))'), contains('T01'));
    expect(errs('(设 a 整数 (库 max 1 2.5))'), contains('T01'));
    expect(errs('(打印 (库 abs "七"))'), contains('T05 「绝对值」要的是数字（整数或小数），文字不行'));
    expect(errs('(打印 (库 max "a" "b"))'), contains('T05'));
    expect(errs('(打印 (库 listSort (列 是 否)))'), contains('T05'));
    expect(errs('(打印 (库 range 1 5))'), contains('T07 「数列」要 3 个参数，给了 2 个'));
    expect(errs('(打印 (库 range 1 5 0.5))'), contains('T01'));
    expect(errs('(打印 (库 random 1 2.5))'), contains('T01'));
    expect(errs('(设 xs (列 1 2)) (库 listInsert xs 0 "a")'), contains('T01'));
    expect(errs('(设 xs (列 1 2)) (设 s 文字 (库 listRemove xs 0))'), contains('T01'));
  });

  for (final language in kGen2Languages) {
    test('$language：生成、真跑，输出逐字节一样', () async {
      final files = gen2Files(language, lcModule(_program));
      final skip = gen2SkipReason(language);
      if (skip != null) {
        // ignore: avoid_print — 跳过的原因要让跑测试的人看见
        print('跳过：$skip');
        markTestSkipped(skip);
        return;
      }
      final run = await gen2RunFiles(language, files);
      expect(run.problem, isNull, reason: language);
      expect(utf8.decode(run.stdout), _want, reason: language);
      expect(run.exitCode, 0, reason: language);
    });
  }
}
