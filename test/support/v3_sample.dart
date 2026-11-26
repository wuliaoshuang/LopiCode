import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 格式第 3 版加的属性都用上的页面：按钮图标 / 禁用，图片说明文字，输入框类型 / 默认值 / 标签 / 必填 / 禁用，
/// 节点名字 / 锁定 / 编辑器里隐藏（这三样不影响导出）。
LcDocument v3Sample() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': '第 3 版样本',
    'root': {
      'id': 'root',
      'type': 'page',
      'props': {'padding': 16, 'gap': 12},
      'children': [
        {
          'id': 'pic',
          'type': 'image',
          'name': '头图',
          'props': {'src': 'https://example.com/a.png', 'alt': '一只 "猫" <在> 睡觉', 'width': 'fill', 'height': 120},
        },
        {
          'id': 'ph',
          'type': 'image',
          'props': {'alt': '还没放图', 'width': 'fill', 'height': 80},
        },
        {
          'id': 'user',
          'type': 'input',
          'name': '账号框',
          'props': {'placeholder': '手机号', 'label': '账号 <b>&', 'required': true, 'inputType': 'tel', 'value': '138"00', 'width': 'fill'},
        },
        {
          'id': 'pwd',
          'type': 'input',
          'locked': true,
          'props': {'placeholder': '密码', 'label': '密码', 'inputType': 'password', 'width': 'fill'},
        },
        {
          'id': 'age',
          'type': 'input',
          'props': {'placeholder': '年龄', 'inputType': 'number', 'disabled': true, 'value': '18'},
        },
        {
          'id': 'mail',
          'type': 'input',
          'hidden': true,
          'props': {'placeholder': '邮箱', 'inputType': 'email', 'required': true},
        },
        {
          'id': 'row',
          'type': 'row',
          'props': {'gap': 8},
          'children': [
            {
              'id': 'ok',
              'type': 'button',
              'props': {'text': '发送', 'icon': 'send', 'bg': '#058654', 'color': '#FFFFFF'},
            },
            {
              'id': 'del',
              'type': 'button',
              'props': {'text': '', 'icon': 'delete', 'disabled': true},
            },
            {
              'id': 'off',
              'type': 'button',
              'props': {'text': '不能点', 'disabled': true},
            },
          ],
        },
      ],
    },
  }),
);
