/// Agent 的两个后端积木工具：读（`backend_get_blocks`）和改（`backend_update_blocks`）。
///
/// 做法照低代码页面的两个工具，但实现放在这里、由 lib/session/toolbox_builder.dart 组装进工具箱
/// （lib/agent 不许依赖 lib/backend）。安全规矩：
/// - 读是 [ToolKind.read]、改是 [ToolKind.write]：“仅可查看”和计划模式下改的那个不会出现，硬调也会被工具箱拒绝；
/// - 路径都过 [PathGuard]；文件必须叫 `backend.lc.json`；团队任务的写入范围（`writeScope`）照样管；
/// - 改：容错解析 → 校验 → 有错误就拒绝（什么都不写）→ 落盘 → 重新生成代码（只覆盖我们自己生成的文件）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:path/path.dart' as p;

const String kBackendGetTool = 'backend_get_blocks';
const String kBackendUpdateTool = 'backend_update_blocks';

/// 写进工具说明里的模型结构（精简版；完整的表在 docs/blocks-v3-design.md）。
String backendModelGuide() =>
    '''文档：{name, port, language, variables:[{name,type:"text|number|bool",initial}], collections:[{name}], routes:[{id, method:"GET|POST|PUT|PATCH|DELETE", path:"/todos/:id", body:[积木…]}]}。language 现在可选：${backendTargets.map((t) => t.id).join(' / ')}。
路径参数写 :名字；接口从上到下匹配（/todos/count 要排在 /todos/:id 前面）；接口跑完没有“返回”积木回 204。变量每次请求重置；集合存在内存里，每条自动带数字 id。
积木：{op, args:{…}, body?:[…], else?:[…]}。op 与 args：
- respondJson{status,value} / respondText{status,value}：返回并结束
- dbInsert{collection,value,into?}、dbUpdate{collection,id,value}（只改给出的字段）、dbDelete{collection,id}
- setVar{name,value}、changeVar{name,by}
- if{cond}+body+else、repeat{times}+body、forEach{list,item}+body
- log{value}、fetch{url,method:"GET|POST",data?,into?}+body(成功)+else(失败)
collection / name / into / item 直接写名字（字符串，要先在 collections / variables 里声明）；其余参数是表达式 {e:种类,…}：
text{v} num{v} bool{v} var{name} bin{l,op,r}（op: + - * / % == != < <= > >= and or） not{x} join{items:[…]}
pathParam{name} query{name} bodyField{name} body{} header{name}（name 直接写字符串，读不到是空）
dbAll{collection} dbGet{collection,id} dbFind{collection,key,value} dbCount{collection}
len{x} isNull{x} now{} obj{fields:[{e:"pair",key:"title",value:表达式}]}（字典） field{of,key}
${backendLangGuide()}
${backendFuncGuide()}
例：{"op":"respondJson","args":{"status":{"e":"num","v":200},"value":{"e":"dbAll","collection":"todos"}}}''';

/// 第 4 版（语言核心）新加的积木和表达式，接在 [backendModelGuide] 后面。
String backendLangGuide() => '''语言核心（第 4 版，用到了文档版本自动升到 2）：
- let{name,value} / const{name,value}：在这个接口里新建变量 / 常量（name 直接写名字，不用在 variables 里声明；常量不许再改）；之后用 var{name} 读、setVar 改
- if 可以带“否则如果”：{op:"if",args:{cond},body:[…],arms:[{args:{cond},body:[…]}…],else:[…]}
- switch{value}+arms:[{args:{value},body:[…]}…]+else(都不是)：等于哪一种就做哪一段
- while{cond}+body、forever+body、forCount{name,from,to,step}+body（含两头）、forEach{list,item,index?}+body（index 是序号的新名字，从 0 数）、forPairs{dict,key,value}+body（key / value 是新名字）、break、continue
- listPush{xs,v} listInsert{xs,i,v} listSet{xs,i,v} listRemove{xs,i} setItem{of,key,value} dictSet{d,k,v} dictRemove{d,k}：原地改列表 / 字典；do{value}：只算一下；note{text}
表达式：logic{l,op:"and|or",r}（短路）；cond{cond,then,orElse}；neg{x}；null{}；isType{x,type:"number|text|bool|null|list|dict"}；convert{x,fn:"toNumber|toText|toBool"}；copy{x}
round{x,fn:"round|floor|ceil"} math{x,fn:"abs|sqrt"} minmax{a,b,fn:"max|min"} pow{a,b} random{a,b}
charAt{s,i} substring{s,from,to} indexOf{sub,s} textHas{s,fn:"contains|startsWith|endsWith",sub} replace{s,from,to} textCase{s,fn:"trim|upper|lower"} repeatText{s,n} split{s,sep} template{s,dict} toJson{x} fromJson{s}
listLit{items:[…]} range{a,b,step} index{of,key} listGet{xs,i} listPop{xs} listContains{xs,v} listIndexOf{v,xs} listSlice{xs,from,to} listConcat{a,b} listOrder{xs,fn:"listReverse|listSort"} listJoin{xs,sep}
dictGet{d,k} dictHas{d,k} dictPart{d,fn:"dictKeys|dictValues|dictPairs"} dictMerge{a,b}
位置都从 0 数；“跳出 / 跳过”只能放在循环里；同一个接口里新名字不能重复。''';

