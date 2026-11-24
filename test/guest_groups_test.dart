// 给 Ubuntu 的 /etc/group 补安卓组名（第二轮真机反馈：终端一打开有四行 groups: cannot find name for group ID）。
// 纯逻辑：不起 PRoot、不下载。样例内容取自真机截图里的编号和 Ubuntu 24.04 基础包里的 /etc/group。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/runtime/guest_groups.dart';
import 'package:path/path.dart' as p;

/// 安卓应用进程的 /proc/self/status（节选；编号和霜霜截图里的一致）。
const androidStatus = '''
Name:	ample.lopicode
Umask:	0077
State:	R (running)
Tgid:	12345
Pid:	12345
Uid:	10556	10556	10556	10556
Gid:	10556	10556	10556	10556
FDSize:	256
Groups:	3003 9997 20556 50556 
VmPeak:	 1234 kB
''';

/// Ubuntu 24.04 基础包里 /etc/group 的开头和结尾几行。
const ubuntuGroup = 'root:x:0:\ndaemon:x:1:\nsudo:x:27:\nusers:x:100:\nnogroup:x:65534:\n';
const ubuntuGshadow = 'root:*::\ndaemon:*::\nsudo:*::\nusers:*::\nnogroup:*::\n';

void main() {
  group('读当前进程的组', () {
    test('安卓的 /proc/self/status：主组在前，附加组在后', () {
      expect(parseProcessGroups(androidStatus), [10556, 3003, 9997, 20556, 50556]);
    });

    test('没有附加组（Groups: 后面是空的）：只有主组', () {
      expect(parseProcessGroups('Gid:\t0\t0\t0\t0\nGroups:\t\n'), [0]);
    });

    test('去重；Windows 换行、很大的编号（厂商分身用的 99909997）都认；4294967295、负数、乱码不要', () {
      expect(parseProcessGroups('Gid:\t10\t10\t10\t10\r\nGroups:\t10 3003 99909997 4294967295 -1 abc 3003\r\n'), [10, 3003, 99909997]);
    });

    test('两行都没有（不是 Linux、内容是空的或乱的）：返回 null，交给兜底', () {
      expect(parseProcessGroups(''), isNull);
      expect(parseProcessGroups('Name:\tfoo\nUid:\t1\t1\t1\t1\n'), isNull);
      expect(parseProcessGroups('\u0000\u0001 垃圾 : : :\n::\n'), isNull);
    });

    test('兜底：id -G 的输出', () {
      expect(parseIdGroups('10556 3003 9997 20556 50556\n'), [10556, 3003, 9997, 20556, 50556]);
      expect(parseIdGroups(''), isNull);
      expect(parseIdGroups('id: not found'), isNull);
    });

    test('宿主机上真读一次不崩（Linux 上能读到自己的主组）', () {
      final groups = readProcessGroups();
      if (Platform.isLinux) expect(groups, isNotEmpty);
    });
  });

  group('补 /etc/group 的内容', () {
    test('缺哪个补哪个：原有内容一字不动，新行加在末尾', () {
      final r = addMissingGroups(ubuntuGroup, [10556, 3003, 9997, 20556, 50556]);
      expect(r.content, '${ubuntuGroup}aid_10556:x:10556:\naid_3003:x:3003:\naid_9997:x:9997:\naid_20556:x:20556:\naid_50556:x:50556:\n');
      expect(r.added.keys, [10556, 3003, 9997, 20556, 50556]);
    });

    test('幂等：补过的再补一次什么都不变', () {
      final once = addMissingGroups(ubuntuGroup, [3003, 9997]).content!;
      final twice = addMissingGroups(once, [3003, 9997]);
      expect(twice.content, isNull);
      expect(twice.added, isEmpty);
    });

    test('编号已经有名字的（哪怕叫别的名字）不重复加；传进来的重复编号只加一次', () {
      final r = addMissingGroups('root:x:0:\ninet:x:3003:\n', [0, 3003, 9997, 9997]);
      expect(r.content, 'root:x:0:\ninet:x:3003:\naid_9997:x:9997:\n');
    });

    test('原文件结尾没有换行：先补一个换行再加', () {
      expect(addMissingGroups('root:x:0:', [3003]).content, 'root:x:0:\naid_3003:x:3003:\n');
    });

    test('空文件', () {
      expect(addMissingGroups('', [3003]).content, 'aid_3003:x:3003:\n');
    });

    test('怪格式：空行、注释、段数不够、编号不是数字的行都原样留着，不崩', () {
      const weird = '\n# 注释\nroot:x:0:\n只有一段\nbad:x:notanumber:\n::\r\nwin:x:7:\r\n\n';
      final r = addMissingGroups(weird, [7, 3003]);
      expect(r.content, '${weird}aid_3003:x:3003:\n');
      expect(r.added.keys, [3003], reason: 'Windows 换行的那一行里的 7 也认得出来');
    });

    test('名字被别的组占了：换个不重名的名字', () {
      final r = addMissingGroups('aid_3003:x:42:\n', [3003]);
      expect(r.content, 'aid_3003:x:42:\naid_3003_:x:3003:\n');
      expect(r.added, {3003: 'aid_3003_'});
    });

    test('不合法的编号不写', () {
      expect(addMissingGroups(ubuntuGroup, [-1, 0xffffffff]).content, isNull);
    });

    test('gshadow：只补没有的名字', () {
      expect(addMissingGshadow(ubuntuGshadow, ['aid_3003', 'root']), '${ubuntuGshadow}aid_3003:!::\n');
      expect(addMissingGshadow('${ubuntuGshadow}aid_3003:!::\n', ['aid_3003']), isNull);
    });
  });

  group('改环境里的文件', () {
    late Directory tmp;
    late String rootfs;
    File group() => File(p.join(rootfs, 'etc', 'group'));
    File gshadow() => File(p.join(rootfs, 'etc', 'gshadow'));

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_groups_');
      rootfs = p.join(tmp.path, 'rootfs');
      Directory(p.join(rootfs, 'etc')).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    List<String> leftovers() => [
      for (final f in Directory(p.join(rootfs, 'etc')).listSync())
        if (p.basename(f.path).contains('lopicode-tmp')) f.path,
    ];

    test('已经装好的旧环境：group 和 gshadow 都补上；再调一次不再写文件', () {
      group().writeAsStringSync(ubuntuGroup);
      gshadow().writeAsStringSync(ubuntuGshadow);
      final first = ensureGuestGroups(rootfs, [10556, 3003, 9997, 20556, 50556]);
      expect(first.added, [10556, 3003, 9997, 20556, 50556]);
      expect(first.skipped, isNull);
      expect(group().readAsStringSync(), startsWith(ubuntuGroup));
      expect(group().readAsStringSync(), endsWith('aid_3003:x:3003:\naid_9997:x:9997:\naid_20556:x:20556:\naid_50556:x:50556:\n'));
      expect(gshadow().readAsStringSync(), '${ubuntuGshadow}aid_10556:!::\naid_3003:!::\naid_9997:!::\naid_20556:!::\naid_50556:!::\n');
      expect(leftovers(), isEmpty, reason: '临时文件已经改名成正式文件');

      final stamp = group().lastModifiedSync();
      final before = group().readAsBytesSync();
      final second = ensureGuestGroups(rootfs, [10556, 3003, 9997, 20556, 50556]);
      expect(second.added, isEmpty);
      expect(second.skipped, isNull);
      expect(group().readAsBytesSync(), before);
      expect(group().lastModifiedSync(), stamp);
      expect(const LineSplitter().convert(group().readAsStringSync()).where((l) => l.contains(':3003:')), hasLength(1));
    });

    test('没有 gshadow：只改 group，不凭空造 gshadow', () {
      group().writeAsStringSync(ubuntuGroup);
      expect(ensureGuestGroups(rootfs, [3003]).added, [3003]);
      expect(gshadow().existsSync(), isFalse);
    });

    test('/etc/group 不存在：新建一个，带上 root 和要补的组', () {
      final r = ensureGuestGroups(rootfs, [3003]);
      expect(r.added, [3003]);
      expect(group().readAsStringSync(), 'root:x:0:\naid_3003:x:3003:\n');
    });

    test('环境还没装（没有 etc 目录）：不动，不崩，不造目录', () {
      final r = ensureGuestGroups(p.join(tmp.path, 'nowhere'), [3003]);
      expect(r.added, isEmpty);
      expect(r.skipped, isNotNull);
      expect(Directory(p.join(tmp.path, 'nowhere')).existsSync(), isFalse);
    });

    test('/etc/group 是个目录或链接：不动，说明原因', () {
      Directory(group().path).createSync();
      expect(ensureGuestGroups(rootfs, [3003]).skipped, contains('不是普通文件'));
      Directory(group().path).deleteSync();
      final elsewhere = File(p.join(tmp.path, 'elsewhere'))..writeAsStringSync(ubuntuGroup);
      Link(group().path).createSync(elsewhere.path);
      expect(ensureGuestGroups(rootfs, [3003]).skipped, contains('不是普通文件'));
      expect(elsewhere.readAsStringSync(), ubuntuGroup, reason: '不顺着链接写到别处去');
    });

    test('文件里有不是 UTF-8 的字节：原样保留', () {
      final bytes = [...utf8.encode('root:x:0:\n'), 0xff, 0xfe, 0x3a, 0x0a];
      group().writeAsBytesSync(bytes);
      expect(ensureGuestGroups(rootfs, [3003]).added, [3003]);
      expect(group().readAsBytesSync(), [...bytes, ...utf8.encode('aid_3003:x:3003:\n')]);
    });

    test('没有组可补：什么都不做', () {
      group().writeAsStringSync(ubuntuGroup);
      expect(ensureGuestGroups(rootfs, const []).added, isEmpty);
      expect(group().readAsStringSync(), ubuntuGroup);
    });

    test('GuestGroupsKeeper：组只读一次；每次都核对文件（重装后还会补）；日志不重复', () {
      group().writeAsStringSync(ubuntuGroup);
      var reads = 0;
      final logs = <String>[];
      final keeper = GuestGroupsKeeper(
        read: () {
          reads++;
          return [3003, 9997];
        },
        log: logs.add,
      );
      expect(keeper.sync(rootfs).added, [3003, 9997]);
      expect(keeper.sync(rootfs).added, isEmpty);
      expect(reads, 1);
      expect(logs, hasLength(1));
      expect(logs.single, contains('3003、9997'));
      // 重装：文件回到出厂的样子
      group().writeAsStringSync(ubuntuGroup);
      expect(keeper.sync(rootfs).added, [3003, 9997]);
      expect(reads, 1);
    });

    test('GuestGroupsKeeper：读不到组（返回 null 或抛异常）不崩，文件不动，只记一行', () {
      group().writeAsStringSync(ubuntuGroup);
      for (final read in <List<int>? Function()>[() => null, () => throw const FileSystemException('读不了')]) {
        final logs = <String>[];
        final keeper = GuestGroupsKeeper(read: read, log: logs.add);
        expect(keeper.sync(rootfs).skipped, isNotNull);
        expect(keeper.sync(rootfs).skipped, isNotNull);
        expect(logs, hasLength(1));
        expect(group().readAsStringSync(), ubuntuGroup);
      }
    });
  });
}
