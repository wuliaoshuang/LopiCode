// 读存盘文件之前先等同一个文件排着队的写入（lib/core/safe_file.dart 的 readJsonFile / pendingWriteOf）：
// 写了不等、马上读，读到的也是刚写的那份——不会读到上一份。
// 起因：一轮对话收尾时先放下“生成中”、再等存盘；这时马上重开这段对话，机器忙时会读到中途存的旧记录、少最后一条回复
// （test/chat_steps_ui_test.dart 深色整条链路用例在机器挤的时候挂过一次，就是这个）。
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_raw_'));
  tearDown(() async {
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  test('写了不等就读：读到的是刚写的那份（连着写几次，读到最后一次的）', () async {
    final file = File(p.join(tmp.path, 'chat.json'));
    await writeJsonAtomic(file, ['旧的']);
    // 一份大一点的内容，写得慢一些；不等它
    final big = [for (var i = 0; i < 20000; i++) '第 $i 条'];
    unawaited(writeJsonAtomic(file, big));
    unawaited(writeJsonAtomic(file, [...big, '最后一条回复']));
    final got = await readJsonFile(file) as List;
    expect(got.length, 20001);
    expect(got.last, '最后一条回复');
  });

  test('没有排队的写入：马上返回；文件不存在照旧是 null', () async {
    final file = File(p.join(tmp.path, 'none.json'));
    await pendingWriteOf(file);
    expect(await readJsonFile(file), isNull);
  });

  test('排着的那次写失败了：读不抛错，读到的是盘上原来那份', () async {
    final dir = Directory(p.join(tmp.path, 'd'))..createSync();
    final file = File(p.join(dir.path, 'a.json'));
    await writeJsonAtomic(file, {'v': 1});
    // 把目标换成一个目录同名的东西让改名失败：先占住 .tmp 的位置为目录
    Directory('${file.path}.tmp').createSync();
    final failing = writeJsonAtomic(file, {'v': 2});
    unawaited(failing.catchError((Object _) {}));
    expect(await readJsonFile(file), {'v': 1});
    await expectLater(failing, throwsA(isA<FileSystemException>()));
    Directory('${file.path}.tmp').deleteSync();
  });

  test('别的文件在写：不等它', () async {
    final a = File(p.join(tmp.path, 'a.json'));
    final b = File(p.join(tmp.path, 'b.json'));
    await writeJsonAtomic(b, [1]);
    final big = [for (var i = 0; i < 20000; i++) '第 $i 条'];
    var aDone = false;
    unawaited(writeJsonAtomic(a, big).then((_) => aDone = true));
    expect(await readJsonFile(b), [1]);
    expect(aDone, isFalse, reason: '读 b 没有等 a 写完');
  });
}
