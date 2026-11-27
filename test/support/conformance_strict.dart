// 一致性样本 135 条的“严格规矩版副本”（积木第 5 版·库 1 下半）。
//
// 文档：conformanceDocument() 标成规矩版本 2；靠宽松规矩才跑得通的那些接口照严格写法重写（见每个接口上面的说明）。
// 请求：还是那 135 条，一条不少、顺序不变。期望值和版本 1 不一样的，逐条写在 [strictDiffs] 里，带原因；
// 没列在里面的＝和版本 1 的期望一个字不差。另外加了几条版本 1 没有的（[strictExtraCases]），考严格规矩才有的“出错”。
import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'backend_conformance.dart';

typedef _J = Map<String, dynamic>;

LcBlock _b(String op, _J args, {List<LcBlock>? body, List<LcBlock>? orElse}) => LcBlock(op: op, args: args, body: body, orElse: orElse);
LcBlock _json(int status, _J value) => _b('respondJson', {'status': exNum(status), 'value': value});
LcBlock _text(int status, _J value) => _b('respondText', {'status': exNum(status), 'value': value});
LcBlock _let(String name, _J value) => _b('let', {'name': name, 'value': value});
LcBlock _if(_J cond, List<LcBlock> then, [List<LcBlock>? orElse]) => _b('if', {'cond': cond}, body: then, orElse: orElse);

// —— 严格规矩下“把话说明白”的那几块 ——
/// 是空就用。
_J _or(_J x, _J d) => {'e': 'orElse', 'x': x, 'd': d};

/// 变成数字（文字 → 小数；不是数字的文字＝出错）。
_J _num(_J x) => {'e': 'convert', 'x': x, 'fn': 'toNumber'};

/// 算不算“是”（空、否、0、空文字＝否）。
_J _bool(_J x) => {'e': 'convert', 'x': x, 'fn': 'toBool'};

/// 变成整数（变不了＝空）。
_J _int(_J s) => {'e': 'parseInt', 's': s};
_J _floor(_J x) => {'e': 'round', 'x': x, 'fn': 'floor'};
_J _min(_J a, _J b) => {'e': 'minmax', 'a': a, 'b': b, 'fn': 'min'};
_J _cond(_J c, _J then, _J orElse) => {'e': 'cond', 'cond': c, 'then': then, 'orElse': orElse};
_J _isA(_J x, String type) => {'e': 'isType', 'x': x, 'type': type};
_J _either(_J l, _J r) => {'e': 'logic', 'op': 'or', 'l': l, 'r': r};
_J _both(_J l, _J r) => {'e': 'logic', 'op': 'and', 'l': l, 'r': r};
const _J _null = {'e': 'null'};

/// 一个“任意”的空：从空字典里取一个没有的字段。
_J get _nul => beField(beObj({}), 'x');

/// 把接口的积木整个换掉。
void _replace(BeDocument doc, String method, String path, List<LcBlock> body) {
  final r = doc.routes.firstWhere((r) => r.method == method && r.path == path);
  r.body
    ..clear()
    ..addAll(body);
}

/// 样本里超出整数范围的那个数（123456789012345678）：严格规矩里整数最大到 9007199254740991，写成小数。
const double _bigFloat = 123456789012345678.0;

