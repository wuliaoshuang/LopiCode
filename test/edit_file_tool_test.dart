// edit_file 工具接进权限以后的行为（真的读写临时目录里的文件）：
// 和 write_file 同一类——仅可查看 / 计划模式 / 预设没勾时不给模型、硬调用也拒绝；路径越界、写入范围外直接拒绝；
// 换行符、BOM、二进制、不存在的文件；write_file / delete_file 带回的改动对比；确认卡的预览。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/edit_file_tool.dart';
import 'package:lopicode/agent/edit_match.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;

void main() {
  late Directory tmp;
  late PathGuard guard;
  late List<ApprovalRequest> asked;
  late bool answer;

  File f(String rel) => File(p.join(tmp.path, 'proj', rel));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_edit_');
    Directory(p.join(tmp.path, 'proj', 'lib')).createSync(recursive: true);
    f('lib/a.dart').writeAsStringSync('void main() {\n  print("hi");\n}\n');
    File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('SECRET');
    guard = PathGuard(p.join(tmp.path, 'proj'));
    asked = [];
    answer = true;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  AgentToolbox box({PermissionLevel level = PermissionLevel.workspace, bool plan = false, Set<String>? allowed, List<String>? scope}) => AgentToolbox(
    guard: guard,
    runner: RecordingRunner(),
    requestApproval: (r) async {
      asked.add(r);
      return answer;
    },
    autoApprove: () => false,
    permission: () => level,
    planMode: () => plan,
    allowedTools: allowed,
    writeScope: scope,
  );

  List<String> names(AgentToolbox b) => [for (final s in b.specs) (s['function'] as Map)['name'] as String];
  Map<String, dynamic> edit(String path, String oldText, String newText, {Object? all}) => {'path': path, 'old_text': oldText, 'new_text': newText, 'replace_all': ?all};

  test('登记：和 write_file 同一类（改动工作区文件），有中文名，系统提示词里说了优先用它', () {
    expect(AgentToolbox.coreKinds['edit_file'], ToolKind.write);
    expect(AgentToolbox.coreKinds['edit_file'], AgentToolbox.coreKinds['write_file']);
    expect(AgentToolbox.approvalRequired, isNot(contains('edit_file')), reason: '和 write_file 一样不出确认卡');
    expect(kToolLabels['edit_file'], '局部修改文件');
    expect(AgentRunner.defaultSystemPrompt, contains('改已有文件优先用 edit_file'));
    expect(AgentRunner.defaultSystemPrompt, contains('新建文件或整份重写才用 write_file'));
    expect(stepKindOf('edit_file'), StepKind.edit);
    expect(describeTool('edit_file', '{"path":"lib/a.dart"}'), '修改 lib/a.dart');
    final spec = editFileSpec['function'] as Map;
    expect((spec['parameters'] as Map)['required'], ['path', 'old_text', 'new_text']);
    expect(((spec['parameters'] as Map)['properties'] as Map).keys, containsAll(['path', 'old_text', 'new_text', 'replace_all']));
  });

  test('工作区内修改：直接改，不问；返回里说了哪一级匹配、改了哪几行；带回对比', () async {
    final b = box();
    expect(names(b), contains('edit_file'));
    final r = await b.execute('edit_file', edit('lib/a.dart', 'print("hi");', 'print("hello");\n  print("bye");'));
    expect(r.ok, isTrue, reason: r.text);
    expect(asked, isEmpty);
    expect(f('lib/a.dart').readAsStringSync(), 'void main() {\n  print("hello");\n  print("bye");\n}\n');
    expect(r.text, contains('已修改 lib/a.dart'));
    expect(r.text, contains('替换了 1 处'));
    expect(r.text, contains('精确匹配'));
    expect(r.text, contains('第 2–3 行'));
    expect(r.text, contains('+2 −1'));
    expect(r.changedFiles, isTrue);
    final c = r.change!;
    expect((c.path, c.kind, c.added, c.removed), ('lib/a.dart', ChangeKind.modified, 2, 1));
    expect(c.hunks.single.lines, [' void main() {', '-  print("hi");', '+  print("hello");', '+  print("bye");', ' }']);
  });

  test('不是精确匹配时，返回里提醒模型是按哪一级找到的', () async {
    final r = await box().execute('edit_file', edit('lib/a.dart', 'print("hi");   ', 'print(1);'));
    expect(r.ok, isTrue, reason: r.text);
    expect(r.text, contains('忽略行首尾空白'));
    expect(r.text, contains('不完全一样'));
    expect(f('lib/a.dart').readAsStringSync(), 'void main() {\n  print(1);\n}\n', reason: '缩进按文件里的对齐');
  });

  test('多处匹配：不改；replace_all（布尔或字符串 "true"）才全部换', () async {
    f('m.txt').writeAsStringSync('a\nb\na\n');
    final b = box();
    final no = await b.execute('edit_file', edit('m.txt', 'a', 'c'));
    expect(no.ok, isFalse);
    expect(no.text, startsWith('错误：'));
    expect(no.text, contains('2 处'));
    expect(no.change, isNull);
    expect(no.changedFiles, isFalse);
    expect(f('m.txt').readAsStringSync(), 'a\nb\na\n');
    expect((await b.execute('edit_file', edit('m.txt', 'a', 'c', all: 'true'))).ok, isTrue);
    expect(f('m.txt').readAsStringSync(), 'c\nb\nc\n');
    expect((await b.execute('edit_file', edit('m.txt', 'c', 'd', all: true))).text, contains('替换了 2 处'));
  });

  test('找不到 / 原文为空 / 缺参数：不改，说清原因', () async {
    final b = box();
    const before = 'void main() {\n  print("hi");\n}\n';
    final miss = await b.execute('edit_file', edit('lib/a.dart', 'print("ho");', 'x'));
    expect(miss.ok, isFalse);
    expect(miss.text, contains('没有找到'));
    expect(miss.text, contains('最接近的是文件第 2 行'));
    final empty = await b.execute('edit_file', edit('lib/a.dart', '', 'x'));
    expect(empty.ok, isFalse);
    expect(empty.text, contains('old_text 不能为空'));
    final noNew = await b.execute('edit_file', {'path': 'lib/a.dart', 'old_text': 'hi'});
    expect(noNew.ok, isFalse);
    expect(noNew.text, contains('new_text'));
    expect(f('lib/a.dart').readAsStringSync(), before);
  });

  test('文件不存在、是目录、是二进制、不是 UTF-8：拒绝，不新建、不弄坏', () async {
    final b = box();
    final none = await b.execute('edit_file', edit('nope.txt', 'a', 'b'));
    expect(none.ok, isFalse);
    expect(none.text, contains('文件不存在'));
    expect(none.text, contains('write_file'));
    expect(f('nope.txt').existsSync(), isFalse);
    expect((await b.execute('edit_file', edit('lib', 'a', 'b'))).text, contains('是一个目录'));
    f('bin.dat').writeAsBytesSync([1, 2, 0, 3, 97]);
    expect((await b.execute('edit_file', edit('bin.dat', 'a', 'b'))).text, contains('二进制'));
    expect(f('bin.dat').readAsBytesSync(), [1, 2, 0, 3, 97]);
    f('gbk.txt').writeAsBytesSync([0xC4, 0xE3, 0xBA, 0xC3, 0x61]);
    final gbk = await b.execute('edit_file', edit('gbk.txt', 'a', 'b'));
    expect(gbk.ok, isFalse);
    expect(gbk.text, contains('不是 UTF-8'));
    expect(f('gbk.txt').readAsBytesSync(), [0xC4, 0xE3, 0xBA, 0xC3, 0x61]);
  });

  test('磁盘上的 CRLF、末尾没有换行、开头的 BOM 都原样保留', () async {
    f('w.txt').writeAsStringSync('\uFEFF一\r\n二\r\n三');
    final r = await box().execute('edit_file', edit('w.txt', '二\n三', '贰\n叁\n肆'));
    expect(r.ok, isTrue, reason: r.text);
    final bytes = f('w.txt').readAsBytesSync();
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'BOM 还在');
    expect(f('w.txt').readAsStringSync().replaceFirst('\uFEFF', ''), '一\r\n贰\r\n叁\r\n肆');
    expect(r.change!.hunks.single.lines, [' 一', '-二', '-三', '+贰', '+叁', '+肆']);
  });

  test('超大文件（超过 $kEditMaxChars 字符）：拒绝，文件没动', () async {
    final big = '${'x' * 99}\n' * 10001;
    f('big.txt').writeAsStringSync(big);
    final r = await box().execute('edit_file', edit('big.txt', 'x', 'y'));
    expect(r.ok, isFalse);
    expect(r.text, contains('$kEditMaxChars'));
    expect(f('big.txt').lengthSync(), big.length);
    f('huge.txt').writeAsStringSync('y' * (kEditMaxChars * 4 + 10));
    expect((await box().execute('edit_file', edit('huge.txt', 'y', 'z'))).text, contains('太大'));
  });

  test('路径越界被拒：工作区外的文件、内部目录都碰不到', () async {
    final b = box(level: PermissionLevel.full);
    for (final path in ['../outside.txt', p.join(tmp.path, 'outside.txt'), 'lib/../../outside.txt']) {
      final r = await b.execute('edit_file', edit(path, 'SECRET', 'x'));
      expect(r.ok, isFalse, reason: path);
      expect(r.text, startsWith('错误：'), reason: path);
      expect(r.text, isNot(contains('SECRET')), reason: path);
    }
    expect(File(p.join(tmp.path, 'outside.txt')).readAsStringSync(), 'SECRET');
    expect((await b.execute('edit_file', edit('.', 'a', 'b'))).ok, isFalse);
  });

  test('计划模式：工具列表里没有 edit_file，硬调用也被拒绝，文件没动', () async {
    final b = box(plan: true);
    expect(names(b), isNot(contains('edit_file')));
    expect(names(b), isNot(contains('write_file')));
    final r = await b.execute('edit_file', edit('lib/a.dart', 'hi', 'ho'));
    expect((r.ok, r.denied), (false, true));
    expect(r.text, contains('计划模式'));
    expect(f('lib/a.dart').readAsStringSync(), contains('"hi"'));
  });

  test('仅可查看：同样不给、不许', () async {
    final b = box(level: PermissionLevel.view);
    expect(names(b), isNot(contains('edit_file')));
    final r = await b.execute('edit_file', edit('lib/a.dart', 'hi', 'ho'));
    expect((r.ok, r.denied), (false, true));
    expect(r.text, contains('仅可查看'));
    expect(f('lib/a.dart').readAsStringSync(), contains('"hi"'));
  });

  test('预设没勾 edit_file：不给、不许；只勾了 edit_file 没勾 write_file：能局部改、不能整份写', () async {
    final off = box(allowed: {'read_file', 'write_file'});
    expect(names(off), isNot(contains('edit_file')));
    final r = await off.execute('edit_file', edit('lib/a.dart', 'hi', 'ho'));
    expect(r.ok, isFalse);
    expect(r.text, contains('没有开启 edit_file'));
    expect(f('lib/a.dart').readAsStringSync(), contains('"hi"'));
    final only = box(allowed: {'read_file', 'edit_file'});
    expect(names(only), contains('edit_file'));
    expect(names(only), isNot(contains('write_file')));
    expect((await only.execute('edit_file', edit('lib/a.dart', 'hi', 'ho'))).ok, isTrue);
    expect((await only.execute('write_file', {'path': 'lib/a.dart', 'content': 'x'})).ok, isFalse);
  });

  test('团队写入范围外被拒；范围内可以改', () async {
    f('web/index.html').createSync(recursive: true);
    f('web/index.html').writeAsStringSync('<h1>hi</h1>\n');
    final b = box(scope: ['web']);
    final out = await b.execute('edit_file', edit('lib/a.dart', 'hi', 'ho'));
    expect(out.ok, isFalse);
    expect(out.text, contains('写入范围是 web'));
    expect(out.text, contains('lib/a.dart 不在范围内'));
    expect(f('lib/a.dart').readAsStringSync(), contains('"hi"'));
    expect((await b.execute('edit_file', edit('web/index.html', 'hi', 'ho'))).ok, isTrue);
    expect(f('web/index.html').readAsStringSync(), '<h1>ho</h1>\n');
    expect(asked, isEmpty, reason: '范围外是直接拒绝，不出确认卡');
  });

  group('write_file / delete_file 带回的改动', () {
    test('write_file 新建：全是增，标新建；覆盖：对比前后；文字结果不变', () async {
      final b = box();
      final made = await b.execute('write_file', {'path': 'n/new.txt', 'content': 'a\nb\n'});
      expect(made.text, '已写入 n/new.txt（4 字符）');
      expect((made.change!.kind, made.change!.added, made.change!.removed), (ChangeKind.created, 2, 0));
      final over = await b.execute('write_file', {'path': 'n/new.txt', 'content': 'a\nB\nc\n'});
      expect((over.change!.kind, over.change!.added, over.change!.removed), (ChangeKind.modified, 2, 1));
      expect(asked, isEmpty, reason: '“工作区内修改”档写文件仍然不问');
    });

    test('write_file 覆盖二进制文件 / 超大文件：没有对比，只有说明，照样写成功', () async {
      f('bin.dat').writeAsBytesSync([0, 1, 2]);
      final r = await box().execute('write_file', {'path': 'bin.dat', 'content': 'text now'});
      expect(r.ok, isTrue);
      expect(r.change!.hasDiff, isFalse);
      expect(r.change!.note, contains('二进制'));
      f('big.txt').writeAsBytesSync(List.filled(kSnapshotMaxBytes + 1, 97));
      final big = await box().execute('write_file', {'path': 'big.txt', 'content': 'small'});
      expect(big.ok, isTrue);
      expect(big.change!.note, contains('太大'));
      expect(f('big.txt').readAsStringSync(), 'small');
    });

    test('delete_file：确认卡上带着“会删掉什么”的预览（不带全文）；允许后带回改动；拒绝则文件还在', () async {
      answer = false;
      final b = box();
      final no = await b.execute('delete_file', {'path': 'lib/a.dart'});
      expect(no.denied, isTrue);
      expect(no.change, isNull);
      expect(f('lib/a.dart').existsSync(), isTrue);
      final preview = asked.single.preview!;
      expect((preview.kind, preview.removed, preview.added), (ChangeKind.deleted, 3, 0));
      expect(preview.hunks.single.lines, ['-void main() {', '-  print("hi");', '-}']);
      expect(preview.before, isNull, reason: '卡片上只带精简对比');
      answer = true;
      final yes = await b.execute('delete_file', {'path': 'lib/a.dart'});
      expect(yes.text, '已删除 lib/a.dart');
      expect((yes.change!.kind, yes.change!.removed), (ChangeKind.deleted, 3));
      expect(f('lib/a.dart').existsSync(), isFalse);
    });

    test('delete_file 删目录：预览和改动只有一句说明', () async {
      final r = await box().execute('delete_file', {'path': 'lib'});
      expect(r.ok, isTrue);
      expect(asked.single.preview!.note, '删除了整个目录');
      expect((r.change!.path, r.change!.kind, r.change!.hasDiff), ('lib/', ChangeKind.deleted, false));
    });

    test('run_command、读文件这些没有改动记录', () async {
      final b = box();
      expect((await b.execute('read_file', {'path': 'lib/a.dart'})).change, isNull);
      expect((await b.execute('run_command', {'command': 'ls'})).change, isNull);
      expect(asked.single.preview, isNull);
    });
  });
}
