/// 后端积木校验的问题种类编号（从 backend_validate.dart 拆出来的；那边原样转出，别处照旧从它 import）。
library;

/// 后端特有的问题种类（通用的——缺参数、没声明的变量、不认识的积木等——用 [LcIssueCode] 里现成的）。
abstract final class BeIssueCode {
  /// 库的问题：用上的库找不到 / 读不懂；这份库文档出不了库文件。
  static const String badLibrary = 'badLibrary';

  /// 集合本身有问题（名字不合规矩、重名）。
  static const String badCollection = 'badCollection';

  /// 用了没声明的集合。
  static const String unknownCollection = 'unknownCollection';

  /// 请求方式不认识。
  static const String badMethod = 'badMethod';

  /// 路径格式不对（含参数名重复）。
  static const String badPath = 'badPath';

  /// 有两个接口的“方式 + 路径”一样。
  static const String duplicateRoute = 'duplicateRoute';

  /// 这个接口被排在前面的接口挡住了（警告）：前面那个的路径参数能匹配到它的固定文字。
  static const String shadowedRoute = 'shadowedRoute';

  /// “路径参数”的名字在这个接口的路径里没有。
  static const String unknownPathParam = 'unknownPathParam';

  /// “返回”之后还有积木（提示：它们不会执行）。
  static const String unreachable = 'unreachable';

  /// 这个接口有的走法没有“返回”（提示：会回 204 空响应）。
  static const String noRespond = 'noRespond';

  /// “对象”的字段里放了不是“一个字段”的东西，或“一个字段”放在了对象外面，或字段名重复 / 没填。
  static const String badPair = 'badPair';

  /// 状态码直接填的数不在 200–599 里（警告：运行时会当成 200）。
  static const String badStatus = 'badStatus';

  /// 选的语言还没有生成器（警告）。
  static const String noGenerator = 'noGenerator';

  /// 端口不在 1–65535 里。
  static const String badPort = 'badPort';
}
