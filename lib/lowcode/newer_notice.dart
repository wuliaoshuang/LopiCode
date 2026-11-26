// “这个页面是新版做的”那句话。搭建页顶上那一条和 Agent 工具的回话用的是同一句（不带界面，两边都能引）。
import 'package:lopicode/lowcode/model.dart';

String lcNewerNoticeText(LcDocument doc) => '这个页面是新版做的（第 ${doc.fileVersion} 版，这里认识到第 ${LcDocument.currentVersion} 版）。看不懂的部分不显示，但会原样留着、不会丢。';
