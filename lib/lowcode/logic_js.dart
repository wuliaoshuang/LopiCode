/// 把页面的逻辑翻成一份浏览器脚本（存成 logic.js，由 index.html 用 `<script src="logic.js" defer>` 引入）。
///
/// 不依赖任何库。页面变量放在一个 `state` 对象里；每个事件处理是一个具名函数；页面准备好以后按 class `n-<控件 id>`
/// 找到元素挂上事件（export_html.dart 给每个控件的元素都带了这个 class）。
///
/// 简化（也写在生成的脚本开头）：**没有数据绑定**——变量改了界面不会自己变，要让界面变得用“改控件”积木。
/// 通用的翻译（流程、运算、转义）在 logic_js_core.dart，Vue / React 导出复用那一部分。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

export 'package:lopicode/lowcode/logic_js_core.dart';

/// 普通网页的写法：变量在 `state` 对象里，控件属性通过 `lcGet` / `lcSet`（见 [lcJsDomRuntime]）读写 DOM。
class DomJsTarget extends JsTarget {
  const DomJsTarget();

  /// 名字合乎标识符写法就写 `state.count`，否则写 `state["…"]`（不把名字直接拼进代码）。
  @override
  String readVar(LcVariable v) => isJsIdentifier(v.name) ? 'state.${v.name}' : 'state[${jsString(v.name)}]';

  @override
  List<String> writeVar(LcVariable v, String valueJs) => ['${readVar(v)} = $valueJs;'];

  @override
  JsExpr readProp(LcNode node, String prop) => JsExpr('lcGet(${jsString(node.id)}, ${jsString(prop)})', prop == 'visible' ? LcType.boolean : LcType.text);

  @override
  List<String> writeProp(LcNode node, String prop, String valueJs) {
    if (!propFitsNode(prop, node.type)) {
      final label = lcSpecs[node.type]?.label ?? node.type;
      // 文字只有 <p> 和 <button> 能整段换：列表是 <ul>（里面是一条条 <li>），容器里面是别的控件，直接改文字会把它们冲掉。
      final why = prop == 'text' ? '$label的文字不能用积木改（导出的是 ${_tagOf(node.type)}，整段换文字会把里面的内容冲掉）' : '$label没有“${describeProp(prop)}”';
      return ['// 跳过：${jsComment(why)}'];
    }
    return ['lcSet(${jsString(node.id)}, ${jsString(prop)}, $valueJs);'];
  }

  static String _tagOf(String type) => switch (type) {
    'list' => '<ul>',
    'input' => '<input>',
    'image' => '<img>',
    'divider' => '<hr>',
    'page' => '<main>',
    _ => '<div>',
  };
}

/// 普通网页用的小工具：按 class 找元素、读写属性、挂事件。找不到元素一律安静跳过，不抛错。
const String lcJsDomRuntime = r'''
// 按控件 id 找页面上的元素（导出的 HTML 里每个控件都带 class "n-<id>"）。找不到返回 null。
function lcEl(id) {
  return document.querySelector(".n-" + id);
}

// 读控件：文字 / 输入内容 / 是否显示。
function lcGet(id, prop) {
  const el = lcEl(id);
  if (prop === "visible") return !!el && el.style.display !== "none";
  if (!el) return "";
  const v = prop === "value" ? el.value : el.textContent;
  return v === null || v === undefined ? "" : String(v);
}

// 改控件。显示 / 隐藏用 style.display：隐藏设成 "none"，显示时清掉这一条，让样式表里原来的 display（比如 flex）重新生效。
function lcSet(id, prop, value) {
  const el = lcEl(id);
  if (!el) return;
  if (prop === "text") el.textContent = value;
  else if (prop === "value") el.value = value;
  else if (prop === "visible") el.style.display = value ? "" : "none";
  else if (prop === "bg") el.style.background = value;
  else if (prop === "color") el.style.color = value;
  else if (prop === "placeholder") el.placeholder = value;
  else if (prop === "src") {
    if (el.tagName === "IMG") el.src = value;
    else {
      // 没填图片地址的图片导出的是一个占位的 <div>，没有 src：改成背景图。
      el.style.backgroundImage = "url(" + JSON.stringify(value) + ")";
      el.style.backgroundSize = "cover";
      el.style.backgroundPosition = "center";
    }
  }
}

// 给控件挂事件。
function lcOn(id, type, handler) {
  const el = lcEl(id);
  if (el) el.addEventListener(type, handler);
}
''';