/// 第 4 版第 2 阶段（函数和“我的积木”）的写法，接在 [backendLangGuide] 后面。
String backendFuncGuide() =>
    '''函数 /“我的积木”（用到了文档版本自动升到 3）：文档顶层加 functions:[{id:"f1", look:{name:"打招呼", shape?:"auto|statement|value|boolean", template?:"向 {谁} 打招呼"}, params:[{name:"谁", default?:"你", rest?:true}], body:[积木…]}]。
- id 写 f 加数字；名字在 look.name 里，不能重名；参数最多 $kBeMaxParams 个，名字不能叫 e、不能用 @ 开头；default 只能是文字 / 数字 / 是否；rest:true＝“剩下的全收”，只能是最后一个（函数里拿到的是一个列表）
- 函数里读参数用 param{name}；交回结果用积木 return{value}，不带值地结束用 returnNothing；函数里看不见 variables 里的变量（要用就当参数传进来），也不能放 respondJson / respondText / fetch
- 调用：单独成句写积木 {op:"call:f1", args:{谁:表达式}}；要它的返回值写表达式 {e:"call:f1", 谁:表达式}。实参按参数名给，没给的用默认值；rest 参数给 listLit{items:[…]} 就逐项传进去。函数可以自己调自己
- 匿名函数：lambda{params:["x"], "@body":[积木…]}（里面用 return 交回结果，能读、能改外面用 let 建的变量）；只有一个式子的写 lambdaExpr{params:["x"], body:表达式}；funcRef{fn:"f1"}＝把一块“我的积木”当成值
- 调用放在变量 / 参数里的函数：表达式 callValue{fn, args:[…]}，单独成句用积木 callValueStmt{fn, args:[…]}
- 拿函数当参数的列表操作（fn 填 lambda / lambdaExpr / funcRef / 存着函数的变量）：积木 listEach{xs,fn}；表达式 listMap{xs,fn} listFilter{xs,fn} listFind{xs,fn}（没有是空） listSome{xs,fn} listEvery{xs,fn} listSortBy{xs,fn}（按 fn 算的分从小到大） listReduce{xs,fn,init}（fn 收两个参数：累到现在的、这一项）''';

/// 一串积木的读法（往 `out` 里一行行写）。`fnName`＝函数 id → 名字。
void _describeBlocks(StringBuffer out, List<LcBlock> list, String indent, int depth, String? Function(String id) fnName) {
  if (depth > LcBlock.maxDepth + 2) return;
  for (final b in list) {
    out.writeln('$indent- ${describeBeBlock(b, fnName)}');
    _describeBlocks(out, b.body, '$indent  ', depth + 1, fnName);
    for (var k = 0; k < b.arms.length; k++) {
      out.writeln('$indent  第 ${k + 1} 段（${beBlockSpecs[b.op]?.arms?.label ?? '段'} ${[for (final v in b.arms[k].args.values) describeBeExpr(v, fnName)].join(' ')}）：');
      _describeBlocks(out, b.arms[k].body, '$indent  ', depth + 1, fnName);
    }
    if (b.orElse.isNotEmpty) {
      out.writeln('$indent  ${beBlockSpecs[b.op]?.arms == null ? '否则 / 失败后' : (beBlockSpecs[b.op]?.elseLabel ?? '否则')}：');
      _describeBlocks(out, b.orElse, '$indent  ', depth + 1, fnName);
    }
    final mouths = b.exprMouths;
    for (var k = 0; k < mouths.length; k++) {
      out.writeln('$indent  ${mouths.length == 1 ? '匿名函数里' : '第 ${k + 1} 个匿名函数里'}：');
      _describeBlocks(out, mouths[k], '$indent  ', depth + 1, fnName);
    }
  }
}

