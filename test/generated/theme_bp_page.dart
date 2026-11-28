// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 主题变量：集中在文件末尾的 LcVars 里，改那里一处，用到的地方全跟着变。
// 断点：按屏幕宽度取样子（平板 ≥768、桌面 ≥1024），见各页的 build。
import 'package:flutter/material.dart';

class ThemeBpHomePage extends StatelessWidget {
  const ThemeBpHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 按屏幕宽度取样子：从宽到窄，先对上哪一档用哪一档。
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1024) return _buildDesktop(context);
    if (width >= 768) return _buildTablet(context);
    return _buildPhone(context);
  }

  /// 手机的样子。
  Widget _buildPhone(BuildContext context) {
    return Scaffold(
        backgroundColor: LcVars.colorBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(LcVars.spaceMd),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '欢迎来到小站',
                    style: TextStyle(fontSize: LcVars.fontLg, fontWeight: FontWeight.w600, color: LcVars.colorText, height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(LcVars.radiusMd), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '草莓蛋糕',
                                style: TextStyle(height: 1.5),
                              ),
                              Text(
                                '新品',
                                style: TextStyle(fontSize: LcVars.fontSm, color: LcVars.colorPrimary, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '抹茶卷',
                                style: TextStyle(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorPrimary, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? LcVars.colorText : LcVars.colorPrimary))),
                    child: Text('去看看'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 平板（屏幕宽度 ≥ 768）的样子。
  Widget _buildTablet(BuildContext context) {
    return Scaffold(
        backgroundColor: LcVars.colorBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(LcVars.spaceMd),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '欢迎来到小站',
                    style: TextStyle(fontSize: LcVars.fontXl, fontWeight: FontWeight.w600, color: LcVars.colorText, height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(LcVars.radiusMd), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '草莓蛋糕',
                                  style: TextStyle(height: 1.5),
                                ),
                                Text(
                                  '新品',
                                  style: TextStyle(fontSize: LcVars.fontSm, color: LcVars.colorPrimary, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '抹茶卷',
                                  style: TextStyle(height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorPrimary, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? LcVars.colorText : LcVars.colorPrimary))),
                    child: Text('去看看'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 桌面（屏幕宽度 ≥ 1024）的样子。
  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
        backgroundColor: LcVars.colorBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(LcVars.spaceMd),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '欢迎来到小站',
                    style: TextStyle(fontSize: LcVars.fontXl, fontWeight: FontWeight.w600, color: LcVars.colorText, height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 24,
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(LcVars.radiusMd), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '草莓蛋糕',
                                  style: TextStyle(height: 1.5),
                                ),
                                Text(
                                  '新品',
                                  style: TextStyle(fontSize: LcVars.fontSm, color: LcVars.colorPrimary, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '抹茶卷',
                                  style: TextStyle(height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorPrimary, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? LcVars.colorText : LcVars.colorPrimary))),
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
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '关于我们',
                    style: TextStyle(color: LcVars.colorTextMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

/// 主题变量：全应用只此一处。改这里的值，用到它的地方都跟着变。
abstract final class LcVars {
  /// 品牌绿（--color-primary）
  static const Color colorPrimary = Color(0xFF058654);

  /// 文字（--color-text）
  static const Color colorText = Color(0xFF222435);

  /// 次要文字（--color-text-muted）
  static const Color colorTextMuted = Color(0xFF5C6479);

  /// 背景（--color-bg）
  static const Color colorBg = Color(0xFFFFFFFF);

  /// 小字（--font-sm）
  static const double fontSm = 12;

  /// 小标题（--font-lg）
  static const double fontLg = 20;

  /// 大标题（--font-xl）
  static const double fontXl = 30;

  /// 中间距（--space-md）
  static const double spaceMd = 16;

  /// 中圆角（--radius-md）
  static const double radiusMd = 10;
}
