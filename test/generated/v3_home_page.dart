// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class V3HomePage extends StatelessWidget {
  const V3HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          title: Row(
            spacing: 8,
            children: [
              Expanded(child: Text('首页')),
              Icon(Icons.search, size: 24, color: const Color(0xFFFFFFFF)),
            ],
          ),
          centerTitle: false,
          backgroundColor: const Color(0xFF058654),
          foregroundColor: const Color(0xFFFFFFFF),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (index) {},
          backgroundColor: const Color(0xFFFFFFFF),
          indicatorColor: const Color(0x33058654),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.search), label: '发现'),
            NavigationDestination(icon: Icon(Icons.person), label: '我的'),
          ],
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Icon(Icons.edit, size: 28, color: const Color(0xFF058654)),
                              Text(
                                '订单',
                                style: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Icon(Icons.favorite, size: 28, color: const Color(0xFF058654)),
                              Text(
                                '收藏',
                                style: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Icon(Icons.download, size: 28, color: const Color(0xFF058654)),
                              Text(
                                '下载',
                                style: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Icon(Icons.mail, size: 28, color: const Color(0xFF058654)),
                              Text(
                                '邮件',
                                style: const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: DefaultTabController(
                      length: 2,
                      initialIndex: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TabBar(
                            labelColor: const Color(0xFF058654),
                            indicatorColor: const Color(0xFF058654),
                            tabs: [
                              Tab(text: '热门'),
                              Tab(text: '最新'),
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
                                                    Text('第一条热门'),
                                                    Text('刚刚', style: const TextStyle(fontSize: 13, color: Color(0xFF5C6479))),
                                                  ],
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
                                                    Text('第二条热门'),
                                                    Text('一小时前', style: const TextStyle(fontSize: 13, color: Color(0xFF5C6479))),
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
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '最新的内容在这里',
                                        style: const TextStyle(height: 1.5),
                                      ),
                                    ],
                                  ),
                                ]),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
