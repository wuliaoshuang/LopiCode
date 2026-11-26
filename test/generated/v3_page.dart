// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class V3Page extends StatelessWidget {
  const V3Page({super.key});

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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: Image.network('https://example.com/a.png', height: 120, width: double.infinity, fit: BoxFit.cover, semanticLabel: '一只 "猫" <在> 睡觉', errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined)),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: Container(height: 80, width: double.infinity, color: const Color(0xFFD3DEE4), alignment: Alignment.center, child: const Icon(Icons.image_outlined, semanticLabel: '还没放图')),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextFormField(
                      initialValue: '138"00',
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: '账号 <b>& *',
                        hintText: '手机号',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '密码',
                        hintText: '密码',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  TextFormField(
                    initialValue: '18',
                    enabled: false,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '年龄',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  TextField(
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: '邮箱',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () {},
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF)),
                          icon: const Icon(Icons.send),
                          label: Text('发送'),
                        ),
                        FilledButton.icon(
                          onPressed: null,
                          style: FilledButton.styleFrom(),
                          icon: const Icon(Icons.delete),
                          label: Text(''),
                        ),
                        FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(),
                          child: Text('不能点'),
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