/// 整份文档的中文读法（每个接口一行标题，下面是一块块积木）。
String describeBackendDocument(BeDocument doc) {
  final out = StringBuffer();
  out.writeln('服务“${doc.name}”，语言 ${backendTargetOf(doc)?.label ?? doc.language}，端口 ${doc.port}。');
  if (doc.variables.isNotEmpty) out.writeln('变量：${doc.variables.map((v) => v.name).join('、')}');
  if (doc.collections.isNotEmpty) out.writeln('数据集合：${doc.collections.map((c) => c.name).join('、')}');
  if (doc.routes.isEmpty) out.writeln('（还没有接口）');
  String? fnName(String id) => doc.function(id)?.name;
  for (final r in doc.routes) {
    out.writeln('接口 ${describeBeRoute(r)}（id ${r.id}）：');
    if (r.body.isEmpty) out.writeln('  （空的，会回 204）');
    _describeBlocks(out, r.body, '  ', 0, fnName);
  }
  for (final f in doc.functions) {
    final params = [for (final p in f.params) '${p.name}${p.rest ? '…（剩下的全收）' : ''}${p.defaultValue == null ? '' : '＝${p.defaultValue}'}'];
    out.writeln('我的积木“${f.name}”（id ${f.id}${params.isEmpty ? '，没有参数' : '，参数：${params.join('、')}'}）：');
    if (f.body.isEmpty) out.writeln('  （空的，什么都不做）');
    _describeBlocks(out, f.body, '  ', 0, fnName);
  }
  return out.toString().trimRight();
}

String _issueLines(List<Object> issues) => issues.map((i) => '- $i').join('\n');

