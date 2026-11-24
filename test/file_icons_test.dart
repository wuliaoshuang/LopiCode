// 文件 / 文件夹 / 语言图标（material-icon-theme）：随包文件和声明一致、映射表指到的图标都在、
// 常见文件名查得到对的图标、文件页和编辑器标签真的显示出来（390×844，浅色深色各一遍）。
//   LOPI_SHOTS=1 flutter test test/file_icons_test.dart   同时把截图写到 docs/screenshots/ic-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/file_icons.dart';
import 'package:lopicode/core/file_icons_files_data.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/core/third_party.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 等 SVG 图标从资源包里读出来（真实的异步读文件）。
Future<void> loadIcons(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String icon(String name) => '$kFileIconDir/$name.svg';

/// 假项目：多种语言的文件和常见文件夹。
const List<String> kSampleFiles = [
  '.github/workflows/ci.yml',
  '.gitignore',
  'Dockerfile',
  'LICENSE',
  'README.md',
  'package.json',
  'tsconfig.json',
  'docs/guide.md',
  'public/logo.png',
  'server/main.go',
  'server/app.py',
  'server/Api.java',
  'server/index.php',
  'server/lib.rs',
  'src/App.vue',
  'src/Home.tsx',
  'src/main.ts',
  'src/style.css',
  'src/index.html',
  'src/util.js',
  'test/app.dart',
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('随包文件和声明', () {
    final dir = Directory(kFileIconDir);
    final present = {for (final f in dir.listSync().whereType<File>()) p.basename(f.path)};

    test('SVG 正好是清单里的那些，校验值与 SHA256SUMS 一致，一共不超过 300KB', () {
      expect(present, {for (final name in fileIconFiles) '$name.svg'}, reason: 'assets/file_icons 里的文件要和 kFileIconFileList 一一对应');
      final sums = {
        for (final line in File('third_party/material-icon-theme/SHA256SUMS').readAsLinesSync().where((l) => l.trim().isNotEmpty)) line.split(RegExp(r'\s+')).last: line.split(RegExp(r'\s+')).first,
      };
      expect(sums.keys.toSet(), present);
      var total = 0;
      for (final entry in sums.entries) {
        final bytes = File(p.join(kFileIconDir, entry.key)).readAsBytesSync();
        expect(sha256.convert(bytes).toString(), entry.value, reason: '${entry.key} 的内容被改过');
        expect(String.fromCharCodes(bytes.take(4)), '<svg', reason: entry.key);
        total += bytes.length;
      }
      expect(total, lessThanOrEqualTo(300 * 1024), reason: '图标总大小 $total 字节');
    });

    test('映射表里提到的每个图标文件都在', () {
      final missing = fileIconsReferenced.where((name) => !fileIconFiles.contains(name)).toList();
      expect(missing, isEmpty);
      expect(fileIconsReferenced.length, greaterThan(300));
    });

    test('版本、许可证、pubspec 的资源声明齐全', () {
      expect(fileIconPack.version, kFileIconPackVersion);
      expect(fileIconPack.packageUrl, contains('material-icon-theme-$kFileIconPackVersion.tgz'));
      final readme = File('third_party/material-icon-theme/README.md').readAsStringSync();
      expect(readme, contains(fileIconPack.version));
      expect(readme, contains(fileIconPack.packageIntegrity));
      expect(readme, contains(fileIconPack.sourceUrl));
      expect(readme, contains('${fileIconFiles.length} 个'));
      final license = File(fileIconPack.licenseAsset).readAsStringSync();
      expect(license, contains('The MIT License (MIT)'));
      expect(license, contains(fileIconPack.copyright));
      expect(license, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
      expect(File('third_party/material-icon-theme/LICENSE').readAsStringSync(), license);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/file_icons/'));
      expect(pubspec, contains('- assets/licenses/'));
      expect(bundledIconPacks, contains(fileIconPack));
      expect(licenseTitle(fileIconPack.licenseAsset), isNot(fileIconPack.licenseAsset));
      expect(File('README.md').readAsStringSync(), contains('material-icon-theme'));
    });
  });

  group('fileIconFor', () {
    test('常见文件：扩展名', () {
      const cases = {
        'index.html': 'html',
        'style.css': 'css',
        'a.scss': 'sass',
        'a.sass': 'sass',
        'a.less': 'less',
        'main.js': 'javascript',
        'main.mjs': 'javascript',
        'main.ts': 'typescript',
        'App.jsx': 'react',
        'App.tsx': 'react_ts',
        'App.vue': 'vue',
        'App.svelte': 'svelte',
        'data.json': 'json',
        'ci.yml': 'yaml',
        'ci.yaml': 'yaml',
        'a.toml': 'toml',
        'a.xml': 'xml',
        'notes.md': 'markdown',
        'app.py': 'python',
        'main.go': 'go',
        'Main.java': 'java',
        'Main.kt': 'kotlin',
        'index.php': 'php',
        'app.rb': 'ruby',
        'lib.rs': 'rust',
        'a.c': 'c',
        'a.cpp': 'cpp',
        'a.h': 'h',
        'A.cs': 'csharp',
        'a.swift': 'swift',
        'main.dart': 'dart',
        'a.lua': 'lua',
        'run.sh': 'console',
        'run.bash': 'console',
        'run.ps1': 'powershell',
        'a.sql': 'database',
        'a.gradle': 'gradle',
        'a.lock': 'lock',
        'a.log': 'log',
        'a.png': 'image',
        'a.jpg': 'image',
        'a.svg': 'svg',
        'a.ttf': 'font',
        'a.mp3': 'audio',
        'a.mp4': 'video',
        'a.pdf': 'pdf',
        'a.zip': 'zip',
        'a.tar.gz': 'zip',
        'a.txt': 'document',
        'a.proto': 'proto',
        'a.graphql': 'graphql',
        'a.r': 'r',
        'a.scala': 'scala',
        'a.ex': 'elixir',
        'a.hs': 'haskell',
        'a.zig': 'zig',
        'a.csv': 'table',
        'a.apk': 'android',
        'a.ipynb': 'jupyter',
      };
      for (final entry in cases.entries) {
        expect(fileIconFor(entry.key), icon(entry.value), reason: entry.key);
      }
    });

    test('整名优先于扩展名', () {
      const cases = {
        'Dockerfile': 'docker',
        'docker-compose.yml': 'docker',
        'Makefile': 'makefile',
        'package.json': 'nodejs',
        'package-lock.json': 'nodejs',
        'pom.xml': 'maven',
        '.gitignore': 'git',
        '.gitattributes': 'git',
        'README.md': 'readme',
        'LICENSE': 'license',
        'CHANGELOG.md': 'changelog',
        'tsconfig.json': 'tsconfig',
        '.editorconfig': 'editorconfig',
        '.eslintrc.json': 'eslint',
        'eslint.config.js': 'eslint',
        '.prettierrc': 'prettier',
        'vite.config.ts': 'vite',
        'yarn.lock': 'yarn',
        'pnpm-lock.yaml': 'pnpm',
        'go.mod': 'go-mod',
        'requirements.txt': 'python-misc',
        'Gemfile': 'gemfile',
        'nginx.conf': 'nginx',
        '.npmrc': 'npm',
        'CMakeLists.txt': 'cmake',
        'AndroidManifest.xml': 'android',
        'gradlew': 'gradle',
        'robots.txt': 'robots',
      };
      for (final entry in cases.entries) {
        expect(fileIconFor(entry.key), icon(entry.value), reason: entry.key);
      }
    });

    test('多段扩展名从最长的往短找；大小写不敏感；路径只看最后一段', () {
      expect(fileIconFor('types.d.ts'), icon('typescript-def'));
      expect(fileIconFor('a.b.d.ts'), icon('typescript-def'));
      expect(fileIconFor('app.test.ts'), icon('test-ts'));
      expect(fileIconFor('app.spec.js'), icon('test-js'));
      expect(fileIconFor('jquery.min.js'), icon('javascript'), reason: 'min.js 没有专门的图标，退到 js');
      expect(fileIconFor('INDEX.HTML'), icon('html'));
      expect(fileIconFor('readme.MD'), icon('readme'));
      expect(fileIconFor('DOCKERFILE'), icon('docker'));
      expect(fileIconFor('src/pages/Home.tsx'), icon('react_ts'));
      expect(fileIconFor(r'C:\work\a.py'), icon('python'));
      expect(fileIconFor('.env'), icon('tune'));
      expect(fileIconFor('.env.local'), icon('tune'));
      expect(fileIconFor('build.gradle'), icon('gradle'));
      expect(fileIconFor('pubspec.yaml'), icon('yaml'));
    });

    test('认不出给默认图标，永远返回随包存在的文件', () {
      for (final name in ['', '.', '..', 'noext', 'a.unknownext', 'a.', '.a.', 'weird name.xyz', '/', 'a/b/']) {
        expect(fileIconFor(name), icon('file'), reason: '"$name"');
      }
      for (final name in ['a.ts', 'x', 'src', '.git', '']) {
        for (final isDir in [true, false]) {
          for (final open in [true, false]) {
            for (final light in [true, false]) {
              final asset = fileIconFor(name, isDir: isDir, open: open, light: light);
              expect(File(asset).existsSync(), isTrue, reason: asset);
            }
          }
        }
      }
    });

    test('文件夹：默认、特殊名字、五种写法、开合', () {
      expect(fileIconFor('whatever', isDir: true), icon('folder'));
      expect(fileIconFor('whatever', isDir: true, open: true), icon('folder-open'));
      const cases = {
        'src': 'folder-src',
        'lib': 'folder-lib',
        'test': 'folder-test',
        'tests': 'folder-test',
        'node_modules': 'folder-node',
        'assets': 'folder-resource',
        'images': 'folder-images',
        'docs': 'folder-docs',
        'dist': 'folder-dist',
        'build': 'folder-dist',
        '.git': 'folder-git',
        '.github': 'folder-github',
        'config': 'folder-config',
        'public': 'folder-public',
        'components': 'folder-components',
        'api': 'folder-api',
        '_utils': 'folder-utils',
        '__tests__': 'folder-test',
        'SRC': 'folder-src',
        'android': 'folder-android',
        'ios': 'folder-ios',
      };
      for (final entry in cases.entries) {
        expect(fileIconFor(entry.key, isDir: true), icon(entry.value), reason: entry.key);
        expect(fileIconFor('a/${entry.key}/', isDir: true, open: true), icon('${entry.value}-open'), reason: '${entry.key}（展开）');
      }
      // 文件夹名不当文件名查，文件名也不当文件夹查
      expect(fileIconFor('src'), icon('file'));
      expect(fileIconFor('package.json', isDir: true), icon('folder'));
      // 官方清单里 proto 没有 __proto__ 这种写法（数据里按原样存的那一条）
      expect(fileIconFor('proto', isDir: true), icon('folder-proto'));
      expect(fileIconFor('.proto', isDir: true), icon('folder-proto'));
      expect(fileIconFor('__proto__', isDir: true), icon('folder'));
    });

    test('浅色主题：官方有浅色版的换浅色版，没有的不变', () {
      expect(fileIconFor('a.toml', light: true), icon('toml_light'));
      expect(fileIconFor('a.toml'), icon('toml'));
      expect(fileIconFor('vercel.json', light: true), icon('vercel_light'));
      expect(fileIconFor('next.config.js', light: true), icon('next_light'));
      expect(fileIconFor('a.ts', light: true), icon('typescript'));
      expect(fileIconFor('src', isDir: true, light: true), icon('folder-src'));
    });
  });

  test('languageIconFor：语言 id、常见叫法、图标名、扩展名', () {
    const cases = {
      'node': 'nodejs',
      'nodejs': 'nodejs',
      'Node.js': 'nodejs',
      'python': 'python',
      'go': 'go',
      'golang': 'go',
      'java': 'java',
      'php': 'php',
      'csharp': 'csharp',
      'C#': 'csharp',
      'rust': 'rust',
      'ruby': 'ruby',
      'kotlin': 'kotlin',
      'html': 'html',
      'css': 'css',
      'vue': 'vue',
      'react': 'react',
      'javascript': 'javascript',
      'typescript': 'typescript',
      'javascriptreact': 'react',
      'typescriptreact': 'react_ts',
      'dart': 'dart',
      'flutter': 'dart',
      'swift': 'swift',
      'cpp': 'cpp',
      'c': 'c',
      'shellscript': 'console',
      'bash': 'console',
      'sql': 'database',
      'docker': 'docker',
      'dockerfile': 'docker',
      'svelte': 'svelte',
      'lua': 'lua',
      'kt': 'kotlin',
      ' Python ': 'python',
    };
    for (final entry in cases.entries) {
      expect(languageIconFor(entry.key), icon(entry.value), reason: entry.key);
      expect(File(languageIconFor(entry.key, light: true)).existsSync(), isTrue, reason: entry.key);
    }
    expect(languageIconFor('没有这种语言'), icon('file'));
    expect(languageIconFor(''), icon('file'));
    expect(languageIconFor('folder-src'), icon('file'), reason: '文件夹图标不当语言图标用');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('文件页与编辑器标签带图标 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        project = await env.services.projects.create('图标样例', ProjectTemplate.empty);
        for (final rel in kSampleFiles) {
          File(p.join(project.dir, rel))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('// $rel\n');
        }
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session, initial: ShellDest.files),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 20, ms: 5);
      await loadIcons(tester);
      final light = mode == ThemeMode.light;
      String key(String name, {bool isDir = false}) => 'file-icon-${fileIconFor(name, isDir: isDir, open: isDir, light: light)}';
      // 文件夹用“展开”的图标（列表里它的内容总是摊开在下面）；文件按名字 / 扩展名
      expect(find.byKey(ValueKey(key('.github', isDir: true))), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('folder-github-open')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('folder-open')}')), findsOneWidget, reason: 'workflows 是普通文件夹');
      expect(find.byKey(ValueKey('file-icon-${icon('docker')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('git')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('license')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('nodejs')}')), findsOneWidget);
      // 图标真的画出来了（不是回退的 Material 图标），大小 20，和文字在同一行上居中
      final docker = find.byKey(ValueKey('file-icon-${icon('docker')}'));
      expect(tester.getSize(docker), const Size(20, 20));
      expect(find.descendant(of: find.byType(FileIcon), matching: find.byIcon(Icons.insert_drive_file_outlined)), findsNothing);
      expect((tester.getCenter(docker).dy - tester.getCenter(find.text('Dockerfile')).dy).abs(), lessThan(2));
      await shot(tester, 'ic-files-top-$suffix');

      final list = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(find.text('util.js'), 200, scrollable: list);
      await loadIcons(tester);
      expect(find.byKey(ValueKey('file-icon-${icon('vue')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('react_ts')}')), findsOneWidget);
      expect(find.byKey(ValueKey('file-icon-${icon('folder-src-open')}')), findsOneWidget);
      await shot(tester, 'ic-files-bottom-$suffix');

      // 打开两个文件：标签上各有一个 16 的图标
      await tester.ensureVisible(find.text('App.vue'));
      await tester.tap(find.text('App.vue'));
      await settle(tester, rounds: 20, ms: 5);
      await loadIcons(tester);
      final tabIcon = find.byKey(ValueKey('file-icon-${icon('vue')}'));
      expect(tabIcon, findsOneWidget);
      expect(tester.getSize(tabIcon), const Size(16, 16));
      await shot(tester, 'ic-editor-tab-$suffix');
    });

    testWidgets('图标一排：语言图标与常见文件 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      const langs = ['node', 'python', 'go', 'java', 'php', 'csharp', 'rust', 'ruby', 'kotlin', 'html', 'vue', 'react', 'dart', 'swift', 'cpp', 'typescript'];
      const files = [
        'a.toml',
        'vercel.json',
        'next.config.js',
        'deno.json',
        'bun.lockb',
        'a.json',
        'a.md',
        'a.sh',
        'a.sql',
        'a.lock',
        'a.txt',
        'a.zip',
        'a.png',
        'LICENSE',
        '.gitignore',
        'unknown.xyz',
      ];
      const dirs = ['x', 'src', 'lib', 'test', 'node_modules', 'docs', 'dist', '.git', '.github', 'config', 'public', 'components', 'api', 'images', 'assets', 'android'];
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('语言（FileIcon.language，28）'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 14, runSpacing: 12, children: [for (final id in langs) _Labeled(FileIcon.language(id, size: 28), id)]),
                  const SizedBox(height: 16),
                  const Text('文件（20）'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 14, runSpacing: 12, children: [for (final name in files) _Labeled(FileIcon(name), name)]),
                  const SizedBox(height: 16),
                  const Text('文件夹（合 / 开，20）'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      for (final name in dirs)
                        _Labeled(Row(mainAxisSize: MainAxisSize.min, children: [FileIcon(name, isDir: true), const SizedBox(width: 4), FileIcon(name, isDir: true, open: true)]), name),
                    ],
                  ),
                ],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await loadIcons(tester);
      expect(find.byType(SvgPicture), findsNWidgets(langs.length + files.length + dirs.length * 2));
      expect(
        find.descendant(of: find.byType(FileIcon), matching: find.byType(Icon)),
        findsNothing,
        reason: '没有一个回退成 Material 图标',
      );
      expect(tester.getSize(find.byType(FileIcon).first), const Size(28, 28));
      await shot(tester, 'ic-gallery-$suffix');
    });
  }

  testWidgets('图标文件读不出来：退回 Material 图标，不报错', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(
      appFor(
        env,
        DefaultAssetBundle(
          bundle: _BrokenBundle(),
          child: const Scaffold(body: Row(children: [FileIcon('a.ts'), FileIcon('src', isDir: true), FileIcon('src', isDir: true, open: true), FileIcon.language('go')])),
        ),
      ),
    );
    await loadIcons(tester);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
    expect(find.byIcon(Icons.code), findsOneWidget);
  });

  testWidgets('第三方声明页列出文件图标包，许可证全文能打开', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(env.dispose);
    await tester.pumpWidget(appFor(env, const ThirdPartyScreen(), font: kTestFont));
    await settle(tester);
    final list = find.descendant(of: find.byKey(const Key('third-party-list')), matching: find.byType(Scrollable)).first;
    final tile = find.byKey(Key('license-${fileIconPack.licenseAsset}'));
    await tester.scrollUntilVisible(tile, 300, scrollable: list);
    await tester.ensureVisible(tile);
    await settle(tester, rounds: 2);
    expect(find.text('${fileIconPack.name} ${fileIconPack.version}'), findsOneWidget);
    await shot(tester, 'ic-third-party-light');
    await tester.tap(tile);
    await settle(tester, rounds: 6);
    await loadIcons(tester);
    expect(find.byKey(const Key('license-text')), findsOneWidget);
    expect(find.textContaining('Material Extensions'), findsOneWidget);
  });
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.icon, this.label);
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: Column(
      children: [
        icon,
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// 什么都读不出来的资源包。
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('读不出来：$key'));
}
