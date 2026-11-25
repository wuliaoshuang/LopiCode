// 积木盒里“放什么”的纯逻辑：一页怎么分小标题、“常用”页放哪些、加星、搜索。不带界面。
//
// - 一页（[BlockCategory]）＝先排不在分组里的，再一组一组排（每组一个小标题）。
// - “常用”页（[bkCommonCategoryId]）是编辑器自己合成的，不用宿主声明：
//   加了星的（按加星的先后）＋ 这份文档里用得最多的 [bkCommonMax] 块；文档还一块积木都没有时，后一半换成宿主给的入门积木。
// - 加星只存“哪一样”（[BlockItemRef.token]），存在哪由外面给的 [BlockStars] 决定。
// - 搜索：按积木上的字、宿主给的别名搜；“一块顶多块”的积木每一种都能按自己的字搜到，拿出来就是那一种。
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “常用”页的 id（宿主的分类不要用 `@` 开头的 id）。
const String bkCommonCategoryId = '@common';

/// “常用”页里“用得最多”最多放几块；最多能加几颗星。
const int bkCommonMax = 12;
const int bkStarMax = 24;

/// 加星存在哪。读出来的东西不保证干净（见 [bkCleanStars]）。
abstract interface class BlockStars {
  Object? load();
  void save(List<String> tokens);
}

/// 只记在内存里的（没给存的地方时用；测试也用）。
class MemoryBlockStars implements BlockStars {
  MemoryBlockStars([this.value]);
  Object? value;
  int saves = 0;

  @override
  Object? load() => value;

  @override
  void save(List<String> tokens) {
    value = List.of(tokens);
    saves++;
  }
}

/// 一页里的一段：`label` 为 null＝不带小标题。
class BkPaletteSection {
  const BkPaletteSection(this.label, this.items);
  final String? label;
  final List<BlockItemRef> items;
}

List<BlockItemRef> _refs(List<BlockHatTemplate> hats, List<String> blocks, List<String> exprs) => [
  for (final h in hats) BlockItemRef.hat(h.id),
  for (final b in blocks) BlockItemRef.block(b),
  for (final e in exprs) BlockItemRef.expr(e),
];

/// 一页怎么分段：不在分组里的在最前面（不带小标题），然后一组一段；空的组不要。
List<BkPaletteSection> bkCategorySections(BlockCategory c) {
  final loose = _refs(c.hats, c.blocks, c.exprs);
  return [
    if (loose.isNotEmpty) BkPaletteSection(null, loose),
    for (final g in c.groups)
      if (!g.isEmpty) BkPaletteSection(g.label, _refs(g.hats, g.blocks, g.exprs)),
  ];
}

/// 积木盒里所有的东西，按页的先后；同一样出现在两页只算第一次。
List<BlockItemRef> bkPaletteItems(BlockHost host) {
  final seen = <String>{};
  return [
    for (final c in bkAllCategories(host))
      for (final s in bkCategorySections(c))
        for (final i in s.items)
          if (seen.add(i.token)) i,
  ];
}

/// 一样东西在界面上的 key（带上 preset，同一块积木的几种变体不重名）：`block-if`、`expr-arith~op=*`。
String bkItemKey(BlockItemRef item) => ['${item.kind.name}-${item.id}', for (final e in item.preset.entries) '${e.key}=${e.value}'].join('~');

/// 帽子模板（按 id 找）。
BlockHatTemplate? bkHatTemplate(BlockHost host, String id) {
  for (final c in bkAllCategories(host)) {
    for (final h in c.allHats) {
      if (h.id == id) return h;
    }
  }
  return null;
}

/// 这一样是什么颜色（它第一次出现的那一页的颜色）。
String bkItemColorKey(BlockHost host, BlockItemRef item) => switch (item.kind) {
  BlockPaletteKind.hat => bkHatTemplate(host, item.id)?.hat.colorKey ?? BlockColorKey.event,
  BlockPaletteKind.block => host.blockColorKey(item.id),
  BlockPaletteKind.expr => host.exprColorKey(item.id),
};

