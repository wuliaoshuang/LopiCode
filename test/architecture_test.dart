// 架构守门：用测试把“谁可以依赖谁”钉住，免得越改越乱。规矩的白话版在 AGENTS.md。
//
// 1. 逻辑文件不许依赖界面：不是界面文件的，不能 import 界面库（material_ui、flutter/widgets…）、lib/ui、lib/theme、别的界面文件。
// 2. 分层：core 只依赖 core；agent 只依赖 core / agent；preview 只依赖 core；theme 只依赖 theme。
// 3. 文件别太长：新文件不超过 [kMaxLines] 行；已经超了的记在清单里，只许变短不许变长。
// 4. 密钥只走 SecretStore；日志不直接 print。
//
// 例外都写在下面的清单里，每条带原因。清单里的例外如果已经不成立（代码改好了），测试也会失败，提醒把它删掉。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _uiSuffixes = ['_screen.dart', '_tab.dart', '_view.dart', '_sheet.dart', '_dialog.dart', '_widgets.dart'];

/// 文件名不像界面、但其实是界面控件的文件。
const _uiFilesByException = {
  'lib/app.dart', // 应用外壳
  'lib/main.dart', // 入口
  'lib/terminal/terminal_input.dart', // 终端输入控件（接管 xterm 的输入法）
};

bool isUiFile(String path) => path.startsWith('lib/ui/') || path.startsWith('lib/theme/') || _uiSuffixes.any(path.endsWith) || _uiFilesByException.contains(path);

/// 逻辑文件不许 import 的包（界面库）。flutter/foundation、flutter/services 可以。
final _uiPackages = RegExp(r'^package:(material_ui/|flutter/(material|widgets|cupertino|rendering|gestures|painting|animation)\.dart|flutter_svg/|webview_flutter|xterm/|re_editor/|image_picker/)');

/// 规则 1 的已知例外：`文件 -> import` ⇒ 原因。
const _uiImportExceptions = {
  'lib/app_services.dart -> package:material_ui/material_ui.dart': 'AppScope（InheritedNotifier）和 ThemeMode 放在这里；迁到 Riverpod 或拆出 app_scope.dart 时一起解决',
  'lib/terminal/terminal_session.dart -> package:xterm/xterm.dart': '终端会话持有 xterm 的 Terminal 缓冲区（数据模型，不是控件）',
};

/// 规则 2 的已知例外。
const _layerExceptions = {'lib/core/templates.dart -> lowcode': '新建“低代码页面”项目时要生成初始页面文件', 'lib/agent/agent_tools.dart -> lowcode': 'Agent 的“改低代码页面”工具要读写页面模型并导出'};

/// 各层允许依赖的层（lib 下的第一级目录名；没列出的目录不限制）。
const _allowedLayers = {
  'core': {'core'},
  'theme': {'theme'},
  'preview': {'core', 'preview'},
  'agent': {'core', 'agent'},
  'terminal': {'core', 'terminal'},
};

const int kMaxLines = 600;

/// 已经超过 [kMaxLines] 的文件和它们的上限（＝收紧规则时的行数，留一点余量）。只许变短。
const _oversized = {
  'lib/lowcode/builder_screen.dart': 1180,
  'lib/project_session.dart': 1445,
  'lib/ui/chat_screen.dart': 910,
  'lib/ui/chat_panels.dart': 920,
  'lib/ui/usage_ui.dart': 890,
  'lib/ui/settings_agent.dart': 725,
  'lib/ui/settings_ai.dart': 650,
};

