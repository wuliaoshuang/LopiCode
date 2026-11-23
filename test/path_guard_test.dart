import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late PathGuard guard;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_guard_');
    Directory(p.join(tmp.path, 'proj', 'src')).createSync(recursive: true);
    File(p.join(tmp.path, 'secret.txt')).writeAsStringSync('outside');
    guard = PathGuard(p.join(tmp.path, 'proj'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('项目内的相对路径可以解析', () {
    expect(guard.resolve('index.html'), p.join(guard.root, 'index.html'));
    expect(guard.resolve('src/a/../b.js'), p.join(guard.root, 'src', 'b.js'));
    expect(guard.resolve(''), guard.root);
    expect(guard.resolve('./src/'), p.join(guard.root, 'src'));
    expect(guard.relative(p.join(guard.root, 'src', 'b.js')), 'src/b.js');
  });

  test('越界路径一律拒绝', () {
    for (final bad in ['../secret.txt', 'src/../../secret.txt', '..', '/etc/passwd', '~/x', r'C:\Windows\x', 'file:///etc/passwd', 'http://example.com/x', r'..\secret.txt', 'a\u0000b']) {
      expect(() => guard.resolve(bad), throwsA(isA<PathGuardException>()), reason: bad);
    }
  });

  test('通过符号链接逃出项目目录也会被拒绝', () {
    Link(p.join(guard.root, 'link')).createSync(tmp.path);
    expect(() => guard.resolve('link/secret.txt'), throwsA(isA<PathGuardException>()));
    // 链接指向项目内部是允许的
    Link(p.join(guard.root, 'inner')).createSync(p.join(guard.root, 'src'));
    expect(guard.resolve('inner/x.js'), p.join(guard.root, 'inner', 'x.js'));
  });

  test('内部目录 .lopicode 默认不可访问', () {
    expect(() => guard.resolve('.lopicode/chat.json'), throwsA(isA<PathGuardException>()));
    expect(() => guard.resolve('.lopicode'), throwsA(isA<PathGuardException>()));
    expect(() => guard.resolve('src/../.lopicode/project.json'), throwsA(isA<PathGuardException>()));
    expect(guard.resolve('.lopicode/chat.json', allowReserved: true), p.join(guard.root, '.lopicode', 'chat.json'));
  });

  group('ProjectStore', () {
    test('创建、列出、改名、删除', () async {
      final store = ProjectStore(p.join(tmp.path, 'projects'));
      expect(await store.list(), isEmpty);
      final web = await store.create('我的网页', ProjectTemplate.web);
      final lc = await store.create('Low Code Demo', ProjectTemplate.lowcode);
      await store.create('我的网页', ProjectTemplate.empty); // 同名不冲突
      expect(File(p.join(web.dir, 'index.html')).existsSync(), isTrue);
      expect(File(p.join(lc.dir, kLowcodePageFile)).existsSync(), isTrue);
      expect(File(p.join(lc.dir, 'index.html')).existsSync(), isTrue);

      final files = await listProjectFiles(web.guard);
      expect(files, containsAll(['index.html', 'style.css', 'script.js']));
      expect(files.any((f) => f.contains('.lopicode')), isFalse);

      await store.rename(web, '新名字');
      final listed = await store.list();
      expect(listed.length, 3);
      expect(listed.map((e) => e.name), contains('新名字'));
      expect(listed.firstWhere((e) => e.id == lc.id).template, ProjectTemplate.lowcode);

      await store.delete(web);
      expect(Directory(web.dir).existsSync(), isFalse);
      expect((await store.list()).length, 2);
    });

    test('项目名校验', () {
      expect(() => ProjectStore.validateName('  '), throwsA(isA<ProjectException>()));
      expect(() => ProjectStore.validateName('x' * 41), throwsA(isA<ProjectException>()));
      expect(ProjectStore.validateName('  ok '), 'ok');
    });
  });
}