/// 造这两个工具。`writeScope`＝团队任务给的写入范围（工作区内的相对路径前缀；null 不限）。
List<ExtraTool> backendTools({required PathGuard guard, List<String>? writeScope}) {
  /// 给的路径（或自动找到的那份）→ 工作区内的相对路径。必须叫 backend.lc.json。
  Future<String> locate(Object? raw, {required bool forWrite}) async {
    if (raw != null && raw is! String) throw ToolArgError('参数 path 应为字符串');
    var rel = (raw as String?)?.trim() ?? '';
    if (rel.isEmpty) {
      final found = await findBackendProjects(guard.root);
      if (found.isNotEmpty) return found.first.file;
      if (!forWrite) throw ToolArgError('这个项目里没有 $kBackendFileName。要新建一份，用 $kBackendUpdateTool 传完整的文档');
      rel = kBackendFileName;
    }
    final full = guard.resolve(rel); // 越界、内部目录在这里被拒绝
    rel = guard.relative(full);
    if (p.posix.basename(rel) != kBackendFileName) throw ToolArgError('后端积木文件必须叫 $kBackendFileName（可以放在子目录里，如 server/$kBackendFileName）');
    return rel;
  }

  void checkScope(String rel) {
    final scope = writeScope;
    if (scope == null) return;
    for (final raw in scope) {
      var prefix = raw.trim();
      while (prefix.endsWith('/')) {
        prefix = prefix.substring(0, prefix.length - 1);
      }
      if (prefix.isEmpty || prefix == '.' || rel == prefix || rel.startsWith('$prefix/')) return;
    }
    throw ToolArgError('这个任务的写入范围是 ${scope.join('、')}，$rel 不在范围内，没有改动');
  }

  Future<ToolOutcome> guarded(Future<ToolOutcome> Function() run) async {
    try {
      return await run();
    } on PathGuardException catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on ToolArgError catch (e) {
      return ToolOutcome('错误：${e.message}', ok: false);
    } on FileSystemException catch (e) {
      return ToolOutcome('错误：文件操作失败（${e.osError?.message ?? e.message}）', ok: false);
    }
  }

  Future<ToolOutcome> get(Map<String, dynamic> args) => guarded(() async {
    final rel = await locate(args['path'], forWrite: false);
    final file = File(guard.resolve(rel));
    if (!await file.exists()) return ToolOutcome('错误：文件不存在：$rel', ok: false);
    if (await file.length() > kBackendMaxFileBytes) return ToolOutcome('错误：$rel 太大了（超过 2MB），没有读', ok: false);
    final source = await file.readAsString();
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      return ToolOutcome('错误：$rel 不是合法的 JSON（${e.message}）。可以用 read_file 看原文，或用 $kBackendUpdateTool 整份重写', ok: false);
    }
    if (json is! Map || (json['kind'] != null && json['kind'] != 'backend')) {
      return ToolOutcome('错误：$rel 不是后端积木文件（应该是 kind 为 backend 的对象）', ok: false);
    }
    final parsed = BeDocument.fromJson(json);
    final issues = validateBackend(parsed.doc, languages: backendTargets.map((t) => t.id));
    final out = StringBuffer();
    out.writeln('文件：$rel');
    out.writeln(parsed.doc.encode());
    out.writeln();
    out.writeln('—— 读法 ——');
    out.writeln(describeBackendDocument(parsed.doc));
    out.writeln();
    if (parsed.note != null) out.writeln('注意：${parsed.note}（上面显示的是跳过之后的内容）');
    out.writeln(
      issues.isEmpty
          ? '校验：没有问题。'
          : '校验：${issues.where((i) => i.isError).length} 处错误，${issues.where((i) => !i.isError).length} 处提醒\n${_issueLines([for (final i in issues) '${i.isError ? '错误' : '提醒'}：${i.where}——${i.problem}'])}',
    );
    return ToolOutcome(out.toString().trimRight());
  });

  Future<ToolOutcome> update(Map<String, dynamic> args) => guarded(() async {
    Object? value = args['backend'];
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw ToolArgError('backend 不是合法 JSON');
      }
    }
    if (value is! Map<String, dynamic>) throw ToolArgError('缺少参数 backend（应为对象）');
    if (value['routes'] is! List) throw ToolArgError('backend.routes 应为数组（没有接口就传 []）');
    if (value['kind'] != null && value['kind'] != 'backend') throw ToolArgError('backend.kind 只能是 "backend"');
    final rel = await locate(args['path'], forWrite: true);
    final dir = p.posix.dirname(rel) == '.' ? '' : p.posix.dirname(rel);
    final file = File(guard.resolve(rel));

    // 没带的顶层字段沿用现有文件的（Agent 只想改接口时常常不带 name / port / language）；routes 必须给全。
    var merged = value;
    if (await file.exists()) {
      try {
        final old = jsonDecode(await file.readAsString());
        if (old is Map<String, dynamic>) {
          merged = {
            ...merged,
            for (final k in const ['name', 'port', 'language', 'variables', 'collections', 'functions'])
              if (!merged.containsKey(k) && old[k] != null) k: old[k],
          };
        }
      } on FormatException {
        // 现有文件本来就坏了：没有可沿用的，照新的写。
      }
    }
    final problems = <String>[];
    final port = merged['port'];
    if (port != null && (port is! int || port < 1 || port > 65535)) problems.add('port 要是 1–65535 的整数');
    final language = merged['language'];
    if (language != null && (language is! String || backendTargetFor(language) == null)) {
      problems.add('language “$language”还没有生成器，现在可选：${backendTargets.map((t) => t.id).join('、')}');
    }
    final parsed = BeDocument.fromJson(merged);
    if (merged['functions'] != null && merged['functions'] is! List) problems.add('functions 应为数组（没有自定义积木就传 [] 或不传）');
    if (parsed.note != null) problems.add('${parsed.note}——有读不懂的条目（变量 / 集合 / 接口 / 自定义积木的格式不对），请改对再传');
    final doc = parsed.doc;
    // 接口里的积木是容错读的（坏的积木会被悄悄丢掉）：数一数，少了就说出来，不让模型以为都写进去了。
    final given = _countBlocks(merged['routes']) + _countBlocks(merged['functions']);
    final kept = [...doc.routes.map((r) => r.body), ...doc.functions.map((f) => f.body)].fold<int>(0, (n, body) => n + _countParsed(body));
    if (kept < given) problems.add('有 ${given - kept} 块积木的格式不对（每块应是 {op, args, body?, else?}）');
    final rawFns = merged['functions'];
    if (rawFns is List && doc.functions.length < rawFns.length) {
      problems.add('functions 里有 ${rawFns.length - doc.functions.length} 条读不懂或超出上限（每条应是 {id, look:{name}, params:[…], body:[…]}，最多 $kBeMaxFunctions 条）');
    }
    if (rawFns is List) {
      for (final raw in rawFns) {
        final ps = raw is Map ? raw['params'] : null;
        final f = raw is Map && raw['id'] is String ? doc.function('${raw['id']}') : null;
        if (ps is List && f != null && f.params.length < ps.length) problems.add('自定义积木“${f.name}”有 ${ps.length - f.params.length} 个参数读不懂、重名或超出上限（最多 $kBeMaxParams 个，每个应是 {name, default?, rest?}）');
      }
    }
    final issues = validateBackend(doc, languages: backendTargets.map((t) => t.id));
    for (final i in issues.where((i) => i.isError)) {
      problems.add('${i.where}——${i.problem}');
    }
    if (problems.isNotEmpty) {
      return ToolOutcome('错误：后端积木有问题，没有保存，文件没有改动：\n${_issueLines(problems)}', ok: false);
    }

    final gen = backendProjectFiles(doc, dir: dir);
    if (gen == null) return ToolOutcome('错误：语言“${doc.language}”还没有生成器，没有保存', ok: false);
    checkScope(rel);
    for (final key in gen.files.keys) {
      checkScope(dir.isEmpty ? key : '$dir/$key');
    }
    await file.parent.create(recursive: true);
    await saveBackendFile(file, doc);
    final result = await regenerateBackend(guard.root, file: rel, doc: doc);
    final warnings = [for (final i in issues.where((i) => !i.isError)) '${i.where}——${i.problem}'];
    final out = StringBuffer('已保存 $rel。${result.summary}');
    if (warnings.isNotEmpty) out.write('\n提醒（不影响保存）：\n${_issueLines(warnings)}');
    final info = (await findBackendProjects(guard.root)).where((b) => b.file == rel).firstOrNull;
    if (info?.terminalCommand != null) out.write('\n启动命令（在项目目录里）：${info!.terminalCommand}');
    return ToolOutcome(out.toString(), ok: result.ok, changedFiles: true);
  });

  return [
    ExtraTool(
      spec: toolSpec(kBackendGetTool, '读取后端积木文件（$kBackendFileName）：返回它的 JSON、中文读法和校验出的问题。后端的接口是用积木搭的，代码由积木生成——要改后端先读这个，不要直接改生成的代码文件。', {
        'path': {'type': 'string', 'description': '文件在项目里的相对路径；省略则自动找（根目录或 server/ 下的 $kBackendFileName）'},
      }),
      kind: ToolKind.read,
      run: get,
    ),
    ExtraTool(
      spec: toolSpec(
        kBackendUpdateTool,
        '用新的 JSON 整体替换后端积木文件，校验通过后保存并重新生成所选语言的代码（校验有错误会拒绝并列出问题，什么都不改）。\n${backendModelGuide()}',
        {
          'backend': {'type': 'object', 'description': '完整的后端文档。routes 必须给全（没给的接口会被删掉）；name / port / language / variables / collections / functions 不传就沿用现有的（要删光自定义积木传 functions: []）'},
          'path': {'type': 'string', 'description': '文件在项目里的相对路径；省略则自动找，找不到就在根目录新建 $kBackendFileName'},
        },
        ['backend'],
      ),
      kind: ToolKind.write,
      run: update,
    ),
  ];
}

