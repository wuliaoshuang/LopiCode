// 聊天正文渲染的样例文字（界面测试和截图共用）。

/// 一张 1×1 的 png。
const String kTinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// 一条把支持的语法都用上的消息。
const String kMdEverything = '''
# 一级标题
## 二级标题
### 三级标题

这是一段正文，有**粗体**、*斜体*、~~删除线~~、`行内代码` 和[一个链接](https://example.com/docs?a=1)。
单个换行也换行。

- 无序第一项
- 无序第二项
  - 嵌套的一项
  - 嵌套里有 `code`
1. 有序第一项
2. 有序第二项

- [x] 做完的任务
- [ ] 没做的任务

> 引用的一句话
> 引用的第二行

| 名称 | 说明 | 数量 |
|:---|:---:|---:|
| 苹果 | 一种很长很长很长很长很长很长很长很长很长的水果说明 | 12 |
| 香蕉 | 黄色 | 3 |

```dart
void main() {
  final greeting = 'hello';
  print(greeting); // 这一行很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长
}
```

---

行内公式 \$E=mc^2\$，下面是公式块：

\$\$
\\int_0^1 x^2 dx
\$\$

内联 HTML：<b>加粗</b>、<u>下划线</u>、<mark>高亮</mark>、<kbd>Ctrl</kbd>+<kbd>C</kbd>、H<sub>2</sub>O、x<sup>2</sup><br>换行以后。

<details><summary>点开看细节</summary>

藏起来的内容

</details>

![一张图](https://example.com/pic.png)

<script>alert(1)</script>
''';

const String kMdHtmlBlock = '''
下面是一个网页：

```html
<!DOCTYPE html>
<html><body>
<h1 onclick="alert(1)">你好</h1>
<img src="https://example.com/a.png">
<a href="https://example.com/next">下一页</a>
</body></html>
```

写完了。
''';
