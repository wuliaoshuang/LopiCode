// 设置里和 Agent 有关的几个页面，2026-11-24 起一页一个文件（这个文件原来 703 行，只许变短）：
// - 个性化、预设编辑　　settings_personalize.dart
// - 子代理与团队　　　　settings_subagent.dart
// - 联网搜索　　　　　　settings_search.dart
// - 技能（列表 / 新建 / 全文）settings_skills.dart
// 这里只把它们转出去（别处 import 这个文件的不用改），外加两个取名字的小函数。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/presets.dart';

export 'package:lopicode/ui/settings_personalize.dart';
export 'package:lopicode/ui/settings_search.dart';
export 'package:lopicode/ui/settings_skills.dart';
export 'package:lopicode/ui/settings_subagent.dart';

/// 工具的中文名（对话页的权限说明等处用）。
String toolLabel(String name) => kToolLabels[name] ?? name;

/// 权限档位的一句话（设置页用）。
String permissionLabel(String id) => PermissionLevel.byId(id).label;
