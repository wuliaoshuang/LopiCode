// 小应用乙组·“用户自己的组件库＋JS 库一起用”：会议室预订三组样例。两样库都走整条产品路径——
//   组件库“预订组件”（登录块、房间项、信息卡、预订块）：项目甲里做 → 收成库 → 导出文件 → 项目乙打开预览、装上；
//   JS 库“会话与接口”：项目甲里新建、用积木写、公开、导出 → 项目乙打开预览、导入。
// 项目乙的多页面文档里：组件放进页面，组件发的事件接到页面逻辑的帽子，逻辑里用 JS 库和自带的“定时”库 →
// 纯网页 / Vue 3 / React 真编译 0 错 0 警告、对着本地假服务真跑。两个安全开关都是默认的关着。故意写错的几条被拦下。
@Tags(['external'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_sheet.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/comp_lib_flow.dart';
import 'support/dev_tools.dart';
import 'support/front_app_b_kit.dart';
import 'support/front_app_b_rooms.dart';
import 'support/front_app_b_rooms_cases.dart';
import 'support/front_app_b_tickets.dart';
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
    dirA = await Directory.systemTemp.createTemp('lopi_a5c_ra_');
    dirB = await Directory.systemTemp.createTemp('lopi_a5c_rb_');
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

  /// JS 库“会话与接口”：甲里新建、写、存、导出；乙里打开预览、导入。
  Future<List<LibLibrary>> jsLibs() async {
    final libJson = sessionLib();
    final made = await beLibCreate(a, id: kSess, name: libJson['name'] as String, author: '霜霜', side: LibSide.frontend);
    expect(made.problem, isNull);
    final saved = await beLibSaveSource(a, made.rel!, parseLangBlocksDocument(libJson));
    expect(saved.problems, isEmpty);
    final out = await beLibExport(a, kSess);
    expect(out.problem, isNull);
    await File(a.resolve(out.rel!)).copy(b.resolve('got.lopilib'));
    final opened = await beLibOpenPack(b, 'got.lopilib');
    expect(opened.problem, isNull);
    expect(opened.preview!.problems, isEmpty);
    expect((await beLibInstall(b, opened.preview!)).problems, isEmpty);
    final stored = await beLibsRead(b);
    expect(stored.single.ok, isTrue, reason: stored.single.lib.problems.join('；'));
    return [stored.single.lib];
  }

  /// 组件库“预订组件”：甲里的组件 → 收成库 → 存 → 导出文件 → 拷进乙 → 打开看（预览）→ 落盘、装进乙的文档。交回装好的那一节。
  Future<List<Object?>> compLibs() async {
    final defs = roomsUiDefs();
    final lib = compLibFromDoc(projectA(defs), [for (final d in defs) d['id']! as String], id: kRoomsUi, name: '预订组件', version: '1.0.0', author: '霜霜');
    expect(await compLibStore(a, lib), isNull);
    final out = await compLibExport(a, (await compLibsRead(a)).single);
    expect(out.rel, isNotNull, reason: out.problem);
    await Directory(b.resolve('exports')).create(recursive: true);
    await File(a.resolve(out.rel!)).copy(b.resolve(out.rel!));
    expect(await compLibPackFiles(b), contains(out.rel));
    final opened = await compLibOpenPack(b, out.rel!, installed: await compLibsRead(b));
    expect(opened.lib.ok, isTrue, reason: opened.lib.problems.join('；'));
    final view = compLibImportView(opened.lib);
    expect(view.canImport, isTrue);
    expect(view.items, hasLength(4));
    expect(await compLibStore(b, opened.lib, from: 'file'), isNull);
    final docB = projectA(const []);
    expect(compLibInstall(docB, opened.lib), isEmpty);
    expect(docB.components.every((c) => compLibOf(c)?.id == kRoomsUi), isTrue);
    return (jsonDecode(jsonEncode(docB.toJson())) as Map)['components'] as List<Object?>;
  }

  Future<LcDocument> app(String base) async => appDoc(roomPages(base), libs: await jsLibs(), extra: {'components': await compLibs()});

  test('有三组样例，画布上的检查都没毛病', () async {
    expect(roomCases().length, greaterThanOrEqualTo(3));
    expect(appIssues(await app('http://127.0.0.1:1')), isEmpty);
  });

  final n = roomCases().length;
  for (var i = 0; i < n; i++) {
    for (final kind in kFrontKinds.entries) {
      test(
        '会议室预订·第 ${i + 1} 组·${kind.value}：两样库走整条路 → 真编译、对着假服务真跑',
        () async {
          final c = roomCases()[i];
          final server = api = await FakeApi.start(c.world.handle);
          await appCheck(kind.key, await app(server.base), c.steps(kind.key));
          c.after(server, c.world);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 6)),
      );
    }
  }

  group('故意写错的被拦下', () {
    /// 把首页（会议室列表）或登录页的帽子换一顶，别的不动。
    Future<LcDocument> swapped(String pageId, String hatId, J newHat) async {
      final pages = roomPages('http://127.0.0.1:1');
      return appDoc(
        [
          for (final p in pages)
            if (p.id != pageId)
              p
            else
              AppPage(p.id, p.children, p.variables, {
                ...p.front,
                'hats': [
                  for (final h in p.front['hats'] as List)
                    if ((h as Map)['id'] == hatId) newHat else h as J,
                ],
              }),
        ],
        libs: await jsLibs(),
        extra: {'components': await compLibs()},
      );
    }

    J emitHat(String node, String event, List<J> body) => hat('h1', 'onEmit', body, args: {'node': node, 'event': event});
    J emit(String name) => ex(pg('emitData'), {'name': tx(name)});

    test('接了组件没有的事件（房间项没有“删掉”）', () async {
      final doc = await swapped('rooms', 'h1', emitHat('rm', 'remove', [show('rm_err', tx('删'))]));
      expect(appIssues(doc), isNotEmpty);
    });
    test('拿了事件没带的数据（“要看”只带 id，没有 price）', () async {
      final doc = await swapped('rooms', 'h1', emitHat('rm', 'open', [show('rm_err', toText(emit('price')))]));
      expect(appIssues(doc).join('；'), contains('没带叫「price」的数据')); // 钉住：原来不拦，读到的是空的
    });
    test('“事件带来的”用在组件事件的帽子外面', () async {
      final doc = await swapped('rooms', 'h2', onClick('h2', 'rm_retry', [show('rm_err', toText(emit('id')))]));
      expect(appIssues(doc), isNotEmpty);
    });
    test('类型放错：组件事件带来的名字和密码拼成一句话当“数据”交给 JS 库的“提交”（要字典）', () async {
      final doc = await swapped(
        'login',
        'h1',
        emitHat('lgf', 'submit', [
          iff(
            ex(beLibOp(kSess, 'submit'), {
              '路径': tx('/x'),
              '数据': cat([toText(emit('user')), toText(emit('pass'))]),
            }),
            [show('lg_msg', tx('成'))],
            noElse: true,
          ),
        ]),
      );
      expect(appIssues(doc), isNotEmpty);
      doc.openPageAt(doc.pages.indexWhere((p) => p.id == 'login'));
      expect(lcLogicErrorCount(doc), greaterThan(0));
      for (final kind in const ['html', 'vue', 'react']) {
        expect(exportFilesOf(doc, kind).values.join('\n'), contains('这一页的逻辑没有导出'), reason: kind);
      }
    });
    test('用了“定时”的积木却没把“定时”库用上', () async {
      final doc = await swapped(
        'rooms',
        'h2',
        onClick('h2', 'rm_retry', [
          let('id', nm(0)),
          blk(fl('timer', 'after'), {'ms': nm(10), 'into': 'id'}, [show('rm_err', tx('到了'))]),
        ]),
      );
      expect(appIssues(doc), isNotEmpty);
    });
  });
}
