/// 一份后端文档眼里的库积木（积木第 5 版·库 2）：它用上了哪些库、每块库积木在编辑器里长什么样（规格、句子、口、“放进变量”槽）。
/// 校验、编辑器宿主都问它。文档一改就重新建一张；任何输入都不抛异常。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';

export 'package:lopicode/lowcode/lib_blocks.dart' show LibEntry, LibTable;

/// 库文档里才有的两块：“做口里的积木”“把 … 交给用的人选的变量”。
const String kBeLibDefCategory = kLibDefCategory;

/// 库积木在编辑器里的样子、库积木表：都是“文档无关”那一层的（lib/lowcode/lib_blocks.dart），后端文档只是它的一个使用者。
typedef BeLibEntry = LibEntry;

class BeLibTable extends LibTable {
  BeLibTable(BeDocument super.doc);
  BeDocument get doc => user as BeDocument;
  @override
  bool get pick => doc.front && doc.library == null;
}
