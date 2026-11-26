// 设计约束：这里只有“名字 → Flutter 图标”的对照（画布和选图标的面板用），没有界面。
// 名字和 icon_set.dart 的清单一一对应（test/lowcode_v3_fields_test.dart 守着），导出的 Flutter 代码写的是同名的 `Icons.xxx`。
import 'package:material_ui/material_ui.dart';

const Map<String, IconData> lcIconData = {
  'add': Icons.add,
  'remove': Icons.remove,
  'check': Icons.check,
  'close': Icons.close,
  'search': Icons.search,
  'arrow_back': Icons.arrow_back,
  'arrow_forward': Icons.arrow_forward,
  'chevron_left': Icons.chevron_left,
  'chevron_right': Icons.chevron_right,
  'expand_more': Icons.expand_more,
  'menu': Icons.menu,
  'more_horiz': Icons.more_horiz,
  'home': Icons.home,
  'person': Icons.person,
  'favorite': Icons.favorite,
  'star': Icons.star,
  'edit': Icons.edit,
  'delete': Icons.delete,
  'send': Icons.send,
  'download': Icons.download,
  'refresh': Icons.refresh,
  'play_arrow': Icons.play_arrow,
  'info': Icons.info,
  'phone': Icons.phone,
  'mail': Icons.mail,
};
