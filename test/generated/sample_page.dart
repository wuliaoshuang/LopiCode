// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class SamplePage extends StatelessWidget {
  const SamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF6FBFD),
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
                    child: Text(
                      '欢迎 <b>\'回来\'</b> \$5',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.5),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: '手机号',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            spacing: 8,
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {},
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF)),
                                  child: Text('登录'),
                                ),
                              ),
                              SizedBox(
                                width: 96,
                                child: FilledButton(
                                  onPressed: () {},
                                  style: FilledButton.styleFrom(),
                                  child: Text('注册'),
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: '行内输入',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  '行内文本',
                                  style: const TextStyle(height: 1.5),
                                ),
                              ),
                              const SizedBox(height: 24, child: VerticalDivider(width: 1)),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(height: 120, width: double.infinity, color: const Color(0xFFD3DEE4), alignment: Alignment.center, child: const Icon(Icons.image_outlined)),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: Image.network('https://example.com/a.png', height: 80, width: 80, fit: BoxFit.cover, errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('• 一', style: const TextStyle(height: 1.75)),
                        Text('• 二 & 三', style: const TextStyle(height: 1.75)),
                      ],
                    ),
                  ),
                  Container(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 4,
                      children: [
                        Container(
                          height: 40,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: const Color(0xFFD3DEE4)),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: const Divider(height: 1),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
