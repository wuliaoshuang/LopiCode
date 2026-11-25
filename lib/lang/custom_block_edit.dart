/// “我的积木”改参数联动（设计稿 5.3 第 4 条）：定义的参数加、删、改名、换顺序以后，所有调用的地方和外观跟着变。
/// 全是纯函数：不改传进来的东西，不抛异常。
///
/// 怎么说“参数怎么变的”：新参数表 [newParams] 配一张等长的 `origin`——`origin[i]` 是新参数 i **原来是旧参数表里的第几个**
/// （改名、换顺序都靠它认），null（或越界 / 被前面用过）＝新加的。只按名字认的话用 [paramOriginsByName]（那样“改名”会被当成删一个加一个）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/custom_block.dart';

/// 按名字对：新参数在旧表里有同名的就认作同一个，否则是新加的。
List<int?> paramOriginsByName(List<LParam> oldParams, List<LParam> newParams) {
  final used = <int>{};
  return [
    for (final p in newParams)
      () {
        for (var i = 0; i < oldParams.length; i++) {
          if (oldParams[i].name == p.name && used.add(i)) return i;
        }
        return null;
      }(),
  ];
}

/// 把 origin 收拾成能用的：长度补齐到和新参数表一样，越界的、重复指向同一个旧参数的当成“新加的”。
List<int?> _cleanOrigins(int oldCount, int newCount, List<int?> origin) {
  final used = <int>{};
  return [
    for (var i = 0; i < newCount; i++)
      () {
        final o = i < origin.length ? origin[i] : null;
        return o != null && o >= 0 && o < oldCount && used.add(o) ? o : null;
      }(),
  ];
}

/// 被丢掉的一份实参：[param] 是它原来填在哪个（旧）参数上，[value] 是填的内容。
class DroppedArg<T> {
  const DroppedArg(this.param, this.value);
  final String param;
  final T value;

  @override
  String toString() => 'DroppedArg($param, $value)';
}

class RemapResult<T> {
  const RemapResult(this.args, this.dropped);

  /// 新的实参表（按新参数表的顺序）。
  final List<T> args;

  /// 被丢掉的内容（界面上删参数前用它提示“有几处在用”）。
  final List<DroppedArg<T>> dropped;
}

/// **按位置**的实参表跟着参数表变。
///
/// - 留下来的参数（`origin` 指得到）：带着原来填的内容走，不管改没改名、换没换位置。
/// - 新加的参数：填 [fill]（调用方按参数的默认值造一个；一般是“默认值的字面量”或一个空槽）。
/// - 删掉的参数：原来填的内容进 [RemapResult.dropped]。
/// - 原来这次调用少给了后面几个有默认值的参数：变完以后如果它们仍在最后，照旧不给；要是后面有了给了值的，中间空着的用 [fill] 补上。
/// - “剩下的全收”的参数（只认排在最后的那个）：它收的那几份一起走；它不再是“全收”了就只留第一份、其余进 dropped；
///   它被删了就全进 dropped；普通参数变成“全收”就带着它那一份。
/// - 实参比旧参数多、又没有“全收”的参数（坏数据）：多出来的进 dropped，参数名记成空文字。
RemapResult<T> remapCallArgs<T>({required List<LParam> oldParams, required List<LParam> newParams, required List<int?> origin, required List<T> args, required T Function(LParam param) fill}) {
  final from = _cleanOrigins(oldParams.length, newParams.length, origin);
  final oldRest = oldParams.isNotEmpty && oldParams.last.rest ? oldParams.length - 1 : -1;
  final newRest = newParams.isNotEmpty && newParams.last.rest ? newParams.length - 1 : -1;

  // 旧参数 i 收到的那几份（普通参数 0 或 1 份）。
  List<T> given(int i) {
    if (i == oldRest) return i < args.length ? args.sublist(i) : const [];
    return i < args.length ? [args[i]] : const [];
  }

  final dropped = <DroppedArg<T>>[];
  final kept = from.whereType<int>().toSet();
  for (var i = 0; i < oldParams.length; i++) {
    if (kept.contains(i)) continue;
    for (final v in given(i)) {
      dropped.add(DroppedArg(oldParams[i].name, v));
    }
  }
  if (oldRest < 0 && args.length > oldParams.length) {
    for (final v in args.sublist(oldParams.length)) {
      dropped.add(DroppedArg('', v));
    }
  }

  // 每个新参数的内容：null＝这次调用没给（可以不写的话就不写）。
  final slots = <List<T>?>[];
  for (var i = 0; i < newParams.length; i++) {
    final o = from[i];
    if (o == null) {
      slots.add(i == newRest ? const [] : [fill(newParams[i])]);
      continue;
    }
    final vs = given(o);
    if (i == newRest) {
      slots.add(vs);
    } else if (vs.isEmpty) {
      slots.add(null);
    } else {
      slots.add([vs.first]);
      for (final v in vs.skip(1)) {
        dropped.add(DroppedArg(oldParams[o].name, v));
      }
    }
  }

  // “全收”收到了东西：它前面的都得写出来。否则后面没给的、而且有默认值的，照旧不给；中间空着的补上。
  final List<T> rest = newRest >= 0 ? (slots[newRest] ?? <T>[]) : <T>[];
  var last = (newRest >= 0 ? newRest : slots.length) - 1;
  if (rest.isEmpty) {
    while (last >= 0 && slots[last] == null && newParams[last].defaultValue != null) {
      last--;
    }
  }
  final out = <T>[];
  for (var i = 0; i <= last; i++) {
    out.addAll(slots[i] ?? [fill(newParams[i])]);
  }
  out.addAll(rest);
  return RemapResult(out, dropped);
}

