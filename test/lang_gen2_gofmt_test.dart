// 版本 2 生成的 Go 代码和 gofmt、go vet：
// - 小库 lc/lc.go、lc/host.go 是写死的文字，要 gofmt 干净；
// - main.go 的缩进是制表符（gofmt 的缩进）；它还有对齐、空行、多余括号这些地方和 gofmt 不一样（见 B-gen-notes 第 12 节，留着没改）；
// - 整套代码 go vet 一条都不报。
// 找不到 go / gofmt 就明确跳过。不联网。
@Tags(['external'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

void main() {
  final go = gen2Tools['go'];
  final gofmt = go == null ? null : '${File(go).parent.path}/gofmt';
  final files = gen2ProgramFiles('go', lcProgram(File('test/fixtures/framework/bookshop.lc').readAsStringSync()));

  Directory write() {
    final dir = Directory.systemTemp.createTempSync('lopi_gen2_fmt_');
    for (final f in files.entries) {
      File('${dir.path}/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    return dir;
  }

  test('main.go 用制表符缩进，没有用空格缩进的行', () {
    final lines = files['main.go']!.split('\n');
    expect(lines.where((l) => l.startsWith(' ')), isEmpty);
    expect(lines.where((l) => l.startsWith('\t')), isNotEmpty);
  });

  test('小库 lc/lc.go、lc/host.go 是 gofmt 干净的', () {
    if (gofmt == null || !File(gofmt).existsSync()) {
      markTestSkipped('这台机器找不到 gofmt，跳过');
      return;
    }
    final dir = write();
    try {
      final r = Process.runSync(gofmt, ['-l', 'lc'], workingDirectory: dir.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}'.trim(), '', reason: '这些文件 gofmt 以后会变');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('小框架生成的整套 Go 代码 go vet 不报', () {
    if (go == null) {
      markTestSkipped(gen2SkipReason('go') ?? '找不到 go');
      return;
    }
    final dir = write();
    try {
      final env = {...Platform.environment, 'GOFLAGS': '-mod=mod', 'GOPROXY': 'off', 'GOCACHE': '${Directory.systemTemp.path}/lopi_gen2_gocache'};
      final r = Process.runSync(go, ['vet', './...'], workingDirectory: dir.path, environment: env);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
