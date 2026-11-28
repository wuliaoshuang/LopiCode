// 用户自己写的前端库（积木第 5 版·前端 2）：默认状态下（两个安全开关都关着），只用语言核心和已有库的积木就能写。
// 三种形状——纯计算的工具库、包一层“状态仓库”的库、包一层“请求”的库——各走一遍整条产品路径：
//   新建（给谁用＝前端）→ 写、公开成积木、存 → 导出成 .lopilib → 另一个项目里打开预览、导入 → 页面逻辑里用 →
//   纯网页 / Vue 3 / React 三种导出真编译、在 Node＋jsdom 里真跑。
// 另：它靠的自带库写进清单的 requires；用它的页面没把靠的库用上、它自己直接碰宿主接口，都被拦下。
@Tags(['external'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
import 'support/dev_tools.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';
import 'support/page_front_samples2.dart';
import 'support/user_libs.dart';

J _frontLib(String name, String id, {required List<J> functions, required List<J> blocks, List<J> uses = const []}) {
  final doc = libDoc(name, id, functions: functions, blocks: blocks, uses: uses);
  return {
    ...doc,
    'library': {...doc['library'] as Map, 'for': 'frontend'},
  };
}

// —— 形状一：纯计算的工具库 ——
const String kPrice = 'shuang/price';
J _priceLib() => _frontLib(
  '价格工具',
  kPrice,
  functions: [
    tfn('f1', '含税', [tpar('价', tNum), tpar('税', tNum)], [ret(op2('*', pm('价'), op2('+', nm(1), pm('税'))))], returns: tNum),
    tfn(
      'f2',
      '标价',
      [tpar('价', tNum)],
      [
        ret(cat([tx('¥'), toText(pm('价'))])),
      ],
      returns: tText,
    ),
  ],
  blocks: [
    def(
      'tax',
      'call',
      fn: 'f1',
      look: look('含税价', '{价} 加上税 {税}', shape: 'value'),
    ),
    def(
      'label',
      'call',
      fn: 'f2',
      look: look('标价', '{价} 的标价', shape: 'value'),
    ),
  ],
);

// —— 形状二：包一层“状态仓库” ——
const String kBook = 'shuang/book';
J _bookLib() => _frontLib(
  '账本',
  kBook,
  uses: [use('lopi/store')],
  functions: [
    tfn(
      'f1',
      '记一笔',
      [tpar('名', tText)],
      [
        lb('lopi/store', 'set', {'store': tx('账本'), 'key': pm('名'), 'value': tx('有')}),
      ],
    ),
    tfn('f2', '记了几笔', const [], [
      ret(
        ex('len', {
          'x': lx('lopi/store', 'all', {'store': tx('账本')}),
        }),
      ),
    ], returns: tNum),
  ],
  blocks: [
    def(
      'add',
      'call',
      fn: 'f1',
      look: look('记一笔', '往账本记一笔 {名}', shape: 'statement'),
    ),
    def(
      'count',
      'call',
      fn: 'f2',
      look: look('记了几笔', '账本记了几笔', shape: 'value'),
    ),
  ],
);

// —— 形状三：包一层“请求” ——
const String kApi = 'shuang/api';
J _apiLib() => _frontLib(
  '取数',
  kApi,
  uses: [use('lopi/http')],
  functions: [
    tfn(
      'f1',
      '取到的话',
      [tpar('网址', tText)],
      [
        ret(
          cat([
            tx('取到 '),
            toText(lx('lopi/http', 'getJson', {'url': pm('网址')})),
          ]),
        ),
      ],
      returns: tText,
    ),
  ],
  blocks: [
    def(
      'say',
      'call',
      fn: 'f1',
      look: look('取到的话', '从 {网址} 取到的话', shape: 'value'),
    ),
  ],
);

void main() {
  late Directory dirA, dirB;
  late PathGuard a, b;
  setUp(() async {
    // 就在默认状态下测：两个开关都关着。
    expect(libNativeCodeEntry, isFalse);
    expect(userLibHostEntry, isFalse);
    dirA = await Directory.systemTemp.createTemp('lopi_a4_a_');
    dirB = await Directory.systemTemp.createTemp('lopi_a4_b_');
    a = PathGuard(dirA.path);
    b = PathGuard(dirB.path);
  });
  tearDown(() async {
    await pendingWrites();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  /// 项目 A 里新建、写、存、导出；项目 B 里打开预览、导入；交回 B 里读到的库和预览里“它要靠的”。
  Future<({List<LibLibrary> libs, List<String> needs, Map<String, Object?> manifest})> carry(J libJson, String id) async {
    final made = await beLibCreate(a, id: id, name: libJson['name'] as String, author: '霜霜', side: LibSide.frontend);
    expect(made.problem, isNull);
    final saved = await beLibSaveSource(a, made.rel!, parseLangBlocksDocument(libJson));
    expect(saved.problems, isEmpty);
    expect(saved.written, isTrue);
    final out = await beLibExport(a, id);
    expect(out.problem, isNull);
    final pack = File(a.resolve(out.rel!));
    const rel = 'got.lopilib';
    await pack.copy(b.resolve(rel));
    final opened = await beLibOpenPack(b, rel);
    expect(opened.problem, isNull);
    final preview = opened.preview!;
    expect(preview.problems, isEmpty);
    expect(preview.lib.side, LibSide.frontend);
    final put = await beLibInstall(b, preview);
    expect(put.problems, isEmpty);
    final stored = await beLibsRead(b);
    expect(stored.single.ok, isTrue, reason: stored.single.lib.problems.join('；'));
    return (libs: [stored.single.lib], needs: preview.needs, manifest: jsonDecode(stored.single.files[kLibManifestFile]!) as Map<String, Object?>);
  }

  group('形状一·纯计算的工具库', () {
    for (final kind in kFrontKinds.entries) {
      test(
        '${kind.value}：新建→公开→导出→另一个项目导入→用→真编译真跑',
        () async {
          final got = await carry(_priceLib(), kPrice);
          expect(got.manifest['requires'] ?? const <Object?>[], isEmpty);
          expect(got.manifest['for'], 'frontend');
          final doc = withLibs(
            frontPage(
              [btn('b1', '算'), txt('t1')],
              const [],
              frontDoc(
                uses: [use(kPrice)],
                hats: [
                  onClick('h1', 'b1', [
                    show(
                      't1',
                      lx(kPrice, 'label', {
                        '价': lx(kPrice, 'tax', {'价': nm(100), '税': nm(0.5)}),
                      }),
                    ),
                  ]),
                ],
              ),
            ),
            got.libs,
          );
          await frontCheckAll(kind.key, doc, [
            [click('b1'), textIs('t1', '¥150')],
          ]);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });

  group('形状二·包一层“状态仓库”的库', () {
    LcDocument page(List<LibLibrary> libs, {bool withStore = true}) => withLibs(
      frontPage(
        [inp('in1'), btn('b1', '记'), btn('b2', '几笔'), txt('t1')],
        const [],
        frontDoc(
          uses: [if (withStore) use('lopi/store'), use(kBook)],
          hats: [
            onClick('h1', 'b1', [
              lb(kBook, 'add', {'名': toText(prGet('in1', 'value'))}),
            ]),
            onClick('h2', 'b2', [show('t1', toText(lx(kBook, 'count')))]),
          ],
        ),
      ),
      libs,
    );

    for (final kind in kFrontKinds.entries) {
      test(
        '${kind.value}：新建→公开→导出→另一个项目导入→用→真编译真跑',
        () async {
          final got = await carry(_bookLib(), kBook);
          // 它靠的自带库写进了清单；导入预览里说得出是哪个库。
          expect(got.manifest['requires'], ['lopi/store']);
          expect(got.needs.join('；'), contains('要靠应用自带的“状态仓库”库'));
          await frontCheckAll(kind.key, page(got.libs), [
            [
              click('b2'),
              textIs('t1', '0'),
              {'op': 'type', 'sel': '.n-in1', 'text': '甲'},
              click('b1'),
              {'op': 'type', 'sel': '.n-in1', 'text': '乙'},
              click('b1'),
              click('b1'),
              click('b2'),
              textIs('t1', '2'),
            ],
          ]);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }

    test('用它的页面没把“状态仓库”也用上：检查拦下，说得出要把哪个库用上', () async {
      final got = await carry(_bookLib(), kBook);
      final doc = page(got.libs, withStore: false);
      expect(lcLogicErrorCount(doc), greaterThan(0));
      final front = lcFrontOf(doc.logic)!;
      expect(lcFrontProgram(front).problems.join('；'), contains('要靠库「状态仓库」'));
    });
  });

  group('形状三·包一层“请求”的库', () {
    late HttpServer server;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((q) {
        q.response
          ..statusCode = 200
          ..write(q.uri.path == '/num' ? '42' : '"别的"');
        unawaited(q.response.close());
      });
    });
    tearDown(() => server.close(force: true));

    for (final kind in kFrontKinds.entries) {
      test(
        '${kind.value}：新建→公开→导出→另一个项目导入→用→对着本地假服务真编译真跑',
        () async {
          final got = await carry(_apiLib(), kApi);
          expect(got.manifest['requires'], ['lopi/http']);
          expect(got.needs.join('；'), contains('要靠应用自带的“请求”库'));
          final doc = withLibs(
            frontPage(
              [btn('b1', '取'), txt('t1')],
              const [],
              frontDoc(
                uses: [use('lopi/http'), use(kApi)],
                hats: [
                  onClick('h1', 'b1', [
                    show('t1', lx(kApi, 'say', {'网址': tx('http://127.0.0.1:${server.port}/num')})),
                  ]),
                ],
              ),
            ),
            got.libs,
          );
          await frontCheckAll(kind.key, doc, [
            [
              {'op': 'net'},
              click('b1'),
              untilText('t1', '取到 42'),
            ],
          ]);
        },
        skip: skipWithoutDom,
        timeout: const Timeout(Duration(minutes: 4)),
      );
    }
  });

  test('默认状态下，自己的前端库直接碰宿主接口照旧被拒绝（要靠自带的库去碰）', () {
    final files = {
      kLibManifestFile:
          '{"kind": "lopicode-lib", "format": 1, "id": "shuang/raw", "name": "直接碰", "version": "1.0.0", "rules": 2, "for": "frontend", "native": {"allowed": false},'
          ' "hosts": ["timer.after"], "modules": [{"file": "modules/m.lc", "name": "直接碰"}], "blocks": ["blocks.json"]}',
      'modules/m.lc': '(模块 直接碰\n  (宿主 timer.after ((毫秒 小数) (做法 (要等函数 () 空))) -> 整数)\n  (公开 (函数 等等做 ((做法 (要等函数 () 空))) (做 (宿 timer.after 10.0 做法)))))',
      'blocks.json': '{"blocks": []}',
    };
    final lib = libRead(files, builtin: false);
    expect(lib.ok, isFalse);
    expect(lib.problems.join('；'), contains('还不能直接碰宿主接口'));
  });
}