BeDocument strictConformanceDocument() {
  final doc = conformanceDocument()..rules = kLangRulesStrict;
  final a = beQuery('a'), b = beQuery('b');
  final x = exVar('x'), y = exVar('y');

  // /echo：“有几个”只收文字、列表、字典（给空会出错）。是这三种才数，不是就 0（A1 的写法）。
  final echo = doc.routes.firstWhere((r) => r.path == '/echo');
  final fields = ((echo.body.single.args['value'] as Map)['fields'] as List).cast<_J>();
  final len = fields.firstWhere((f) => f['key'] == 'nameLen');
  final name = (len['value'] as Map)['x'] as _J;
  len['value'] = _cond(_either(_isA(name, 'text'), _either(_isA(name, 'list'), _isA(name, 'dict'))), beLen(name), exNum(0));

  // /calc：网址参数是“可空的文字”。先明着“是空就用 "0"”再“变成数字”（不是数字的文字＝出错，不再悄悄当 0）；
  // 除、余先看除数是不是 0（是 0 就给空）；余只算整数（先向下取整）；并且 / 或者 / 不是 先明着“算不算是”。
  _replace(doc, 'GET', '/calc', [
    _let('x', _num(_or(a, exText('0')))),
    _let('y', _num(_or(b, exText('0')))),
    _json(
      200,
      beObj({
        'sum': exBin('+', x, y),
        'diff': exBin('-', x, y),
        'prod': exBin('*', x, y),
        'quot': _cond(exBin('==', y, exNum(0)), _null, exBin('/', x, y)),
        'rem': _cond(exBin('==', _floor(y), exNum(0)), _null, exBin('%', _floor(x), _floor(y))),
        'lt': exBin('<', x, y),
        'le': exBin('<=', x, y),
        'gt': exBin('>', x, y),
        'ge': exBin('>=', x, y),
        'eq': exBin('==', x, y),
        'ne': exBin('!=', x, y),
        'and': _both(_bool(a), _bool(b)),
        'or': _either(_bool(a), _bool(b)),
        'notA': exNot(_bool(a)),
      }),
    ),
  ]);

  // /numbers：除以 0、对 0 取余在严格规矩下是出错（另开 /div-zero、/rem-zero 两个接口单考）；小数不能取余（先向下取整）；
  // 太大的整数写成小数；1e308 × 10.5 超出小数能表示的范围：不是出错，得到“无穷大”（另开 /overflow 单考）。
  final numbers = doc.routes.firstWhere((r) => r.path == '/numbers');
  final nums = ((numbers.body.single.args['value'] as Map)['fields'] as List).cast<_J>();
  nums.removeWhere((f) => f['key'] == 'divZero' || f['key'] == 'remZero' || f['key'] == 'overflow');
  nums.firstWhere((f) => f['key'] == 'fracRem')['value'] = exBin('%', _floor(exNum(5.5)), exNum(2));
  nums.firstWhere((f) => f['key'] == 'bigInt')['value'] = exNum(_bigFloat);
  doc.addRoute('GET', '/div-zero')!.body.add(_json(200, beObj({'v': exBin('/', exNum(5), exNum(0))})));
  doc.addRoute('GET', '/rem-zero')!.body.add(_json(200, beObj({'v': exBin('%', exNum(5), exNum(0))})));
  doc.addRoute('GET', '/overflow')!.body.add(_json(200, beObj({'v': exBin('*', exNum(1e308), exNum(10.5))})));

  // 照版本 1 的宽松比法要明着写：两边先“变成文字”。
  _J text(_J v) => {'e': 'convert', 'x': v, 'fn': 'toText'};
  doc
      .addRoute('GET', '/equal-text')!
      .body
      .add(
        _json(
          200,
          beObj({
            'numText': exBin('==', text(exNum(5)), exText('5')),
            'nullEmpty': exBin('==', text(_nul), exText('')),
            'boolText': exBin('==', text(exBool(true)), exText('true')),
            'objText': exBin('==', text(beObj({'a': exNum(1)})), exText('{"a":1}')),
          }),
        ),
      );

  // /truthy：“不是（不是 x）”在严格规矩里只收“是 / 否”。换成明着的“算不算是”。
  final truthy = doc.routes.firstWhere((r) => r.path == '/truthy');
  for (final f in ((truthy.body.single.args['value'] as Map)['fields'] as List).cast<_J>()) {
    final inner = ((f['value'] as Map)['x'] as Map)['x'] as _J;
    f['value'] = _bool(inner);
  }

  // /len：“有几个”给数字、给空在严格规矩下是出错：这两格拿掉，另开 /len-null 单考。
  final lens = doc.routes.firstWhere((r) => r.path == '/len');
  ((lens.body.single.args['value'] as Map)['fields'] as List).cast<_J>().removeWhere((f) => f['key'] == 'num' || f['key'] == 'null');
  doc.addRoute('GET', '/len-null')!.body.add(_json(200, beObj({'v': beLen(_nul)})));

  // /loop：次数要整数。网址参数先“是空就用 """、再“变成整数”（变不了＝空）、再“是空就用 0”；最多 10000 次也明着写（较小的）。
  final loop = doc.routes.firstWhere((r) => r.path == '/loop');
  loop.body[2].args['times'] = _min(_or(_int(_or(beQuery('times'), exText(''))), exNum(0)), exNum(10000));

  // /each：对文字“每个”在严格规矩下查不过（要列表）：那一段拿掉（版本 1 里它本来也一遍都不做）。
  final each = doc.routes.firstWhere((r) => r.path == '/each');
  each.body.removeAt(2);

  // /branch：比大小先变成整数；“如果 网址参数”先明着“算不算是”。
  _replace(doc, 'GET', '/branch', [
    _if(
      exBin('>', _or(_int(_or(beQuery('x'), exText(''))), exNum(0)), exNum(10)),
      [_text(200, exText('大'))],
      [
        _if(_bool(beQuery('x')), [_text(200, exText('小'))], [_text(200, exText('没有'))]),
      ],
    ),
  ]);

  // /bump：“加上”用在放着文字的变量上，严格规矩下是出错（不再先当 0）：那一块拿掉，另开 /bump-text 单考。
  final bump = doc.routes.firstWhere((r) => r.path == '/bump');
  final onText = bump.body.removeAt(1);
  doc.addRoute('GET', '/bump-text')!.body.addAll([
    onText,
    _json(200, beObj({'s': exVar('s')})),
  ]);

  // /holes：“空 + 空”（左右都没填的运算）严格规矩下查不过：那一格拿掉。别的没填好的地方照旧当成空。
  final holes = doc.routes.firstWhere((r) => r.path == '/holes');
  ((holes.body.last.args['value'] as Map)['fields'] as List).cast<_J>().removeWhere((f) => f['key'] == 'missing');
  return doc;
}