/// 原始 JSON 里一共写了多少块积木（按 {op:…} 的对象数，沿 body / arms / else 和匿名函数的口往里数）。`trees`＝routes 或 functions。
int _countBlocks(Object? trees) {
  var n = 0;
  late void Function(Object? list, int depth) walk;
  // 参数里的匿名函数：它口里的积木也要数。
  void mouths(Object? value, int depth) {
    if (depth > LcBlock.maxDepth + kMaxExprDepth * 2 + 8) return;
    if (value is Map) {
      for (final e in value.entries) {
        e.key == kLcExprBody ? walk(e.value, depth + 1) : mouths(e.value, depth + 1);
      }
    } else if (value is List) {
      for (final v in value) {
        mouths(v, depth + 1);
      }
    }
  }

  walk = (list, depth) {
    if (list is! List || depth > LcBlock.maxDepth + kMaxExprDepth * 2 + 8) return;
    for (final b in list) {
      n++;
      if (b is Map) {
        mouths(b['args'], depth + 1);
        walk(b['body'], depth + 1);
        final arms = b['arms'];
        if (arms is List) {
          for (final a in arms.take(LcBlock.maxArms)) {
            if (a is Map) {
              mouths(a['args'], depth + 1);
              walk(a['body'], depth + 1);
            }
          }
        }
        walk(b['else'], depth + 1);
      }
    }
  };

  if (trees is List) {
    for (final r in trees) {
      if (r is Map) walk(r['body'], 0);
    }
  }
  return n;
}

int _countParsed(List<LcBlock> list) {
  var n = 0;
  beVisitBlocks(list, (_) => n++);
  return n;
}
