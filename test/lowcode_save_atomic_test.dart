// 低代码页面存盘（saveLowcodePage，搭建页和 Agent 共用）必须是“先写临时文件再改名”：
// 写不进去 / 写到一半时，原来的页面文件、网页还是完整的旧内容。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

LcDocument _big(String title, int count) {
  final doc = LcDocument.starter(title);
  for (var i = 0; i < count; i++) {
    doc.insert(doc.root.id, doc.newNode('text')..props['text'] = '第 $i 段：${'字' * 200}');
  }
  return doc;
}

void main() {
  late Directory tmp;
  late PathGuard guard;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lc_save_atomic');
    guard = PathGuard(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  File f(String name) => File(p.join(tmp.path, name));

  test('存完以后四个文件内容都对，目录里不剩临时文件', () async {
    final doc = _big('一页', 3);
    await saveLowcodePage(guard, doc);
    expect(f(kLowcodePageFile).readAsStringSync(), doc.encode());
    expect(f('index.html').readAsStringSync(), contains('<title>一页</title>'));
    expect(f('style.css').readAsStringSync(), contains('.lc-page'));
    expect([for (final e in tmp.listSync()) p.basename(e.path)].where((n) => n.endsWith('.tmp')), isEmpty);
  });

  test('写不进去（临时文件的位置被占了）：报错，原来的页面文件一个字都没变', () async {
    final v1 = _big('旧的', 2);
    await saveLowcodePage(guard, v1);
    final before = f(kLowcodePageFile).readAsStringSync();
    // 临时文件叫“页面文件名.tmp”：在那个位置放一个目录，临时文件就写不出来。
    // 直接往页面文件里写的写法不会碰到它（那样就不是先写临时文件再改名了，这条用例会失败）。
    Directory(p.join(tmp.path, '$kLowcodePageFile.tmp')).createSync();
    await expectLater(saveLowcodePage(guard, _big('新的', 2)), throwsA(isA<FileSystemException>()));
    expect(f(kLowcodePageFile).readAsStringSync(), before);
    expect(LcDocument.parse(f(kLowcodePageFile).readAsStringSync()).title, '旧的');
  });

  test('网页文件写不进去：页面文件已经是新的、完整的；网页还是完整的旧内容', () async {
    await saveLowcodePage(guard, _big('旧的', 2));
    final oldHtml = f('index.html').readAsStringSync();
    Directory(p.join(tmp.path, 'index.html.tmp')).createSync();
    await expectLater(saveLowcodePage(guard, _big('新的', 2)), throwsA(isA<FileSystemException>()));
    expect(LcDocument.parse(f(kLowcodePageFile).readAsStringSync()).title, '新的');
    expect(f('index.html').readAsStringSync(), oldHtml);
  });

  test('一边反复存、一边反复读：读到的永远是一份完整的页面（不会读到半截）', () async {
    final docs = [_big('甲', 400), _big('乙', 400)];
    await saveLowcodePage(guard, docs[0]);
    var saving = true;
    var reads = 0;
    final bad = <String>[];
    final reader = () async {
      while (saving) {
        final text = await f(kLowcodePageFile).readAsString();
        reads++;
        try {
          final title = (jsonDecode(text) as Map)['title'];
          if (title != '甲' && title != '乙') bad.add('标题不对：$title');
        } on FormatException {
          bad.add('读到 ${text.length} 个字的半截文件');
        }
      }
    }();
    for (var i = 0; i < 30; i++) {
      await saveLowcodePage(guard, docs[i % 2]);
    }
    saving = false;
    await reader;
    expect(reads, greaterThan(0));
    expect(bad, isEmpty);
  });
}
