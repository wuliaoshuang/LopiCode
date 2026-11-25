// 本地打包测试的公用工具：替身模板、造 PNG、不签名的签名器、样例项目、官方工具的调用。
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_signer.dart';
import 'package:lopicode/apkpack/zip/zip_model.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:path/path.dart' as p;

/// 替身壳模板（tool/make_fake_apk_shell.sh 生成，约定和真模板一样）。
Uint8List fakeShell() => File('test/fixtures/apkpack/fake_shell.apk').readAsBytesSync();

/// 真的壳模板：从壳那一块（分支 la-shell，提交 f3584a5）的 assets/apk_shell/shell.apk 原样拷来的一份，
/// sha256 4976223b2b60909d758c636241beaee7fbde9c63fecd0f272226b57033b6d658。只给测试用；壳重编后要重新拷。
/// 和替身的差别：图标目录不带 -v4、没有 assets/、应用名是 LopiApp、清单里多 meta-data 和主题引用。
Uint8List realShell() => File('test/fixtures/apkpack/real_shell.apk').readAsBytesSync();

/// 替身模板里的二进制清单。
Uint8List fakeManifest() => readZip(fakeShell()).firstWhere((e) => e.name == 'AndroidManifest.xml').content();

/// 不签名的替身：v1 不产出文件，v2 原样返回。产物交给官方 apksigner 去签。
class NoSigner implements ApkSigner {
  const NoSigner();
  @override
  Map<String, Uint8List> v1Files(Map<String, Uint8List> entries) => const {};
  @override
  Uint8List v2(Uint8List alignedZip) => alignedZip;
  @override
  String get certSha256Hex => '';
}

/// 造一张 [size]×[size] 的纯色 PNG（8 位 RGB，不压缩的 deflate 也行，这里用正常压缩）。
Uint8List solidPng(int size, {int r = 200, int g = 40, int b = 40, int? height}) {
  final h = height ?? size;
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    for (var x = 0; x < size; x++) {
      raw.add([r, g, (b + x + y) & 0xFF]);
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final out = ByteData(8 + data.length + 4)
      ..setUint32(0, data.length)
      ..setUint32(8 + data.length, crc32Of(body));
    return out.buffer.asUint8List()..setRange(4, 8 + data.length, body);
  }

  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', ihdr.buffer.asUint8List()),
    ...chunk('IDAT', ZLibEncoder().convert(raw.takeBytes())),
    ...chunk('IEND', const []),
  ]);
}

/// 五个密度的图标。
Map<int, Uint8List> fiveIcons({int r = 200}) => {
  for (final s in const [48, 72, 96, 144, 192]) s: solidPng(s, r: r),
};

void writeFiles(String root, Map<String, Object> files) {
  for (final e in files.entries) {
    final f = File(p.join(root, e.key))..parent.createSync(recursive: true);
    final v = e.value;
    v is String ? f.writeAsStringSync(v) : f.writeAsBytesSync(v as List<int>);
  }
}

/// 样例一：纯静态页。
void sampleStatic(String root) => writeFiles(root, {
  'index.html': '<!doctype html><title>你好</title><link rel="stylesheet" href="style.css"><h1>你好</h1><script src="script.js"></script>',
  'style.css': 'h1{color:#36c}',
  'script.js': 'console.log("hi")',
});

/// 样例二：带子目录和大图（约 1.2MB 的 PNG，内容是伪随机的，压不动）。
void sampleWithAssets(String root) {
  var seed = 12345;
  final noise = Uint8List(1200 * 1024);
  for (var i = 0; i < noise.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    noise[i] = seed >> 16;
  }
  writeFiles(root, {
    'index.html': '<!doctype html><img src="img/big.png"><script src="js/app/main.js"></script>',
    'img/big.png': [0x89, 0x50, 0x4E, 0x47, ...noise],
    'img/图标 一.svg': '<svg xmlns="http://www.w3.org/2000/svg"/>',
    'js/app/main.js': 'document.title = "ok";\n' * 200,
    'css/a/b/c/deep.css': 'body{margin:0}',
    'fonts/x.woff2': List<int>.generate(3000, (i) => (i * 7) & 0xFF),
    'node_modules/pkg/index.js': 'no',
    '.git/config': 'no',
    '.env': 'SECRET=no',
    'build/old.apk': 'no',
  });
}

/// 样例三：模拟低代码项目（搭建器保存后根目录有页面源文件 + 导出的网页）。
void sampleLowcode(String root) => writeFiles(root, {
  'page.lc.json': '{"version":2}',
  'index.html': '<!doctype html><link rel="stylesheet" href="style.css"><div id="app"></div><script src="logic.js" defer></script>',
  'style.css': '#app{display:flex}',
  'logic.js': '// 由 LopiCode 低代码搭建器生成\n',
  'export/vue/App.vue': '<template/>',
  '.lopicode/project.json': '{}',
});

