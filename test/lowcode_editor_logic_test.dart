// 低代码编辑器第 5 版第 1 期的纯逻辑：组件盒目录（分类 / 搜索 / 常用）、常用的存盘、存盘合并、拖动落点、边缘自动滚、尺寸标签位置。
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/editor_recents.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/save_queue.dart';

List<String> keysOf(List<PaletteEntry> list) => [for (final e in list) e.key];

const builtinKeys = [
  'component:lib_lopi_builtin_iconButton',
  'component:lib_lopi_builtin_link',
  'component:lib_lopi_builtin_grid',
  'component:lib_lopi_builtin_scroll',
  'component:lib_lopi_builtin_stepper',
  'component:lib_lopi_builtin_formItem',
];

void main() {
  group('组件盒目录', () {
    final mine = [
      LcComponentDef(
        id: 'c1',
        name: '问候卡',
        root: LcNode(id: 'k1', type: 'card'),
      ),
      LcComponentDef(
        id: 'c2',
        name: '价格表',
        root: LcNode(id: 'k2', type: 'card'),
      ),
    ];
    final all = paletteEntries(mine);

    test('全部条目：内置的一个不少、顺序不变，自定义组件排在后面', () {
      // 第四轮 B5：原生控件后面多了内置组件库里进组件盒的六个
      expect(keysOf(all), [...lcPaletteTypes, ...builtinKeys, 'component:c1', 'component:c2']);
      expect(all.last.label, '价格表');
      expect(all.last.group, PaletteGroup.mine);
    });

    test('分类：每个内置组件都归到一类里，一个不漏；没有自定义组件时不显示“我的”', () {
      final grouped = <String>{};
      for (final g in PaletteGroup.values) {
        if (g == PaletteGroup.recent || g == PaletteGroup.mine) continue;
        final inGroup = keysOf(paletteInGroup(all, g, const []));
        expect(inGroup, isNotEmpty, reason: g.label);
        expect(grouped.intersection(inGroup.toSet()), isEmpty, reason: '一个组件只在一类里');
        grouped.addAll(inGroup);
      }
      expect(grouped, {...lcPaletteTypes, ...builtinKeys});
      expect(keysOf(paletteInGroup(all, PaletteGroup.layout, const [])), [
        'container',
        'row',
        'column',
        'card',
        'spacer',
        'dialog',
        'component:lib_lopi_builtin_grid',
        'component:lib_lopi_builtin_scroll',
      ]);
      expect(keysOf(paletteInGroup(all, PaletteGroup.mine, const [])), ['component:c1', 'component:c2']);
      expect([for (final g in paletteGroups(all)) g.label], ['常用', '布局', '基础', '表单', '展示', '导航', '我的']);
      expect([for (final g in paletteGroups(paletteEntries(const []))) g.label], ['常用', '布局', '基础', '表单', '展示', '导航']);
    });

    test('常用：没用过是内置的 8 个起步组件；用过的排前面、不重复、最多 8 个；已经不存在的跳过', () {
      expect(keysOf(paletteRecent(all, const [])), kPaletteStarters);
      expect(kPaletteStarters.length, kPaletteRecentMax);
      final recent = keysOf(paletteRecent(all, const ['divider', 'component:c2', 'component:gone', 'text']));
      expect(recent.take(3), ['divider', 'component:c2', 'text']);
      expect(recent.length, kPaletteRecentMax);
      expect(recent.toSet().length, recent.length);
      expect(recent, isNot(contains('component:gone')));
    });

    test('用了一个：排到最前，重复的去掉，最多留 8 个', () {
      var keys = <String>[];
      for (final k in ['text', 'button', 'text', 'image']) {
        keys = paletteTouch(keys, k);
      }
      expect(keys, ['image', 'text', 'button']);
      for (var i = 0; i < 20; i++) {
        keys = paletteTouch(keys, 'k$i');
      }
      expect(keys.length, kPaletteRecentMax);
      expect(keys.first, 'k19');
    });

    test('PaletteRecents：变了才通知；连着用同一个不重复通知', () {
      final seen = <List<String>>[];
      final r = PaletteRecents(onChanged: seen.add);
      r.touch('text');
      r.touch('text');
      r.touch('button');
      expect(seen, [
        ['text'],
        ['button', 'text'],
      ]);
      expect(r.keys, ['button', 'text']);
    });

    test('搜索：按名字、中文别名、英文、拼音；不分大小写、去首尾空格；自定义组件按名字', () {
      // 第四轮 B5：多了“图标按钮”，搜“按钮”它也在
      expect(keysOf(paletteSearch(all, '按钮')), ['button', 'component:lib_lopi_builtin_iconButton']);
      expect(keysOf(paletteSearch(all, ' BUTTON ')), ['button', 'component:lib_lopi_builtin_iconButton']);
      expect(keysOf(paletteSearch(all, 'btn')), ['button']);
      expect(keysOf(paletteSearch(all, 'anniu')), ['button', 'component:lib_lopi_builtin_iconButton']);
      expect(keysOf(paletteSearch(all, '图')), contains('image'));
      expect(keysOf(paletteSearch(all, '输入')), ['input', 'textarea']);
      expect(keysOf(paletteSearch(all, '问候')), ['component:c1']);
      expect(keysOf(paletteSearch(all, '价')), ['component:c2']);
      expect(paletteSearch(all, '根本没有这个'), isEmpty);
      expect(paletteSearch(all, '   '), all, reason: '空的搜索词＝全部');
      // 每个内置组件用自己的名字都搜得到自己
      for (final type in lcPaletteTypes) {
        expect(keysOf(paletteSearch(all, lcSpecs[type]!.label)), contains(type), reason: type);
      }
    });
  });

  group('常用的存盘（.lopicode/lowcode-editor.json）', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_recent_');
      guard = PathGuard(tmp.path);
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    test('没有文件：空表，不建文件', () async {
      expect(await loadPaletteRecent(guard), isEmpty);
      expect(tmp.listSync(recursive: true), isEmpty);
    });

    test('存了再读：原样回来；只留前 8 个；存在内部目录里，不在项目根目录', () async {
      await savePaletteRecent(guard, ['text', 'component:c1', for (var i = 0; i < 20; i++) 'k$i']);
      final back = await loadPaletteRecent(guard);
      expect(back.length, kPaletteRecentMax);
      expect(back.take(2), ['text', 'component:c1']);
      expect(File('${tmp.path}/.lopicode/lowcode-editor.json').existsSync(), isTrue);
      expect([for (final e in tmp.listSync()) e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)], ['.lopicode']);
    });

    test('条目类型不对的跳过，读到哪算哪', () async {
      File('${tmp.path}/.lopicode/lowcode-editor.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"recent": ["text", 5, null, "", {"a": 1}, "button"]}');
      expect(await loadPaletteRecent(guard), ['text', 'button']);
    });
  });

  group('存盘合并', () {
    testWidgets('连着改好几下：停手 0.4 秒后只写一次，写的是最后的内容', (tester) async {
      var value = 0;
      final written = <int>[];
      final states = <SaveState>[];
      final q = SaveQueue<int>(snapshot: () => value, write: (v) async => written.add(v), describeError: (e) => '$e', onState: states.add);
      for (var i = 1; i <= 5; i++) {
        value = i;
        q.markDirty();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(written, isEmpty, reason: '还在改，不写');
      expect(q.state, SaveState.pending);
      await tester.pump(const Duration(milliseconds: 399));
      await tester.pump();
      expect(written, [5]);
      expect(q.writes, 1);
      expect(q.state, SaveState.saved);
      expect(states, [SaveState.pending, SaveState.saved]);
    });

    testWidgets('flush：有没存的立刻写并等它写完；没有改动时不写', (tester) async {
      var value = 1;
      final written = <int>[];
      final q = SaveQueue<int>(snapshot: () => value, write: (v) async => written.add(v), describeError: (e) => '$e');
      var done = false;
      unawaited(q.flush().then((_) => done = true));
      await tester.pump();
      expect(written, isEmpty);
      expect(done, isTrue);
      value = 2;
      q.markDirty();
      done = false;
      unawaited(q.flush().then((_) => done = true));
      await tester.pump();
      expect(written, [2]);
      expect(done, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(written, [2], reason: 'flush 过了，到点不再写第二次');
    });

    testWidgets('一次写入没做完时又改了：排在后面再写一次，不会两次同时写', (tester) async {
      var value = 1, running = 0, maxRunning = 0;
      final written = <int>[];
      final q = SaveQueue<int>(
        snapshot: () => value,
        write: (v) async {
          running++;
          maxRunning = running > maxRunning ? running : maxRunning;
          await Future<void>.delayed(const Duration(seconds: 1));
          written.add(v);
          running--;
        },
        describeError: (e) => '$e',
      );
      q.markDirty();
      await tester.pump(const Duration(milliseconds: 500)); // 第一次写开始了，还没完
      value = 2;
      q.markDirty();
      await tester.pump(const Duration(milliseconds: 450));
      expect(q.state, SaveState.pending);
      await tester.pump(const Duration(seconds: 3));
      expect(written, [1, 2]);
      expect(maxRunning, 1);
      expect(q.state, SaveState.saved);
    });

    testWidgets('第一次写完时第二次已经排上队了：还不算“已保存”，等第二次也写完才算（多页面存盘慢了才露出来的）', (tester) async {
      var value = 1;
      final written = <int>[];
      final states = <SaveState>[];
      final q = SaveQueue<int>(
        snapshot: () => value,
        write: (v) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          written.add(v);
        },
        describeError: (e) => '$e',
        onState: states.add,
      );
      q.markDirty();
      await tester.pump(const Duration(milliseconds: 500)); // 第一次写开始了（400 毫秒时），要到 1400 毫秒才完
      value = 2;
      q.markDirty();
      await tester.pump(const Duration(milliseconds: 450)); // 第二次到点了，排在第一次后面
      await tester.pump(const Duration(milliseconds: 500)); // 第一次写完了，第二次刚开始
      expect(written, [1]);
      expect(q.state, SaveState.pending, reason: '还有一次没写完');
      expect(states, [SaveState.pending]);
      await tester.pump(const Duration(seconds: 2));
      expect(written, [1, 2]);
      expect(states, [SaveState.pending, SaveState.saved]);
    });

    testWidgets('没存上：状态是 failed、原因写清；下一次修改照常再存；连着两次没存上每次都通知', (tester) async {
      var fail = true;
      final states = <SaveState>[];
      final q = SaveQueue<int>(
        snapshot: () => 1,
        write: (v) async {
          if (fail) throw const FileSystemException('写不进去', '/x/page.lc.json', OSError('No space left on device', 28));
        },
        describeError: describeSaveError,
        onState: states.add,
      );
      q.markDirty();
      await tester.pump(const Duration(seconds: 1));
      expect(q.state, SaveState.failed);
      expect(q.lastError, 'No space left on device（/x/page.lc.json）');
      q.markDirty();
      await tester.pump(const Duration(seconds: 1));
      expect(states.where((s) => s == SaveState.failed).length, 2);
      fail = false;
      q.markDirty();
      await tester.pump(const Duration(seconds: 1));
      expect(q.state, SaveState.saved);
      expect(q.lastError, isNull);
    });

    testWidgets('dispose：没存的照样存完，之后不再通知界面、不再接新的', (tester) async {
      final written = <int>[];
      final states = <SaveState>[];
      final q = SaveQueue<int>(snapshot: () => 7, write: (v) async => written.add(v), describeError: (e) => '$e', onState: states.add);
      q.markDirty();
      unawaited(q.dispose());
      await tester.pump();
      expect(written, [7]);
      expect(states, [SaveState.pending]);
      q.markDirty();
      await tester.pump(const Duration(seconds: 1));
      expect(written, [7]);
    });

    test('describeSaveError：系统给的原因优先；没有就用异常自己的话；路径守卫的话原样', () {
      expect(describeSaveError(const FileSystemException('Cannot open file', '/a/b', OSError('Permission denied', 13))), 'Permission denied（/a/b）');
      expect(describeSaveError(const FileSystemException('Cannot open file', '/a/b')), 'Cannot open file（/a/b）');
      expect(describeSaveError(const FileSystemException('')), '写不进文件');
      expect(describeSaveError(PathGuardException('路径越界')), '路径越界');
    });
  });

  group('拖动落点', () {
    // 页面 300 宽，竖着排三样：文字 a（0–40）、卡片 card（50–200，里面竖着排 x、y）、行 row（210–260，里面横着排 p、q）
    const a = DropBox(id: 'a', label: '文本', rect: Rect.fromLTWH(10, 0, 280, 40));
    const x = DropBox(id: 'x', label: '文本', rect: Rect.fromLTWH(20, 60, 260, 40));
    const y = DropBox(id: 'y', label: '按钮', rect: Rect.fromLTWH(20, 110, 80, 40));
    const card = DropBox(id: 'card', label: '卡片', rect: Rect.fromLTWH(10, 50, 280, 150), container: true, children: [x, y]);
    const p = DropBox(id: 'p', label: '文本', rect: Rect.fromLTWH(10, 210, 100, 50));
    const q = DropBox(id: 'q', label: '文本', rect: Rect.fromLTWH(120, 210, 100, 50));
    const row = DropBox(id: 'row', label: '行', rect: Rect.fromLTWH(10, 210, 280, 50), container: true, row: true, children: [p, q]);
    const empty = DropBox(id: 'empty', label: '容器', rect: Rect.fromLTWH(10, 270, 280, 48), container: true);
    const root = DropBox(id: 'root', label: '页面', rect: Rect.fromLTWH(0, 0, 300, 400), container: true, children: [a, card, row, empty]);
    bool any(String _) => true;
    DropTarget? pick(Offset at, {Set<String> armed = const {}, String? moving, bool Function(String)? can}) => pickDropTarget(root, at, armed: armed, canDrop: can ?? any, movingId: moving);

    test('页面里：按越过了几个子项的中点算第几个；蓝线是 3 像素的横线，夹在前后两个中间', () {
      final first = pick(const Offset(150, 5))!;
      expect((first.parentId, first.index, first.ordinal), ('root', 0, 1));
      expect(first.line!.height, kDropLineWidth);
      expect(first.line!.bottom, lessThanOrEqualTo(a.rect.top + kDropLineWidth), reason: '在最前：贴着第一个的上沿');
      final second = pick(const Offset(150, 45))!;
      expect((second.index, second.label), (1, '放到 页面 里 · 第 2 个'));
      expect(second.line!.center.dy, 45, reason: '夹在 a 的下沿 40 和卡片的上沿 50 中间');
      expect(second.line!.left, 10);
      expect(second.line!.right, 290);
      final last = pick(const Offset(150, 390))!;
      expect((last.index, last.ordinal), (4, 5));
      expect(last.inside, isFalse);
    });

    test('手指在卡片上：没停够先算“放在它前面 / 后面”；停够了才放进它里面', () {
      final before = pick(const Offset(150, 70))!;
      expect((before.parentId, before.index), ('root', 1));
      final after = pick(const Offset(150, 180))!;
      expect((after.parentId, after.index), ('root', 2));
      final inside = pick(const Offset(150, 105), armed: {'card'})!;
      expect((inside.parentId, inside.index, inside.label), ('card', 1, '放到 卡片 里 · 第 2 个'));
      expect(inside.inside, isTrue, reason: '停够了才进去的容器要描边');
      expect(inside.line!.center.dy, 105);
    });

    test('横着排的容器里：蓝线是竖线', () {
      final t = pick(const Offset(115, 235), armed: {'row'})!;
      expect((t.parentId, t.index), ('row', 1));
      expect(t.line!.width, kDropLineWidth);
      expect(t.line!.center.dx, 115);
      expect(t.line!.height, 50);
      expect(pick(const Offset(250, 235), armed: {'row'})!.index, 2);
    });

    test('倒着排的容器：反过来数', () {
      const rev = DropBox(
        id: 'rev',
        label: '行',
        rect: Rect.fromLTWH(0, 0, 300, 50),
        container: true,
        row: true,
        reverse: true,
        children: [
          DropBox(id: 'r1', label: '文本', rect: Rect.fromLTWH(200, 0, 100, 50)), // 第 1 个在最右
          DropBox(id: 'r2', label: '文本', rect: Rect.fromLTWH(90, 0, 100, 50)),
        ],
      );
      DropTarget at(double dx) => pickDropTarget(rev, Offset(dx, 25), armed: const {}, canDrop: any)!;
      expect(at(290).index, 0);
      expect(at(195).index, 1);
      expect(at(195).line!.center.dx, 195);
      expect(at(10).index, 2);
    });

    test('空容器：不用等，直接放进去；没有线，整块高亮', () {
      final t = pick(const Offset(150, 290))!;
      expect((t.parentId, t.index, t.ordinal), ('empty', 0, 1));
      expect(t.line, isNull);
      expect(t.inside, isTrue);
      expect(t.parentRect, empty.rect);
    });

    test('挪已有的组件：放回原地 / 紧挨着自己前后＝原地不动；“第几个”不把自己算两遍', () {
      final same = pick(const Offset(150, 5), moving: 'a')!;
      expect(same.noop, isTrue);
      expect(pick(const Offset(150, 45), moving: 'a')!.noop, isTrue);
      final down = pick(const Offset(150, 390), moving: 'a')!;
      expect(down.noop, isFalse);
      expect((down.index, down.ordinal), (4, 4), reason: '插到第 4 个后面，挪走自己以后它是第 4 个');
      final up = pick(const Offset(150, 5), moving: 'row')!;
      expect((up.index, up.ordinal, up.noop), (0, 1, false));
    });

    test('不能放进自己里面：手指在自己身上时落点在上一层', () {
      final t = pick(const Offset(150, 105), armed: {'card'}, moving: 'card')!;
      expect(t.parentId, 'root');
      expect(t.noop, isTrue);
    });

    test('调用方说不能放的容器往上一层找；一层都不行就没有落点', () {
      final t = pick(const Offset(150, 105), armed: {'card'}, can: (id) => id != 'card')!;
      expect(t.parentId, 'root');
      expect(pick(const Offset(150, 290), can: (id) => id != 'empty')!.parentId, 'root');
      expect(pick(const Offset(150, 105), can: (_) => false), isNull);
    });

    test('手指在页面外面：按最近的页面里的点算', () {
      expect(pick(const Offset(150, -500))!.index, 0);
      expect(pick(const Offset(-80, 9000))!.index, 4);
    });

    test('sameSpot：同一个容器同一个位置算同一个落点', () {
      expect(pick(const Offset(150, 45))!.sameSpot(pick(const Offset(60, 47))), isTrue);
      expect(pick(const Offset(150, 45))!.sameSpot(pick(const Offset(150, 5))), isFalse);
      expect(pick(const Offset(150, 45))!.sameSpot(null), isFalse);
    });
  });

  group('边缘自动滚', () {
    test('离边缘 64 以内才滚；越靠边越快；到边外面按最快；中间不滚', () {
      expect(autoScrollSpeed(400, 100, 700), 0);
      expect(autoScrollSpeed(100 + kAutoScrollEdge, 100, 700), 0);
      expect(autoScrollSpeed(700 - kAutoScrollEdge, 100, 700), 0);
      final slow = autoScrollSpeed(690 - 40, 100, 700), fast = autoScrollSpeed(695, 100, 700);
      expect(slow, greaterThan(0));
      expect(fast, greaterThan(slow));
      expect(autoScrollSpeed(900, 100, 700), kAutoScrollMax);
      expect(autoScrollSpeed(120, 100, 700), lessThan(0));
      expect(autoScrollSpeed(-50, 100, 700), -kAutoScrollMax);
    });

    test('可滚的那一段太短（放不下两条边缘）：不滚', () {
      expect(autoScrollSpeed(10, 0, 100), 0);
    });
  });

  group('尺寸标签放哪', () {
    const visible = Rect.fromLTWH(0, 0, 390, 700);
    const text = '160 × 48';

    test('放得下：在选中框里面的右下角', () {
      const rect = Rect.fromLTWH(20, 100, 300, 120);
      final at = sizeLabelOrigin(rect, visible, 1, text);
      expect(rect.contains(at), isTrue);
      expect(at.dx, greaterThan(rect.center.dx));
      expect(at.dy, greaterThan(rect.center.dy));
      expect(at.dy + 19, lessThanOrEqualTo(rect.bottom));
    });

    test('框太小：放到框的上方，不盖住框', () {
      const rect = Rect.fromLTWH(40, 200, 64, 30);
      final at = sizeLabelOrigin(rect, visible, 1, '64 × 30');
      expect(at.dy + 19, lessThanOrEqualTo(rect.top));
    });

    test('框太小又贴着屏幕顶：放到下方', () {
      const rect = Rect.fromLTWH(40, 4, 64, 30);
      final at = sizeLabelOrigin(rect, visible, 1, '64 × 30');
      expect(at.dy, greaterThanOrEqualTo(rect.bottom));
    });

    // 第 3 期第 3 段：看图发现标签盖住了旁边的组件（网格里跨两列的格子下面那一格、小按钮上面那行字）。
    Rect box(Offset at, String text) => at & Size(text.length * 7.0 + 12, 19);

    test('B5：选中贴着屏幕顶的顶栏，右边放着按钮：标签不压在按钮上', () {
      const bar = Rect.fromLTWH(0, 0, 390, 56);
      const t = '390 × 56';
      const right = Rect.fromLTWH(318, 8, 64, 40), below = Rect.fromLTWH(0, 56, 390, 40);
      final at = box(sizeLabelOrigin(bar, visible, 1, t, avoid: const [right, below]), t);
      expect(at.overlaps(right), isFalse, reason: '$at');
      expect(at.overlaps(below), isFalse, reason: '$at');
      // 左右都放着按钮：放正中间
      const left = Rect.fromLTWH(8, 8, 64, 40);
      final mid = box(sizeLabelOrigin(bar, visible, 1, t, avoid: const [left, right, below]), t);
      expect(mid.overlaps(left) || mid.overlaps(right) || mid.overlaps(below), isFalse, reason: '$mid');
    });

    test('上方有别的组件：换到下方；上下都有：换到左右；都不盖住旁边的', () {
      const rect = Rect.fromLTWH(16, 116, 64, 48);
      const t = '64 × 48';
      const up = Rect.fromLTWH(16, 84, 20, 24), down = Rect.fromLTWH(16, 180, 64, 40);
      expect(box(sizeLabelOrigin(rect, visible, 1, t, avoid: const [up]), t).overlaps(up), isFalse);
      final both = box(sizeLabelOrigin(rect, visible, 1, t, avoid: const [up, down]), t);
      expect(both.overlaps(up) || both.overlaps(down) || both.overlaps(rect), isFalse);
      // 截图里那两种：网格里“第 1 格”跨两列，下面是“第 3 格”“第 4 格”，右边是“第 2 格”
      const cell = Rect.fromLTWH(16, 80, 236, 24);
      const others = [Rect.fromLTWH(260, 80, 114, 24), Rect.fromLTWH(16, 112, 114, 24), Rect.fromLTWH(138, 112, 114, 24)];
      final at = box(sizeLabelOrigin(cell, visible, 1, '236 × 24', avoid: others), '236 × 24');
      expect(others.any(at.overlaps) || at.overlaps(cell), isFalse, reason: '$at');
      // 这一格贴着屏幕顶（上方露不出来）、下面右边都有格子：收进框里面的右头，不盖别的格子，也不盖左边的字
      const top = Rect.fromLTWH(16, 4, 236, 24);
      final crowded = [for (final r in others) r.shift(const Offset(0, -76))];
      final inside = box(sizeLabelOrigin(top, visible, 1, '236 × 24', avoid: crowded), '236 × 24');
      expect(crowded.any(inside.overlaps), isFalse, reason: '$inside');
      expect(inside.left, greaterThan(top.center.dx));
      expect(inside.right, lessThanOrEqualTo(top.right));
      expect(at.top >= visible.top && at.bottom <= visible.bottom && at.left >= visible.left && at.right <= visible.right, isTrue);
    });

    test('四周挤满了：用盖得最少的那个位置，照样整个露在看得见的地方', () {
      const rect = Rect.fromLTWH(160, 300, 64, 30);
      final crowd = [
        for (var x = 0.0; x < 390; x += 40)
          for (var y = 200.0; y < 420; y += 22) Rect.fromLTWH(x, y, 38, 20),
      ];
      final at = box(sizeLabelOrigin(rect, visible, 1, '64 × 30', avoid: crowd), '64 × 30');
      expect(at.overlaps(rect), isFalse);
      expect(visible.contains(at.topLeft) && visible.contains(at.bottomRight), isTrue);
    });

    test('哪些要避：自己、包着自己的容器、里面有东西的容器不避；旁边的叶子组件避', () {
      final doc = LcDocument.starter('x');
      final col = doc.newNode('column'), a = doc.newNode('text'), b = doc.newNode('text');
      doc.insert(doc.root.id, col);
      doc.insert(col.id, a);
      doc.insert(col.id, b);
      const ra = Rect.fromLTWH(0, 0, 100, 20), rb = Rect.fromLTWH(0, 24, 100, 20), rc = Rect.fromLTWH(0, 0, 100, 44);
      expect(sizeLabelAvoids(doc, a.id, ra, a.id, ra), isFalse);
      expect(sizeLabelAvoids(doc, a.id, ra, col.id, rc), isFalse);
      expect(sizeLabelAvoids(doc, a.id, ra, b.id, rb), isTrue);
      expect(sizeLabelAvoids(doc, a.id, ra, 'inst__k5', rb), isTrue, reason: '自定义组件里面画出来的东西也算');
      expect(sizeLabelAvoids(doc, a.id, ra, '${col.id}#left', rb), isFalse);
      // 第四轮 B5：选中的是容器，它里面的叶子组件也要避（顶栏右边放的按钮）
      expect(sizeLabelAvoids(doc, col.id, rc, b.id, rb), isTrue);
    });

    test('贴着屏幕边：整个标签都在看得见的那一块里', () {
      for (final rect in const [Rect.fromLTWH(-200, 100, 230, 20), Rect.fromLTWH(380, 690, 300, 300), Rect.fromLTWH(0, 650, 30, 500)]) {
        for (final scale in [0.5, 1.0, 2.0]) {
          final v = Rect.fromLTWH(0, 0, 390 / scale, 700 / scale);
          final at = sizeLabelOrigin(rect, v, scale, text);
          expect(at.dx, greaterThanOrEqualTo(v.left - 0.01), reason: '$rect @$scale');
          expect(at.dy, greaterThanOrEqualTo(v.top - 0.01), reason: '$rect @$scale');
          expect(at.dx + (text.length * 7 + 12) / scale, lessThanOrEqualTo(v.right + 0.01), reason: '$rect @$scale');
          expect(at.dy + 19 / scale, lessThanOrEqualTo(v.bottom + 0.01), reason: '$rect @$scale');
        }
      }
    });
  });
}
