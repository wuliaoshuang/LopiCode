// 库机制（积木第 5 版·库 1）：落盘格式读得进来、四种定义积木的办法、隐含的东西、放进变量、口里放“返回”的原地展开、设置项。
//
// 用的是示例库 test/fixtures/libs/demo-kit（和内置库同一种格式、同一个读入器）。拼出来的程序交给规矩版本 2 的生成器，
// 五种语言真的编译、真的跑，输出逐字节一样。缺哪种语言的编译器就跳过那种并打印原因。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

import 'support/gen2_run.dart';
import 'support/lib_files.dart';

const String _expect = '''
8
报告：红×4
6
里：蓝×4
口袋用完了
口袋用完了
早退：绿×4
收工：你好、拿出红、放进6、拿出蓝、拿出绿
''';

LProgram _program(LibLibrary lib) {
  var n = 0;
  String fresh(String name) => '${name}_${++n}';
  const settings = <String, Object?>{'size': 4, 'greeting': '你好'};
  LibBlock b(String id) => lib.block(id)!;
  LibApplied use(String id, LibUse u, Map<String, String> context) {
    final got = libApply(lib, b(id), u, LibCx(context: context, settings: settings, fresh: fresh));
    expect(got.problem, isNull, reason: id);
    return got;
  }

  LExpr value(String id, Map<String, LExpr> values, [Map<String, String> context = const {}]) => use(id, LibUse(values: values), context).value!;
  LStmt say(LExpr x) => LExprStmt(LRt('log', [x]));

  // 带口的积木：先给它要递的东西起好名字，再翻口里的，最后用它。
  List<LStmt> pocket(String name, Map<String, String> outer, List<LStmt> Function(Map<String, String> context) body) {
    final provided = libProvided(b('withPocket'), fresh);
    final inner = {...outer, ...provided};
    return use('withPocket', LibUse(values: {'name': LLit(name)}, mouths: {'body': body(inner)}, provided: provided), outer).stmts;
  }

  final init = libMoment(lib, lib.init, LibCx(settings: settings, fresh: fresh));
  final start = libMoment(lib, lib.start, LibCx(settings: settings, fresh: fresh));
  expect(init.problem, isNull);
  expect(start.problem, isNull);
  final top = {...lib.provides};

  // 口里放“返回”：返回的是外面这个函数（原地展开，不是包成匿名函数）。
  final early = LFuncDecl(
    '找',
    const [LParam('本', type: LType.listOf(LType.text))],
    [
      ...pocket(
        '绿',
        {'账本': '本'},
        (cx) => [
          LReturn(value('pocketReport', const {'prefix': LLit('早退：')}, cx)),
        ],
      ),
      const LReturn(LLit('没早退')),
    ],
    type: LType.text,
  );

  final main = <LStmt>[
    ...init.stmts,
    LLet('c', value('counterZero', const {})),
    const LLet('结果', LLit(0)),
    // 调对象的方法 + 放进变量；槽里又是一块调函数的积木。
    ...use(
      'counterAdd',
      LibUse(
        values: {
          'c': const LName('c'),
          'n': value('double', const {'x': LLit(4)}),
        },
        targets: {'into': '结果'},
      ),
      top,
    ).stmts,
    say(const LName('结果')),
    // 没选变量：只调不存。实参是预先填死的那块。
    ...use('counterAdd', LibUse(values: {'c': const LName('c'), 'n': value('fixedDouble', const {})}), top).stmts,
    ...pocket(
      '红',
      top,
      (cx) => [
        say(value('pocketReport', const {'prefix': LLit('报告：')}, cx)),
        const LLet('几', LLit(0)),
        ...use('pocketPut', const LibUse(values: {'n': LLit(2)}, targets: {'into': '几'}), cx).stmts,
        say(const LName('几')),
        // 口袋里再拿一个口袋：里面那块“口袋报告”用的是里面的口袋。
        ...pocket(
          '蓝',
          cx,
          (cx2) => [
            say(value('pocketReport', const {'prefix': LLit('里：')}, cx2)),
          ],
        ),
      ],
    ),
    say(LCall(const LName('找'), [LName(top['账本']!)])),
    ...start.stmts,
  ];
  return libProgram([lib], LModule(name: '主程序', decls: [early], body: main));
}

