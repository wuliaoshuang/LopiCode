// 积木第 5 版的验证原型（docs/blocks-v5-prototypes/）收成的回归测试：把设计时跑通的样本每次都重跑一遍，
// 核对的是“通过了多少条”这些数，不是只看退出码。
//   后端库“接口服务”135 条 · 小框架 39 条 · 类型 16 个程序＋4 组错例 · 前端状态库 / 事件总线 48 条 · 组件 25 条 · 完整流程 15 条
// 做法：把原型目录整个复制到临时目录里跑（原型脚本会改写 out/ 和 RESULT 文件，不能弄脏工程），端口、临时目录用环境变量换开。
// 要 bash、node、python3；类型那一组另要 go、javac（没有的那种标“跳过”）。原型只翻成 Node 和 Python（类型另有手写的 Go、Java），没有 PHP。不联网。
// 实测耗时（2026-11-26，1.5 核的开发机）：机器空着时一共约 70 秒，其中类型那一组约 50 秒；
// 机器半忙时（负载 8 上下、只开一路）实测一共 199 秒；
// 别的任务把机器占满时（负载 15 上下）实测过一共 12 分钟，类型那一组占了 10 分半——所以类型拆成三段跑，单条上限放到 30 分钟（dart_test.yaml）。
@Tags(['external'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/backend_conformance.dart' show findGo;

bool _has(String exe, [List<String> args = const ['--version']]) {
  try {
    return Process.runSync(exe, args).exitCode == 0;
  } on ProcessException {
    return false; // 这台机器没装：相关用例跳过
  }
}

final String? _missing = () {
  final lack = [if (!_has('bash')) 'bash', if (!_has('node')) 'node', if (!_has('python3')) 'python3'];
  return lack.isEmpty ? null : '这台机器上没有 ${lack.join('、')}，跳过第 5 版原型的回归测试';
}();

late Directory _work;
late Map<String, String> _env;

/// 跑原型里的一个脚本，返回它说的每一行（标准输出＋标准错误）。
Future<({int code, List<String> lines})> _run(String script, {List<String> args = const [], Map<String, String> extra = const {}}) async {
  final r = await Process.run('bash', [script, ...args], workingDirectory: '${_work.path}/proto', environment: {..._env, ...extra});
  return (code: r.exitCode, lines: '${r.stdout}\n${r.stderr}'.split('\n'));
}

void _expectLine(List<String> lines, String line) => expect(lines, contains(line), reason: '脚本的输出里没有这一行。全部输出：\n${lines.join('\n')}');

void main() {
  if (_missing != null) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】$_missing');
  }
  final Object skip = _missing ?? false;

  setUpAll(() async {
    if (_missing != null) return;
    _work = Directory.systemTemp.createTempSync('lopi_v5_proto_');
    final copied = await Process.run('cp', ['-r', '${Directory.current.path}/docs/blocks-v5-prototypes', '${_work.path}/proto']);
    expect(copied.exitCode, 0, reason: '${copied.stderr}');
    // 上次留在原型目录里的生成物不算数：这次都重新生成。
    for (final d in ['01-backend-lib/out', '02-web-framework/out', '03-frontend-lib/out', '04-component/out', '05-full-flow/out']) {
      final out = Directory('${_work.path}/proto/$d');
      if (out.existsSync()) out.deleteSync(recursive: true);
    }
    _env = {
      'LC_PROTO_TMP': '${_work.path}/tmp',
      // 端口按进程号错开：两个工作目录同时跑检查也不会撞。
      'LC_PROTO_PORT_BASE': '${20000 + (pid % 150) * 100}',
      'PYTHONDONTWRITEBYTECODE': '1',
    };
  });

  tearDownAll(() {
    if (_missing != null) return;
    _work.deleteSync(recursive: true);
  });

  test('翻译脚本自测：36 行输出，Node 和 Python 逐字节相同、等于手写的期望', () async {
    final r = await _run('tool/selftest/run.sh');
    _expectLine(r.lines, '[自测] 语言特性 36 行输出：Node 和 Python 逐字节相同，并且等于手写的期望 → 通过');
    expect(r.code, 0);
  }, skip: skip);

  test('后端库“接口服务”：135 条请求两轮、两种语言都等于期望，互相逐字节相同；同时加 30 条不丢不撞', () async {
    final r = await _run('01-backend-lib/run.sh');
    for (final round in ['第1轮', '第2轮']) {
      for (final lang in ['node', 'python']) {
        _expectLine(r.lines, '[01 接口服务·$round] $lang：135 条请求，135 条等于写死的期望，0 条不等');
        _expectLine(r.lines, '[01 接口服务·$round] $lang：标准输出 1 行，等于期望的 1 行');
      }
      _expectLine(r.lines, '[01 接口服务·$round] node 和 python 逐条比（状态码＋响应头＋内容，逐字节）：134 条相同，0 条不同');
      _expectLine(r.lines, '[01 接口服务·$round] 结果：全部通过');
      _expectLine(r.lines, '[$round python] 同时发 30 个“加一条”：集合里有 30 条，发回来的编号有 30 种 → 没丢没撞');
    }
    expect(r.code, 0);
  }, skip: skip);

  test('小框架：39 条请求，第 2 轮两种语言全对、互相逐字节相同；第 1 轮和留档的一样（只有第 17 条不过）', () async {
    final r = await _run('02-web-framework/run.sh');
    for (final lang in ['node', 'python']) {
      _expectLine(r.lines, '[02 小框架·第2轮] $lang：39 条请求，39 条等于写死的期望，0 条不等');
      _expectLine(r.lines, '[02 小框架·第2轮] $lang：标准输出 39 行，等于期望的 39 行');
      _expectLine(r.lines, '[02 小框架·第1轮] $lang：39 条请求，38 条等于写死的期望，1 条不等');
    }
    _expectLine(r.lines, '[02 小框架·第2轮] node 和 python 逐条比（状态码＋响应头＋内容，逐字节）：39 条相同，0 条不同');
    _expectLine(r.lines, '[02 小框架·第2轮] 结果：全部通过');
    _expectLine(r.lines, '[02 小框架·第1轮] 和预期一样：只有第 17 条不过');
    expect(r.code, 0);
  }, skip: skip);

  test('前端状态库 / 事件总线：48 条检查，第 2 轮两种语言全对、逐字节相同；第 1 轮和留档的一样', () async {
    final r = await _run('03-frontend-lib/run.sh');
    for (final lang in ['node', 'python']) {
      _expectLine(r.lines, '[03 第2轮 $lang] 48 条检查，48 条等于手写的期望，0 条不等');
      _expectLine(r.lines, '[03 第2轮] $lang 退出码 0，错误输出 0 行');
    }
    _expectLine(r.lines, '[03 第2轮] node 和 python 的输出逐字节相同');
    _expectLine(r.lines, '[03 第1轮] 和留档的一样：node 6/48（跑到第 [3b] 条时程序死了），python 45/48');
    expect(r.code, 0);
  }, skip: skip);

  test('组件“待办列表”：25 条检查，第 2 轮全对；第 1 轮和留档的一样（13/25）', () async {
    final r = await _run('04-component/run.sh');
    _expectLine(r.lines, '[04 第2轮 node] 25 条检查，25 条等于手写的期望，0 条不等');
    _expectLine(r.lines, '[04 第2轮] node 退出码 0，错误输出 0 行');
    _expectLine(r.lines, '[04 第1轮] 和留档的一样：13/25');
    expect(r.code, 0);
  }, skip: skip);

  test('完整流程（前端真发请求到 Node / Python 两个后端）：15 条检查，第 2 轮全对、对两个后端逐字节相同；第 1 轮和留档的一样', () async {
    final r = await _run('05-full-flow/run.sh');
    for (final lang in ['node', 'python']) {
      _expectLine(r.lines, '[05 第2轮 对 $lang 服务] 15 条检查，15 条等于手写的期望，0 条不等');
      _expectLine(r.lines, '[05 第2轮 对 $lang 服务] 前端退出码 0，错误输出 0 行');
    }
    _expectLine(r.lines, '[05 第2轮] 对 Node 服务和对 Python 服务，前端的输出逐字节相同');
    _expectLine(r.lines, '[05 第1轮] 和留档的一样：对两个服务都是 11/15');
    expect(r.code, 0);
  }, skip: skip);

  // 类型那一组最慢（每个程序都要用 Go、Java 真编译一遍），拆成三段跑：机器忙的时候单段也不至于超时。
  final typeRows = <String, String>{};
  for (final part in const [
    (name: '第 1–8 个程序', prefixes: ['p00', 'p01', 'p02', 'p03', 'p04', 'p05', 'p06', 'p07', 'p08'], programs: 8, wrongs: 0),
    (name: '第 9–16 个程序', prefixes: ['p09', 'p1'], programs: 8, wrongs: 0),
    (name: '4 组错例', prefixes: ['e'], programs: 0, wrongs: 4),
  ]) {
    test('类型（${part.name}）：在 Node / Python / Go / Java 上的输出等于期望、互相逐字节相同，自动推断等于手写；错例报的错等于手写', () async {
      final go = await findGo();
      final hasJava = _has('javac', const ['-version']);
      final skipped = [if (go == null) 'go', if (!hasJava) 'java'];
      if (skipped.isNotEmpty) {
        // ignore: avoid_print 跳过的原因要在测试输出里看得见
        print('【部分跳过】类型原型：这台机器上没有 ${skipped.join('、')}，这${skipped.length == 1 ? '一' : '两'}种语言不跑，别的照跑');
      }
      final home = Platform.environment['HOME'] ?? '';
      final existing = [
        for (final d in Directory('${_work.path}/proto/types').listSync().whereType<Directory>())
          if (RegExp(r'^[pe][0-9]{2}-').hasMatch(d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      ];
      // 只把真有目录对得上的前缀交给脚本（对不上的前缀会被当成一个不存在的目录）。
      final prefixes = [
        for (final p in part.prefixes)
          if (existing.any((d) => d.startsWith(p))) p,
      ];
      final r = await _run(
        'types/run_all.sh',
        args: prefixes,
        extra: {
          'LC_PROTO_SKIP': skipped.join(' '),
          if (go != null && go.contains('/')) 'PATH': '${File(go).parent.path}:${Platform.environment['PATH']}',
          // Go 的编译缓存用平时那一份（每次重编标准库要多花一分钟）。
          if (home.isNotEmpty) 'LC_PROTO_GOCACHE': '$home/.cache/go-build',
        },
      );
      final rows = {
        for (final l in r.lines)
          if (RegExp(r'^[pe][0-9]{2}-').hasMatch(l)) l.split(':').first: l,
      };
      typeRows.addAll(rows);
      final programs = rows.keys.where((k) => k.startsWith('p')).toList();
      final wrongs = rows.keys.where((k) => k.startsWith('e')).toList();
      expect(programs.length, part.programs, reason: r.lines.join('\n'));
      expect(wrongs.length, part.wrongs, reason: r.lines.join('\n'));
      final ran = 4 - skipped.length;
      for (final p in programs) {
        final row = rows[p]!;
        expect('通过'.allMatches(row).length, ran + 1, reason: '应该是 $ran 种语言＋自动推断都通过：$row');
        expect(row, isNot(contains('不符')));
        expect(row, contains('${ran == 4 ? '四' : ran}份逐字节相同=是'));
        expect(row, contains('自动推断对比手写=通过'));
        for (final s in skipped) {
          expect(row, contains('${s == 'go' ? 'Go' : 'Java'}=跳过'));
        }
      }
      for (final e in wrongs) {
        expect(rows[e], contains('自动报错对比手写=通过'), reason: rows[e]);
      }
      _expectLine(r.lines, '合计：通过 ${part.programs * (ran + 1) + part.wrongs} 项，不符 0 项');
      expect(r.code, 0);
    }, skip: skip);
  }

  test('类型：三段加起来正好是 16 个程序＋4 组错例，一个不多一个不少', () {
    expect(typeRows.keys.where((k) => k.startsWith('p')).length, 16, reason: '${typeRows.keys.toList()}');
    expect(typeRows.keys.where((k) => k.startsWith('e')).length, 4, reason: '${typeRows.keys.toList()}');
    final onDisk = [
      for (final d in Directory('docs/blocks-v5-prototypes/types').listSync().whereType<Directory>())
        if (RegExp(r'^[pe][0-9]{2}-').hasMatch(d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ];
    expect(typeRows.keys.toSet(), onDisk.toSet(), reason: '原型目录里的每个程序都要跑到');
  }, skip: skip);
}
