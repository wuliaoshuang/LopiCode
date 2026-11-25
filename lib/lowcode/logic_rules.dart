/// 积木校验的规则表：每一种问题（[LcLogicIssue.code]）有一个稳定的规则编号、一句名字、一句“怎么改”。
///
/// 页面逻辑（lib/lowcode/logic_validate.dart）和后端积木（lib/backend/backend_validate.dart）共用这一张表：
/// G＝两边都有的，P＝只有页面逻辑有的，S＝只有后端有的，L＝语言核心的（积木第 4 版，编号照 docs/blocks-v4-language-design.md 第 7 节）。编号一旦发出去就不再改、不复用（文档、测试、给模型的工具结果里都会出现）。
/// 加规则：在这里加一行，再到 docs/blocks-v3-design.md 的“校验规则表”补一行。
library;

/// 一条规则。级别不写在这里：同一条规则在不同情况下可能是错误也可能是警告（见各校验文件和设计文档里的表）。
class LcRule {
  const LcRule(this.id, this.title, this.fix);

  /// 稳定的编号，如 `G01`。
  final String id;

  /// 规则的名字（问题列表里不显示，文档和测试用）。
  final String title;

  /// 默认的“怎么改”；具体问题可以给更具体的（[LcLogicIssue.fix]）。
  final String fix;
}

/// 问题种类（code）→ 规则。
const Map<String, LcRule> kLcRules = {
  // —— 两边都有 ——
  'missingArg': LcRule('G01', '必填的格子空着', '点一下标红的那一格，填上或选一个。'),
  'badArg': LcRule('G02', '格子里的值不对', '点一下标红的那一格，重新填或重新选。'),
  'unknownVar': LcRule('G03', '用了没有声明的变量', '到“变量”里把它加回来，或者在这一格里换一个变量。'),
  'badVariable': LcRule('G04', '变量的名字 / 类型不对', '到“变量”里给它改个名字：英文字母开头，只用字母、数字和下划线，不能重名。'),
  'unknownOp': LcRule('G05', '不认识的积木', '这块积木是别的版本做的，这里用不了；不需要就删掉它。'),
  'unknownExpr': LcRule('G06', '不认识的值', '长按这个值，换成一个认识的。'),
  'tooDeep': LcRule('G07', '套得太深', '把里面的几块拿出来，少套几层。'),
  'strayBody': LcRule('G08', '不能嵌积木的地方放了积木', '把里面的积木拖出来，接到别的地方。'),
  'changeVarNotNumber': LcRule('G09', '“加上”用在不是数字的变量上', '换成数字类型的变量，或者改用“设置变量”。'),
  'badType': LcRule('G10', '值的类型对不上', '长按这个值，换成合适类型的值。'),
  'emptyScript': LcRule('G11', '事件下面是空的', '往它下面接一块积木；不需要这个事件就删掉它。'),
  'badRepeat': LcRule('G12', '重复的次数不对', '把次数改成 0 以上的整数。'),
  'divByZero': LcRule('G13', '除以 0', '把除数改成不是 0 的数。'),
  'badUrl': LcRule('G14', '网址没填或不像网址', '填一个完整的网址，例如 https://example.com/api 。'),
  // —— 只有页面逻辑 ——
  'nodeNotFound': LcRule('P01', '控件已经不在页面里', '点一下标红的那一格，重新选一个控件；不需要这块就删掉它。'),
  'missingTarget': LcRule('P02', '事件没选控件', '点帽子上的“选控件”，选是哪个控件触发的。'),
  'inputOnNonInput': LcRule('P03', '“内容变化”挂在不是输入框的控件上', '把控件换成输入框，或者改用“被点击”。'),
  'unknownEvent': LcRule('P04', '不认识的事件', '删掉这一串，从“事件”里重新拖一个出来。'),
  'eventOutsideInput': LcRule('P05', '“输入的内容”用错了地方', '把它换成“控件的属性”读那个输入框的输入内容。'),
  'propNotSupported': LcRule('P06', '控件没有这个属性', '换一个这种控件有的属性，或者换一个控件。'),
  'duplicateEvent': LcRule('P07', '同一个控件的同一个事件有两串', '把两串合成一串，免得改了一串忘了另一串。'),
  // —— 只有后端 ——
  'badPort': LcRule('S01', '端口不对', '到“服务设置”里把端口改成 1 到 65535 之间的数。'),
  'noGenerator': LcRule('S02', '选的语言不能生成', '到“语言”里换一种能生成的语言。'),
  'badCollection': LcRule('S03', '集合的名字不对', '到“变量与集合”里给它改个名字：英文字母开头，只用字母、数字和下划线，不能重名。'),
  'unknownCollection': LcRule('S04', '用了没有的集合', '到“变量与集合”里把它加回来，或者在这一格里换一个集合。'),
  'badMethod': LcRule('S05', '请求方式不认识', '点帽子上的请求方式，重新选一个。'),
  'badPath': LcRule('S06', '接口路径不合规矩', '点帽子上的路径重新填：以 / 开头，参数写成 :名字，名字不能重复。'),
  'duplicateRoute': LcRule('S07', '两个接口是同一个地址', '改掉其中一个的路径或请求方式，或者删掉一个。'),
  'shadowedRoute': LcRule('S08', '接口被前面的挡住', '把这个接口拖到挡住它的那个前面。'),
  'unknownPathParam': LcRule('S09', '取了路径里没有的参数', '把名字改成路径里有的，或者在路径里加上 :这个名字。'),
  'unreachable': LcRule('S10', '“返回”后面还有积木', '把后面的积木挪到“返回”前面，或者删掉。'),
  'noRespond': LcRule('S11', '有的走法没有“返回”', '在每条走法的最后都接一块“返回”（“如果”的“否则”里也要）。'),
  'badPair': LcRule('S12', '对象的字段不对', '“对象”里只放“名字: 值”，名字不能空着、不能重复。'),
  // —— 语言核心（第 4 版；现在只有后端用到） ——
  'outsideLoop': LcRule('L04', '“跳出 / 跳过”不在循环里', '把它拖进“重复”“当…时重复”“对每一项”这些循环里面，或者删掉。'),
  'duplicateName': LcRule('L09', '同一层里名字重复', '给其中一个换个名字；想改它的值就用“把变量设为”。'),
  'assignConst': LcRule('L11', '给常量重新赋值', '常量新建以后不能改；想改就把“新建常量”换成“新建变量”。'),
  'endlessLoop': LcRule('L13', '可能停不下来的循环', '在循环里放一块“跳出循环”或“返回”，或者把条件换成会变的。'),
  'badStatus': LcRule('S13', '状态码不对', '把状态码改成 200 到 599 之间的整数，例如 200、201、404。'),
};

/// 一种问题的规则编号；表里没有的（不该发生）原样返回 code。
String lcRuleId(String code) => kLcRules[code]?.id ?? code;