void main() {
  final files = libFilesFromDir('test/fixtures/libs/demo-kit');
  final lib = libRead(files, builtin: false);

  test('示例库读得进来，一条问题都没有', () {
    expect(lib.problems, isEmpty);
    expect(lib.id, 'demo/kit');
    expect(lib.moduleNames, ['小工具']);
    expect(
      [for (final b in lib.blocks) '${b.id}:${b.how.name}'],
      ['double:call', 'counterZero:static', 'counterAdd:method', 'withPocket:expand', 'pocketReport:call', 'pocketPut:expand', 'fixedDouble:call'],
    );
    expect([for (final s in lib.settings) s.id], ['size', 'greeting']);
    expect(lib.hosts, isEmpty);
  });

  test('拼出来的程序检查没有问题', () {
    final (linked, result) = checkProgramTypes(_program(lib));
    expect([for (final i in linked.issues) '$i'], isEmpty);
    expect([for (final e in result?.errors ?? const []) '${e.code} ${e.where} ${e.message}'], isEmpty);
  });

  for (final language in kGen2Languages) {
    test('$language：四种办法、隐含的东西、放进变量、口里返回、设置项，真跑的输出一样', () async {
      final skip = gen2SkipReason(language);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final run = await gen2RunFiles(language, gen2ProgramFiles(language, _program(lib)));
      expect(run.problem, isNull);
      expect(utf8.decode(run.stdout), _expect.trimLeft());
      expect(run.exitCode, 0);
    });
  }

  group('读坏的库：说得出哪里不对，不抛异常', () {
    Map<String, String> edit(String file, String from, String to) {
      expect(files[file], contains(from));
      return {...files, file: files[file]!.replaceFirst(from, to)};
    }

    void says(Map<String, String> bad, String what, {bool builtin = false}) {
      final got = libRead(bad, builtin: builtin);
      expect(got.ok, isFalse);
      expect(got.problems.join('\n'), contains(what));
    }

    test('清单', () {
      says({}, '没有清单');
      says({...files, 'lib.json': '{'}, '没有清单');
      says(edit('lib.json', 'lopicode-lib', 'something'), '不是一个库');
      says(edit('lib.json', 'demo/kit', 'Demo Kit'), '标识');
      says(edit('lib.json', '"1.0.0"', '"一"'), '版本号');
      says(edit('lib.json', '"format": 1', '"format": 99'), '更新的应用');
      says(edit('lib.json', '"rules": 2', '"rules": 1'), '严格规矩');
      says(edit('lib.json', 'modules/kit.lc', 'modules/nope.lc'), '不在库里');
      says(edit('lib.json', '(设置 greeting)', '(设置 nope)'), '没有的设置项');
    });

    test('模块', () {
      says(edit('modules/kit.lc', '(模块 小工具', '(模块 小工具 (主 (打印 1))'), '程序开始时');
      says(edit('modules/kit.lc', '(返回 (* x 2))))', '(返回 (* x 2))'), '读不了');
    });

    test('积木', () {
      says(edit('blocks.json', '"of": "加倍", "args": ["x"]', '"of": "没有的", "args": ["x"]'), '没有');
      says(edit('blocks.json', '"of": "加倍", "args": ["x"]', '"of": "加倍", "args": ["x", "x"]'), '实参表');
      says(edit('modules/kit.lc', '(公开 (函数 加倍 ((x 整数)) -> 整数 (返回 (* x 2))))', '(函数 加倍 ((x 整数)) -> 整数 (返回 (* x 2)))'), '公开');
      says(edit('blocks.json', '"of": "计数器.从零"', '"of": "计数器.加"'), '类自己的方法');
      says(edit('blocks.json', '"how": "method", "of": "加"', '"how": "method", "of": "减"'), '方法「减」');
      says(edit('blocks.json', '(名 (槽 name))', '(名 (槽 nope))'), '外观上没有的槽');
      says(edit('blocks.json', '(件数 (设置 size))', '(件数 (槽 name))'), '不止一次');
      says(edit('blocks.json', '"needs": ["口袋", "账本"]', '"needs": ["账本"]'), 'needs');
      says(edit('blocks.json', '"needs": ["口袋"],', '"needs": ["钱包"],'), '没有哪块积木');
      says(edit('blocks.json', '(口 body (收尾', '(口 name (收尾'), '不是一个口');
      says(edit('blocks.json', '"how": "static"', '"how": "magic"'), 'how');
    });

    test('只有自带的库能做的两件事：旧名对照、旧文档的键；直接声明宿主接口要在清单里写明', () {
      final host = edit('modules/kit.lc', '(模块 小工具', '(模块 小工具 (宿主 time.now () -> 整数)');
      // 第四轮：自己写的库也能直接声明宿主接口了（复制自带库来改要用），但清单的 hosts 里必须一个不落写明。
      says(host, 'hosts 里没有写明');
      final declared = libRead({...host, 'lib.json': host['lib.json']!.replaceFirst('"rules": 2,', '"rules": 2, "hosts": ["time.now"],')}, builtin: false);
      expect(declared.problems, isEmpty);
      expect(declared.hosts, ['time.now']);
      expect(libRead(host, builtin: true).problems, isEmpty);
      expect(libRead(host, builtin: true).hosts, ['time.now']);
      says(edit('modules/kit.lc', '(模块 小工具', '(模块 小工具 (宿主 disk.format () -> 空)'), '没有它', builtin: true);
      final legacy = edit('blocks.json', '"id": "double",', '"id": "double", "legacy": {"fn": "dbl", "args": ["x"]},');
      says(legacy, '只有应用自带的库可以写');
      expect(libRead(legacy, builtin: true).legacy('dbl')?.id, 'double');
      says(edit('lib.json', '"min": 0,', '"legacyKey": "size", "min": 0,'), '只有应用自带的库可以写');
    });

    test('手写代码：默认不收（要全应用的开关开着、这个库又确认过）；文件没在清单里登记也不收', () {
      // 第四轮：手写代码有了能启用的路。读库时默认（nativeOk 否）照旧不收，说法换了。
      says({...files, 'native/x.node.js': 'return 1;'}, '要先打开“允许库里的手写代码”');
      says({...edit('lib.json', '"rules": 2,', '"rules": 2, "native": {"allowed": true},'), 'native/x.node.js': 'return 1;'}, '清单里没有登记');
      expect(libRead({...edit('lib.json', '"rules": 2,', '"rules": 2, "native": {"allowed": true},'), 'native/x.node.js': 'return 1;'}, builtin: false, nativeOk: true).ok, isFalse);
    });

    test('用的时候：不在给它东西的积木下面，说得出来', () {
      final got = libApply(lib, lib.block('pocketReport')!, const LibUse(), LibCx(fresh: (n) => n));
      expect(got.problem, contains('口袋'));
    });
  });
}