/// 和版本 1 的期望不一样的那一条：新的状态码、内容，和原因。
class StrictDiff {
  const StrictDiff(this.status, this.expect, this.why, {this.type = kJson});
  final int status;
  final String expect;
  final String why;
  final String? type;
}

/// 严格规矩下运行时出错：回 500 和这一句。
const String kStrictFailed = '{"error":"服务器内部出错"}';

/// 第几条（从 1 数，对着 conformanceCases）的期望和版本 1 不一样。
const Map<int, StrictDiff> strictDiffs = {
  33: StrictDiff(200, r'{"list":3,"obj":2,"text":3}', '“有几个”给数字、给空在严格规矩下是出错：这两格拿掉了（出错另由 /len-null 考）'),
  40: StrictDiff(
    200,
    r'{"and":true,"diff":4.5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":17.5,"quot":2.8,"rem":1,"sum":9.5}',
    '“余”只算整数：7 余 2.5 先各自向下取整成 7 余 2，得 1；版本 1 按小数算得 2',
  ),
  41: StrictDiff(500, kStrictFailed, '“abc”不是数字，“变成数字”出错（回 500）；版本 1 悄悄当 0'),
  42: StrictDiff(
    200,
    r'{"and":false,"diff":5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":0,"quot":null,"rem":null,"sum":5}',
    'b 没给，当 0；除数是 0 时样本明着先判断、给空；版本 1 悄悄得 0',
  ),
  43: StrictDiff(
    200,
    r'{"and":false,"diff":0,"eq":true,"ge":true,"gt":false,"le":true,"lt":false,"ne":false,"notA":true,"or":false,"prod":0,"quot":null,"rem":null,"sum":0}',
    'a、b 都没给，当 0；除数是 0 时给空；版本 1 悄悄得 0',
  ),
  44: StrictDiff(
    200,
    r'{"and":true,"diff":999.5,"eq":false,"ge":true,"gt":true,"le":false,"lt":false,"ne":true,"notA":false,"or":true,"prod":500,"quot":2000,"rem":null,"sum":1000.5}',
    '“余”先向下取整，0.5 取整是 0，除数是 0 给空；版本 1 按小数算得 0',
  ),
  45: StrictDiff(500, kStrictFailed, '“0x10”、全角的“５”不是数字，“变成数字”出错；版本 1 悄悄当 0'),
  46: StrictDiff(500, kStrictFailed, '“Infinity”“1_000”不是数字，“变成数字”出错；版本 1 悄悄当 0'),
  47: StrictDiff(500, kStrictFailed, '“1e999”超出小数范围，“变成数字”出错；版本 1 悄悄当 0'),
  49: StrictDiff(
    200,
    r'{"and":true,"diff":0,"eq":true,"ge":true,"gt":false,"le":true,"lt":false,"ne":false,"notA":false,"or":true,"prod":25,"quot":1,"rem":0,"sum":10}',
    '“5”和“5.0”先变成数字再比，相等；版本 1 两边都是文字、按文字比，不相等',
  ),
  50: StrictDiff(500, kStrictFailed, 'b 给了但是空文字，“变成数字”出错；版本 1 悄悄当 0'),
  51: StrictDiff(
    200,
    r'{"big":1e21,"bigInt":1.23456789012e17,"e15":1000000000000000,"frac":123456.789,"fracRem":1,"half":0.5,"justUnder":999999999999999,"long":1234567890.12,"neg":-42,"negFrac":-0.5,"negRem":-1,"negTie":-12345678901.3,"negZero":0,"nines":1e15,"pointThree":0.3,"small":2.5e-10,"third":0.333333333333,"tie":12345678901.3,"tinier":1.2e-8,"tiny":0.00000012,"whole":3}',
    '除以 0、对 0 取余、算出界三格拿掉了（另由 /div-zero、/rem-zero、/overflow 考）；5.5 余 2 先取整得 1；1e15 是整数，按整数写全（版本 1 不分整数小数，写成 1e15）',
  ),
  52: StrictDiff(
    200,
    r'{"boolText":false,"floatSum":false,"listSame":true,"neText":true,"nullEmpty":false,"nullNull":true,"nullZero":false,"numText":false,"numTextDot":false,"objDiff":false,"objOrder":true,"objText":false,"oneTrue":false,"zeroEmpty":false}',
    '不同类型比“相等”一律不相等、不做宽松换算：数字和文字、空和空文字、是否和文字、字典和文字这四格从 true 变 false（照版本 1 的比法另由 /equal-text 考）',
  ),
  62: StrictDiff(200, r'{"n":10}', '“变成整数”不收“2.9”（给空，再“是空就用 0”）所以重复 0 次；版本 1 向下取整成 2 次'),
  76: StrictDiff(200, r'{"class":6,"n":8,"s":"初始\"值\\"}', '往放着文字的变量“加上”在严格规矩下是出错：那一块拿掉了，s 保持原样（出错另由 /bump-text 考）'),
  77: StrictDiff(200, r'{"class":6,"n":8,"s":"初始\"值\\"}', '同第 76 条'),
  116: StrictDiff(200, r'{"badCollection":null,"badOp":null,"badParam":null,"ok":1,"undeclared":null,"unknown":null}', '“空 + 空”（两边都没填的运算）严格规矩下查不过：那一格拿掉了'),
};

