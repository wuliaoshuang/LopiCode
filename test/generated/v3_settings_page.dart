// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class V3SettingsPage extends StatelessWidget {
  const V3SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF4F7F9),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          leading: const BackButton(),
          title: Row(
            spacing: 8,
            children: [
              Expanded(child: Text('设置')),
              Icon(Icons.more_horiz, size: 24),
            ],
          ),
          centerTitle: false,
          backgroundColor: const Color(0xFFFFFFFF),
          foregroundColor: const Color(0xFF222435),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              spacing: 12,
                              children: [
                                Icon(Icons.person, size: 40, color: const Color(0xFF058654)),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('霜霜'),
                                      Text('点这里改资料', style: const TextStyle(fontSize: 13, color: Color(0xFF5C6479))),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8B93A7)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              spacing: 12,
                              children: [
                                Icon(Icons.mail, size: 24),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('消息通知'),
                                    ],
                                  ),
                                ),
                                Switch(value: true, onChanged: (value) {}),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              spacing: 12,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('深色模式'),
                                    ],
                                  ),
                                ),
                                Switch(value: false, onChanged: (value) {}),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        SizedBox(
                          width: double.infinity,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              spacing: 12,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('语言'),
                                    ],
                                  ),
                                ),
                                Text('简体中文', style: const TextStyle(fontSize: 14, color: Color(0xFF5C6479))),
                                const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8B93A7)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Text(
                          '字号',
                          style: const TextStyle(fontSize: 14, color: const Color(0xFF5C6479), height: 1.5),
                        ),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          emptySelectionAllowed: true,
                          segments: [
                            ButtonSegment(value: 's', label: Text('小')),
                            ButtonSegment(value: 'm', label: Text('中')),
                            ButtonSegment(value: 'l', label: Text('大')),
                          ],
                          selected: {'m'},
                          onSelectionChanged: (value) {},
                        ),
                        DropdownMenu<String>(
                          hintText: '选择地区',
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            DropdownMenuEntry(value: 'bj', label: '北京'),
                            DropdownMenuEntry(value: 'sh', label: '上海'),
                          ],
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: TextField(
                            maxLines: 3,
                            maxLength: 200,
                            decoration: InputDecoration(
                              labelText: '意见反馈',
                              alignLabelWithHint: true,
                              hintText: '想说点什么',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFFFFF), foregroundColor: const Color(0xFFC62828), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text('退出登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 弹窗「退出登录」：要打开它的时候调用（比如放在按钮的 onPressed 里）。
  static Future<void> showDialog_sure(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text('退出登录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('确定要退出吗？'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('再想想')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('退出')),
        ],
      ),
    );
  }
}
