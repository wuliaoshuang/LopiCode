// 底部导航的触感（霜霜真机反馈第二轮第 1 条）：点任何一项都短震一下。
// - 用 lightImpact：安卓上它对应系统“虚拟按键”那一下（系统自己的导航键就是这个手感），短、轻、但确实感觉得到；
//   selectionClick 在安卓上是“时钟滴答”级别，不少机型上弱到几乎没有，她明确要“震动”，所以不选它。
// - 点当前已经选中的那一项也震：震动是“按到了”的确认，不是“换页了”的通知，和系统导航键一致。
// - 跟积木编辑器一样直接调 Flutter 自带的 HapticFeedback，不等它返回；系统关了“触摸反馈”时它自己不响。
import 'dart:async';

import 'package:flutter/services.dart' show HapticFeedback;

/// 底部导航被点了一下：一次短促的轻震。
void navTapHaptic() => unawaited(HapticFeedback.lightImpact());
