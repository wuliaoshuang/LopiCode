/// 生成代码时的“作用域”：现在在哪个函数里、它有哪些自己的名字、一个名字到底指的是什么（这一层的变量、
/// 外层函数的变量、模块级变量、还是一个有名字的函数）。
library;

import 'package:lopicode/lang/ast.dart';

/// 模块顶层有什么：函数、模块级变量。[prefix] 用来给它们在生成的代码里起名（一个脚本里有几个模块时互相不撞）。
class LangModuleInfo {
  const LangModuleInfo({this.funcs = const {}, this.vars = const {}, this.prefix = ''});

  LangModuleInfo.of(Iterable<LFuncDecl> functions, {this.vars = const {}, this.prefix = ''}) : funcs = {for (final f in functions) f.name: f};

  final Map<String, LFuncDecl> funcs;
  final Set<String> vars;
  final String prefix;
}

enum LangNameKind { local, module, function, unknown }

class LangResolved {
  const LangResolved(this.kind, {this.scope, this.func});
  final LangNameKind kind;

  /// [LangNameKind.local] 时：是哪一层的。
  final LangScope? scope;
  final LFuncDecl? func;
}

class LangScope {
  /// 宿主管着的一层（后端的接口函数体、单独生成的一段）：这一层有哪些变量语言核心不全知道，
  /// 所以认不出来的名字都当成这一层的变量（除非它是一个有名字的函数）。[locals] 是宿主说的“这一层已经有的变量”。
  LangScope.open({this.module = const LangModuleInfo(), Set<String>? locals, Set<String>? boxed})
    : parent = null,
      open = true,
      returnsValue = false,
      locals = locals ?? {},
      boxed = boxed ?? {},
      alias = const {},
      rename = const {};

  /// 一个函数自己的一层。[parent] 是 null＝模块顶层的函数（或模块的“启动时”）。
  LangScope.function(this.parent, {LangModuleInfo? module, required this.locals, Set<String>? boxed, this.alias = const {}, this.rename = const {}, this.returnsValue = true})
    : module = module ?? parent?.module ?? const LangModuleInfo(),
      open = false,
      boxed = boxed ?? {};

  final LangScope? parent;
  final LangModuleInfo module;
  final bool open;

  /// 是不是一个真的函数（“返回”总是可以用，没带值的返回空）。宿主那一层、模块的“启动时”不是。
  final bool returnsValue;

  /// 这一层自己的名字（参数、新建的变量、循环变量）。
  final Set<String> locals;

  /// 这一层的变量里要装“盒子”的（Java：被里层函数用到的）。
  final Set<String> boxed;

  /// 这一层的名字 → 直接写成的代码（Go / Java 短写法的匿名函数：参数是从参数表里现取的）。
  final Map<String, String> alias;

  /// 这一层的名字 → 在代码里改叫什么（Java 不许里层的变量和外层的重名）。
  final Map<String, String> rename;

  /// 等着放到“当前这一句”前面的代码（带函数体的匿名函数先在前面定义好，再在式子里用它的名字）。
  List<String> pending = [];

  int get depth => parent == null ? 0 : parent!.depth + 1;

  LangResolved resolve(String name) {
    for (LangScope? s = this; s != null; s = s.parent) {
      if (s.locals.contains(name)) return LangResolved(LangNameKind.local, scope: s);
      if (s.open) {
        if (module.vars.contains(name)) return const LangResolved(LangNameKind.module);
        final f = module.funcs[name];
        return f != null ? LangResolved(LangNameKind.function, func: f) : LangResolved(LangNameKind.local, scope: s);
      }
    }
    if (module.vars.contains(name)) return const LangResolved(LangNameKind.module);
    final f = module.funcs[name];
    return f != null ? LangResolved(LangNameKind.function, func: f) : const LangResolved(LangNameKind.unknown);
  }

  /// 外面几层（不算自己）看不看得见一个叫 [name] 的局部变量。
  bool outerHas(String name) {
    for (var s = parent; s != null; s = s.parent) {
      if (s.locals.contains(name)) return true;
    }
    return false;
  }
}

/// 一个函数体里共用的东西：给循环、匿名函数用的临时名字编号（同一个函数里不许重），和现在所在的作用域。
class LangCtx {
  LangCtx({LangScope? scope}) : scope = scope ?? LangScope.open();

  int _n = 0;
  int next() => ++_n;

  /// 现在在哪一层。生成器进出函数时会换。
  LangScope scope;

  /// 正在生成的那个函数体的 ctx（生成式子时要用：式子的函数不带 ctx 参数）。生成是同步的，用完就还原。
  static LangCtx? current;

  /// 在 [ctx] 里做一件事（宿主单独生成一个式子、声明变量时用）。
  static T run<T>(LangCtx ctx, T Function() body) {
    final prev = current;
    current = ctx;
    try {
      return body();
    } finally {
      current = prev;
    }
  }
}
