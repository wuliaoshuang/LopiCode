/// 新建项目用的后端积木入门样本，和“后端服务（积木）”模板要写进项目的文件。
///
/// 样本是一份能直接跑的小服务：问候接口（网址参数 + 条件）、待办的增删改查（集合读写、路径参数、请求内容字段）、计数接口。
/// 校验必须零问题（test/project_templates_test.dart 守着）。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';

LcBlock _b(String op, Map<String, dynamic> args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
LcBlock _json(int status, Map<String, dynamic> value) => _b('respondJson', {'status': exNum(status), 'value': value});
LcBlock _if(Map<String, dynamic> cond, List<LcBlock> then, [List<LcBlock>? orElse]) => _b('if', {'cond': cond}, body: then, orElse: orElse);

/// 入门样本。`name`＝服务名（一般是项目名），`language`＝语言 id。
///
/// 这是“新建后端积木文档”唯一的入口，所以新文档的规矩版本在这里定：默认读 `beNewDocRules`（backend_targets.dart；它默认跟着开关 `kLangRulesForNewDocs`）。
BeDocument backendStarterDocument(String name, {String language = kBeDefaultLanguage, int port = kBeDefaultPort, int? rules}) {
  rules ??= beNewDocRules;
  final id = bePathParam('id');
  final doc = BeDocument(
    name: name.trim().isEmpty ? '我的后端' : name.trim(),
    port: port,
    language: language,
    variables: [LcVariable(name: 'todo')],
    collections: [BeCollection(name: 'todos')],
    rules: rules,
  );
  void route(String method, String path, List<LcBlock> body) => doc.addRoute(method, path)!.body.addAll(body);
  // 严格规矩下“等于”不再把空和 "" 当成一样，所以可能是空的值先明着处理：网址参数“是空就用 \"\"”，请求内容的字段先问“是空”。
  // 老规矩的样本一个字不变。
  final strict = langRulesStrict(rules);
  final who = strict ? {'e': 'orElse', 'x': beQuery('name'), 'd': exText('')} : beQuery('name');
  final title = beBodyField('title');
  final noTitle = strict ? {'e': 'logic', 'op': 'or', 'l': beIsNull(title), 'r': exBin('==', title, exText(''))} : exBin('==', title, exText(''));
  LcBlock notFound() => _if(beIsNull(beDbGet('todos', id)), [
    _json(
      404,
      beObj({
        'error': exJoin([exText('找不到 id 是 '), id, exText(' 的待办')]),
      }),
    ),
  ]);

  // 问候：/hello?name=小明 → 带名字；没带名字 → 你好，世界
  route('GET', '/hello', [
    _if(
      exBin('!=', who, exText('')),
      [
        _json(
          200,
          beObj({
            'message': exJoin([exText('你好，'), who, exText('！')]),
          }),
        ),
      ],
      [
        _json(200, beObj({'message': exText('你好，世界！')})),
      ],
    ),
  ]);

  // 待办：增删改查
  route('GET', '/todos', [_json(200, beDbAll('todos'))]);
  route('POST', '/todos', [
    _if(noTitle, [
      _json(400, beObj({'error': exText('缺少 title')})),
    ]),
    _b('dbInsert', {
      'collection': 'todos',
      'value': beObj({'title': beBodyField('title'), 'done': exBool(false), 'createdAt': beNow()}),
      'into': 'todo',
    }),
    _json(201, exVar('todo')),
  ]);
  // 计数：要排在 /todos/:id 前面（接口从上到下匹配）
  route('GET', '/todos/count', [
    _json(200, beObj({'count': beDbCount('todos')})),
  ]);
  route('GET', '/todos/:id', [notFound(), _json(200, beDbGet('todos', id))]);
  route('PATCH', '/todos/:id', [
    notFound(),
    _b('dbUpdate', {
      'collection': 'todos',
      'id': id,
      'value': beObj({'done': beBodyField('done')}),
    }),
    _json(200, beDbGet('todos', id)),
  ]);
  route('DELETE', '/todos/:id', [
    notFound(),
    _b('dbDelete', {'collection': 'todos', 'id': id}),
    _json(200, beObj({'ok': exBool(true)})),
  ]);
  return doc;
}

/// “后端服务（积木）”模板的文件：`backend.lc.json` ＋ 所选语言生成的代码 ＋ README。
/// `dir`＝放在项目的哪个子目录（空＝根目录；全栈模板是 `server`），返回的路径已经带上它。
/// 这种语言没有生成器返回 null。
Map<String, String>? backendBlocksTemplateFiles(String name, String language, {String dir = ''}) {
  final doc = backendStarterDocument(name, language: language);
  final gen = backendProjectFiles(doc, dir: dir);
  if (gen == null) return null;
  String at(String rel) => dir.isEmpty ? rel : '$dir/$rel';
  return {at(kBackendFileName): '${doc.encode()}\n', for (final f in gen.files.entries) at(f.key): f.value};
}

/// 新建项目时可选的后端积木语言（＝现有的生成器，别人注册新的会自动出现）。
List<BackendTarget> get backendTemplateTargets => backendTargets;
