part of 'typecheck.dart';

/// “要不要等”（核心 3）：自动推、放错地方时拦。设计：docs/blocks-v5-foundation-design.md 6.3、
/// docs/blocks-v5-parts/A2-features-advanced.md 10.f；做法和细则：docs/blocks-v5-parts/B-gen-notes.md 第 16 节。
///
/// **推**（和类型一起一遍一遍地过，直到不变）：一个函数 / 方法 / 匿名函数 /“开始做”里的那几句，只要里面有一件“要等的事”，它就“要等”。
/// 要等的事＝“等 …”、要等的宿主接口和小库函数（等一会儿、开服务、请求网址、等全部…）、调一个要等的函数或方法、
/// 调一个“可能要等”的函数值。匿名函数里面的事算匿名函数自己的，不算外面那个函数的；“开始做”也一样（所以“开始做”本身不用等）。
/// 互相调用、递归：集合只会变大，转几圈就不变了。
///
/// - 方法：子类重写的方法要等＝父类那个方法也算要等（拿着父类的变量调它，实际跑的可能是子类的）；
///   实现接口的方法要等＝接口里那个方法也算要等。
/// - 函数值：类型里带着“要不要等”（`LType.waits`）：true＝可能要等，false＝规定不许等，null＝没说。
///   没说的那种看整个程序：只要有一个要等的函数值混进过“没说”的地方（[LTypeWorld.waitEscaped]），调它们就都当成可能要等。
/// - 写的人明着标的“要等”（库的文字写法里的 `要等函数`…）照样算数：标了就是要等。
///
/// **拦**（最后一遍报）：
/// - T29 这里不能有要等的事：类的“创建时”、字段的初始值、规定了“不许等”的函数 / 方法、实现或重写了规定“不许等”的方法。
/// - T30 要等的函数放进了只收不用等的函数的地方（排序 / 映射 / 筛选这些小库函数的口、“改格子”的改法、标了“不等函数”的参数）。
/// - T31 “等”后面不是“稍后的结果”。
mixin _Waits on _Core {
  @override
  bool fnWaits(String key) => waitKeys.contains(key);

  @override
  void waited(_Scope sc, LNode at, String what, {String? slot}) {
    if (waitKeys.add(sc.key)) w.changed = true;
    if (slot == null) {
      _hard.add(sc.key);
    } else {
      (_soft[sc.key] ??= {}).add(slot);
    }
    if (finalPass) _why.putIfAbsent(sc.key, () => (at, what));
  }

  /// 要等的原因。[_hard]：里面真有要等的事；[_soft]：只是调了自己外面那个函数的参数（“函数记号#位置”），而那个参数没说要不要等。
  final Set<String> _hard = {};
  final Map<String, Set<String>> _soft = {};

  final Map<String, (LNode, String)> _why = {};

  @override
  bool valueWaits(LType ft0) {
    final ft = w.res(ft0);
    if (ft.kind == LKind.fn) return ft.waits == true || (ft.waits == null && w.waitEscaped);
    return (ft.isAny || ft.isNever) && w.waitEscaped;
  }

  /// 明着标了“要等”的先放进去。
  void seedWaits() {
    for (final f in w.funcs.values) {
      if (f.decl?.waits == true && waitKeys.add(f.key)) _hard.add(f.key);
    }
    for (final c in w.classes.values) {
      for (final m in c.methods.values) {
        if (m.decl?.waits == true && waitKeys.add(m.key)) _hard.add(m.key);
      }
    }
    for (final i in w.interfaces.values) {
      for (final m in i.methods) {
        if (m.waits) waitIface.add('${i.name}.${m.name}');
      }
    }
  }

  /// 一遍过完：把“要等”往上传（子类 → 父类的同名方法，实现 → 接口的方法）；“这个参数只收不用等的函数”也往父类的同名方法传。
  void spreadWaits() {
    for (final slot in [...noWaitParams]) {
      final cut = slot.lastIndexOf('#'), dot = slot.indexOf('.');
      if (dot < 0) continue;
      final c = w.classes[slot.substring(0, dot)];
      final name = slot.substring(dot + 1, cut);
      var guard = 0;
      for (var p = w.classes[c?.decl.parent]; p != null && guard++ < 64; p = w.classes[p.decl.parent]) {
        final up = p.methods[name];
        if (up != null && noWaitParams.add('${up.key}${slot.substring(cut)}')) w.changed = true;
      }
    }
    for (final c in w.classes.values) {
      for (final m in c.methods.values) {
        if (!waitKeys.contains(m.key)) continue;
        var guard = 0;
        for (var p = w.classes[c.decl.parent]; p != null && guard++ < 64; p = w.classes[p.decl.parent]) {
          final up = p.methods[m.name];
          if (up != null && waitKeys.add(up.key)) w.changed = true;
        }
      }
      for (final i in w.supers(c.name)) {
        final iface = w.interfaces[i];
        if (iface == null) continue;
        for (final m in iface.methods) {
          final got = w.classMethod(c, m.name);
          if (got != null && waitKeys.contains(got.$1.key) && waitIface.add('$i.${m.name}')) w.changed = true;
        }
      }
    }
  }

  String _whyText(String key) {
    final why = _why[key];
    return why == null ? '里面有要等的事' : '里面有要等的事（${why.$2}）';
  }

  LNode? _whyNode(String key) => _why[key]?.$1;

  /// 那件要等的事要是单独一句话（结果没人用），可以一键改成“开始做”（不等它）。
  List<LFix> _spawnFix(String key) {
    final at = _whyNode(key);
    return at is LExpr && _alone.contains(at) ? [LFix(LFixKind.wrapSpawn, '改成“开始做”（不等它做完）', target: at)] : const [];
  }

  /// T29：最后一遍过完以后查。
  void waitRules(_Scope top) {
    for (final c in w.classes.values) {
      final ctor = c.ctor;
      if (ctor != null && waitKeys.contains(ctor.key)) {
        err('T29', top, '「${c.name}」的“创建时”${_whyText(ctor.key)}：新建对象不能等。把要等的事挪到一个方法里，新建以后再调', node: _whyNode(ctor.key) ?? ctor.decl, where: ctor.key, fixes: _spawnFix(ctor.key));
      }
      final fk = '${c.name}.字段';
      if (waitKeys.contains(fk)) err('T29', top, '「${c.name}」的字段的初始值${_whyText(fk)}：这里不能等。先放一个空的，在方法里再算', node: _whyNode(fk) ?? c.decl, where: c.name);
      for (final m in c.methods.values) {
        if (!waitKeys.contains(m.key)) continue;
        if (m.decl?.noWait == true) {
          err('T29', top, '「${c.name}」的「${m.name}」规定了不许等，可是${_whyText(m.key)}', node: _whyNode(m.key) ?? m.decl, where: m.key, fixes: _spawnFix(m.key));
          continue;
        }
        if (!_why.containsKey(m.key) && m.decl?.waits != true) continue; // 自己不等，是被子类传上来的：在子类那里报
        var guard = 0;
        for (var p = w.classes[c.decl.parent]; p != null && guard++ < 64; p = w.classes[p.decl.parent]) {
          if (p.methods[m.name]?.decl?.noWait == true) {
            err('T29', top, '「${c.name}」重写的「${m.name}」${_whyText(m.key)}，可是父类「${p.name}」规定这个方法不许等：重写的要和父类的一致', node: _whyNode(m.key) ?? m.decl, where: m.key, fixes: _spawnFix(m.key));
            break;
          }
        }
      }
      for (final i in w.supers(c.name)) {
        final iface = w.interfaces[i];
        if (iface == null) continue;
        for (final m in iface.methods) {
          if (!m.noWait) continue;
          final got = w.classMethod(c, m.name);
          if (got == null || !waitKeys.contains(got.$1.key) || got.$2.name != c.name && !c.decl.interfaces.contains(i)) continue;
          final k = got.$1.key;
          err('T29', top, '「${got.$2.name}」的「${m.name}」${_whyText(k)}，可是接口「$i」规定这个方法不许等：实现的要和接口的一致', node: _whyNode(k) ?? got.$1.decl, where: k, fixes: _spawnFix(k));
        }
      }
    }
    // 推出来“只收不用等的函数”的参数，要是这个方法是实现接口的：接口那边也得这么规定，不然拿着接口调就拦不住了。
    for (final slot in noWaitParams) {
      final cut = slot.lastIndexOf('#'), dot = slot.indexOf('.');
      final c = dot < 0 ? null : w.classes[slot.substring(0, dot)];
      if (c == null) continue;
      final name = slot.substring(dot + 1, cut), index = int.parse(slot.substring(cut + 1));
      for (final i in w.supers(c.name)) {
        final m = w.interfaces[i]?.methods.where((m) => m.name == name).firstOrNull;
        if (m == null || index >= m.params.length) continue;
        final pt = w.resolve(m.params[index].type);
        if (pt.kind == LKind.fn && pt.waits != false) {
          err('T30', top, '「${c.name}」的「$name」把第 ${index + 1} 个参数放进了只收不用等的函数的地方，可是接口「$i」没有规定这个参数不许等。在接口里把这个参数的类型标成“不等函数”', node: c.methods[name]?.decl ?? c.decl, where: '${c.name}.$name');
        }
      }
    }
    for (final f in w.funcs.values) {
      if (f.decl?.noWait == true && waitKeys.contains(f.key)) {
        err('T29', top, '「${f.name}」规定了不许等，可是${_whyText(f.key)}', node: _whyNode(f.key) ?? f.decl, where: f.key, fixes: _spawnFix(f.key));
      }
    }
  }

  @override
  void waitFit(_Scope sc, LExpr e, LType src0, LType dst0, String where, {int? argIndex}) {
    final src = w.res(src0), dst = w.res(dst0);
    if (dst.kind != LKind.fn || dst.waits != false || src.kind != LKind.fn) return;
    if (src.waits == null && e is LName) {
      // 把自己的参数原样放进只收不用等的函数的地方：这个参数也就只收不用等的函数（往调用的人那边传，转几圈就不变了）。
      final slot = vt[find(sc, e.name)]?.slot;
      if (slot != null) {
        if (noWaitParams.add(slot)) w.changed = true;
        return;
      }
    }
    if (!finalPass) return;
    final fixes = [
      if (e is LLambda && _spawnable(e)) LFix(LFixKind.wrapSpawn, '把里面要等的事改成“开始做”（不等它做完）', target: _whyNode(lambdaKeys[e] ?? '')),
    ];
    if (src.waits == true) {
      final key = e is LLambda ? lambdaKeys[e] : (e is LName ? e.name : null);
      // 它要等只是因为调了外面函数的参数：记下来，带着“那个参数只收不用等的函数”重查一遍（checkTypes）。
      if (key != null && !_hard.contains(key)) demand.addAll(_soft[key] ?? const {});
      final why = key != null && _why.containsKey(key) ? '它${_whyText(key)}' : '它是要等的';
      err('T30', sc, '$where只收不用等的函数，放进来的函数要等：$why。要等的事挪到外面先做完，或者在里面放一块“开始做”', node: e, argIndex: argIndex, fixes: fixes);
    } else if (src.waits == null && w.waitEscaped && e is! LLambda && !(e is LName && w.funcs.containsKey(e.name) && find(sc, e.name) == null)) {
      err('T30', sc, '$where只收不用等的函数，放进来的这个函数说不准要不要等（程序里有要等的函数被当成值传来传去）。换成直接写在这里的匿名函数', node: e, argIndex: argIndex);
    }
  }

  bool _spawnable(LLambda e) {
    final at = _whyNode(lambdaKeys[e] ?? '');
    return at is LExpr && _alone.contains(at);
  }

  /// 单独成一句的式子（“做 …”那种，结果没人用）。
  final Set<LExpr> _alone = HashSet.identity();

  @override
  void noteAlone(LExpr e) {
    if (finalPass) _alone.add(e);
  }
}