/// 版本 1 没有、严格规矩才有的（接在 135 条后面）。
const List<BeCase> strictExtraCases = [
  // 出错的四样：除以 0、对 0 取余、“有几个”给空、往文字变量“加上”。
  BeCase('GET', '/div-zero', 500, kStrictFailed),
  BeCase('GET', '/rem-zero', 500, kStrictFailed),
  BeCase('GET', '/len-null', 500, kStrictFailed),
  BeCase('GET', '/bump-text', 500, kStrictFailed),
  // 小数算出界不算出错（只有整数超范围才是）：得到“无穷大”，写进 JSON 是空。
  BeCase('GET', '/overflow', 200, '{"v":null}'),
  // 出过错以后服务照常。
  BeCase('GET', '/todos/count', 200, '{"count":3}'),
  // 照版本 1 的比法（两边先明着“变成文字”再比）：和版本 1 的 /equal 那四格一样是 true。
  BeCase('GET', '/equal-text', 200, '{"boolText":true,"nullEmpty":true,"numText":true,"objText":true}'),
];

/// 严格版的 135 条（顺序、请求和版本 1 一样；期望照 [strictDiffs] 换）＋ [strictExtraCases]。
List<BeCase> strictCases() => [
  for (var i = 0; i < conformanceCases.length; i++)
    if (strictDiffs[i + 1] case final d?)
      BeCase(
        conformanceCases[i].method,
        conformanceCases[i].target,
        d.status,
        d.expect,
        body: conformanceCases[i].body,
        bodyBytes: conformanceCases[i].bodyBytes,
        headers: conformanceCases[i].headers,
        type: d.type,
      )
    else
      conformanceCases[i],
  ...strictExtraCases,
];