List<String> libFiles() => [
  for (final e in Directory('lib').listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e.path.replaceAll('\\', '/'),
]..sort();

/// 文件开头的 import（只看指令区，不看后面字符串模板里长得像 import 的行）。
List<String> importsOf(String path) {
  final out = <String>[];
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('//') || line.startsWith('library')) continue;
    final m = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''').firstMatch(line);
    if (m != null) {
      out.add(m[1]!);
      continue;
    }
    // 多行 import 的后半截（show / hide / as / 条件导入）和 part 指令：还在指令区里
    if (RegExp(r'^(part|show|hide|as|if)\b').hasMatch(line)) continue;
    break; // 指令区结束
  }
  return out;
}

void main() {
  final files = libFiles();

  test('逻辑文件不依赖界面（界面库、lib/ui、lib/theme、别的界面文件）', () {
    final found = <String>{};
    for (final f in files.where((f) => !isUiFile(f))) {
      for (final imp in importsOf(f)) {
        final isUiPkg = _uiPackages.hasMatch(imp);
        final isUiLocal = imp.startsWith('package:lopicode/') && isUiFile('lib/${imp.substring('package:lopicode/'.length)}');
        if (isUiPkg || isUiLocal) found.add('$f -> $imp');
      }
    }
    final unexpected = found.difference(_uiImportExceptions.keys.toSet());
    expect(unexpected, isEmpty, reason: '这些逻辑文件依赖了界面。把界面代码挪到 lib/ui（或 *_screen.dart），逻辑里只留数据和通知：\n${unexpected.join('\n')}');
    final stale = _uiImportExceptions.keys.toSet().difference(found);
    expect(stale, isEmpty, reason: '这些例外已经不成立了，从 _uiImportExceptions 里删掉：\n${stale.join('\n')}');
  });

  test('相对路径 import 不许用（统一 package:lopicode/…，守门测试才看得见）', () {
    final bad = <String>[];
    for (final f in files) {
      for (final imp in importsOf(f)) {
        if (!imp.startsWith('package:') && !imp.startsWith('dart:')) bad.add('$f -> $imp');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('分层：core / theme / preview / agent / terminal 只依赖允许的层', () {
    final found = <String>{};
    for (final f in files) {
      final layer = f.split('/')[1];
      final allowed = _allowedLayers[layer];
      if (allowed == null) continue;
      for (final imp in importsOf(f)) {
        final m = RegExp(r'^package:lopicode/([a-z_]+)(/|\.dart)').firstMatch(imp);
        if (m == null) continue;
        final target = m[2] == '/' ? m[1]! : '(根目录的 ${m[1]}.dart)';
        if (!allowed.contains(target)) found.add('$f -> $target');
      }
    }
    final unexpected = found.difference(_layerExceptions.keys.toSet());
    expect(unexpected, isEmpty, reason: '依赖方向反了（下层依赖了上层）：\n${unexpected.join('\n')}');
    final stale = _layerExceptions.keys.toSet().difference(found);
    expect(stale, isEmpty, reason: '这些例外已经不成立了，从 _layerExceptions 里删掉：\n${stale.join('\n')}');
  });

  test('文件行数：新文件不超过 $kMaxLines 行；超长清单里的只许变短', () {
    final tooLong = <String>[];
    final seen = <String>{};
    for (final f in files) {
      final lines = File(f).readAsLinesSync().length;
      final cap = _oversized[f];
      if (cap != null) {
        seen.add(f);
        if (lines > cap) tooLong.add('$f：$lines 行，超过了它的上限 $cap（这个文件早就太长了，新功能请拆到新文件里）');
        if (lines <= kMaxLines) tooLong.add('$f 已经降到 $lines 行，从 _oversized 里删掉它');
      } else if (lines > kMaxLines) {
        tooLong.add('$f：$lines 行，超过 $kMaxLines。拆一拆；确实拆不了再加进 _oversized 并写明原因');
      }
    }
    expect(tooLong, isEmpty, reason: tooLong.join('\n'));
    expect(_oversized.keys.toSet().difference(seen), isEmpty, reason: '_oversized 里有已经不存在的文件');
  });

  test('密钥只走 SecretStore：除了它的实现，别处不直接用 flutter_secure_storage', () {
    final bad = [
      for (final f in files)
        if (f != 'lib/core/secure_secret_store.dart' && importsOf(f).any((i) => i.startsWith('package:flutter_secure_storage/'))) f,
    ];
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('不直接 print / debugPrint（要记就进 CrashLog 或运行环境日志）', () {
    final bad = <String>[];
    for (final f in files) {
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (RegExp(r'(^|[^\w.])(print|debugPrint)\(').hasMatch(code) && !code.contains("'") && !code.contains('"')) bad.add('$f:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('存盘的 JSON 文件统一走 safe_file（原子写 + 坏文件备份），不直接 writeAsString(jsonEncode…)', () {
    final bad = <String>[];
    for (final f in files) {
      if (f == 'lib/core/safe_file.dart') continue;
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'writeAsString\(\s*jsonEncode').hasMatch(lines[i])) bad.add('$f:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: '改用 writeJsonAtomic：\n${bad.join('\n')}');
  });

  test('工程规矩文件都在', () {
    for (final f in ['AGENTS.md', 'tool/check.sh', 'analysis_options.yaml', 'docs/dsh-go-architecture-study.md']) {
      expect(File(f).existsSync(), isTrue, reason: '$f 不在');
    }
    final agents = File('AGENTS.md').readAsStringSync();
    for (final must in ['依赖方向', 'tool/check.sh', 'cast<List<int>>', 'writeJsonAtomic', 'CrashLog']) {
      expect(agents, contains(must), reason: 'AGENTS.md 里要讲到 $must');
    }
  });
}
