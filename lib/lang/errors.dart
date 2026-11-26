/// 错误是对象（积木第 5 版·核心 2）。设计：docs/blocks-v5-foundation-design.md 7.1 第 1 条、
/// docs/blocks-v5-parts/A2-features-advanced.md 第 4 节（E03、E05、E06、E08、E16、E17、E19）、F1 的 GAP-F1-01。
///
/// - 内置类“错误”（[kErrBase]）：一个字段“消息”（文字），可以被继承；自己定义的错误＝父类是“错误”（或它的子类）的类，
///   想带什么数据（状态码、详情…）就加什么字段。
/// - 内置的一棵小树（[kErrBuiltinKinds]）：找不到、类型不对、数值不对、超时、取消了、读写失败，父类都是“错误”。
///   小库自己报的错按 [kErrKindOfMessage] 的规矩归到其中几种。
/// - 每个错误对象都能读“种类”（[kErrKindField]）：它是哪个类的，一段文字；只能读、不能改。
/// - 这些内置类不是手写在各语言小库里的，而是一小段语法树（[langErrorPrelude]）：检查器把它们放进声明表，
///   生成器在程序用到错误时把它们和用户的类一起生成——五种语言里它们和用户自己写的类是同一种东西，继承、“是不是”都不用特殊处理。
/// - 抛出去的时候外面包一层小库的 `LcError`（各语言的异常必须是特定的类，用户的类不是）；接住的时候再拆出来。
///   小库自己报的错只有一句话和一个种类名，接住时才按种类造出对象（生成的程序开头登记了“怎么造”）。
///
/// 规矩版本 1 的文档不走这里。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

/// 内置的“错误”类。
const String kErrBase = '错误';

/// 它的字段：那句话。
const String kErrMessageField = '消息';

/// 只读的“种类”：这个错误对象是哪个类的（文字）。
const String kErrKindField = '种类';

/// 内置的几种错误（父类都是 [kErrBase]）。
const List<String> kErrBuiltinKinds = ['找不到', '类型不对', '数值不对', '超时', '取消了', '读写失败'];

/// 全部内置错误类的名字：用户的声明不许叫这些。
const List<String> kErrBuiltinNames = [kErrBase, ...kErrBuiltinKinds];

/// 小库自己报的错归到哪一种：消息里**含有**左边这段字的，是右边这一种（从上往下第一条对得上的算）；都对不上＝“错误”。
/// 五种语言的小库里各有一份一样的（`errKind` / `ErrKind`）；用户用“抛出 (一句话)”抛的不按这个归，一律是“错误”。
const List<(String, String)> kErrKindOfMessage = [
  ('除以 0', '数值不对'),
  ('整数超出范围', '数值不对'),
  ('变不成整数', '数值不对'),
  ('超出了', '找不到'),
  ('拿到的是', '类型不对'),
  ('值是空', '类型不对'),
];

bool langIsBuiltinError(String? name) => name != null && kErrBuiltinNames.contains(name);

/// 内置错误类的语法树。每次调用都新建节点（检查结果按节点对象记，不能共用；所以下面故意不写成常量）。
List<LClassDecl> langErrorPrelude() {
  LParam message() => const LParam(kErrMessageField, type: LType.text);
  LExpr name(String n) => LName(n);
  LExpr self(Object? _) => const LThis();
  return [
    LClassDecl(
      kErrBase,
      isOpen: true,
      isPublic: true,
      fields: const [LFieldDecl(kErrMessageField, LLit(''), type: LType.text)],
      ctor: LFuncDecl('创建', [message()], [LAssign(LTField(self(null), kErrMessageField), name(kErrMessageField))]),
    ),
    for (final k in kErrBuiltinKinds)
      LClassDecl(
        k,
        parent: kErrBase,
        isOpen: true,
        isPublic: true,
        ctor: LFuncDecl('创建', [message()], [
          LExprStmt(LSuperSend.ctor([name(kErrMessageField)])),
        ]),
      ),
  ];
}