const String _header = '''// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份脚本：
// - 页面变量都在 state 里；每个“处理”是下面的一个函数；最后的 lcStart 把它们挂到控件上。
// - 变量改了以后，界面上不会自动跟着变（没有数据绑定）。要让界面变，用“改控件”积木（下面的 lcSet）。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）；除以 0 的结果也当 0。要拼文字用“拼成文字”。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
"use strict";
''';

List<String> _indentBlock(String text) => [for (final l in text.trim().split('\n')) l.isEmpty ? '' : l];

/// 变量的初始值写成字面量。按声明的类型再收一遍（内存里的对象可能被改得类型对不上）。
String _initialLiteral(LcVariable v) {
  final value = v.initial;
  return switch (v.type) {
    'number' => value is num && value.isFinite ? (value is int || value == value.roundToDouble() && value.abs() < 1e15 ? '${value.round()}' : '$value') : '0',
    'bool' => value == true ? 'true' : 'false',
    _ => jsString(value is String ? value : ''),
  };
}

/// 把整页的逻辑翻成一份脚本。没有变量也没有处理时返回空字符串（调用方据此决定要不要生成 logic.js）。
///
/// 任何输入都不抛异常、生成的脚本语法始终正确：有问题的积木翻成一行注释跳过（问题的详细说明用 `validateLogic` 看）。
String exportLogicJs(LcDocument doc) {
  final logic = doc.logic;
  if (logic.isEmpty) return '';
  const target = DomJsTarget();
  final writer = JsLogicWriter(doc, target);
  final names = logicHandlerNames(doc);
  final out = StringBuffer(_header)..writeln();

  // —— 变量 ——
  final seen = <String>{};
  out.writeln('// 页面变量');
  out.writeln('const state = {');
  for (final v in logic.variables) {
    if (!seen.add(v.name)) continue; // 重名的只留第一个
    // 名字不合标识符写法的用 ["…"] 这种写法（含 __proto__：这样写才是一个普通的键，不会去动原型）。
    out.writeln('  ${isJsIdentifier(v.name) ? v.name : '[${jsString(v.name)}]'}: ${_initialLiteral(v)},');
  }
  out.writeln('};');
  out.writeln();

  // —— 小工具 ——
  out.writeln('// —— 小工具（每份导出都一样）——');
  _indentBlock(lcJsRuntime).forEach(out.writeln);
  out.writeln();
  _indentBlock(lcJsDomRuntime).forEach(out.writeln);
  out.writeln();

  // —— 处理 ——
  final start = <String>[];
  for (var i = 0; i < logic.handlers.length; i++) {
    final h = logic.handlers[i];
    final name = names[i];
    out.writeln('// ${jsComment(describeHandler(h, doc))}');
    out.writeln('function $name(${h.event == 'load' ? '' : 'event'}) {');
    for (final line in writer.blocks(h.body, event: h.event)) {
      out.writeln('  $line');
    }
    out.writeln('}');
    out.writeln();

    final targetId = h.target;
    final node = targetId == null ? null : doc.find(targetId);
    if (h.event == 'load') {
      start.add('$name();');
    } else if (h.event != 'click' && h.event != 'input') {
      start.add('// $name：${jsComment('不认识的事件 ${h.event}')}，没有挂上');
    } else if (node == null || !isSafeNodeId(node.id)) {
      start.add('// $name：触发它的控件不在页面里，没有挂上');
    } else {
      start.add('lcOn(${jsString(node.id)}, "${h.event}", $name);');
    }
  }

  out.writeln('// 页面准备好以后：把处理挂到控件上，再执行“页面打开时”的处理。');
  out.writeln('function lcStart() {');
  for (final line in start) {
    out.writeln('  $line');
  }
  out.writeln('}');
  out.writeln();
  // 用 defer 引入时脚本在 DOMContentLoaded 之前执行，正常走第一条；万一被放到页面最后或动态插入（页面已经准备好了），直接开始。
  out.writeln('if (document.readyState === "loading") {');
  out.writeln('  document.addEventListener("DOMContentLoaded", lcStart);');
  out.writeln('} else {');
  out.writeln('  lcStart();');
  out.writeln('}');
  return out.toString();
}
