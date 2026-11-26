// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import 'package:flutter/material.dart';

class V3LoginPage extends StatelessWidget {
  const V3LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          leading: const BackButton(),
          title: Text('登录'),
          centerTitle: true,
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
                spacing: 16,
                children: [
                  Icon(Icons.person, size: 56, color: const Color(0xFF058654)),
                  Text(
                    '欢迎回来',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: '手机号 *',
                        hintText: '请输入手机号',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '密码 *',
                        hintText: '请输入密码',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(value: true, onChanged: (value) {}),
                              Flexible(child: Text('记住我')),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '忘记密码？',
                            style: const TextStyle(fontSize: 14, color: const Color(0xFF058654), height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF058654), foregroundColor: const Color(0xFFFFFFFF), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('登录'),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(value: false, onChanged: (value) {}),
                      Flexible(child: Text('我已阅读并同意《用户协议》', style: const TextStyle(fontSize: 13, color: const Color(0xFF5C6479)))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
