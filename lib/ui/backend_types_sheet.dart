// 设计约束（后端积木·类型相关的三张底部面板，390 宽，浅色 + 深色）— 2026-11-26
// - 升级到严格规矩：标题一行；一句话说这是什么；下面“会变的地方”一条一行（上：变什么，下：小字说明）；
//   再一行说“现在升级会多出几处要改的”（照现在的积木真查出来的数）；一行小字说后果（存盘后回不去，刚升完能撤销）。
//   主操作＝“升级”（实心按钮），次操作＝“先不升”（文字按钮），上下排，不并排挤。
// - 标类型（“定义”帽子）：标题一行（哪块积木）；每个参数一行（左：名字，右：现在的类型，没标是灰色“没标”）；最后一行“交回什么”。
//   点一行进“选类型”。主操作＝点一行去改。
// - 选类型：一种类型一行（单选）；选了“列表 / 字典”才多出一行“里面放什么”（下拉）；最后一行开关“可以是空”。
//   选了就生效（不用再点确定），面板留着方便接着调“里面放什么”“可以是空”；右上角“好了”关掉。
// - 类型名一律中文，不出现英文类型名。层级：标题 > 行的名字 > 行右边的值（次要色）> 小字说明。
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_type_host.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// “升级到严格规矩”的确认面板。点了“升级”就升（一条撤销记录）并返回 true。
Future<bool> showBeUpgradeStrict(BuildContext context, BeBlockHost host) async {
  final preview = host.previewStrict();
  if (preview == null) return false;
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      final t = Theme.of(sheet).textTheme;
      final after = preview.errors > 0
          ? '照现在的积木，升级后会有 ${preview.errors} 处标红要改${preview.others > 0 ? '、${preview.others} 处提醒' : ''}。改好之前不会生成新代码，现在的代码原样留着。'
          : (preview.others > 0 ? '照现在的积木，升级后没有要改的错误，有 ${preview.others} 处提醒。' : '照现在的积木，升级后没有要改的地方。');
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.86),
          child: Column(
            key: const ValueKey('be-strict-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                child: Text('升级到严格规矩', style: t.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text('严格规矩会检查每个地方放的东西对不对，错的当场标出来，而不是悄悄换算。升级后这些地方会变：', style: t.bodySmall?.copyWith(color: c.textMuted)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  children: [
                    for (final (i, ch) in kBeStrictChanges.indexed)
                      Padding(
                        key: ValueKey('be-strict-change-$i'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ch.title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(ch.detail, style: t.bodySmall?.copyWith(color: c.textMuted)),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.x2),
                    DecoratedBox(
                      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.x3),
                        child: Text(after, key: const ValueKey('be-strict-preview'), style: t.bodyMedium),
                      ),
                    ),
                    const SizedBox(height: Space.x2),
                    Text('升级并存盘以后不能降回老规矩；刚升完后悔，可以马上点“撤销”。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(key: const ValueKey('be-strict-go'), onPressed: () => Navigator.pop(sheet, true), child: const Text('升级')),
                    const SizedBox(height: Space.x1),
                    TextButton(key: const ValueKey('be-strict-cancel'), onPressed: () => Navigator.pop(sheet, false), child: const Text('先不升')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (go != true) return false;
  host.upgradeToStrict();
  return true;
}

String _show(LType? t) => t == null ? '没标' : t.show();

/// 选中的积木上点了“标类型”：“定义”帽子 → 参数和结果的列表；“新建变量 / 常量” → 直接选类型。
Future<void> showBeTypeEditor(BuildContext context, BeBlockHost host, BlockSelection sel) async {
  if (sel.path.isNotEmpty) {
    final name = host.script(sel.scriptId)?.blockAt(sel.path)?.args['name'];
    await showBeTypePicker(
      context,
      title: '「${name is String ? name : '变量'}」放什么',
      read: () => host.letTypeAt(sel.scriptId, sel.path),
      write: (t) => host.setLetType(sel.scriptId, sel.path, t),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, refresh) {
        final c = sheet.colors;
        final t = Theme.of(sheet).textTheme;
        final f = host.doc.function(sel.scriptId);
        if (f == null) return const SizedBox.shrink();
        Widget row(String key, String label, LType? type, LType? Function() read, void Function(LType?) write) => InkWell(
          key: ValueKey(key),
          onTap: () async {
            await showBeTypePicker(sheet, title: label, read: read, write: write);
            if (sheet.mounted) refresh(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyLarge),
                ),
                const SizedBox(width: Space.x3),
                Text(_show(type), style: t.bodyMedium?.copyWith(color: type == null ? c.textMuted : c.text)),
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
              ],
            ),
          ),
        );
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
            child: Column(
              key: const ValueKey('be-types-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                  child: Text('「${f.name}」的类型', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                  child: Text('标了以后，用这块积木的地方放错东西会标红。没标的会自己推。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in f.params)
                        row('be-type-param-${p.name}', '参数「${p.name}」', p.type, () => host.doc.function(f.id)?.params.where((x) => x.name == p.name).firstOrNull?.type, (v) => host.setParamType(f.id, p.name, v)),
                      row('be-type-returns', '交回什么', f.returns, () => host.doc.function(f.id)?.returns, (v) => host.setReturnType(f.id, v)),
                    ],
                  ),
                ),
                const SizedBox(height: Space.x2),
              ],
            ),
          ),
        );
      },
    ),
  );
}

