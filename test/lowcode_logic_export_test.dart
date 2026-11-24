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

    test('积木逻辑有错误：页面、网页、样式照常保存，logic.js 留着上一次的；修好（或只剩警告）以后照常导出', () async {
      await saveLowcodePage(guard, _withLogic());
      final before = f('logic.js').readAsStringSync();

      final bad = _withLogic()..title = '改了标题';
      bad.logic.handlers.single.body.add(LcBlock(op: 'setVar', args: {'name': 'ghost', 'value': exNum(1)}));
      expect(validateLogic(bad).where((i) => i.isError), hasLength(1));
      await saveLowcodePage(guard, bad);
      expect(f('logic.js').readAsStringSync(), before, reason: '有错误不导出新的 logic.js');
      expect(f('index.html').readAsStringSync(), contains('改了标题'));
      expect(LcDocument.parse(f(kLowcodePageFile).readAsStringSync()).logic.handlers.single.body.last.args['name'], 'ghost', reason: '模型照常保存');

      // 只有警告（多一串空的事件）：照常导出。
      final warn = _withLogic();
      warn.logic.handlers.single.body.add(LcBlock(op: 'log', args: {'value': exBin('/', exNum(1), exNum(0))}));
      expect(validateLogic(warn).where((i) => i.isError), isEmpty);
      expect(validateLogic(warn), isNotEmpty);
      await saveLowcodePage(guard, warn);
      expect(f('logic.js').readAsStringSync(), isNot(before));
      expect(f('logic.js').readAsStringSync(), contains('console.log'));
    });

    test('Agent 更新页面：带错误的积木照常保存，校验问题作为工具结果返回，logic.js 不更新；没问题时结果里不多话', () async {
      await saveLowcodePage(guard, _withLogic());
      final before = f('logic.js').readAsStringSync();
      final box = AgentToolbox(guard: guard, runner: _NoRunner(), requestApproval: (_) async => true, autoApprove: () => true);

      final bad = _withLogic();
      bad.logic.handlers.single.body.add(LcBlock(op: 'setVar', args: {'name': 'ghost', 'value': exNum(1)}));
      final r = await box.execute('lowcode_update_page', {'page': bad.toJson()});
      expect(r.ok, isTrue);
      expect(r.text, contains('页面已更新'));
      expect(r.text, contains('有 1 个错误，logic.js 没有更新'));
      expect(r.text, contains('[G03]'));
      expect(r.text, contains('ghost'));
      expect(f('logic.js').readAsStringSync(), before);

      final good = await box.execute('lowcode_update_page', {'page': _withLogic().toJson()});
      expect(good.text, '页面已更新，并重新导出了 index.html 和 style.css。');
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
