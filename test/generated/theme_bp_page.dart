// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 主题变量：这里写的是导出那一刻的值（底色、文字颜色、字号、内外边距、圆角、间距、宽高认得；别的样式本来就不导出）。改了变量要重新导出。
// 断点：屏幕更宽时（平板、桌面）的样式差别没有导出，这里是手机的样子。
import 'package:flutter/material.dart';

class ThemeBpHomePage extends StatelessWidget {
  const ThemeBpHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
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
                    '欢迎来到小站',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: const Color(0xFF222435), height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '草莓蛋糕',
                                style: const TextStyle(height: 1.5),
                              ),
                              Text(
                                '新品',
                                style: const TextStyle(fontSize: 12, color: const Color(0xFF058654), height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '抹茶卷',
                                style: const TextStyle(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF)),
                    child: Text('去看看'),
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
                    '关于我们',
                    style: const TextStyle(color: const Color(0xFF5C6479), height: 1.5),
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
