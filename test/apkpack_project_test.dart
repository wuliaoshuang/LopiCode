// 项目识别、收集文件、输入校验的测试（纯 Dart）。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_validators.dart';
import 'package:lopicode/apkpack/web_project.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apkpack_proj_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('项目识别', () {
    Future<WebProjectInfo> detect(Map<String, Object> files) {
      writeFiles(tmp.path, files);
      return detectWebProject(tmp.path);
    }

    test('根目录有 index.html → 纯网页', () async {
      final i = await detect({'index.html': 'x', 'style.css': ''});
      expect((i.applicable, i.kind, i.webRoot, i.entry), (true, 'static', tmp.path, 'index.html'));
      expect(i.reason, contains('index.html'));
    });

    test('真的“前端网页”模板 → 纯网页', () async {
      final i = await detect(templateFiles(ProjectTemplate.web, '演示')!.cast());
      expect((i.applicable, i.kind), (true, 'static'));
    });

    test('真的“低代码页面”模板 → 用根目录导出的网页', () async {
      final i = await detect(templateFiles(ProjectTemplate.lowcode, '演示')!.cast());
      expect((i.applicable, i.kind, i.webRoot, i.entry), (true, 'lowcode', tmp.path, 'index.html'));
    });

    test('低代码项目还没导出网页 → 不适用，告诉她去保存一次', () async {
      final i = await detect({'page.lc.json': '{}'});
      expect(i.applicable, isFalse);
      expect(i.reason, contains('保存一次'));
    });

    test('真的“前端 + 后端”模板 → 只打包 web 目录', () async {
      final files = projectTemplateFiles(ProjectTemplate.fullstack, '演示');
      final i = await detect(files.cast());
      expect((i.applicable, i.kind, i.webRoot), (true, 'web', p.join(tmp.path, 'web')));
      expect(i.reason, contains('后端不会放进安装包'));
    });

    test('要构建的前端工程：有 dist 用 dist，没有就让她先构建', () async {
      var i = await detect({'package.json': '{"scripts":{"build":"vite build"}}', 'index.html': '<script type="module" src="/src/main.js">', 'src/main.js': ''});
      expect(i.applicable, isFalse);
      expect(i.reason, contains('npm run build'));
      i = await detect({'dist/index.html': 'built'});
      expect((i.applicable, i.kind, i.webRoot), (true, 'dist', p.join(tmp.path, 'dist')));
    });

    test('根目录没有入口但有产物目录', () async {
      final i = await detect({'build/web/x': '', 'www/index.html': 'x'});
      expect((i.applicable, i.kind, i.webRoot), (true, 'dist', p.join(tmp.path, 'www')));
    });

    test('package.json 是坏的也不崩，按普通网页处理', () async {
      final i = await detect({'package.json': '{not json', 'index.html': 'x'});
      expect((i.applicable, i.kind), (true, 'static'));
    });

    test('Flutter、原生安卓、纯后端、空项目、目录不存在 → 不适用，说明原因并指向远程打包', () async {
      Future<void> no(Map<String, Object> files, String part, {bool remote = true}) async {
        final d = Directory(p.join(tmp.path, 'case${files.length}_${part.hashCode}'))..createSync();
        writeFiles(d.path, files);
        final i = await detectWebProject(d.path);
        expect(i.applicable, isFalse, reason: part);
        expect(i.webRoot, isNull);
        expect(i.reason, contains(part));
        if (remote) expect(i.reason, contains('远程打包'));
      }

      await no({'pubspec.yaml': 'name: x', 'build/web/index.html': 'x', 'web/index.html': 'x'}, 'Flutter');
      await no({'settings.gradle.kts': '', 'app/src/main/AndroidManifest.xml': ''}, '原生安卓');
      await no({'build.gradle': '', 'index.html': ''}, '原生安卓');
      await no({'backend.lc.json': '{}', 'server.js': ''}, '后端');
      await no({'main.py': 'print(1)'}, '后端');
      await no({'README.md': '# hi'}, '找不到网页入口');
      final gone = await detectWebProject(p.join(tmp.path, 'nope'));
      expect(gone.applicable, isFalse);
    });

    test('后端代码模板（各语言）都不适用', () async {
      for (final t in [ProjectTemplate.backendBlocks, ProjectTemplate.backendCode, ProjectTemplate.empty]) {
        final d = Directory(p.join(tmp.path, t.id))..createSync();
        final files = t.builtIn ? templateFiles(t, 'x')! : projectTemplateFiles(t, 'x');
        writeFiles(d.path, files.cast());
        expect((await detectWebProject(d.path)).applicable, isFalse, reason: t.id);
      }
    });
  });

  group('收集文件', () {
    test('排除 node_modules、隐藏文件、顶层 build 和 apk；路径用 / 且排好序', () {
      sampleWithAssets(tmp.path);
      writeFiles(tmp.path, {'sub/build/keep.js': 'k', 'out.apk': 'x', 'sub/.hidden': 'x', 'sub/node_modules/a.js': 'x'});
      final files = collectWebFiles(tmp.path, entry: 'index.html');
      expect([for (final f in files) f.rel], ['css/a/b/c/deep.css', 'fonts/x.woff2', 'img/big.png', 'img/图标 一.svg', 'index.html', 'js/app/main.js', 'sub/build/keep.js']);
      expect(files.every((f) => File(f.path).lengthSync() == f.size), isTrue);
    });

    test('低代码项目：不收页面源文件和 export 目录', () {
      sampleLowcode(tmp.path);
      expect([for (final f in collectWebFiles(tmp.path, entry: 'index.html')) f.rel], ['index.html', 'logic.js', 'style.css']);
    });

    test('符号链接：指到外面的不收，指到里面文件的收，指到目录的不收', () {
      sampleStatic(tmp.path);
      final outside = Directory.systemTemp.createTempSync('apkpack_out_');
      addTearDown(() => outside.deleteSync(recursive: true));
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('secret');
      Link(p.join(tmp.path, 'leak.txt')).createSync(p.join(outside.path, 'secret.txt'));
      Link(p.join(tmp.path, 'leakdir')).createSync(outside.path);
      Link(p.join(tmp.path, 'alias.css')).createSync(p.join(tmp.path, 'style.css'));
      Link(p.join(tmp.path, 'broken')).createSync(p.join(tmp.path, 'nope'));
      Link(p.join(tmp.path, 'loop')).createSync(tmp.path);
      expect([for (final f in collectWebFiles(tmp.path, entry: 'index.html')) f.rel], ['alias.css', 'index.html', 'script.js', 'style.css']);
    });

    test('超限和缺入口都报明确的错', () {
      sampleStatic(tmp.path);
      Matcher err(String part) => throwsA(isA<ApkPackException>().having((e) => e.message, 'message', contains(part)).having((e) => e.field, 'field', 'project'));
      expect(() => collectWebFiles(tmp.path, entry: 'main.html'), err('找不到入口文件 main.html'));
      expect(() => collectWebFiles(tmp.path, entry: 'index.html', maxFileCount: 2), err('超过 2 个'));
      expect(() => collectWebFiles(tmp.path, entry: 'index.html', maxFileBytes: 10), err('太大了'));
      expect(() => collectWebFiles(tmp.path, entry: 'index.html', maxTotalBytes: 100), err('加起来超过'));
      expect(() => collectWebFiles(p.join(tmp.path, 'nope'), entry: 'index.html'), err('找不到要打包的网页目录'));
    });

    test('默认上限：100MB、5000 个、单个 50MB', () => expect((kMaxWebTotalBytes, kMaxWebFileCount, kMaxWebFileBytes), (100 * 1024 * 1024, 5000, 50 * 1024 * 1024)));
  });

  group('校验', () {
    test('包名', () {
      for (final ok in ['com.example.app', 'a.b', 'Com.Example_1.x9', 'com.lopicode.shell', 'a${'.abcdefghij' * 20}']) {
        expect(validatePackageName(ok), isNull, reason: ok);
      }
      expect(validatePackageName(''), contains('不能为空'));
      expect(validatePackageName('myapp'), contains('至少要有两段'));
      expect(validatePackageName('com..app'), contains('连着的句号'));
      expect(validatePackageName('com.app.'), contains('句号'));
      expect(validatePackageName('com.1app'), contains('字母开头'));
      expect(validatePackageName('com._app'), contains('字母开头'));
      expect(validatePackageName('com.my-app'), contains('只能用英文字母'));
      expect(validatePackageName('com.应用.x'), contains('只能用英文字母'));
      expect(validatePackageName('com.my app'), contains('空格'));
      expect(validatePackageName('com.class.app'), contains('保留字'));
      expect(validatePackageName('com.example.int'), contains('保留字'));
      expect(validatePackageName('a${'.abcdefghij' * 21}'), contains('太长'));
      expect(validatePackageName('a.${'b' * 221}'), isNull, reason: '正好 223');
      expect(validatePackageName('a.${'b' * 222}'), contains('太长'));
    });

    test('应用名、版本名', () {
      expect(validateAppName('我的应用'), isNull);
      expect(validateAppName('App 😀 & <1> "x"'), isNull);
      expect(validateAppName('字' * 50), isNull);
      expect(validateAppName('😀' * 50), isNull, reason: '按字数算，不按码元');
      expect(validateAppName('字' * 51), contains('太长'));
      expect(validateAppName(''), contains('不能为空'));
      expect(validateAppName('   '), contains('不能为空'));
      expect(validateAppName(' a'), contains('空格'));
      expect(validateAppName('a\nb'), contains('换行'));
      expect(validateAppName('a${String.fromCharCode(0xD83D)}'), contains('不完整'));
      expect(validateVersionName('1.0.0-beta+3'), isNull);
      expect(validateVersionName(''), contains('不能为空'));
      expect(validateVersionName('1' * 51), contains('太长'));
    });

    test('版本号边界：1 到 2100000000', () {
      expect(validateVersionCode(1), isNull);
      expect(validateVersionCode(2100000000), isNull);
      expect(validateVersionCode(0), isNotNull);
      expect(validateVersionCode(-5), isNotNull);
      expect(validateVersionCode(2100000001), contains('2100000000'));
    });

    test('图标：确实是 PNG、尺寸对', () {
      expect(validateIconPng(48, solidPng(48)), isNull);
      expect(validateIconPng(192, solidPng(192)), isNull);
      expect(validateIconPng(48, solidPng(72)), contains('72×72'));
      expect(validateIconPng(96, solidPng(96, height: 90)), contains('96×90'));
      expect(validateIconPng(50, solidPng(50)), contains('只能是'));
      expect(validateIconPng(48, Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0)])), contains('不是 PNG'));
      expect(validateIconPng(48, Uint8List(0)), contains('不是 PNG'));
      final cut = solidPng(48);
      expect(validateIconPng(48, Uint8List.sublistView(cut, 0, cut.length - 5)), contains('不是 PNG'));
    });

    test('权限表：七项，默认只勾联网，id 不重复', () {
      expect(kApkPermissionOptions.map((o) => o.id), [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.VIBRATE',
        'android.permission.WAKE_LOCK',
      ]);
      expect(kApkPermissionOptions.where((o) => o.defaultOn).map((o) => o.id), ['android.permission.INTERNET']);
      expect(kApkPermissionOptions.every((o) => o.label.isNotEmpty && o.hint.isNotEmpty && validatePermission(o.id) == null), isTrue);
      expect(validatePermission('CAMERA'), isNotNull);
      expect(validatePermission('android.permission.X Y'), isNotNull);
    });
  });
}
