// 逻辑接进网页导出：有逻辑才有 logic.js 和 <script>；逻辑删光后清掉我们自己生成的 logic.js。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

class _NoRunner implements CommandRunner {
  @override
  String get description => '测试里不跑命令';

  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = const Duration(seconds: 1)}) => throw StateError('不该跑命令');
}

LcDocument _withLogic() {
  final doc = LcDocument.starter('计数');
  doc.logic.addVariable('count', type: 'number');
  final button = doc.root.children.last.children.last;
  final h = doc.logic.addHandler('click', target: button.id)!;
  h.insertBlock(const [], LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}));
  return doc;
}

void main() {
  test('没有逻辑：网页里没有 script，js 是空的', () {
    final out = exportHtml(LcDocument.starter('页'));
    expect(out.js, isEmpty);
    expect(out.html, isNot(contains('<script')));
  });

  test('有逻辑：网页引用 logic.js，脚本以我们的标记开头', () {
    final out = exportHtml(_withLogic());
    expect(out.html, contains('<script src="logic.js" defer></script>\n</head>'));
    expect(out.js, startsWith(kLowcodeLogicMarker));
    expect(out.js, exportLogicJs(_withLogic()));
  });

  group('存盘', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lc_logic_export');
      guard = PathGuard(tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));
    File f(String name) => File(p.join(tmp.path, name));

    test('有逻辑写出 logic.js；逻辑删光后把它删掉', () async {
      await saveLowcodePage(guard, _withLogic());
      expect(f('logic.js').readAsStringSync(), contains('count'));
      expect(f('index.html').readAsStringSync(), contains('logic.js'));

      await saveLowcodePage(guard, LcDocument.starter('计数'));
      expect(f('logic.js').existsSync(), isFalse);
      expect(f('index.html').readAsStringSync(), isNot(contains('logic.js')));
    });

    test('用户自己写的 logic.js（没有我们的标记）不删', () async {
      f('logic.js').writeAsStringSync('console.log("我自己写的");\n');
      await saveLowcodePage(guard, LcDocument.starter('页'));
      expect(f('logic.js').readAsStringSync(), 'console.log("我自己写的");\n');
    });

    test('存下来的页面文件读回来逻辑还在', () async {
      await saveLowcodePage(guard, _withLogic());
      final back = LcDocument.parse(f(kLowcodePageFile).readAsStringSync());
      expect(back.logic.variables.single.name, 'count');
      expect(back.logic.handlers.single.body.single.op, 'changeVar');
    });

    test('Agent 更新页面时没带 logic：沿用现有的；明确传空才清掉', () async {
      await saveLowcodePage(guard, _withLogic());
      final box = AgentToolbox(guard: guard, runner: _NoRunner(), requestApproval: (_) async => true, autoApprove: () => true);
      final page = LcDocument.starter('改版').toJson();
      expect(page.containsKey('logic'), isFalse);
      expect((await box.execute('lowcode_update_page', {'page': page})).ok, isTrue);
      var back = LcDocument.parse(f(kLowcodePageFile).readAsStringSync());
      expect(back.title, '改版');
      expect(back.logic.variables.single.name, 'count');
      expect(f('logic.js').existsSync(), isTrue);

      expect(
        (await box.execute('lowcode_update_page', {
          'page': {...page, 'logic': <String, dynamic>{}},
        })).ok,
        isTrue,
      );
      back = LcDocument.parse(f(kLowcodePageFile).readAsStringSync());
      expect(back.logic.isEmpty, isTrue);
      expect(f('logic.js').existsSync(), isFalse);
    });
  });
}
