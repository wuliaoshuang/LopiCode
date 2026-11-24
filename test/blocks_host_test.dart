// 前端的积木宿主（lib/lowcode/logic_block_host.dart）和画布排布（lib/blocks/block_canvas_layout.dart）的单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/blocks_fixture.dart';

double fakeMeasure(String s) => s.runes.fold(0.0, (w, r) => w + (r < 128 ? 8 : 14));

const m = BkMetrics();

LogicBlockHost hostOf(LcDocument doc) => LogicBlockHost(doc: doc, onEdit: (change) => change(doc));

BlockLayoutEngine engineOf(BlockHost host) => BlockLayoutEngine(host, fakeMeasure);

void main() {
  group('前端宿主', () {
    test('目录：事件页有三个帽子；每种积木和表达式都在某一页，颜色不是“不认识”', () {
      final host = hostOf(sampleDoc());
      expect(host.categories.first.hats.map((h) => h.id), LcHandler.events);
      for (final op in lcBlockSpecs.keys) {
        expect(host.blockColorKey(op), isNot(BlockColorKey.unknown), reason: op);
      }
      for (final e in lcExprSpecs.keys) {
        expect(host.exprColorKey(e), isNot(BlockColorKey.unknown), reason: e);
      }
      expect(host.blockColorKey('nope'), BlockColorKey.unknown);
      expect({for (final c in host.categories) c.id}.length, host.categories.length);
    });

    test('帽子：显示什么、槽位的可选项、改槽位', () {
      final doc = sampleDoc();
      final host = hostOf(doc);
      final click = host.script('h1')!, input = host.script('h2')!, load = host.script('h3')!;
      expect([for (final p in host.hatOf(click).parts) p.text], ['当', '按钮“提交”', '被点击']);
      expect(host.hatOf(load).parts.single.isSlot, isFalse);
      expect(host.hatSlotValue(click, 'target'), nodeIdOf(doc, 'button'));
      expect(host.hatSlotOptions(input, 'target').map((o) => o.value), [nodeIdOf(doc, 'input')]);
      expect(host.hatSlotOptions(click, 'target').length, greaterThan(3));
      expect(host.hatSlotOptions(load, 'target'), isEmpty);
      host.edit(() => expect(host.setHatSlot(host.script('h1')!, 'target', nodeIdOf(doc, 'text')), isTrue));
      expect((host.script('h1')! as LcHandler).target, nodeIdOf(doc, 'text'));
      expect(host.setHatSlot(host.script('h1')!, 'target', 'gone'), isFalse);
      expect(host.setHatSlot(host.script('h3')!, 'target', nodeIdOf(doc, 'text')), isFalse);
    });

    test('新建 / 删除脚本、改动通知、校验和代码', () {
      final doc = sampleDoc();
      final host = hostOf(doc);
      var changed = 0;
      host.onChanged = () => changed++;
      final rev = host.revision;
      late String id;
      host.edit(() => id = host.addScript('click', x: 40, y: 80)!.id);
      expect(changed, 1);
      expect(host.revision, rev + 1);
      final added = host.script(id)! as LcHandler;
      expect(added.target, nodeIdOf(doc, 'button'));
      expect((added.x, added.y), (40, 80));
      expect(host.addScript('nope'), isNull);
      host.edit(() => expect(host.removeScript(id), isTrue));
      expect(host.script(id), isNull);

      expect(host.issues, isEmpty);
      host.edit(() => host.script('h1')!.insertBlock(const [], LcBlock(op: 'setVar', args: {'name': 'ghost', 'value': exNum(1)})));
      final issue = host.issues.single;
      expect(issue.scriptId, 'h1');
      expect(bkSameBlockPath(issue.path, [lcStep(3)]), isTrue);
      expect(issue.arg, 'name');
      expect(issue.isError, isTrue);
      expect(host.codeLanguage, 'JavaScript');
      expect(host.codeText, contains('count'));
    });

    test('参数的可选项和显示：变量、控件、固定选项（只列这个控件真有的属性）', () {
      final doc = sampleDoc();
      final host = hostOf(doc);
      final fetch = lcBlockSpecs['fetch']!, setProp = lcBlockSpecs['setProp']!;
      expect(host.options(fetch.arg('into')!).map((o) => o.value), ['', 'count', 'msg', 'ok']);
      expect(host.options(lcBlockSpecs['setVar']!.arg('name')!).map((o) => o.value), ['count', 'msg', 'ok']);
      final onInput = LcBlock(op: 'setProp', args: {'node': nodeIdOf(doc, 'input'), 'prop': 'value', 'value': exText('')});
      final props = host.options(setProp.arg('prop')!, block: onInput).map((o) => o.value).toList();
      expect(props, contains('placeholder'));
      expect(props, isNot(contains('src')));
      expect(host.optionLabel(setProp.arg('node')!, nodeIdOf(doc, 'button')), '按钮“提交”');
      expect(host.optionLabel(setProp.arg('prop')!, 'visible'), '是否显示');
      expect(host.optionLabel(lcExprSpecs['bin']!.arg('op')!, '>='), '≥');
      expect(host.optionLabel(fetch.arg('method')!, 'GET'), 'GET');
      expect(host.options(const LcArgSpec('c', '集合', LcArgKind.collection)), isEmpty);
    });

    test('撤销重做交给外面；换了文档以后脚本从新文档里取', () {
      final a = sampleDoc(), b = LcDocument.starter('另一页');
      var undone = 0;
      final host = LogicBlockHost(
        doc: a,
        onEdit: (change) => change(a),
        canUndoOf: () => true,
        onUndo: () {
          undone++;
          return b;
        },
      );
      expect(host.canUndo, isTrue);
      expect(host.canRedo, isFalse);
      final rev = host.revision;
      host.undo();
      expect(undone, 1);
      expect(host.doc, same(b));
      expect(host.scripts, isEmpty);
      expect(host.revision, rev + 1);
      host.redo(); // 没给 onRedo：什么都不做
      expect(host.revision, rev + 1);
    });
  });

  group('画布排布', () {
    test('没有位置的自上而下排，不重叠，不写回模型；有位置的照着放，自动的排在它们下面', () {
      final doc = sampleDoc();
      final host = hostOf(doc);
      final engine = engineOf(host);
      final auto = layoutBlockCanvas(host, engine);
      expect([for (final s in auto.scripts) s.id], ['h1', 'h2', 'h3']);
      for (var i = 0; i < 3; i++) {
        expect(auto.scripts[i].auto, isTrue);
        expect(auto.scripts[i].origin.dx, 16);
        if (i > 0) expect(auto.scripts[i].origin.dy, auto.scripts[i - 1].bounds.bottom + 28);
      }
      expect(doc.logic.handlers.every((h) => h.x == null && h.y == null), isTrue);
      expect(doc.encode(), sampleDoc().encode(), reason: '只是打开看看，文件内容不变');

      doc.logic.handlers[1]
        ..x = 200
        ..y = 500;
      final mixed = layoutBlockCanvas(host, engine);
      final h2 = mixed.placed('h2')!;
      expect(h2.auto, isFalse);
      expect(h2.origin, const Offset(200, 500));
      expect(mixed.placed('h1')!.origin.dy, h2.bounds.bottom + 28);
      expect(mixed.extent.width, greaterThanOrEqualTo(h2.bounds.right));
      expect(mixed.extent.height, greaterThanOrEqualTo(mixed.placed('h3')!.bounds.bottom));
    });

    test('画布上点哪是哪、找最近的拼接点（跨脚本，坐标是画布的）', () {
      final host = hostOf(sampleDoc());
      final canvas = layoutBlockCanvas(host, engineOf(host));
      final h2 = canvas.placed('h2')!;
      final block = h2.layout.blockAt([lcStep(1)])!;
      final found = canvas.hitTest(h2.origin + block.head.topLeft + const Offset(3, 3))!;
      expect(found.script.id, 'h2');
      expect(bkSameBlockPath(found.hit.block.path, [lcStep(1)]), isTrue);
      expect(canvas.hitTest(const Offset(2, 2)), isNull);

      final near = canvas.nearestSnap(h2.origin + block.rect.bottomLeft + const Offset(4, 3), kind: BkSnapKind.statement)!;
      expect(near.script.id, 'h2');
      expect(near.snap.index, 2);
      expect(near.anchor, h2.origin + block.rect.bottomLeft);
      // 正在拖 h2 的第 2 块：它自己里面不算，但别的脚本照常。
      final h3 = canvas.placed('h3')!;
      final other = canvas.nearestSnap(h3.origin + h3.layout.hat!.rect.bottomLeft, kind: BkSnapKind.statement, excludeScript: 'h2', exclude: [lcStep(1)])!;
      expect(other.script.id, 'h3');
      expect(other.snap.index, 0);
      expect(canvas.nearestSnap(const Offset(5000, 5000), kind: BkSnapKind.expr), isNull);
    });
  });
}