/// 存下来的加星清单读回来：不是表＝空；不是字符串、格式不对、重复的都丢掉；太多只留前 [bkStarMax] 个。
List<String> bkCleanStars(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final t in raw) {
    final ref = BlockItemRef.parse(t);
    if (ref == null || out.contains(ref.token)) continue;
    out.add(ref.token);
    if (out.length >= bkStarMax) break;
  }
  return out;
}

/// 加星 / 去星以后的新清单。加满了（[bkStarMax]）返回 null。
List<String>? bkToggleStar(List<String> stars, String token) {
  if (stars.contains(token)) {
    return [
      for (final s in stars)
        if (s != token) s,
    ];
  }
  if (stars.length >= bkStarMax) return null;
  return [...stars, token];
}

void _countExpr(Object? v, Map<String, int> out, int depth) {
  if (depth > 40) return;
  if (v is List) {
    for (final x in v) {
      _countExpr(x, out, depth + 1);
    }
  } else if (v is Map) {
    final e = v['e'];
    if (e is String) out['expr:$e'] = (out['expr:$e'] ?? 0) + 1;
    for (final x in v.values) {
      _countExpr(x, out, depth + 1);
    }
  }
}

/// 这份文档里每样积木用了几次（`token → 次数`）。帽子不算（一串一个，不是“拿来用”的）。
Map<String, int> bkUsage(BlockHost host) {
  final out = <String, int>{};
  for (final s in host.scripts) {
    s.visitBlocks((b, _) {
      out['block:${b.op}'] = (out['block:${b.op}'] ?? 0) + 1;
      _countExpr(b.args.values.toList(), out, 0);
      for (final LcArm a in b.arms) {
        _countExpr(a.args.values.toList(), out, 0);
      }
    });
  }
  return out;
}

/// “常用”页的内容。[stars]＝加了星的（[bkCleanStars] 洗过的）。积木盒里已经没有的那些不显示。
List<BkPaletteSection> bkCommonSections(BlockHost host, List<String> stars) {
  final all = bkPaletteItems(host);
  final byToken = {for (final i in all) i.token: i};
  final starred = [
    for (final t in stars)
      if (byToken[t] != null) byToken[t]!,
  ];
  final taken = {for (final i in starred) i.token};
  final usage = bkUsage(host);
  final order = {for (var i = 0; i < all.length; i++) all[i].token: i};
  final used =
      [
        for (final i in all)
          if ((usage[i.token] ?? 0) > 0 && !taken.contains(i.token) && !_isBareValue(host, i)) i,
      ]..sort((a, b) {
        final d = usage[b.token]! - usage[a.token]!;
        return d != 0 ? d : order[a.token]! - order[b.token]!;
      });
  if (usage.isNotEmpty) {
    return [if (starred.isNotEmpty) BkPaletteSection('加了星的', starred), if (used.isNotEmpty) BkPaletteSection('这里用得最多', used.take(bkCommonMax).toList())];
  }
  // 新文档：宿主给的入门积木；没给就每页拿第一样（先帽子那页，这样第一块能拿到的就是“开头”）。
  final seen = <String>{...taken};
  var starter = [
    for (final i in host.starterItems)
      if (byToken[i.token] != null && seen.add(i.token)) byToken[i.token]!,
  ];
  if (starter.isEmpty && host.starterItems.isEmpty) {
    starter = [
      for (final c in bkAllCategories(host))
        for (final s in bkCategorySections(c).take(1))
          if (seen.add(s.items.first.token)) s.items.first,
    ].take(bkCommonMax).toList();
  }
  return [if (starred.isNotEmpty) BkPaletteSection('加了星的', starred), if (starter.isNotEmpty) BkPaletteSection('入门', starter)];
}