/// **按槽名**存的实参（积木的 `args` 就是这样）跟着参数表变：留下来的改成新名字，新加的填 [fill]，删掉的进 dropped。
/// 结果的键按新参数表的顺序。旧表里没有的键（坏数据）也进 dropped。
RemapResult<MapEntry<String, T>> remapCallArgsByName<T>({
  required List<LParam> oldParams,
  required List<LParam> newParams,
  required List<int?> origin,
  required Map<String, T> args,
  required T Function(LParam param) fill,
}) {
  final from = _cleanOrigins(oldParams.length, newParams.length, origin);
  final out = <MapEntry<String, T>>[];
  final taken = <String>{};
  for (var i = 0; i < newParams.length; i++) {
    final o = from[i];
    final oldName = o == null ? null : oldParams[o].name;
    if (oldName != null && args.containsKey(oldName) && taken.add(oldName)) {
      out.add(MapEntry(newParams[i].name, args[oldName] as T));
    } else {
      if (oldName != null) taken.add(oldName);
      out.add(MapEntry(newParams[i].name, fill(newParams[i])));
    }
  }
  final dropped = <DroppedArg<MapEntry<String, T>>>[
    for (final e in args.entries)
      if (!taken.contains(e.key)) DroppedArg(e.key, e),
  ];
  return RemapResult(out, dropped);
}

/// 外观跟着参数表变：
/// - 改了名的参数：文案里的 `{旧名}` 换成 `{新名}`，槽的设置跟着改名；
/// - 删掉的参数：文案里的那个槽拿掉（两边的字留着，多出来的连续空格并成一个），槽的设置删掉；
/// - 新加的参数：文案最后接上 ` {新名}`；
/// - 换顺序：文案不动（文案里槽的先后本来就不必和参数表一样）。
/// 文案是空的（用默认样子）就一直是空的。
CustomBlockLook remapLook(CustomBlockLook look, {required List<LParam> oldParams, required List<LParam> newParams, required List<int?> origin}) {
  final from = _cleanOrigins(oldParams.length, newParams.length, origin);
  final rename = <String, String>{};
  final added = <String>[];
  for (var i = 0; i < newParams.length; i++) {
    final o = from[i];
    if (o == null) {
      added.add(newParams[i].name);
    } else {
      rename[oldParams[o].name] = newParams[i].name;
    }
  }
  final oldNames = {for (final p in oldParams) p.name};

  var template = look.template;
  if (template.trim().isNotEmpty) {
    final segs = <LookSegment>[];
    for (final s in parseLookTemplate(template)) {
      if (!s.isSlot) {
        // 前一个槽刚被拿掉、两边都是空格：并成一个。
        if (segs.isNotEmpty && !segs.last.isSlot) {
          final prev = segs.removeLast().text;
          segs.add(LookSegment.text(prev.endsWith(' ') && s.text.startsWith(' ') ? prev + s.text.substring(1) : prev + s.text));
        } else {
          segs.add(s);
        }
      } else if (rename.containsKey(s.text)) {
        segs.add(LookSegment.slot(rename[s.text]!));
      } else if (!oldNames.contains(s.text)) {
        segs.add(s); // 本来就对不上的槽不替用户删，留给校验报 B02
      }
    }
    final present = {
      for (final s in segs)
        if (s.isSlot) s.text,
    };
    for (final n in added) {
      if (present.contains(n)) continue;
      segs
        ..add(const LookSegment.text(' '))
        ..add(LookSegment.slot(n));
    }
    template = formatLookTemplate(segs).trim();
  }

  final newNames = {for (final p in newParams) p.name};
  final seen = <String>{};
  final slots = <CustomBlockSlot>[];
  for (final s in look.slots) {
    final name = rename[s.name] ?? (oldNames.contains(s.name) ? null : s.name);
    if (name == null || !newNames.contains(name) || !seen.add(name)) continue;
    slots.add(name == s.name ? s : s.copyWith(name: name));
  }
  return look.copyWith(template: template, slots: slots);
}
