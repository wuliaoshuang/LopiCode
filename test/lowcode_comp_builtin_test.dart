// 第四轮 B5：内置组件库（lopi/builtin）——只读的库定义、第一次用才装进文档、复制一份来改、组件盒里的条目。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/comp_lib_builtin_p1.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'support/bind_export_files.dart';

LcDocument _empty() => LcDocument.fromJson({
  'version': 3,
  'title': 'T',
  'root': {'id': 'page', 'type': 'page', 'children': <Object?>[]},
});

void main() {
  group('内置组件库', () {
    test('库：标识用的是应用自己留着的作者段；十四个定义一个不少，都解析得出来', () {
      final lib = lcBuiltinCompLib();
      expect(lib.id, 'lopi/builtin');
      expect(kCompLibId.hasMatch(lib.id), isTrue);
      expect(compLibAuthorReserved('lopi'), isTrue, reason: '别人的库用不了这个标识');
      expect(lib.ok, isTrue);
      expect([for (final d in lib.defs) d.id], [for (final b in kBuiltinComps) b.id]);
      expect(lib.defs, hasLength(8 + lcBuiltinP1Defs().length));
      expect(lcBuiltinP1Defs(), hasLength(6));
      expect({for (final d in lib.defs) d.name}.length, lib.defs.length, reason: '名字不重');
    });

    test('库：和用户的组件库同一种文件写法——写成库文件再读回来，没有问题、定义一样', () {
      final lib = lcBuiltinCompLib();
      final back = compLibRead(compLibFiles(lib));
      // 标识里的 lopi 只在“导入别人的库”时拦；读法本身认它。
      expect(back.defs.map((d) => jsonEncode(d.toJson())).toList(), lib.defs.map((d) => jsonEncode(d.toJson())).toList());
    });

    test('包一层的八个：最外层就是那个现成的控件；容器类带一个插槽', () {
      final lib = lcBuiltinCompLib();
      for (final id in ['card', 'row', 'column', 'spacer', 'divider', 'list', 'listItem', 'appBar']) {
        final d = lib.defs.firstWhere((d) => d.id == id);
        expect(d.root.type, id, reason: id);
        expect(d.slots.length, ['card', 'row', 'column'].contains(id) ? 1 : 0, reason: id);
        expect(lcSpecs[id]!.label, d.name, reason: id);
      }
    });

    test('P1 六个：事件、变体、插槽照说明里写的', () {
      final by = {for (final d in lcBuiltinCompLib().defs) d.id: d};
      expect(lcCompEvents(by['iconButton']!).map((e) => e.name), ['tap']);
      expect(by['iconButton']!.slots, hasLength(1));
      expect(lcCompEvents(by['link']!).map((e) => e.name), ['tap']);
      expect(by['link']!.props.map((p) => p.name), ['text']);
      expect(lcVariants(by['grid']!), isNotEmpty);
      expect(by['grid']!.slots, hasLength(1));
      expect(lcVariants(by['scroll']!), isNotEmpty);
      expect(by['stepper']!.props.map((p) => p.name), ['value', 'min', 'max', 'step']);
      expect(lcCompEvents(by['stepper']!).single.name, 'change');
      expect(lcCompEvents(by['stepper']!).single.params.single.name, 'value');
      expect(by['formItem']!.props.map((p) => p.name), ['label', 'required', 'help', 'error']);
      expect(by['formItem']!.slots, hasLength(1));
    });

    test('第一次用才装：只装要的那一个，带着来源；再调一次不重复装', () {
      final doc = _empty();
      final id = lcBuiltinDefId('stepper');
      expect(id, 'lib_lopi_builtin_stepper');
      expect(lcEnsureBuiltin(doc, 'c1'), isFalse);
      expect(lcEnsureBuiltin(doc, null), isFalse);
      expect(lcEnsureBuiltin(doc, 'lib_lopi_builtin_nope'), isFalse);
      expect(doc.components, isEmpty);
      expect(lcEnsureBuiltin(doc, id), isTrue);
      expect(lcEnsureBuiltin(doc, id), isFalse);
      expect(doc.components.single.id, id);
      expect(lcIsBuiltinDef(doc.components.single), isTrue);
      expect(compLibOf(doc.components.single)!.name, '内置组件库');
      expect(compLibsInDoc(doc).keys, ['lopi/builtin']);
      // 存出去再读回来还在
      final back = LcDocument.parse(doc.encode());
      expect(lcIsBuiltinDef(back.components.single), isTrue);
      expect(back.encode(), doc.encode());
    });

    test('复制一份来改：得到项目自己的组件（没有来源那一笔）；为复制临时装的那份不留下', () {
      final doc = _empty();
      final made = lcForkBuiltin(doc, 'card');
      expect(made, 'c1');
      expect(doc.components.single.name, '卡片 副本');
      expect(compLibOf(doc.components.single), isNull);
      expect(doc.components.single.root.type, 'card');
      // 已经在用的内置组件：复制以后原来那份还在
      lcEnsureBuiltin(doc, lcBuiltinDefId('link'));
      final made2 = lcForkBuiltin(doc, 'link');
      expect(made2, 'c2');
      expect(doc.component(lcBuiltinDefId('link')), isNotNull);
      expect(doc.component('c2')!.name, '链接 副本');
      expect(lcForkBuiltin(doc, 'nope'), isNull);
      // 每一个都复制得出来
      for (final b in kBuiltinComps) {
        expect(lcForkBuiltin(_empty(), b.id), 'c1', reason: b.id);
      }
    });

    test('组件盒：六个 P1 在各自的分类里；装进文档以后不在“我的”里再出现', () {
      final all = paletteEntries(const []);
      final built = [
        for (final e in all)
          if (e.builtin != null) e,
      ];
      expect(built.map((e) => e.label), ['图标按钮', '链接', '网格', '滚动区', '步进器', '表单项']);
      expect(
        {for (final e in built) e.label: e.group},
        {'图标按钮': PaletteGroup.basic, '链接': PaletteGroup.basic, '网格': PaletteGroup.layout, '滚动区': PaletteGroup.layout, '步进器': PaletteGroup.form, '表单项': PaletteGroup.form},
      );
      expect(built.every((e) => e.type == 'component' && e.ref == lcBuiltinDefId(e.builtin!.id)), isTrue);
      final doc = _empty();
      lcEnsureBuiltin(doc, lcBuiltinDefId('grid'));
      final after = paletteEntries(doc.components);
      expect(after.where((e) => e.group == PaletteGroup.mine), isEmpty);
      expect(after.length, all.length);
      // 搜得到
      expect(paletteSearch(all, '加减').map((e) => e.label), contains('步进器'));
      expect(paletteSearch(all, '宫格').map((e) => e.label), contains('网格'));
      expect(paletteSearch(all, 'link').map((e) => e.label), contains('链接'));
    });

    test('每一个内置定义：放一个实例上页面，四种导出都导得出东西', () {
      for (final b in kBuiltinComps) {
        final doc = _empty();
        final ref = lcBuiltinDefId(b.id);
        expect(lcEnsureBuiltin(doc, ref), isTrue, reason: b.id);
        final node = doc.newNode('component')..props['ref'] = ref;
        doc.insert(doc.root.id, node);
        lcLinkInstances(doc);
        final files = allExportFiles(doc);
        for (final k in ['html/index.html', 'flutter/page.dart']) {
          expect(files[k], isNotEmpty, reason: '${b.id} $k');
        }
        expect(files.keys.where((k) => k.startsWith('vue/') && k.endsWith('.vue')), isNotEmpty, reason: b.id);
        expect(files.keys.where((k) => k.startsWith('react/') && k.endsWith('.jsx')), isNotEmpty, reason: b.id);
      }
    });
  });
}
