// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class SlotCardPage extends StatelessWidget {
  const SlotCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF4F7F9),
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
                    '今日推荐',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '草莓蛋糕',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.5),
                        ),
                        Container(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 6,
                            children: [
                              Container(
                                width: double.infinity,
                                child: Text(
                                  '新鲜草莓，当天现做',
                                  style: const TextStyle(height: 1.5),
                                ),
                              ),
                              Text(
                                '¥ 68',
                                style: const TextStyle(fontWeight: FontWeight.w600, color: const Color(0xFFC2410C), height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.end,
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () {},
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: Text('立即购买'),
                              ),
                              FilledButton(
                                onPressed: () {},
                                style: FilledButton.styleFrom(padding: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: Text('收藏'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '商品名',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.5),
                        ),
                        Container(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 6,
                            children: [
                              Text(
                                '暂无介绍',
                                style: const TextStyle(color: const Color(0xFF5C6479), height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.end,
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () {},
                                style: FilledButton.styleFrom(padding: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: Text('加入购物车'),
                              ),
                            ],
                          ),
                        ),
                      ],
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
