// 第四轮 B2：用户自己的组件库——收成库、读（带检查）、落盘、导出导入、装进文档、重查、复制一份来改；
// 故意做坏的库都被拦下并说清原因；坏文件不崩。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_sheet.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:path/path.dart' as p;

import 'support/comp_lib_flow.dart';
import 'support/comp_samples.dart';

void main() {
  late Directory tmp;
  late PathGuard guard;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('complib');
    guard = PathGuard(p.join(tmp.path, 'proj'));
    await Directory(guard.root).create(recursive: true);
  });
  tearDown(() => tmp.delete(recursive: true));

  CompLib sample({String version = '1.0.0'}) =>
      compLibFromDoc(projectA([productCardDef(), loginFormDef(), tagBarDef()]), ['c1', 'c2', 'c3'], id: 'shuang/shop', name: '商城组件', version: version, author: '霜霜');

  Map<String, String> broken(void Function(Map<String, dynamic> manifest, Map<String, dynamic> body) change) {
    final files = compLibFiles(sample());
    final m = (jsonDecode(files[kCompLibManifest]!) as Map).cast<String, dynamic>(), b = (jsonDecode(files[kCompLibDefsFile]!) as Map).cast<String, dynamic>();
    change(m, b);
    return {kCompLibManifest: jsonEncode(m), kCompLibDefsFile: jsonEncode(b)};
  }

  test('收成库再读回来：组件、事件、变体、状态、绑定一样不少；写出来的文件一个字不差', () {
    final lib = sample();
    final files = compLibFiles(lib);
    final back = compLibRead(files);
    expect(back.problems, isEmpty);
    expect(back.id, 'shuang/shop');
    expect(back.defs.map((d) => d.name), ['商品卡片', '登录表单', '标签筛选条']);
    final card = back.defs.first;
    expect(card.slots, isNotEmpty);
    expect(lcCompEvents(card), isNotEmpty);
    expect(lcVariants(card).length, greaterThanOrEqualTo(2));
    expect(back.hasLogic, isTrue);
    expect(compLibFiles(back), files);
    expect(compLibSum(compLibFiles(back)), compLibSum(files));
  });

  test('套着别的组件的组件：里面那个自动带上；图片带进包里，太大的记成没带上', () {
    final inner = {
      'id': 'c8',
      'name': '头像',
      'root': cn('a', 'image', {'src': 'images/a.png'}),
    };
    final outer = {
      'id': 'c9',
      'name': '名片',
      'root': cn('b', 'column', {}, [
        cn('i', 'component', {'ref': 'c8'}),
        cn('big', 'image', {'src': 'images/big.png'}),
        cn(
          't',
          'text',
          {'text': 'x'},
          [],
          {
            'style': {'color': 'var(--color-brand)'},
          },
        ),
      ]),
    };
    final doc = projectA([inner, outer])
      ..more['theme'] = {
        'vars': {'color-brand': '#112233', 'color-other': '#000000'},
      };
    final lib = compLibFromDoc(doc, ['c9'], id: 'shuang/cards', name: '名片', version: '1.0.0', readImage: (rel) => rel == 'images/a.png' ? [1, 2, 3] : null);
    expect(lib.defs.map((d) => d.id).toSet(), {'c8', 'c9'});
    expect(lib.images.keys, ['images/a.png']);
    expect(lib.missingImages, ['images/big.png']);
    expect(lib.themeVars, {'color-brand': '#112233'});
    final back = compLibRead(compLibFiles(lib));
    expect(back.ok, isTrue);
    expect(base64Decode(back.images['images/a.png']!), [1, 2, 3]);
    final view = compLibImportView(back);
    expect(view.canImport, isTrue);
    expect(view.items.length, 2);
    expect(view.needs.join('\n'), allOf(contains('1 张图片'), contains('没带上'), contains('主题变量'), contains('没有手写代码')));
  });

  group('故意做坏的库都被拦下', () {
    test('清单缺字段', () {
      for (final key in ['id', 'name', 'version']) {
        final lib = compLibRead(broken((m, _) => m.remove(key)));
        expect(lib.ok, isFalse);
        expect(lib.problems.join(), contains('清单缺一项：$key'));
      }
      expect(compLibRead({kCompLibDefsFile: '{}'}).problems.single, contains('没有清单'));
      expect(compLibRead(broken((m, _) => m['side'] = 'backend')).problems.join(), contains('不是前端'));
      expect(compLibRead(broken((m, _) => m['id'] = 'lopi/x')).problems.join(), contains('留着用'));
      expect(compLibRead(broken((m, _) => m['id'] = '../x')).problems.join(), contains('标识不对'));
    });

    test('组件互相套成圈', () {
      final lib = compLibRead(
        broken((_, b) {
          b['components'] = [
            {
              'id': 'x',
              'name': '甲',
              'root': cn('r', 'column', {}, [
                cn('i', 'component', {'ref': 'y'}),
              ]),
            },
            {
              'id': 'y',
              'name': '乙',
              'root': cn('r', 'column', {}, [
                cn('i', 'component', {'ref': 'x'}),
              ]),
            },
          ];
        }),
      );
      expect(lib.ok, isFalse);
      expect(lib.problems.join(), contains('套成了圈'));
    });

    test('用到了库里没有的组件、带手写代码、是积木库、读不懂的组件', () {
      expect(
        compLibRead(
          broken((_, b) {
            b['components'] = [
              {
                'id': 'x',
                'name': '甲',
                'root': cn('r', 'column', {}, [
                  cn('i', 'component', {'ref': 'nope'}),
                ]),
              },
            ];
          }),
        ).problems.join(),
        contains('库里没有的组件'),
      );
      expect(compLibRead({...broken((_, _) {}), 'native/a.js': 'x'}).problems.join(), contains('手写代码'));
      expect(compLibRead(broken((m, _) => m['kind'] = 'lopicode-lib')).problems.single, contains('积木库'));
      expect(compLibRead(broken((_, b) => b['components'] = [1, 'x', <String, Object?>{}])).problems.join(), contains('读不懂'));
      expect(compLibRead(broken((_, b) => b['components'] = <Object?>[])).problems.join(), contains('一个组件都没有'));
    });

    test('导出文件：路径往外跳、超大小、不是压缩包、同标识同版本不同内容', () async {
      Future<CompLib> open(List<int> bytes, {List<CompStoredLib> installed = const []}) async {
        await File(guard.resolve('bad.lopilib')).writeAsBytes(bytes);
        return (await compLibOpenPack(guard, 'bad.lopilib', installed: installed)).lib;
      }

      final good = compLibFiles(sample());
      final jump = await open(beLibPack({...good, '../evil.json': '{}'}));
      expect(jump.ok, isFalse);
      final big = await open(List.filled(kBeLibMaxPackBytes + 1, 0));
      expect(big.problems.single, contains('太大'));
      final fat = await open(
        beLibPack({
          ...good,
          kCompLibImagesFile: jsonEncode({'images/a.png': 'A' * (kBeLibMaxFileBytes + 10)}),
        }),
      );
      expect(fat.ok, isFalse);
      expect((await open(utf8.encode('这不是压缩包'))).ok, isFalse);
      expect((await compLibOpenPack(guard, '../outside.lopilib')).lib.ok, isFalse);
      expect((await compLibOpenPack(guard, 'none.lopilib')).lib.problems.single, contains('找不到'));

      expect(await compLibStore(guard, sample()), isNull);
      final installed = await compLibsRead(guard);
      expect((await open(beLibPack(good), installed: installed)).ok, isTrue, reason: '内容一样可以再导入');
      final other = compLibFromDoc(projectA([productCardDef()]), ['c1'], id: 'shuang/shop', name: '商城组件', version: '1.0.0', author: '霜霜');
      final clash = await open(beLibPack(compLibFiles(other)), installed: installed);
      expect(clash.ok, isFalse);
      expect(clash.problems.single, contains('内容却不一样'));
      final newer = compLibFromDoc(projectA([productCardDef()]), ['c1'], id: 'shuang/shop', name: '商城组件', version: '1.0.1', author: '霜霜');
      expect((await open(beLibPack(compLibFiles(newer)), installed: installed)).ok, isTrue, reason: '改了版本号就能导入');
    });
  });

  test('落盘：文件夹、登记表、导出文件；再读回来一样；拿掉以后干净', () async {
    expect(await compLibStore(guard, sample()), isNull);
    final index = jsonDecode(await File(guard.resolve(kCompLibsIndexFile)).readAsString()) as Map;
    expect(index['format'], 1);
    expect((index['libs'] as List).single, containsPair('id', 'shuang/shop'));
    expect((index['libs'] as List).single, containsPair('from', 'project'));
    final stored = (await compLibsRead(guard)).single;
    expect(stored.ok, isTrue);
    expect(stored.sum, (index['libs'] as List).single['sum']);
    final out = await compLibExport(guard, stored);
    expect(out.rel, 'exports/组件库-商城组件-1.0.0.lopilib');
    expect(await compLibPackFiles(guard), [out.rel]);
    final again = await compLibExport(guard, stored);
    expect(again.rel, out.rel, reason: '同样的库导出来的包一个字节不差');
    await compLibDelete(guard, 'shuang/shop');
    expect(await compLibsRead(guard), isEmpty);
    expect(await Directory(guard.resolve('components/shuang/shop')).exists(), isFalse);
  });

  test('坏文件不崩：登记表、清单、组件文件是乱的', () async {
    await Directory(guard.resolve('components/shuang/shop')).create(recursive: true);
    await File(guard.resolve(kCompLibsIndexFile)).writeAsString('{{{不是 JSON');
    await File(guard.resolve('components/shuang/shop/lib.json')).writeAsString('[1,2');
    await File(guard.resolve('components/shuang/shop/components.json')).writeAsBytes([0xff, 0xfe, 0x00]);
    final libs = await compLibsRead(guard);
    expect(libs.single.ok, isFalse);
    expect(libs.single.problem, contains('没有清单'));
    expect((await compLibExport(guard, libs.single)).rel, isNull);
    expect(await compLibStore(guard, sample()), isNull, reason: '坏的可以被好的盖掉');
    expect((await compLibsRead(guard)).single.ok, isTrue);
  });

  test('装进文档、组件盒一个库一组、更新后重查、复制一份来改、拿掉', () async {
    final flow = await compLibFullFlow(tmp, [productCardDef()]);
    final doc = flow.doc;
    expect(flow.notes, isEmpty);
    final def = doc.component('lib_shuang_shop_c1')!;
    expect(compLibOf(def)!.name, '商城组件');
    expect(compLibsInDoc(doc).keys, ['shuang/shop']);
    final entries = paletteEntries(doc.components);
    expect(entries.where((e) => e.lib == '商城组件').map((e) => e.label), ['商品卡片']);

    // 新版把事件、插槽、变体都拿掉了：用着它的页面重查，一条条说出来。
    final slim = {
      'id': 'c1',
      'name': '商品卡片',
      'root': cn('card', 'card', {}, [
        cn('t', 'text', {'text': '没了'}),
      ]),
    };
    final v2 = compLibFromDoc(projectA([slim]), ['c1'], id: 'shuang/shop', name: '商城组件', version: '2.0.0');
    final notes = compLibInstall(doc, v2);
    expect(notes, isNotEmpty);
    expect(notes.join('\n'), allOf(contains('页面「Shop」'), contains('新版没有')));
    expect(compLibOf(doc.component('lib_shuang_shop_c1')!)!.version, '2.0.0');

    final forked = compLibFork(doc, 'lib_shuang_shop_c1')!;
    expect(compLibOf(doc.component(forked)!), isNull);
    expect(doc.component(forked)!.name, '商品卡片 副本');
    expect(paletteEntries(doc.components).firstWhere((e) => e.ref == forked).lib, isNull);

    expect(compLibRemoveFromDoc(doc, 'shuang/shop'), 1, reason: '页面上还在用：留下来变成项目自己的');
    expect(compLibsInDoc(doc), isEmpty);
    expect(doc.component('lib_shuang_shop_c1'), isNotNull);
    // 存盘再读，来源那一笔和别的字段都还在（老版本应用也是原样留着 more 里的字段）。
    final again = compLibFullFlow(await tmp.createTemp('second'), [tagBarDef()], id: 'shuang/tags');
    final d2 = (await again).doc;
    final json = jsonDecode(jsonEncode(d2.toJson())) as Map;
    expect(jsonEncode(json), contains('"lib":{"id":"shuang/tags"'));
  });
}
