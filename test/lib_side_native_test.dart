// 第四轮·A1 不真跑的部分：库积木的“文档无关”一层、库的“给谁用”、复制自带的“接口服务”来改、
// 带手写代码的库的规矩和放行（全应用的开关、每库确认、代码变了要重确认、声明写错被拦）。
// 真跑在 lib_fork_native_run_test.dart；界面在 lib_more_ui_test.dart。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/backend/lib_service_fork.dart';
import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lc_locate.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/ui/backend_lib_import_sheet.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/lib_switches.dart';
import 'support/native_lib.dart';
import 'support/service_strict_doc.dart';
import 'support/user_libs.dart';

/// 一份“不是后端文档”的会用库的文档：证明库积木表那一层不认后端。
class FakePageDoc implements LibUser {
  FakePageDoc(this.uses, this.loaded, {this.bodies = const []});
  @override
  final List<LibUse> uses;
  @override
  List<LibLibrary> loaded;
  final List<List<LcBlock>> bodies;
  @override
  LibSide get libSide => LibSide.frontend;
  @override
  String? get libraryId => null;
  @override
  List<String> libMouthsOf(String fnId) => const [];
  @override
  Iterable<List<LcBlock>> get libBodies => bodies;
  @override
  Iterable<String> get libHatOps => const [];
}

J pureLib(String id, String side) {
  final doc = libDoc(
    '纯工具',
    id,
    functions: [
      tfn(
        'f1',
        '加感叹',
        [tpar('话', tText)],
        [
          ret(cat([pm('话'), tx('！')])),
        ],
        returns: tText,
      ),
    ],
    blocks: [
      def(
        'bang',
        'call',
        fn: 'f1',
        look: look('加感叹', '{话} 加感叹', shape: 'value'),
      ),
    ],
  );
  return {
    ...doc,
    'library': {...doc['library'] as Map, if (side != 'backend') 'for': side},
  };
}

