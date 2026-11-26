// 第 5 版编辑器第 2 期的纯逻辑：剪贴板（复制 / 粘贴 / 包成容器）、图层面板的行与落点、项目里的图片。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/editor_recents.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/image_assets.dart';
import 'package:lopicode/lowcode/layers_tree.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/node_actions.dart';
import 'package:path/path.dart' as p;

List<String> _ids(LcNode n) => [n.id, for (final c in n.children) ..._ids(c)];

/// 页面 → [文字A, 容器(文字B, 按钮), 卡片()]
(LcDocument, Map<String, String>) _page() {
  final doc = LcDocument(
    title: 't',
    root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults)),
  );
  LcNode add(String parent, String type, [String? text]) {
    final n = doc.newNode(type);
    if (text != null) n.props['text'] = text;
    doc.insert(parent, n);
    return n;
  }

  final a = add('root', 'text', 'A');
  final box = add('root', 'container');
  final b = add(box.id, 'text', 'B');
  final btn = add(box.id, 'button', '按钮');
  final card = add('root', 'card');
  return (doc, {'a': a.id, 'box': box.id, 'b': b.id, 'btn': btn.id, 'card': card.id});
}

void main() {
  setUp(lcClipboardClear);

  group('剪贴板', () {
    test('一开始是空的：粘贴不了，文档不变', () {
      final (doc, id) = _page();
      final before = doc.encode();
      expect(lcClipboardHasContent, isFalse);
      expect(lcClipboardPasteAfter(doc, id['a']!), isNull);
      expect(doc.encode(), before);
    });

    test('页面本身不能复制', () {
      final (doc, _) = _page();
      expect(lcClipboardCopy(doc, 'root'), isFalse);
      expect(lcClipboardHasContent, isFalse);
    });

    test('复制不改文档；粘贴到它后面：整棵子树、编号全新、属性和样式一样', () {
      final (doc, id) = _page();
      doc.find(id['box']!)!.style['background-color'] = '#ff0000';
      final before = doc.encode();
      expect(lcClipboardCopy(doc, id['box']!), isTrue);
      expect(doc.encode(), before);

      final oldIds = _ids(doc.root).toSet();
      final pasted = lcClipboardPasteAfter(doc, id['a']!)!;
      final root = doc.root.children;
      expect(root.map((n) => n.id).toList(), [id['a'], pasted, id['box'], id['card']]);
      final copy = doc.find(pasted)!, src = doc.find(id['box']!)!;
      expect(_ids(copy).toSet().intersection(oldIds), isEmpty);
      expect(_ids(doc.root).toSet().length, _ids(doc.root).length, reason: '全页没有重复的编号');
      expect(copy.style, src.style);
      expect(copy.children.map((n) => n.type).toList(), ['text', 'button']);
      expect(copy.children.first.props['text'], 'B');
    });

    test('可以连着贴好几次；贴进去以后再改原件，剪贴板里的不跟着变', () {
      final (doc, id) = _page();
      lcClipboardCopy(doc, id['a']!);
      doc.find(id['a']!)!.props['text'] = '改了';
      final one = lcClipboardPaste(doc, id['card']!)!, two = lcClipboardPaste(doc, id['card']!)!;
      expect(one, isNot(two));
      expect(doc.find(id['card']!)!.children.map((n) => n.props['text']).toList(), ['A', 'A']);
    });

    test('只能贴进容器；贴不了时文档不变', () {
      final (doc, id) = _page();
      lcClipboardCopy(doc, id['a']!);
      final before = doc.encode();
      expect(lcClipboardPaste(doc, id['btn']!), isNull);
      expect(lcClipboardPaste(doc, '没有这个'), isNull);
      expect(doc.encode(), before);
    });

    test('积木逻辑不跟着复制', () {
      final (doc, id) = _page();
      doc.logic.addHandler('click', target: id['btn']!);
      lcClipboardCopy(doc, id['btn']!);
      final pasted = lcClipboardPasteAfter(doc, id['btn']!)!;
      expect(doc.logic.handlersFor(pasted), isEmpty);
      expect(doc.logic.handlersFor(id['btn']!), hasLength(1));
    });

    test('跨页面粘贴：用到的自定义组件一起带过去，实例指向带过去的那个', () {
      final (doc, id) = _page();
      final r = saveAsComponent(doc, id['box']!, '卡片头');
      expect(r.ok, isTrue);
      final instance = doc.root.children.firstWhere((n) => n.type == 'component');
      lcClipboardCopy(doc, instance.id);
      expect(lcClipboardHasInstances, isTrue);

      // 另一页：已经有一个编号一样、内容不一样的组件，名字也撞了。
      final (other, oid) = _page();
      expect(saveAsComponent(other, oid['a']!, '卡片头').ok, isTrue);
      final clash = other.components.single;
      expect(clash.id, doc.components.single.id, reason: '这个用例要的就是编号撞上');
      final pasted = lcClipboardPaste(other, 'root')!;
      expect(other.components, hasLength(2));
      final brought = other.components.last;
      expect(brought.id, isNot(clash.id));
      expect(brought.name, isNot(clash.name));
      expect(other.find(pasted)!.props['ref'], brought.id);
      expect(brought.root.children.map((n) => n.type).toList(), ['text', 'button']);
      // 页面还能原样存、原样读。
      expect(LcDocument.parse(other.encode()).encode(), other.encode());

      // 再贴一次：一模一样的那个已经在了，不重复带。
      lcClipboardPaste(other, 'root');
      expect(other.components, hasLength(2));
    });

    test('同一页里粘贴实例：不多出组件定义', () {
      final (doc, id) = _page();
      saveAsComponent(doc, id['box']!, '卡片头');
      final instance = doc.root.children.firstWhere((n) => n.type == 'component');
      lcClipboardCopy(doc, instance.id);
      final pasted = lcClipboardPasteAfter(doc, instance.id)!;
      expect(doc.components, hasLength(1));
      expect(doc.find(pasted)!.props['ref'], doc.components.single.id);
    });
  });

  group('包成容器', () {
    test('原地多一层容器，里面只有它；导出的网页里它的内容不变', () {
      final (doc, id) = _page();
      final box = wrapInContainer(doc, id['btn']!)!;
      final parent = doc.find(id['box']!)!;
      expect(parent.children.map((n) => n.id).toList(), [id['b'], box]);
      expect(doc.find(box)!.type, 'container');
      expect(doc.find(box)!.children.single.id, id['btn']);
      expect(doc.find(box)!.props.containsKey('padding'), isFalse, reason: '新容器不自带留白');
      expect(exportHtml(doc).html, contains('按钮'));
    });

    test('页面本身、不存在的组件包不了，文档不变', () {
      final (doc, _) = _page();
      final before = doc.encode();
      expect(wrapInContainer(doc, 'root'), isNull);
      expect(wrapInContainer(doc, 'x'), isNull);
      expect(doc.encode(), before);
    });
  });

  group('菜单里的操作', () {
    test('每项只走一次修改入口（一条撤销）；复制不走', () {
      final (doc, id) = _page();
      var edits = 0;
      void apply(void Function(LcDocument d) change) {
        edits++;
        change(doc);
      }

      expect(runLcNodeAction('clip', doc, id['a']!, apply), (true, id['a']));
      expect(edits, 0);
      final (ok, sel) = runLcNodeAction('paste', doc, id['a']!, apply);
      expect((ok, edits), (true, 1));
      expect(doc.root.children[1].id, sel);
      final (_, dup) = runLcNodeAction('dup', doc, id['card']!, apply);
      expect(edits, 2);
      expect(doc.find(dup!)!.type, 'card');
      final (_, wrapped) = runLcNodeAction('wrap', doc, id['a']!, apply);
      expect(doc.find(wrapped!)!.children.single.id, id['a']);
      expect(runLcNodeAction('down', doc, wrapped, apply), (true, wrapped));
      expect(doc.root.children.first.id, isNot(wrapped));
      expect(runLcNodeAction('delete', doc, id['a']!, apply), (false, null), reason: '删除要先问人，由页面自己做');
      expect(runLcNodeAction('pasteInto', doc, 'root', apply).$1, isTrue);
      expect(doc.root.children.last.props['text'], 'A');
    });
  });

  group('图层面板的行', () {
    test('按层排；折起来的只显示自己', () {
      final (doc, id) = _page();
      final all = layerRows(doc.root, const {});
      expect(all.map((r) => (r.node.id, r.depth)).toList(), [('root', 0), (id['a'], 1), (id['box'], 1), (id['b'], 2), (id['btn'], 2), (id['card'], 1)]);
      final folded = layerRows(doc.root, {id['box']!, id['card']!});
      expect(folded.map((r) => r.node.id).toList(), ['root', id['a'], id['box'], id['card']]);
      expect(folded[2].collapsed, isTrue);
      expect(folded[3].collapsed, isFalse, reason: '空容器没有可折的');
    });
  });

  group('图层面板拖动的落点', () {
    const h = 44.0, w = 390.0;
    // 行号：0 页面 / 1 文字A / 2 容器 / 3 文字B / 4 按钮 / 5 卡片
    LayerDrop? at(LcDocument doc, String drag, int row, {bool lower = false, bool right = false, Set<String> collapsed = const {}}) =>
        layerDropTarget(doc.root, layerRows(doc.root, collapsed), drag, row * h + (lower ? 33 : 11), right ? 300 : 60, rowHeight: h, width: w);

    /// 照落点真的挪一下，返回全页的顺序。
    List<String> moved(LcDocument doc, String drag, LayerDrop d) {
      expect(doc.move(drag, d.parentId, d.index), isTrue);
      return _ids(doc.root);
    }

    test('拖到另一行的上半 / 下半＝放在它前面 / 后面', () {
      var (doc, id) = _page();
      var d = at(doc, id['card']!, 1)!; // 卡片 → 文字A 的上半
      expect((d.parentId, d.index, d.line, d.into), ('root', 0, 1, false));
      expect(moved(doc, id['card']!, d), ['root', id['card'], id['a'], id['box'], id['b'], id['btn']]);

      (doc, id) = _page();
      d = at(doc, id['a']!, 3, lower: true)!; // 文字A → 文字B 的下半（进了容器）
      expect((d.parentId, d.index, d.line), (id['box'], 1, 4));
      expect(moved(doc, id['a']!, d), ['root', id['box'], id['b'], id['a'], id['btn'], id['card']]);
    });

    test('拖到容器那一行的右半边＝放进它里面（排最后）', () {
      final (doc, id) = _page();
      final d = at(doc, id['a']!, 5, right: true)!;
      expect((d.parentId, d.index, d.into, d.line), (id['card'], 0, true, 5));
      expect(moved(doc, id['a']!, d), ['root', id['box'], id['b'], id['btn'], id['card'], id['a']]);
    });

    test('展开着的容器的下半行＝放成它里面的第一个；折着的＝放在它后面', () {
      var (doc, id) = _page();
      var d = at(doc, id['card']!, 2, lower: true)!;
      expect((d.parentId, d.index), (id['box'], 0));
      (doc, id) = _page();
      d = at(doc, id['a']!, 2, lower: true, collapsed: {id['box']!})!;
      expect((d.parentId, d.index), ('root', 2));
      expect(moved(doc, id['a']!, d), ['root', id['box'], id['b'], id['btn'], id['a'], id['card']]);
    });

    test('不能放进自己或自己里面；原地不算；页面那一行只能放进去', () {
      final (doc, id) = _page();
      expect(at(doc, id['box']!, 2, right: true), isNull, reason: '自己');
      expect(at(doc, id['box']!, 3), isNull, reason: '自己里面');
      expect(at(doc, id['box']!, 1, lower: true), isNull, reason: '已经紧跟在文字A 后面');
      expect(at(doc, id['box']!, 5), isNull, reason: '已经紧挨在卡片前面');
      expect(at(doc, id['a']!, 1), isNull, reason: '自己那一行');
      final d = at(doc, id['b']!, 0)!;
      expect((d.parentId, d.index, d.into), ('root', 3, true));
      expect(at(doc, '没有', 1), isNull);
    });

    test('每个组件拖到每个位置：算出的落点真的挪得动，挪完一个不多一个不少', () {
      final (base, _) = _page();
      final ids = _ids(base.root).skip(1).toList();
      var tried = 0;
      for (final drag in ids) {
        for (var row = 0; row < 6; row++) {
          for (final lower in [false, true]) {
            for (final right in [false, true]) {
              final (doc, _) = _page();
              final d = at(doc, drag, row, lower: lower, right: right);
              if (d == null) continue;
              tried++;
              final before = doc.encode();
              expect(doc.move(drag, d.parentId, d.index), isTrue, reason: '$drag → 行 $row');
              expect(_ids(doc.root).toSet(), _ids(base.root).toSet());
              expect(doc.encode(), isNot(before), reason: '$drag → 行 $row 下半=$lower 右=$right：算出了落点却没挪动');
            }
          }
        }
      }
      expect(tried, greaterThan(40));
    });
  });

  group('项目里的图片', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lc_img_');
      guard = PathGuard(tmp.path);
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    test('拷进 images/，返回相对地址；名字里的怪字符换掉，没有后缀当 jpg', () async {
      final rel = await lcImportImage(guard, 'IMG 2026(1).PNG', Uint8List.fromList([1, 2, 3]));
      expect(rel, 'images/IMG-2026-1.png');
      expect(File(p.join(tmp.path, rel)).readAsBytesSync(), [1, 2, 3]);
      expect(await lcImportImage(guard, '../../etc/x', Uint8List.fromList([9])), 'images/x.jpg');
      expect(await lcImportImage(guard, '', Uint8List.fromList([8])), 'images/image.jpg');
      expect(Directory(tmp.path).listSync().map((e) => p.basename(e.path)).toList(), ['images'], reason: '没有写到 images/ 外面');
    });

    test('重名：内容一样直接用已有的，不一样加序号，不覆盖', () async {
      final a = await lcImportImage(guard, 'a.png', Uint8List.fromList([1]));
      expect(await lcImportImage(guard, 'a.png', Uint8List.fromList([1])), a);
      final b = await lcImportImage(guard, 'a.png', Uint8List.fromList([2]));
      expect(b, 'images/a-2.png');
      expect(File(p.join(tmp.path, a)).readAsBytesSync(), [1]);
      expect(await lcImportImage(guard, 'a.png', Uint8List.fromList([2])), b);
    });

    test('地址怎么认：网址不是文件；跑出项目的、不是图片的一律不读', () async {
      await lcImportImage(guard, 'a.png', Uint8List.fromList([1]));
      expect(lcResolveImage(guard, 'images/a.png'), p.join(guard.root, 'images', 'a.png'));
      expect(lcResolveImage(guard, ' images/a.png?v=2 '), p.join(guard.root, 'images', 'a.png'));
      for (final bad in [
        'https://x.com/a.png',
        'data:image/png;base64,AAAA',
        '//x.com/a.png',
        '../a.png',
        'images/../../a.png',
        '/etc/passwd',
        '/etc/a.png',
        'file:///a.png',
        'images/a.txt',
        '',
        '.lopicode/a.png',
      ]) {
        expect(lcResolveImage(guard, bad), isNull, reason: bad);
      }
      expect(lcIsRemoteSrc('HTTPS://x.com/a.png'), isTrue);
      expect(lcIsRemoteSrc('images/a.png'), isFalse);
    });

    test('列出项目里的图片：images/ 的排前面；隐藏目录、node_modules 不看', () async {
      for (final f in ['images/b.png', 'images/a.jpg', 'pic/z.webp', 'logo.svg', 'readme.md', '.lopicode/x.png', 'node_modules/m/y.png', 'build/o.png']) {
        File(p.join(tmp.path, f))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([0]);
      }
      expect(await lcListProjectImages(guard), ['images/a.jpg', 'images/b.png', 'logo.svg', 'pic/z.webp']);
    });

    test('导出 Vue / React：页面和自定义组件里用到的项目图片拷到 <目录>/public/ 下，网址和读不到的不拷', () async {
      final (doc, id) = _page();
      await lcImportImage(guard, 'a.png', Uint8List.fromList([1, 2]));
      File(p.join(tmp.path, 'pic', 'b.jpg'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([3]);
      for (final src in ['images/a.png', 'images/a.png', 'https://x.com/c.png', 'images/没有.png', '../out.png']) {
        doc.insert('root', doc.newNode('image')..props['src'] = src);
      }
      doc.insert(id['box']!, doc.newNode('image')..props['src'] = 'pic/b.jpg');
      expect(saveAsComponent(doc, id['box']!, '带图').ok, isTrue);
      expect(lcLocalImageSrcs(doc), ['images/a.png', 'images/没有.png', '../out.png', 'pic/b.jpg']);
      expect(await lcCopyExportImages(guard, 'export/vue', doc), 2);
      expect(File(p.join(tmp.path, 'export/vue/public/images/a.png')).readAsBytesSync(), [1, 2]);
      expect(File(p.join(tmp.path, 'export/vue/public/pic/b.jpg')).readAsBytesSync(), [3]);
      expect(Directory(p.join(tmp.path, 'export/vue/public')).listSync(recursive: true).whereType<File>(), hasLength(2));
    });

    test('导出：网页原样写相对地址；Flutter 代码里项目图片用 Image.asset、网址用 Image.network', () {
      final (doc, _) = _page();
      final local = doc.newNode('image')..props['src'] = 'images/a.png';
      final remote = doc.newNode('image')..props['src'] = 'https://x.com/b.png';
      doc
        ..insert('root', local)
        ..insert('root', remote);
      expect(exportHtml(doc).html, contains('src="images/a.png"'));
      final dart = exportDart(doc);
      expect(dart, contains("Image.asset('images/a.png'"));
      expect(dart, contains("Image.network('https://x.com/b.png'"));
    });
  });

  group('编辑器自己的状态文件', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lc_state_');
      guard = PathGuard(tmp.path);
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    test('“常用”和“图层折叠”各记各的，互不覆盖；同时存也不丢', () async {
      await Future.wait([
        savePaletteRecent(guard, ['text', 'button']),
        saveLayersCollapsed(guard, {'n3', 'n1'}),
      ]);
      expect(await loadPaletteRecent(guard), ['text', 'button']);
      expect(await loadLayersCollapsed(guard), {'n1', 'n3'});
      await savePaletteRecent(guard, ['image']);
      expect(await loadLayersCollapsed(guard), {'n1', 'n3'});
      await saveLayersCollapsed(guard, {});
      expect(await loadPaletteRecent(guard), ['image']);
      expect(await loadLayersCollapsed(guard), isEmpty);
    });

    test('文件里别人写的项原样留着', () async {
      final f = File(p.join(tmp.path, '.lopicode', 'lowcode-editor.json'))..parent.createSync(recursive: true);
      f.writeAsStringSync('{"recent":["text"],"以后的东西":{"a":1}}');
      await saveLayersCollapsed(guard, {'n2'});
      expect(f.readAsStringSync(), contains('"以后的东西":{"a":1}'));
      expect(await loadPaletteRecent(guard), ['text']);
    });
  });
}
