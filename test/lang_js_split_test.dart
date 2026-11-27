// JS 生成器拆成“公共＋Node 目标＋浏览器目标”以后的钉子（积木第 5 版·第四轮·A2）：
// Node 那一份——小库 lc2.js 和 test/fixtures 下“要等的事”“核心 2”“小框架”三组样例生成出来的全部文件——和拆之前逐字节一样。
// 下面两串指纹是拆之前（提交 e27fe52）算出来的；以后只有“有意改 Node 的生成结果”才许改它们，改的时候在提交说明里写为什么。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen2_js.dart';
import 'package:lopicode/lang/gen2_node.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/proto_lc.dart';

const String _runtimeSha = '2a30feefcf05f9c40d2730c8b038c94f82ed78c99d35156d828977e79f3918dd';
const String _samplesSha = 'ae9d9f823ac6b26e88b0a8eefa8ab9df3d848163437b838a810386381d5e6bc5';
const int _samplesCount = 43;

bool _isProgram(String src) => lcParse(src).any((d) => d is List && d.isNotEmpty && d[0] == '模块');

void main() {
  test('Node 的小库 lc2.js 和拆之前逐字节一样', () {
    final files = gen2Files('node', lcModule('(主 (打印 "x"))'));
    expect(sha256.convert(utf8.encode(files['lc2.js']!)).toString(), _runtimeSha);
  });

  test('三组样例生成出来的 Node 文件和拆之前逐字节一样', () {
    final all = StringBuffer();
    var count = 0;
    for (final dir in ['waits', 'core2', 'framework']) {
      final names = [
        for (final f in Directory('test/fixtures/$dir').listSync().whereType<File>())
          if (f.path.endsWith('.lc')) f.path,
      ]..sort();
      for (final path in names) {
        final src = File(path).readAsStringSync();
        Map<String, String> files;
        try {
          files = _isProgram(src) ? gen2ProgramFiles('node', lcProgram(src)) : gen2Files('node', lcModule(src));
        } on LangUnsupported catch (e) {
          files = {'!': e.message}; // 故意写错的样例：比的是那句话
        }
        count++;
        for (final k in files.keys.toList()..sort()) {
          if (k == 'lc2.js') continue;
          all.writeln('== $path :: $k\n${files[k]}');
        }
      }
    }
    final got = sha256.convert(utf8.encode(all.toString())).toString();
    expect(count, _samplesCount);
    expect(got, _samplesSha);
  });

  test('Node 目标是 JS 公共部分上面的一层', () {
    final m = lcModule('(主 (打印 "x"))');
    expect(gen2For('node', m, checkModuleTypes(m)), isA<JsGen2>());
    expect(gen2For('node', m, checkModuleTypes(m)), isA<NodeGen2>());
  });
}
