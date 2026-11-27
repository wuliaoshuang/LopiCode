/// React 导出里“积木逻辑怎么读写变量和控件属性”（从 export_react.dart 拆出来的，内容没变）。
library;

import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react_bind.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

String _member(String object, String key) => isJsIdentifier(key) ? '$object.$key' : '$object[${jsString(key)}]';

/// React 的写法：变量在 `lcVars`、控件属性在 `lcUi`（见文件开头的说明），写完调用 `lcRefresh()`。
class ReactJsTarget extends JsTarget {
  ReactJsTarget(this.states, this.notes, {this.bind});
  final LcPropStates states;
  final List<String> notes;

  /// 用了状态与绑定的页面才有：项目级状态、派生值各有各的读写法。
  final LcReactBind? bind;

  @override
  String readVar(LcVariable v) => bind?.read(v.name) ?? _member('lcVars', v.name);

  @override
  List<String> writeVar(LcVariable v, String valueJs) => bind?.write(v.name, valueJs) ?? ['${readVar(v)} = $valueJs;', 'lcRefresh();'];

  @override
  JsExpr readProp(LcNode node, String prop) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: false);
      notes.add('逻辑里有一处读不到：$why。');
      return JsExpr('"" /* ${jsComment(why)} */', LcType.text);
    }
    return JsExpr('lcUi.${states.require(node, prop).name}', prop == 'visible' ? LcType.boolean : LcType.text);
  }

  @override
  List<String> writeProp(LcNode node, String prop, String valueJs) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: true);
      notes.add('逻辑里有一块“改控件”被跳过了：$why。');
      return ['// 跳过：${jsComment(why)}'];
    }
    return ['lcUi.${states.require(node, prop).name} = $valueJs;', 'lcRefresh();'];
  }

  @override
  List<String> goPage(LcDocument doc, LcPage page) => lcHashGoPage(page);
}
