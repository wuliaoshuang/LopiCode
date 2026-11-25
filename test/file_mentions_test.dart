// 聊天输入框“打 @ 选文件”的规则：什么时候算在打 @、扫哪些文件、怎么筛、选中后草稿怎么改。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/file_mentions.dart';
import 'package:path/path.dart' as p;

MentionTrigger? _at(String text, {int? cursor, int cs = -1, int ce = -1, bool whileComposing = true}) =>
    mentionTriggerAt(text, selStart: cursor ?? text.length, selEnd: cursor ?? text.length, composingStart: cs, composingEnd: ce, filterWhileComposing: whileComposing);

void main() {
  group('什么时候算在打 @', () {
    test('草稿开头的 @、空白后的 @、换行后的 @ 都算', () {
      expect(_at('@'), const MentionTrigger(0, 1, ''));
      expect(_at('@ma'), const MentionTrigger(0, 3, 'ma'));
      expect(_at('看一下 @lib/ma'), const MentionTrigger(4, 11, 'lib/ma'));
      expect(_at('第一行\n@in'), const MentionTrigger(4, 7, 'in'));
      expect(_at('全角空格　@a'), const MentionTrigger(5, 7, 'a'));
      expect(_at('@文件'), const MentionTrigger(0, 3, '文件'));
    });

    test('夹在字中间的 @ 不算（邮箱、a@b）', () {
      expect(_at('a@b.com'), isNull);
      expect(_at('发给 me@example.com'), isNull);
      expect(_at('你好@ma'), isNull);
      expect(_at('@@ma'), isNull, reason: '第二个 @ 前面不是空白');
    });

    test('打了空格、删掉 @、光标移走：不算', () {
      expect(_at('@main.dart '), isNull, reason: '空格之后就结束了');
      expect(_at('@main 再说'), isNull);
      expect(_at('main'), isNull, reason: '@ 被删掉了');
      expect(_at(''), isNull);
      expect(_at('@main 你好', cursor: 9), isNull, reason: '光标在后面那段字里');
      expect(_at('你好 @main', cursor: 1), isNull, reason: '光标挪到前面去了');
    });

    test('光标停在 @xxx 中间：只认到光标为止', () {
      expect(_at('@main.dart', cursor: 3), const MentionTrigger(0, 3, 'ma'));
    });

    test('选中了一段字：不算', () {
      expect(mentionTriggerAt('@main', selStart: 1, selEnd: 5), isNull);
      expect(mentionTriggerAt('@main', selStart: -1, selEnd: -1), isNull, reason: '没有光标');
      expect(mentionTriggerAt('@main', selStart: 9, selEnd: 9), isNull, reason: '光标越界');
    });

    test('输入法组字：@ 自己还在组字里不弹；组字在 @ 后面时拿组字里的字筛', () {
      expect(_at('@', cs: 0, ce: 1), isNull, reason: '@ 还没上屏');
      expect(_at('你好 @ni', cs: 3, ce: 6), isNull, reason: '@ 在组字范围里');
      expect(_at('@nihao', cs: 1, ce: 6), const MentionTrigger(0, 6, 'nihao'), reason: '拼音还没上屏：先拿拼音筛，不改草稿');
      expect(_at('@你好', cs: -1, ce: -1), const MentionTrigger(0, 3, '你好'), reason: '上屏以后按上屏的字筛');
      expect(_at('a@nihao', cs: 2, ce: 7), isNull, reason: '组字时也不放过“夹在中间的 @”');
    });

    test('组字期间不筛的开关：只认已经上屏的那一截', () {
      expect(_at('@nihao', cs: 1, ce: 6, whileComposing: false), const MentionTrigger(0, 6, ''));
      expect(_at('@lib/nihao', cs: 5, ce: 10, whileComposing: false), const MentionTrigger(0, 10, 'lib/'));
      expect(_at('@', cs: 0, ce: 1, whileComposing: false), isNull);
    });
  });

  group('扫工作区文件', () {
    late Directory tmp;
    late PathGuard guard;

    void put(String rel, [String body = 'x']) {
      File(p.join(tmp.path, rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(body);
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_mention_');
      guard = PathGuard(tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('只列文件，浅的在前，同一层按名字排', () async {
      put('index.html');
      put('app.js');
      put('src/main.dart');
      put('src/ui/home.dart');
      put('docs/readme.md');
      final scan = await scanMentionFiles(guard);
      expect(scan.error, isNull);
      expect(scan.truncated, isFalse);
      expect(scan.files, ['app.js', 'index.html', 'docs/readme.md', 'src/main.dart', 'src/ui/home.dart']);
    });

    test('不进应用内部目录、版本库、依赖、构建产物', () async {
      put('main.dart');
      put('.lopicode/project.json');
      put('.lopicode-attachments/a.png');
      put('.git/config');
      put('node_modules/left-pad/index.js');
      put('web/node_modules/x/y.js');
      put('build/app.apk');
      put('dist/bundle.js');
      put('.dart_tool/package_config.json');
      put('py/__pycache__/a.pyc');
      put('.gitignore');
      put('builder/keep.dart');
      final scan = await scanMentionFiles(guard);
      expect(scan.files, ['.gitignore', 'main.dart', 'builder/keep.dart'], reason: '只按整个目录名跳过：.gitignore、builder/ 不受影响');
      expect(kMentionSkipDirs, containsAll(['.git', 'node_modules', PathGuard.reservedDir, 'build']));
    });

    test('文件太多：扫到上限就停，并标出没扫完', () async {
      for (var i = 0; i < 30; i++) {
        put('f${i.toString().padLeft(2, '0')}.txt');
      }
      final scan = await scanMentionFiles(guard, maxFiles: 10);
      expect(scan.files, hasLength(10));
      expect(scan.truncated, isTrue);
      final exact = await scanMentionFiles(guard, maxFiles: 30);
      expect(exact.files, hasLength(30));
      expect(exact.truncated, isFalse, reason: '刚好扫完不算“太多”');
    });

    test('超时：到点就停，已经扫到的照用', () async {
      put('a.txt');
      put('deep/b.txt');
      put('deep/er/c.txt');
      var ticks = 0;
      // 假时钟：每看一次表过 1 秒，预算 2 秒 → 扫完第一层就到点。
      final scan = await scanMentionFiles(
        guard,
        budget: const Duration(seconds: 2),
        now: () => Duration(seconds: ticks++),
      );
      expect(scan.truncated, isTrue);
      expect(scan.files, ['a.txt']);
      final none = await scanMentionFiles(guard, budget: Duration.zero);
      expect(none.truncated, isTrue);
      expect(none.files, isEmpty);
    });

    test('一个目录里东西特别多也会看表', () async {
      for (var i = 0; i < 450; i++) {
        put('big/f$i.txt');
      }
      var ticks = 0;
      final scan = await scanMentionFiles(
        guard,
        budget: const Duration(seconds: 3),
        now: () => Duration(seconds: ticks++),
      );
      expect(scan.truncated, isTrue);
      expect(scan.files.length, lessThan(450));
    });

    test('不跟符号链接：指到工作区外面的目录和文件都不列', () async {
      final outside = Directory.systemTemp.createTempSync('lopi_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('s');
      put('ok.txt');
      Link(p.join(tmp.path, 'escape')).createSync(outside.path);
      Link(p.join(tmp.path, 'leak.txt')).createSync(p.join(outside.path, 'secret.txt'));
      final scan = await scanMentionFiles(guard);
      expect(scan.files, ['ok.txt']);
    });

    test('空工作区、工作区不见了：不抛异常', () async {
      expect((await scanMentionFiles(guard)).files, isEmpty);
      final gone = PathGuard(p.join(tmp.path, 'nope'));
      final scan = await scanMentionFiles(gone);
      expect(scan.files, isEmpty);
      expect(scan.error, contains('读不了工作区的文件'));
    });
  });

  group('筛选和排序', () {
    const files = ['main.dart', 'README.md', 'lib/main.dart', 'lib/ui/home_main.dart', 'lib/domain/user.dart', 'test/main_test.dart', 'web/index.html'];

    test('没打字：按扫出来的顺序', () {
      final m = filterMentionFiles(files, '');
      expect(m.files, files);
      expect(m.clipped, isFalse);
    });

    test('文件名开头匹配 → 文件名里有 → 路径里有；同档路径短的在前；不分大小写', () {
      expect(filterMentionFiles(files, 'main').files, ['main.dart', 'lib/main.dart', 'test/main_test.dart', 'lib/ui/home_main.dart', 'lib/domain/user.dart']);
      expect(filterMentionFiles(files, 'readme').files, ['README.md']);
      expect(filterMentionFiles(files, 'lib/ui').files, ['lib/ui/home_main.dart']);
      expect(filterMentionFiles(files, 'HTML').files, ['web/index.html']);
    });

    test('没有匹配：空的', () {
      final m = filterMentionFiles(files, 'zzz');
      expect(m.files, isEmpty);
      expect(m.total, 0);
    });

    test('匹配太多：只留前 N 个，记下一共多少', () {
      final many = [for (var i = 0; i < 120; i++) 'f$i.txt'];
      final m = filterMentionFiles(many, 'f');
      expect(m.files, hasLength(kMentionMaxResults));
      expect(m.total, 120);
      expect(m.clipped, isTrue);
      expect(filterMentionFiles(many, '').files, hasLength(kMentionMaxResults));
    });
  });

  group('选中以后草稿怎么改', () {
    test('把正在打的 @xxx 换成 @路径 加一个空格，光标落在后面', () {
      final e = applyMention('@ma', const MentionTrigger(0, 3, 'ma'), 'lib/main.dart');
      expect(e.text, '@lib/main.dart ');
      expect(e.cursor, e.text.length);
      expect(e.added, isTrue);
    });

    test('前后的字不动', () {
      final e = applyMention('看一下 @ho 再改颜色', const MentionTrigger(4, 7, 'ho'), 'lib/ui/home.dart');
      expect(e.text, '看一下 @lib/ui/home.dart  再改颜色');
      expect(e.cursor, '看一下 @lib/ui/home.dart '.length);
    });

    test('已经引用过：只去掉 @xxx，不加第二遍', () {
      final e = applyMention('@lib/main.dart 和 @ma', const MentionTrigger(17, 20, 'ma'), 'lib/main.dart');
      expect(e.added, isFalse);
      expect(e.text, '@lib/main.dart 和 ');
      expect(e.cursor, 17);
    });

    test('正在打的那段刚好等于路径：不算“已经引用过”', () {
      final e = applyMention('@main.dart', const MentionTrigger(0, 10, 'main.dart'), 'main.dart');
      expect(e.added, isTrue);
      expect(e.text, '@main.dart ');
    });

    test('名字只是别的引用的一部分：不算引用过', () {
      expect(draftHasMention('@lib/main.dart.bak ', 'lib/main.dart'), isFalse);
      expect(draftHasMention('x@lib/main.dart ', 'lib/main.dart'), isFalse);
      expect(draftHasMention('看 @lib/main.dart', 'lib/main.dart'), isTrue);
      expect(draftHasMention('@a.txt\n@b.txt', 'b.txt'), isTrue);
    });

    test('从加号里插入：和 @ 选出来的是同一个样子', () {
      expect(insertMention('', 0, 'a.txt').text, '@a.txt ');
      expect(insertMention('看', 1, 'a.txt').text, '看 @a.txt ', reason: '前面不是空白先补一个空格');
      expect(insertMention('看 ', 2, 'a.txt').text, '看 @a.txt ');
      expect(insertMention('看\n', 2, 'a.txt').text, '看\n@a.txt ');
    });
  });
}
