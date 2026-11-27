// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class PagesHomePage extends StatelessWidget {
  const PagesHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          title: Text('首页'),
          centerTitle: false,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (index) => _lcSwitchTo(context, const <Widget?>[null, LowcodePage(), MePage()][index]),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.search), label: '商品'),
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
                  Text(
                    '欢迎',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF4F7F9), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '今日推荐',
                          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
                        ),
                        Text(
                          '草莓蛋糕',
                          style: const TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _lcGoTo(context, const LowcodePage()),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('去看商品'),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 8,
                      children: [
                        Flexible(
                          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _lcGoTo(context, const MePage()), child: Text(
                            '我的资料',
                            style: const TextStyle(height: 1.5),
                          )),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: '数量',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('数量够了就去我的'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

class LowcodePage extends StatelessWidget {
  const LowcodePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          leading: const BackButton(),
          title: Text('商品'),
          centerTitle: false,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (index) => _lcSwitchTo(context, const <Widget?>[PagesHomePage(), null, MePage()][index]),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.search), label: '商品'),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF4F7F9), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '蛋糕',
                          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
                        ),
                        Text(
                          '（空的）',
                          style: const TextStyle(color: const Color(0xFF5C6479), height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _lcGoTo(context, const PagesHomePage()), child: SizedBox(
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
                                Text('回首页'),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8B93A7)),
                        ],
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 2,
          onDestinationSelected: (index) => _lcSwitchTo(context, const <Widget?>[PagesHomePage(), LowcodePage(), null][index]),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.search), label: '商品'),
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
                  Text(
                    '昵称：小橘',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                  FilledButton(
                    onPressed: () => _lcGoTo(context, const PagesHomePage()),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('回首页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

/// 去另一页（叠在当前页上面，系统的返回能回来）。
void _lcGoTo(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// 换成另一页（底部导航用：不往上叠）。page 是 null＝这一项没设去哪页，什么都不做。
void _lcSwitchTo(BuildContext context, Widget? page) {
  if (page == null) return;
  Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
}