/// 只有一个直接填的参数的值（数字、文字、是否）：每个空槽里本来就有一个，不用从“常用”里拿，放上去只是占地方。
/// （加了星的不管：那是她自己要的。）
bool _isBareValue(BlockHost host, BlockItemRef item) {
  if (item.kind != BlockPaletteKind.expr) return false;
  final args = host.exprSpec(item.id)?.args;
  if (args == null || args.length != 1) return false;
  final k = args.single.kind;
  return k == LcArgKind.literalText || k == LcArgKind.literalNumber || k == LcArgKind.literalBool;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

final RegExp _hole = RegExp(r'\{[^{}]*\}');

/// 积木上写着的字（标题 + 那句话里槽以外的字 + 各个口上的字）。
List<String> bkItemWords(BlockHost host, BlockItemRef item) {
  switch (item.kind) {
    case BlockPaletteKind.hat:
      final hat = bkHatTemplate(host, item.id)?.hat;
      return [
        if (hat != null)
          [
            for (final p in hat.parts)
              if (!p.isSlot) p.text,
          ].join(),
      ];
    case BlockPaletteKind.block:
      final LcBlockSpec? spec = host.blockSpec(item.id);
      if (spec == null) return const [];
      return [
        spec.label,
        ?host.blockSentence(item.id)?.replaceAll(_hole, ' '),
        ?spec.bodyLabel,
        ?spec.elseLabel,
        if (spec.arms != null) (host.armSentence(item.id) ?? spec.arms!.label).replaceAll(_hole, ' '),
      ];
    case BlockPaletteKind.expr:
      final spec = host.exprSpec(item.id);
      if (spec == null) return const [];
      return [spec.label, ?host.exprSentence(item.id)?.replaceAll(_hole, ' ')];
  }
}

/// 一种变体自己的字：下拉上显示的那个字 + 宿主给这一种的别名。
List<String> _variantWords(BlockHost host, BlockItemRef v) {
  final List<LcArgSpec> args = switch (v.kind) {
    BlockPaletteKind.block => host.blockSpec(v.id)?.args ?? const [],
    BlockPaletteKind.expr => host.exprSpec(v.id)?.args ?? const [],
    BlockPaletteKind.hat => const [],
  };
  final out = <String>[...host.aliasesOf(v)];
  for (final e in v.preset.entries) {
    for (final a in args) {
      if (a.name != e.key) continue;
      out.add(host.optionLabel(a, e.value));
    }
  }
  return out;
}

/// 0＝字完全一样，1＝以它开头，2＝包含；-1＝没搜到。
int _score(List<String> words, String q) {
  var best = -1;
  for (final raw in words) {
    final w = _norm(raw);
    if (w.isEmpty) continue;
    final s = w == q ? 0 : (w.startsWith(q) ? 1 : (w.contains(q) ? 2 : -1));
    if (s >= 0 && (best < 0 || s < best)) best = s;
  }
  return best;
}

/// 搜积木。按“像不像”排：积木上的字完全一样 → 开头一样 → 包含 → 别名（同样三档）；一样像的按积木盒里的先后。
/// “一块顶多块”的积木：整块搜到了就给整块；整块没搜到、某几种搜到了，就给那几种（带 `preset`）。空的词＝空表。
List<BlockItemRef> bkSearchPalette(BlockHost host, String query) {
  final q = _norm(query);
  if (q.isEmpty) return const [];
  final hits = <(int, int, BlockItemRef)>[];
  var n = 0;
  for (final item in bkPaletteItems(host)) {
    n++;
    final own = _score(bkItemWords(host, item), q);
    final alias = _score(host.aliasesOf(item), q);
    if (own >= 0 || alias >= 0) {
      hits.add((own >= 0 ? own : 3 + alias, n, item));
      continue;
    }
    for (final v in host.variantsOf(item)) {
      n++;
      final s = _score(_variantWords(host, v), q);
      if (s >= 0) hits.add((3 + s, n, v));
    }
  }
  hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final h in hits) h.$3];
}

/// “我的积木”那一页在积木盒里的 id。
const String bkCustomCategoryId = '@custom';

/// 积木盒里全部的分类：宿主给的，加上“我的积木”（宿主有 [BlockHost.custom] 才有；一块都没有时这一页也在——里面有“新建积木”）。
List<BlockCategory> bkAllCategories(BlockHost host) {
  final custom = host.custom;
  if (custom == null) return host.categories;
  final all = custom.customs;
  return [
    ...host.categories,
    BlockCategory(
      id: bkCustomCategoryId,
      label: kBlockCustomCategory,
      colorKey: BlockColorKey.custom,
      blocks: [
        for (final c in all)
          if (!c.isValue) c.id,
      ],
      exprs: [
        for (final c in all)
          if (c.isValue) c.id,
      ],
    ),
  ];
}