void main() {
  // 中途包：带手写代码的库的启用、自己的库直接用宿主接口默认都关着（rules.dart）；这里测的是开着时的样子，每条先打开、测完改回默认。
  libSwitchesOn();
  late Directory dir;
  late PathGuard guard;
  setUp(() async {
    LibNativeTrust.instance = LibNativeTrust();
    dir = await Directory.systemTemp.createTemp('lopi_a1_');
    guard = PathGuard(dir.path);
  });
  tearDown(() async {
    await pendingWrites();
    await dir.delete(recursive: true);
    LibNativeTrust.instance = LibNativeTrust();
  });

  group('给谁用', () {
    test('清单里记着；没写＝后端；后端的库存盘不多写一个字', () {
      expect(LibSide.read(null), LibSide.backend);
      expect(LibSide.read('乱写'), LibSide.backend);
      final back = buildUserLib(pureLib('tata/pure', 'backend'));
      expect(back.lib.side, LibSide.backend);
      expect(jsonDecode(back.files[kLibManifestFile]!) as Map, isNot(contains('for')), reason: '旧库、后端库的清单不改写');
      expect(parseLangBlocksDocument(pureLib('tata/pure', 'backend')).toJson()['library'] as Map, isNot(contains('for')));
      final both = buildUserLib(pureLib('tata/pure', 'both'));
      expect(both.lib.side, LibSide.both);
      expect((jsonDecode(both.files[kLibManifestFile]!) as Map)['for'], 'both');
      expect(parseLangBlocksDocument(pureLib('tata/pure', 'both')).library!.clone().side, LibSide.both);
    });

    test('只用语言核心的库两边都能用；只给前端的库后端文档里用不了（检查和生成都拦）', () {
      final both = buildUserLib(pureLib('tata/pure', 'both')).lib, front = buildUserLib(pureLib('tata/front', 'frontend')).lib;
      J user(String id) => {
        ...coreDoc(
          '用它',
          main: [
            log(lx(id, 'bang', {'话': tx('好')})),
          ],
        ),
        'version': 5,
        'uses': [use(id)],
      };
      final ok = userDocument(user('tata/pure'), [both]);
      expect(backendErrors(ok), isEmpty);
      expect(beServiceGenerate(ok, 'node').problem, isNull);
      final bad = userDocument(user('tata/front'), [front]);
      expect(backendErrors(bad), isNotEmpty, reason: '检查阶段拦');
      expect(beServiceProgram(bad).problems.join(), contains('只给前端用的库'));
      expect(beServiceGenerate(bad, 'node').files, isNull);
    });

    test('写了“都行”或“前端”却靠着接口服务、碰了宿主接口：读库时就是问题', () {
      final todo = buildUserLib(todoLibDoc()).files;
      Map<String, String> as(String side) => {
        ...todo,
        kLibManifestFile: jsonEncode({...jsonDecode(todo[kLibManifestFile]!) as Map, 'for': side}),
      };
      expect(libRead(todo, builtin: false).ok, isTrue);
      expect(libRead(as('both'), builtin: false).problems.join(), contains('接口服务'));
      expect(libRead(as('frontend'), builtin: false).problems.join(), contains('接口服务'));
      final fork = beServiceForkFiles(id: 'shuang/svc', name: '我的接口服务').files!;
      final forkBoth = {
        ...fork,
        kLibManifestFile: jsonEncode({...jsonDecode(fork[kLibManifestFile]!) as Map, 'for': 'both'}),
      };
      expect(libRead(forkBoth, builtin: false).ok, isFalse);
    });

    test('导入预览里看得到“给谁用”', () {
      expect(beLibImportView(beLibPreview(buildUserLib(pureLib('tata/pure', 'both')).files)).side, '后端和前端都行');
      expect(beLibImportView(beLibPreview(buildUserLib(pureLib('tata/pure', 'backend')).files)).side, '后端');
    });
  });

  group('文档无关的库积木表', () {
    test('一份不是后端文档的文档也能用：表、积木盒分页、数用了几处；给谁用对不上的库不进表', () {
      final both = buildUserLib(pureLib('tata/pure', 'both')).lib, back = buildUserLib(pureLib('tata/back', 'backend')).lib;
      final op = libOp('tata/pure', 'bang');
      final page = FakePageDoc(
        [LibUse('tata/pure'), LibUse('tata/back')],
        [both, back],
        bodies: [
          [
            LcBlock(
              op: 'log',
              args: {
                'value': {'e': op, '话': '好'},
              },
            ),
          ],
        ],
      );
      final table = LibTable(page);
      expect([for (final l in table.libs) l.id], ['tata/pure'], reason: '只给后端的库不进前端文档的表');
      expect(table.of(op)?.exprSpec.label, '加感叹');
      expect(table.of(libOp('tata/back', 'bang')), isNull);
      expect(table.usesOfLib('tata/pure'), 1);
      final pages = libCategories(table);
      expect([for (final c in pages) c.id], ['lib:tata/pure']);
      expect(pages.single.exprs, [op]);
    });
  });

  group('复制自带的“接口服务”来改', () {
    test('复制件读得进来、记着从谁复制、写明顶替谁和碰了哪些宿主能力；标识不合规矩不给复制', () {
      expect(beServiceForkFiles(id: 'lopi/x', name: '甲').problem, contains('留着用'));
      expect(beServiceForkFiles(id: 'Bad', name: '甲').problem, isNotNull);
      final files = beServiceForkFiles(id: 'shuang/svc', name: '我的接口服务').files!;
      final lib = libRead(files, builtin: false);
      expect(lib.problems, isEmpty);
      expect(lib.replaces, kBeServiceLibId);
      expect(lib.hosts.toSet(), beServiceLibrary().hosts.toSet());
      expect([for (final b in lib.blocks) b.id], [for (final b in beServiceLibrary().blocks) b.id]);
      expect((jsonDecode(files[kLibManifestFile]!) as Map)['origin'], {'id': kBeServiceLibId, 'version': beServiceLibrary().version});
      // 预览页写明它碰了哪些宿主能力。
      final preview = beLibPreview(files);
      expect(preview.canImport, isTrue);
      expect(preview.needs.join('\n'), contains(beHostWord('http.serve')));
      // 清单里少写一个宿主接口：读不过。
      final manifest = jsonDecode(files[kLibManifestFile]!) as Map;
      final less = {
        ...files,
        kLibManifestFile: jsonEncode({
          ...manifest,
          'hosts': [
            for (final h in manifest['hosts'] as List)
              if (h != 'net.fetch') h,
          ],
        }),
      };
      expect(libRead(less, builtin: false).problems.join(), contains('hosts 里没有写明'));
    });

    test('放进项目、文档指定用它顶替：生成得出来；和原库同时在名字不撞；不能当普通库用上', () async {
      final made = await beServiceFork(guard, id: 'shuang/svc', name: '我的接口服务');
      expect(made.problem, isNull);
      expect((await beServiceFork(guard, id: 'shuang/svc', name: '再来')).problem, contains('已经有'));
      final stored = (await beLibsRead(guard)).single;
      expect(stored.ok, isTrue);
      expect(stored.from, 'copy');
      expect(stored.hasSource, isFalse);
      final doc = serviceStrictDocument()..serviceLib = 'shuang/svc';
      await beLibsAttach(guard, doc);
      expect(backendErrors(doc), isEmpty);
      for (final language in kGen2Languages) {
        final gen = beServiceGenerate(doc, language);
        expect(gen.problem, isNull, reason: language);
      }
      // 复制件和原库同时在项目里、各有文档在用：两份文档各生成各的，名字不撞（复制件的模块、启动时的变量都换了名）。
      final plain = serviceStrictDocument();
      await beLibsAttach(guard, plain);
      expect(beServiceGenerate(plain, 'node').problem, isNull);
      expect(beServiceGenerate(plain, 'node').files!.values.join(), isNot(contains('shuang')));
      // 一个靠自带“接口服务”的库，放进用复制件顶替的文档里：两边的“请求”不是一样东西，如实拦下并说怎么办。
      final todo = buildUserLib(todoLibDoc()).lib;
      final mixed = userDocument(todoUserDoc(), [todo, stored.lib])..serviceLib = 'shuang/svc';
      expect(beServiceGenerate(mixed, 'node').files, isNull);
      expect(beServiceProgram(mixed).problems.join(), contains('两边接不上'));
      expect(beServiceGenerate(userDocument(todoUserDoc(), [todo, stored.lib]), 'node').problem, isNull, reason: '不顶替时照常');
      // 当普通库“用上”不行。
      final wrong = serviceStrictDocument()
        ..uses.add(LibUse('shuang/svc'))
        ..loaded = [stored.lib];
      expect(beServiceProgram(wrong).problems.join(), contains('顶替'));
      // 指定了一个不在项目里的：说得出来。
      final gone = serviceStrictDocument()..serviceLib = 'shuang/none';
      expect(beServiceProgram(gone).problems, isNotEmpty);
    });

    test('改库的文字：改得对就存；改坏了不存、说原因；标识不许在这里改', () async {
      await beServiceFork(guard, id: 'shuang/svc', name: '我的接口服务');
      var s = (await beLibsRead(guard)).single;
      expect(beLibTextFiles(s), ['blocks.json', 'lib.json', 'modules/service.lc']);
      final module = s.files['modules/service.lc']!;
      expect(await beLibSaveText(guard, 'shuang/svc', 'modules/service.lc', '$module\n; 我加的一句注释\n'), isNull);
      s = (await beLibsRead(guard)).single;
      expect(s.ok, isTrue);
      expect(s.files['modules/service.lc'], contains('我加的一句注释'));
      final bad = await beLibSaveText(guard, 'shuang/svc', 'modules/service.lc', '(模块 shuang/svc (函数 坏了');
      expect(bad, isNotNull);
      expect((await beLibsRead(guard)).single.files['modules/service.lc'], contains('我加的一句注释'), reason: '改坏的没有存');
      final renamed = s.files[kLibManifestFile]!.replaceFirst('"shuang/svc"', '"shuang/other"');
      expect(await beLibSaveText(guard, 'shuang/svc', kLibManifestFile, renamed), contains('标识'));
      expect(await beLibSaveText(guard, 'shuang/svc', 'native/x.js', 'x'), contains('不能在这里改'));
    });
  });

  group('改库的文字：写坏了说得出第几行', () {
    test('模块文件：少右括号、多右括号、引号没收尾、某一句读不了——各说各的行；没毛病不说话', () {
      expect(lcLocateProblem('(模块 甲\n  (函数 好 () (做 (返回 1)))\n  (函数 坏了'), contains('第 3 行'));
      expect(lcLocateProblem('(模块 甲\n  (函数 好 () (做 (返回 1))))\n)'), contains('第 3 行：多了一个右括号'));
      expect(lcLocateProblem('(模块 甲\n\n  (函数 好 () -> 文字 (返回 "没收尾))\n)'), contains('第 3 行：文字的双引号没有收尾'));
      final odd = lcLocateProblem('(模块 甲\n  (函数 好 () -> 整数 (返回 1))\n\n  (函数 怪 () -> 整数\n    (返回 (不认识的东西 1 2))))');
      expect(odd, allOf(contains('第 4 行开始的这一句'), contains('不认识')));
      expect(lcLocateProblem('; 注释里的 ( 和 " 不算\n(模块 甲 (函数 好 () -> 整数 (返回 1)))'), isNull);
      expect(lcLocateProblem(kBeServiceModuleLc), isNull, reason: '自带库的模块一句一句单独读都读得了（不然会冤枉好文件）');
    });
    test('JSON 文件：说出停在第几行', () {
      expect(jsonLocateProblem('{\n  "a": 1,\n  "b": [1, 2,]\n}'), contains('第 3 行'));
      expect(jsonLocateProblem('{"a": 1}'), isNull);
    });
    test('存和检查都带着行：括号坏了说行；类型对不上的点得出名字的补一句“第几行附近”；检查不存', () async {
      await beServiceFork(guard, id: 'shuang/svc', name: '我的接口服务');
      final s = (await beLibsRead(guard)).single;
      final module = s.files['modules/service.lc']!;
      final lines = module.split('\n');
      final cut = lines.take(40).join('\n');
      expect(await beLibCheckText(guard, 'shuang/svc', 'modules/service.lc', cut), contains('行'));
      // 把“状态码”函数的返回从整数改成文字：读库查得出来，问题里带着行。
      final at = lines.indexWhere((l) => l.contains('(函数 状态码 '));
      expect(at, greaterThan(0));
      final wrong = [...lines]..[at] = lines[at].replaceFirst('-> 整数', '-> 文字');
      final bad = await beLibCheckText(guard, 'shuang/svc', 'modules/service.lc', wrong.join('\n'));
      expect(bad, isNotNull, reason: '类型写错的当场查得出来，不等到用的时候');
      // ignore: avoid_print — 这句话长什么样要让跑测试的人看见
      print('类型写错时说的话：$bad');
      expect(bad, contains('行'), reason: bad);
      // 清单改坏：JSON 的行。
      expect(await beLibCheckText(guard, 'shuang/svc', 'lib.json', '{\n"kind": \n}'), contains('第 3 行'));
      // 检查不存：改得对的也只是查。
      expect(await beLibCheckText(guard, 'shuang/svc', 'modules/service.lc', '$module\n; 只是查查\n'), isNull);
      expect((await beLibsRead(guard)).single.files['modules/service.lc'], module);
    });
  });

  group('带手写代码的库', () {
    test('样例库：放行时读得进来，两个手写函数、一个要等；不放行就是问题', () {
      final ok = libRead(handLibFiles(), builtin: false, nativeOk: true);
      expect(ok.problems, isEmpty);
      expect([for (final n in ok.natives) '${n.name}:${n.waits}'], ['join:false', 'twice:true']);
      expect(ok.natives.first.ident, 'LcN_shuang__hand_join');
      final off = libRead(handLibFiles(), builtin: false);
      expect(off.ok, isFalse);
      expect(off.problems.join(), contains('允许库里的手写代码'));
    });

    test('声明写错的被拦：类型对不上、文件没登记、没声明、不是规定的样子、类型太复杂、前端库带手写代码', () {
      List<String> bad(Map<String, String> files) => libRead(files, builtin: false, nativeOk: true).problems;
      final good = handLibFiles();
      // 模块里的声明和清单对不上。
      expect(bad({...good, 'modules/hand.lc': good['modules/hand.lc']!.replaceFirst('join ((s 文字) (n 整数)) -> 文字', 'join ((s 文字) (n 文字)) -> 文字')}).join(), contains('对不上'));
      // 多了一个没登记的文件。
      expect(bad({...good, 'native/extra.js': 'module.exports = () => 1;'}).join(), contains('没有登记'));
      // 清单里有、模块里没声明。
      expect(
        bad({...good, 'modules/hand.lc': good['modules/hand.lc']!.replaceFirst('  (宿主 手写.$kLibHand.twice ((n 整数)) -> 整数)\n', '').replaceFirst('(宿 手写.$kLibHand.twice n)', 'n')}).join(),
        contains('没有声明'),
      );
      // 文件不是规定的样子。
      expect(bad({...good, 'native/join.py': 'print(1)\n'}).join(), contains('不是规定的样子'));
      // 清单没写 allowed。
      expect(
        bad(
          handLibFiles(
            manifest: {
              'native': {'functions': (jsonDecode(good[kLibManifestFile]!) as Map)['native']['functions']},
            },
          ),
        ).join(),
        contains('allowed'),
      );
      // 复杂类型不收。
      final m = jsonDecode(good[kLibManifestFile]!) as Map;
      final fns = [...(m['native'] as Map)['functions'] as List];
      fns[0] = {...fns[0] as Map, 'returns': '(列表 文字)'};
      expect(
        bad({
          ...good,
          kLibManifestFile: jsonEncode({
            ...m,
            'native': {'allowed': true, 'functions': fns},
          }),
        }).join(),
        contains('只能是'),
      );
      // 给前端或两边用的库不许带手写代码。
      expect(bad(handLibFiles(manifest: {'for': 'both'})), isNotEmpty);
    });

    test('调用和声明对不上：检查阶段拦（给整数的地方给了文字）', () {
      final lib = libRead(handLibFiles(), builtin: false, nativeOk: true);
      final doc = userDocument(
        {
          ...coreDoc(
            '用错了',
            main: [
              log(lx(kLibHand, 'join', {'s': tx('嗨'), 'n': tx('三')})),
            ],
          ),
          'version': 5,
          'uses': [use(kLibHand)],
        },
        [lib],
      );
      expect(beServiceGenerate(doc, 'node').files, isNull);
    });

    test('哪种语言缺手写文件，那种语言就不生成并说明；别的语言照常', () {
      final lib = libRead(handLibFiles(only: ['node', 'python']), builtin: false, nativeOk: true);
      expect(lib.problems, isEmpty);
      final doc = userDocument(handUserDoc(), [lib]);
      expect(beServiceGenerate(doc, 'node').problem, isNull);
      expect(beServiceGenerate(doc, 'go').files, isNull);
      expect(beServiceGenerate(doc, 'go').problem, contains('join'));
    });

    test('生成的工程里带着手写文件，占位的名字换好了；应用自己不执行它', () {
      final lib = libRead(handLibFiles(), builtin: false, nativeOk: true);
      final doc = userDocument(handUserDoc(), [lib]);
      final go = beServiceGenerate(doc, 'go').files!;
      expect(go.keys, contains('LcN_shuang__hand_join.go'));
      expect(go['LcN_shuang__hand_join.go'], contains('func LcN_shuang__hand_join('));
      expect(go['LcN_shuang__hand_join.go'], isNot(contains('__NAME__')));
      expect(beServiceGenerate(doc, 'node').files!.keys, containsAll(['LcN_shuang__hand_join.js', 'LcN_shuang__hand_twice.js']));
    });

    test('开关关着：预览说不能导入、导入被拒、什么都不放进项目；勾了也没用', () async {
      final preview = beLibPreview(beLibUnpack(beLibPack(handLibFiles())).files!);
      expect(preview.hasNative, isTrue);
      expect(preview.nativeFiles, hasLength(10));
      expect(preview.canImport, isFalse);
      expect((await beLibInstall(guard, preview, nativeConfirmed: true)).problems.join(), contains('关着'));
      expect(await beLibsRead(guard), isEmpty);
      expect(await LibNativeTrust.instance.confirm(guard.root, kLibHand, 'x'), isFalse, reason: '开关关着时确认不记');
    });

    test('开关开着：没勾“我看过了”不许；勾了导入；用得上；代码变了一个字要重新确认；关开关全部作废', () async {
      await LibNativeTrust.instance.setEnabled(true);
      final preview = beLibPreview(beLibUnpack(beLibPack(handLibFiles())).files!);
      expect(preview.canImport, isTrue, reason: preview.problems.join());
      expect((await beLibInstall(guard, preview)).problems.join(), contains('我看过这些代码了'));
      expect(await beLibsRead(guard), isEmpty);
      expect((await beLibInstall(guard, preview, nativeConfirmed: true)).problems, isEmpty);
      var s = (await beLibsRead(guard)).single;
      expect(s.ok, isTrue);
      expect(s.files.keys.where((f) => f.startsWith('native/')), hasLength(10));
      final doc = userDocument(handUserDoc(), const []);
      await beLibsAttach(guard, doc);
      expect(backendErrors(doc), isEmpty);
      expect(beServiceGenerate(doc, 'python').problem, isNull);

      // 有人（比如 Agent）改了项目里那个库的手写代码：校验值对不上，库马上用不了。
      File(guard.resolve('${s.dir}/native/join.js')).writeAsStringSync('module.exports = function (s, n) { require("child_process"); return s; };\n');
      s = (await beLibsRead(guard)).single;
      expect(s.ok, isFalse);
      expect(s.problem, contains('允许库里的手写代码'));
      final again = userDocument(handUserDoc(), const []);
      await beLibsAttach(guard, again);
      expect(beServiceGenerate(again, 'node').files, isNull);
      // 重新确认这一份以后又能用。
      expect(await LibNativeTrust.instance.confirm(guard.root, kLibHand, libNativeSum(s.files)), isTrue);
      expect((await beLibsRead(guard)).single.ok, isTrue);
      // 换一个项目不算确认过。
      expect(LibNativeTrust.instance.allows('${guard.root}-别处', kLibHand, libNativeSum(s.files)), isFalse);
      // 关掉开关：全部作废；再打开也要重新确认。
      await LibNativeTrust.instance.setEnabled(false);
      expect((await beLibsRead(guard)).single.ok, isFalse);
      await LibNativeTrust.instance.setEnabled(true);
      expect((await beLibsRead(guard)).single.ok, isFalse);
    });

    test('确认记录存在应用自己的目录里，重开应用还在；默认是关', () async {
      final file = File('${dir.path}/app-private/lib_native_trust.json');
      final a = LibNativeTrust();
      await a.attach(file);
      expect(a.enabled, isFalse);
      await a.setEnabled(true);
      expect(await a.confirm('/p', kLibHand, 'abc'), isTrue);
      await pendingWrites();
      final b = LibNativeTrust();
      await b.attach(file);
      expect(b.enabled, isTrue);
      expect(b.allows('/p', kLibHand, 'abc'), isTrue);
      expect(b.allows('/p', kLibHand, 'abd'), isFalse);
    });

    test('导出包带着手写文件，防护不放松：整包、文件数、路径的上限照旧', () async {
      await LibNativeTrust.instance.setEnabled(true);
      expect((await beLibInstall(guard, beLibPreview(handLibFiles()), nativeConfirmed: true)).problems, isEmpty);
      final out = await beLibExport(guard, kLibHand);
      expect(out.problem, isNull);
      final back = beLibUnpack(File(guard.resolve(out.rel!)).readAsBytesSync());
      expect(back.files!.keys.where((f) => f.startsWith('native/')), hasLength(10));
      expect(beLibUnpack(beLibPack({...handLibFiles(), '../native/x.js': 'x'})).problem, contains('不对劲'));
      expect(beLibUnpack(List.filled(kBeLibMaxPackBytes + 1, 0)).problem, contains('太大'));
    });
  });
}
