// 小应用乙组·“用户自己写的 JS 库驱动”：工单小应用四组样例。库走整条产品路径——
//   项目甲里新建（给谁用＝前端）→ 用积木写、公开成带类型的积木、存 → 导出成 .lopilib → 项目乙里打开预览、导入 →
//   项目乙的多页面文档里用它搭登录 → 列表 → 详情 → 提交 → 纯网页 / Vue 3 / React 真编译 0 错 0 警告、对着本地假服务真跑。
// 头两组和第四组用“会话与接口”库（包请求＋本地保存＋状态仓库）；第三组换“金额与格式”（纯计算）＋“通知”（包事件总线）。
// 两个安全开关都是默认的关着。故意写错的几条被拦下。
@Tags(['external'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/dev_tools.dart';
import 'support/front_app_b_kit.dart';
import 'support/front_app_b_tickets.dart';
import 'support/front_app_b_tickets_cases.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

void main() {
  late Directory dirA, dirB;
  late PathGuard a, b;
  FakeApi? api;
  setUp(() async {
    expect(libNativeCodeEntry, isFalse);
    expect(userLibHostEntry, isFalse);
    dirA = await Directory.systemTemp.createTemp('lopi_a5c_a_');
    dirB = await Directory.systemTemp.createTemp('lopi_a5c_b_');
    a = PathGuard(dirA.path);
    b = PathGuard(dirB.path);
  });
  tearDown(() async {
    await api?.stop();
    api = null;
    await pendingWrites();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  /// 项目甲里新建、写、存、导出；项目乙里打开预览、导入。交回预览里说的“它要靠的”和清单。
  Future<({List<String> needs, Map<String, Object?> manifest})> carry(J libJson, String id) async {
    final made = await beLibCreate(a, id: id, name: libJson['name'] as String, author: '霜霜', side: LibSide.frontend);
    expect(made.problem, isNull);
    final saved = await beLibSaveSource(a, made.rel!, parseLangBlocksDocument(libJson));
    expect(saved.problems, isEmpty);
    expect(saved.written, isTrue);
    final out = await beLibExport(a, id);
    expect(out.problem, isNull);
    final rel = 'got-${id.split('/').last}.lopilib';
    await File(a.resolve(out.rel!)).copy(b.resolve(rel));
    final opened = await beLibOpenPack(b, rel);
    expect(opened.problem, isNull);
    final preview = opened.preview!;
    expect(preview.problems, isEmpty);
    expect(preview.lib.side, LibSide.frontend);
    final put = await beLibInstall(b, preview);
    expect(put.problems, isEmpty);
    final stored = await beLibsRead(b);
    final mine = stored.firstWhere((s) => s.lib.id == id);
    return (needs: preview.needs, manifest: jsonDecode(mine.files[kLibManifestFile]!) as Map<String, Object?>);
  }

  /// 这种搭法要的库都走一遍整条路，交回项目乙里装着的库。
  Future<List<LibLibrary>> libsFor(TkKit k) async {
    if (k.rich) {
      final m = await carry(moneyLib(), kMoney);
      expect(m.manifest['requires'] ?? const <Object?>[], isEmpty);
      final n = await carry(noticeLib(), kNotice);
      expect(n.manifest['requires'], unorderedEquals(['lopi/bus', 'lopi/store']));
      expect(n.needs.join('；'), contains('事件总线'));
    } else {
      final s = await carry(sessionLib(), kSess);
      expect(s.manifest['for'], 'frontend');
      expect(s.manifest['requires'], unorderedEquals(['lopi/http', 'lopi/storage', 'lopi/store']));
      expect(s.needs.join('；'), allOf(contains('请求'), contains('本地保存'), contains('状态仓库')));
    }
    final stored = await beLibsRead(b);
    for (final s in stored) {
      expect(s.ok, isTrue, reason: s.lib.problems.join('；'));
    }
    return [for (final s in stored) s.lib];
  }

  test('有四组样例（其中一组换了两个不同形状的库），画布上的检查都没毛病', () async {
    expect(ticketCases().length, greaterThanOrEqualTo(3));
    expect(ticketCases().where((c) => c.kit.rich).length, greaterThanOrEqualTo(1));
    for (final k in const [TkKit(), TkKit(rich: true)]) {
      expect(appIssues(appDoc(ticketPages(k, 'http://127.0.0.1:1'), libs: await libsFor(k))), isEmpty);
    }
  });

  final n = ticketCases().length;
  for (var i = 0; i < n; i++) {
    for (final kind in kFrontKinds.entries) {
      test(
        '工单·第 ${i + 1} 组·${kind.value}：库走整条路 → 真编译、对着假服务真跑',
        () async {
          final c = ticketCases()[i];
          final libs = await libsFor(c.kit);
          final server = api = await FakeApi.start(c.world.handle);
          await appCheck(kind.key, appDoc(ticketPages(c.kit, server.base), libs: libs), c.steps(kind.key));
          c.after(server, c.world);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 6)),
      );
    }
  }

  group('故意写错的被拦下', () {
    LcDocument one(List<LibLibrary> libs, List<J> body, {List<J>? uses}) => appDoc([
      AppPage('p', [btn('b1', '点'), inp('in1'), txt('t1')], const [], frontDoc(uses: uses ?? const TkKit().uses(), hats: [onClick('h1', 'b1', body)])),
    ], libs: libs);
    void blocked(LcDocument doc, [String? says]) {
      expect(lcLogicErrorCount(doc), greaterThan(0));
      if (says != null) expect(lcFrontProgram(lcFrontOf(doc.logic)!).problems.join('；'), contains(says));
      for (final kind in const ['html', 'vue', 'react']) {
        expect(exportFilesOf(doc, kind).values.join('\n'), contains('这一页的逻辑没有导出'), reason: kind);
      }
    }

    J sx(String block, [J args = const {}]) => ex(beLibOp(kSess, block), args);

    test('对照：写对的不拦', () async {
      final libs = await libsFor(const TkKit());
      expect(appIssues(one(libs, [show('t1', sx('err'))])), isEmpty);
    });
    test('用了“会话与接口”却没把它靠的“状态仓库”用上', () async {
      final libs = await libsFor(const TkKit());
      blocked(
        one(libs, [show('t1', sx('err'))], uses: [useLib('http'), useLib('storage'), {'id': kSess}]),
        '要靠库「状态仓库」',
      );
    });
    test('类型放错：“提交”的数据给了一句话（要字典）', () async {
      final libs = await libsFor(const TkKit());
      blocked(
        one(libs, [
          iff(sx('submit', {'路径': tx('/x'), '数据': tx('你好')}), [show('t1', tx('成'))], noElse: true),
        ]),
      );
    });
    test('类型放错：“登录”的名字给了数（要文字）', () async {
      final libs = await libsFor(const TkKit());
      blocked(
        one(libs, [
          iff(sx('login', {'名': nm(1), '密码': tx('b')}), [show('t1', tx('成'))], noElse: true),
        ]),
      );
    });
    test('用了库里没公开的积木', () async {
      final libs = await libsFor(const TkKit());
      blocked(one(libs, [show('t1', sx('url', {'路径': tx('/x')}))]));
    });
    test('库自己写错：说好交回数的函数交回了字——存库时就不让过', () async {
      final bad = frontLib(
        '坏库',
        'shuang/bad',
        functions: [
          tfn('f1', '算', const [], [ret(tx('字'))], returns: tNum),
        ],
        blocks: [
          {'id': 'calc', 'how': 'call', 'fn': 'f1', 'look': {'name': '算', 'shape': 'value', 'template': '算一下'}},
        ],
      );
      final made = await beLibCreate(a, id: 'shuang/bad', name: '坏库', author: '霜霜', side: LibSide.frontend);
      final saved = await beLibSaveSource(a, made.rel!, parseLangBlocksDocument(bad));
      expect(saved.problems, isNotEmpty);
      expect(beLibFiles(parseLangBlocksDocument(bad)).files, isNull);
    });
    test('默认状态下，自己的前端库越界直接碰宿主接口（请求、本地保存）被拒绝', () {
      final files = {
        kLibManifestFile:
            '{"kind": "lopicode-lib", "format": 1, "id": "shuang/rawsess", "name": "直接碰", "version": "1.0.0", "rules": 2, "for": "frontend", "native": {"allowed": false},'
            ' "hosts": ["storage.get"], "modules": [{"file": "modules/m.lc", "name": "直接碰"}], "blocks": ["blocks.json"]}',
        'modules/m.lc': '(模块 直接碰\n  (宿主 storage.get ((键 文字)) -> 文字)\n  (公开 (函数 偷看 ((键 文字)) -> 文字 (返回 (宿 storage.get 键)))))',
        'blocks.json': '{"blocks": []}',
      };
      final lib = libRead(files, builtin: false);
      expect(lib.ok, isFalse);
      expect(lib.problems.join('；'), contains('还不能直接碰宿主接口'));
    });
  });
}
