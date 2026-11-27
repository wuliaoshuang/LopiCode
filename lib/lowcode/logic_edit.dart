/// 逻辑的“连带修改”：删控件时清掉引用它的处理和积木、变量改名 / 删除时同步引用、查某个东西还有没有人在用。
///
/// 单纯的结构操作（按路径插入 / 删除 / 移动积木、深拷贝）在 logic_model.dart；这里的操作要知道
/// “哪个参数是变量名、哪个是控件 id”，所以照着积木目录（logic_blocks.dart）来，放在这个文件。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 走一遍一块积木参数里所有的表达式（含嵌在里面的），`visit` 拿到的是可以原地改的 Map。
void _visitExprs(Object? value, void Function(Map<Object?, Object?> expr) visit, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2) return;
  if (value is Map) {
    if (isExpr(value)) visit(value);
    for (final v in value.values) {
      _visitExprs(v, visit, depth + 1);
    }
  } else if (value is List) {
    for (final v in value) {
      _visitExprs(v, visit, depth + 1);
    }
  }
}

/// 积木自己（不含表达式里）哪些参数是某一种（变量名 / 控件 id）。
Iterable<String> _argsOfKind(LcBlock b, LcArgKind kind) => [
  for (final a in lcBlockSpecs[b.op]?.args ?? const <LcArgSpec>[])
    if (a.kind == kind) a.name,
];

void _walk(List<LcBlock> list, void Function(LcBlock b) visit) {
  for (final b in list) {
    visit(b);
    _walk(b.body, visit);
    _walk(b.orElse, visit);
  }
}

extension LcLogicEdit on LcLogic {
  /// 有多少处用到了这个控件（挂在它上面的处理 + 改它的积木 + 读它的表达式）。删控件前可以先问一句。
  int nodeRefCount(String nodeId) {
    var n = 0;
    for (final h in handlers) {
      if (h.target == nodeId) n++;
      _walk(h.body, (b) {
        for (final a in _argsOfKind(b, LcArgKind.node)) {
          if (b.args[a] == nodeId) n++;
        }
        _visitExprs(b.args, (e) {
          if (e['e'] == 'prop' && e['node'] == nodeId) n++;
        });
      });
    }
    return n;
  }

  /// 控件删掉以后清理逻辑：挂在它上面的处理整个删掉；改它的积木删掉；读它的表达式换成一段空文字
  /// （表达式不能直接拿掉，不然外面那块积木就缺参数了）。返回改了几处。
  int removeNodeRefs(String nodeId) {
    var n = 0;
    final before = handlers.length;
    handlers.removeWhere((h) => h.event != 'load' && h.target == nodeId);
    n += before - handlers.length;

    void clean(List<LcBlock> list) {
      final len = list.length;
      list.removeWhere((b) => _argsOfKind(b, LcArgKind.node).any((a) => b.args[a] == nodeId));
      n += len - list.length;
      for (final b in list) {
        _visitExprs(b.args, (e) {
          if (e['e'] == 'prop' && e['node'] == nodeId) {
            e
              ..clear()
              ..addAll(exText(''));
            n++;
          }
        });
        clean(b.body);
        clean(b.orElse);
      }
    }

    for (final h in handlers) {
      clean(h.body);
    }
    return n;
  }

  /// 有多少处用到了这个变量（设置 / 加上 / 请求结果放进它 / 读它）。
  int variableRefCount(String name) {
    var n = 0;
    for (final h in handlers) {
      _walk(h.body, (b) {
        for (final a in _argsOfKind(b, LcArgKind.variable)) {
          if (b.args[a] == name) n++;
        }
        _visitExprs(b.args, (e) {
          if (e['e'] == 'var' && e['name'] == name) n++;
        });
      });
    }
    return n;
  }

  /// 变量改名，所有用到它的地方一起改。新名字不合规矩、已经被别的变量用了、或没有这个变量，就什么都不改，返回 false。
  bool renameVariable(String oldName, String newName) {
    final v = variable(oldName);
    if (v == null || !LcVariable.namePattern.hasMatch(newName)) return false;
    if (oldName == newName) return true;
    if (variable(newName) != null) return false;
    v.name = newName;
    renameVariableRefs(oldName, newName);
    return true;
  }

  /// 只改“用到它的地方”（积木的参数和值），不动变量表。项目级状态改名时，各页的积木靠它跟着改。
  void renameVariableRefs(String oldName, String newName) {
    for (final h in handlers) {
      _walk(h.body, (b) {
        for (final a in _argsOfKind(b, LcArgKind.variable)) {
          if (b.args[a] == oldName) b.args[a] = newName;
        }
        _visitExprs(b.args, (e) {
          if (e['e'] == 'var' && e['name'] == oldName) e['name'] = newName;
        });
      });
    }
  }

  /// 删变量。用到它的积木**不动**（校验会把它们标成“变量还没有声明”，由人决定怎么改）。返回是否删了。
  bool removeVariable(String name) {
    final before = variables.length;
    variables.removeWhere((v) => v.name == name);
    return variables.length != before;
  }

  /// 改变量的类型，初始值跟着换成新类型的默认值（原来的值能直接用就留着）。类型不认识返回 false。
  bool retypeVariable(String name, String type) {
    final i = variables.indexWhere((v) => v.name == name);
    if (i < 0 || !LcVariable.stateTypes.contains(type)) return false;
    variables[i] = LcVariable(name: name, type: type, initial: variables[i].initial, derived: variables[i].derived);
    return true;
  }
}