ApkPackRequest requestFor(
  String webRoot,
  String out, {
  String packageName = 'com.example.demo',
  String appName = '演示',
  String versionName = '1.0.0',
  int versionCode = 1,
  Set<String> permissions = const {'android.permission.INTERNET'},
  Map<int, Uint8List> icons = const {},
  String entry = 'index.html',
}) => ApkPackRequest(
  webRoot: webRoot,
  entry: entry,
  packageName: packageName,
  appName: appName,
  versionName: versionName,
  versionCode: versionCode,
  permissions: permissions,
  outputPath: out,
  iconPngs: icons,
);

/// 官方工具（aapt2 / zipalign / apksigner / keytool）。找不到时 [missing] 说明原因，测试据此 skip。
class AndroidTools {
  AndroidTools._(this.buildTools, this.missing);
  final String? buildTools;
  final String? missing;

  static AndroidTools find() {
    final env = Platform.environment;
    final home = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'] ?? p.join(env['HOME'] ?? '', 'workspace/tools/android-sdk');
    final dir = Directory(p.join(home, 'build-tools'));
    if (!dir.existsSync()) return AndroidTools._(null, '没有找到安卓 SDK 的 build-tools（ANDROID_HOME=$home），官方工具核对跳过');
    final versions = dir.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
    for (final v in versions.reversed) {
      if (['aapt2', 'zipalign', 'apksigner'].every((t) => File(p.join(v, t)).existsSync())) return AndroidTools._(v, null);
    }
    return AndroidTools._(null, '$home/build-tools 里没有 aapt2 / zipalign / apksigner，官方工具核对跳过');
  }

  ProcessResult run(String tool, List<String> args) => Process.runSync(p.join(buildTools!, tool), args, environment: {'JAVA_TOOL_OPTIONS': ''});

  String badging(String apk) {
    final r = run('aapt2', ['dump', 'badging', apk]);
    if (r.exitCode != 0) throw StateError('aapt2 dump badging 失败：${r.stderr}');
    return r.stdout as String;
  }

  String xmltree(String apk) {
    final r = run('aapt2', ['dump', 'xmltree', '--file', 'AndroidManifest.xml', apk]);
    if (r.exitCode != 0) throw StateError('aapt2 dump xmltree 失败：${r.stderr}');
    return r.stdout as String;
  }

  ProcessResult zipalignCheck(String apk) => run('zipalign', ['-c', '-v', '4', apk]);

  /// 用 keytool 造一把临时测试钥匙（放在临时目录里，不提交）。没有 keytool 返回 null。
  static String? makeTestKey(String dir) {
    final ks = p.join(dir, 'test.keystore');
    try {
      final r = Process.runSync(
        'keytool',
        ['-genkeypair', '-keystore', ks, '-storepass', 'testpass', '-keypass', 'testpass', '-alias', 'k', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '30', '-dname', 'CN=LopiCode Test'],
        environment: {'JAVA_TOOL_OPTIONS': ''},
      );
      return r.exitCode == 0 ? ks : null;
    } on ProcessException {
      return null;
    }
  }

  /// 签名（v1 + v2）并验证；返回 (是否通过, 输出)。
  /// 验证跑两遍：`--min-sdk-version 24`（要求的那条；这个版本起系统只看 v2，所以 apksigner 会报 v1 没用上），
  /// 再 `--min-sdk-version 21` 一遍，让它把 v1（JAR 签名）也真的验一下。
  (bool, String) signAndVerify(String apk, String keystore, String signedOut) {
    final s = run('apksigner', [
      'sign',
      '--ks',
      keystore,
      '--ks-pass',
      'pass:testpass',
      '--key-pass',
      'pass:testpass',
      '--min-sdk-version',
      '21',
      '--v1-signing-enabled',
      'true',
      '--v2-signing-enabled',
      'true',
      '--out',
      signedOut,
      apk,
    ]);
    if (s.exitCode != 0) return (false, 'apksigner sign 失败：${s.stdout}${s.stderr}');
    final v24 = run('apksigner', ['verify', '--verbose', '--min-sdk-version', '24', signedOut]);
    final v21 = run('apksigner', ['verify', '--verbose', '--min-sdk-version', '21', signedOut]);
    return (v24.exitCode == 0 && v21.exitCode == 0, '[min-sdk 24]\n${v24.stdout}${v24.stderr}[min-sdk 21]\n${v21.stdout}${v21.stderr}');
  }
}
