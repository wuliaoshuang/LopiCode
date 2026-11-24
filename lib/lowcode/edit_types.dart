import 'package:lopicode/lowcode/model.dart';

/// 搭建器里“改一下页面”的统一入口：把一个改动函数交给搭建页，由它改模型、记撤销历史、存盘并重新导出。
/// 各个面板（样式、积木、组件）都只拿这个回调，不自己存盘。
typedef LcEdit = void Function(void Function(LcDocument doc) change);
