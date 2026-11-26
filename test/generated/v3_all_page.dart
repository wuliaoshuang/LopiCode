// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class V3AllPage extends StatelessWidget {
  const V3AllPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          leading: const BackButton(),
          title: Row(
            spacing: 8,
            children: [
              Icon(Icons.menu, size: 24),
              Expanded(child: Text('全部 <组件> & "引号"', textAlign: TextAlign.center)),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(6)),
                child: Text('存'),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFFFFFFFF),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (index) {},
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.star), label: ''),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  SizedBox(
                    height: 56,
                    child: AppBar(
                      primary: false,
                      automaticallyImplyLeading: false,
                      title: Text('不在最上面的导航栏'),
                      centerTitle: false,
                    ),
                  ),
                  Icon(Icons.star, size: 32, color: const Color(0xFFE0A100)),
                  Icon(Icons.star, size: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextFormField(
                      initialValue: '第一行\n第二行 </textarea> {{ x }}',
                      minLines: 2,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: '写点什么',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      enabled: false,
                      maxLines: 3,
                      maxLength: 50,
                      decoration: InputDecoration(
                        labelText: '备注 <b> *',
                        alignLabelWithHint: true,
                        hintText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 12,
                      children: [
                        Switch(value: true, onChanged: (value) {}),
                        Switch(value: false, onChanged: null),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(value: true, onChanged: (value) {}),
                              Flexible(child: Text('同意 {条款}')),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(value: false, onChanged: null),
                              Flexible(child: Text('不能点')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_button_unchecked, size: 20),
                          const SizedBox(width: 8),
                          Flexible(child: Text('甲')),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_button_checked, size: 20),
                          const SizedBox(width: 8),
                          Flexible(child: Text('乙 "x"')),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_button_unchecked, size: 20),
                          const SizedBox(width: 8),
                          Flexible(child: Text('c')),
                        ],
                      ),
                    ],
                  ),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: [
                      ButtonSegment(value: 'x', label: Text('左')),
                      ButtonSegment(value: 'y', label: Text('右')),
                    ],
                    selected: {'x'},
                    onSelectionChanged: null,
                  ),
                  DropdownMenu<String>(
                    initialSelection: 'b',
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(value: 'a', label: '苹果'),
                      DropdownMenuEntry(value: 'b', label: '香蕉 <b>'),
                    ],
                  ),
                  DropdownMenu<String>(
                    hintText: '请选择',
                    enabled: false,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(value: 'a', label: 'a'),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      color: const Color(0xFFF4F7F9),
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        spacing: 12,
                        children: [
                          Icon(Icons.home, size: 24),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('两行的列表行'),
                                Text('副标题', style: const TextStyle(fontSize: 13, color: Color(0xFF5C6479))),
                              ],
                            ),
                          ),
                          Text('说明', style: const TextStyle(fontSize: 14, color: Color(0xFF5C6479))),
                          Switch(value: true, onChanged: (value) {}),
                          Flexible(
                            child: Text(
                              '没写插槽',
                              style: const TextStyle(height: 1.5),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8B93A7)),
                        ],
                      ),
                    ),
                  ),
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
                                Text('一行的列表行'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: DefaultTabController(
                      length: 3,
                      initialIndex: 1,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerHeight: 0,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(color: const Color(0x14000000), borderRadius: BorderRadius.circular(999)),
                            tabs: [
                              Tab(text: '甲'),
                              Tab(text: '乙'),
                              Tab(text: 'c'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final tabs = DefaultTabController.of(context);
                              return AnimatedBuilder(
                                animation: tabs,
                                builder: (context, child) => IndexedStack(index: tabs.index, children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '甲页签的内容',
                                        style: const TextStyle(height: 1.5),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextField(
                                          decoration: InputDecoration(
                                            hintText: '乙页签里的输入框',
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () {},
                                        style: FilledButton.styleFrom(),
                                        child: Text('乙页签里的按钮'),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [],
                                  ),
                                ]),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('打开弹窗'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 弹窗「自己的内容」：要打开它的时候调用（比如放在按钮的 onPressed 里）。
  static Future<void> showDialog_dlg(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('自己的内容'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '弹窗里的输入框',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              Text(
                '没写插槽的算内容',
                style: const TextStyle(height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 弹窗「一开始就开着」：要打开它的时候调用（比如放在按钮的 onPressed 里）。
  static Future<void> showDialog_dlg2(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text('一开始就开着'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('点确定关掉'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('确定')),
        ],
      ),
    );
  }
}