enum _Pick { none, integer, number, text, boolean, any, list, dict }

_Pick _pickOf(LType? t) => switch (t?.kind) {
  null => _Pick.none,
  LKind.integer => _Pick.integer,
  LKind.number => _Pick.number,
  LKind.text => _Pick.text,
  LKind.bool => _Pick.boolean,
  LKind.list => _Pick.list,
  LKind.dict => _Pick.dict,
  _ => _Pick.any,
};

const Map<_Pick, (String, String)> _pickText = {
  _Pick.none: ('不标', '让它自己推'),
  _Pick.integer: ('整数', '1、2、-3 这样没有小数点的数'),
  _Pick.number: ('小数', '带小数点的数；整数也能放进来'),
  _Pick.text: ('文字', ''),
  _Pick.boolean: ('是 / 否', ''),
  _Pick.list: ('列表', '一串同一种东西'),
  _Pick.dict: ('字典', '名字对应的值都是同一种东西'),
  _Pick.any: ('任意', '什么都能放；用的时候再检查'),
};

/// 选一种类型。选了马上写回去（[write]），面板留着；[read] 取现在的值。
Future<void> showBeTypePicker(BuildContext context, {required String title, required LType? Function() read, required void Function(LType? type) write}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, refresh) {
        final c = sheet.colors;
        final t = Theme.of(sheet).textTheme;
        final now = read();
        final pick = _pickOf(now);
        final inner = now?.of ?? LType.any;
        final canNull = pick != _Pick.none && pick != _Pick.any;
        void set(LType? next) {
          write(next);
          refresh(() {});
        }

        LType? build(_Pick p, {LType? of, bool nullable = false}) {
          final base = switch (p) {
            _Pick.none => null,
            _Pick.integer => LType.integer,
            _Pick.number => LType.number,
            _Pick.text => LType.text,
            _Pick.boolean => LType.boolean,
            _Pick.any => LType.any,
            _Pick.list => LType.listOf(of ?? LType.any),
            _Pick.dict => LType.dictOf(of ?? LType.any),
          };
          return base != null && nullable && p != _Pick.any ? base.orNull : base;
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.86),
            child: Column(
              key: const ValueKey('be-type-picker'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x2, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                      ),
                      TextButton(key: const ValueKey('be-type-done'), onPressed: () => Navigator.pop(sheet), child: const Text('好了')),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in _Pick.values)
                        InkWell(
                          key: ValueKey('be-type-${p.name}'),
                          onTap: () => set(build(p, of: inner, nullable: now?.nullable ?? false)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 10),
                            child: Row(
                              children: [
                                Icon(p == pick ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20, color: p == pick ? c.accent : c.textMuted),
                                const SizedBox(width: Space.x3),
                                Text(_pickText[p]!.$1, style: t.bodyLarge),
                                const SizedBox(width: Space.x3),
                                Expanded(
                                  child: Text(_pickText[p]!.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: c.textMuted)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (pick == _Pick.list || pick == _Pick.dict)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                          child: Row(
                            children: [
                              Expanded(child: Text('里面放什么', style: t.bodyLarge)),
                              DropdownButton<LType>(
                                key: const ValueKey('be-type-inner'),
                                value: kBeTypeChoices.contains(inner) ? inner : LType.any,
                                underline: const SizedBox.shrink(),
                                items: [for (final x in kBeTypeChoices) DropdownMenuItem(value: x, child: Text(x.show()))],
                                onChanged: (x) => set(build(pick, of: x, nullable: now?.nullable ?? false)),
                              ),
                            ],
                          ),
                        ),
                      SwitchListTile(
                        key: const ValueKey('be-type-nullable'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
                        title: const Text('可以是空'),
                        subtitle: Text(canNull ? '开了以后，用它之前要先判断“不是空”' : '“不标”和“任意”本来就可以是空', style: t.bodySmall?.copyWith(color: c.textMuted)),
                        value: canNull && (now?.nullable ?? false),
                        onChanged: canNull ? (v) => set(build(pick, of: inner, nullable: v)) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x3),
                        child: Text('现在：${_show(now)}', key: const ValueKey('be-type-now'), style: t.bodyMedium?.copyWith(color: c.textMuted)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
