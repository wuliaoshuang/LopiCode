/// “前端 + 后端”模板里前端那一半：`web/` 下一个调用后端接口的小页面（列出待办、添加、勾完成、删除），
/// 外加项目根目录的 `index.html`（预览打开的是根目录的 index.html，它把人带到 `web/`）和根 README。
///
/// 后端的地址可以在页面上改（存在浏览器的 localStorage 里），默认 `http://localhost:端口`。
/// 页面只用 `textContent` 往界面上放后端给的内容，不拼 HTML。
library;

import 'dart:convert';

import 'package:lopicode/templates/code_starters.dart' show starterTitle;

String _esc(String s) => const HtmlEscape().convert(s);

/// 前端这一半的文件（路径相对项目根目录）。`port`＝后端的默认端口。
Map<String, String> fullstackWebFiles(String name, {required int port}) => {
  'index.html': _rootIndex(name),
  'web/index.html': _webIndex(name),
  'web/style.css': _webCss,
  'web/app.js': _webJs.replaceAll('__PORT__', '$port'),
};

String _rootIndex(String name) =>
    '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0; url=web/">
  <title>${_esc(name)}</title>
</head>
<body>
  <p>页面在 <a href="web/">web/</a> 里，正在跳过去…</p>
</body>
</html>
''';

String _webIndex(String name) =>
    '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc(name)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="card">
    <h1>${_esc(name)}</h1>
    <p id="status" class="status">正在连接后端…</p>

    <div class="row">
      <input id="title" type="text" placeholder="要做什么？" autocomplete="off">
      <button id="add" type="button">添加</button>
    </div>

    <ul id="list" class="list"></ul>
    <p id="empty" class="hint" hidden>还没有待办，添加一条试试。</p>

    <details class="settings">
      <summary>后端地址</summary>
      <div class="row">
        <input id="api" type="url" inputmode="url" autocomplete="off">
        <button id="save" type="button" class="quiet">保存</button>
      </div>
      <p class="hint">手机上 localhost 指手机自己：后端要先在这台手机的终端里启动。</p>
    </details>
  </main>
  <script src="app.js"></script>
</body>
</html>
''';

const String _webCss = '''* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  padding: 24px 16px;
  font-family: system-ui, -apple-system, "Noto Sans SC", sans-serif;
  background: #f6fbfd;
  color: #222435;
}
.card {
  width: min(100%, 480px);
  margin: 0 auto;
  padding: 24px;
  border-radius: 12px;
  background: #fff;
  box-shadow: 0 4px 6px rgba(0, 0, 0, .08);
}
h1 { margin: 0 0 4px; font-size: 24px; }
.status { margin: 0 0 16px; font-size: 14px; color: #5c6479; }
.status.ok { color: #058654; }
.status.bad { color: #c0392b; }
.row { display: flex; gap: 8px; }
input[type="text"], input[type="url"] {
  flex: 1;
  min-width: 0;
  padding: 10px 12px;
  border: 1px solid #cfd6e4;
  border-radius: 8px;
  font-size: 16px;
}
button {
  padding: 10px 16px;
  border: 0;
  border-radius: 8px;
  background: #2962cb;
  color: #fff;
  font-size: 16px;
}
button.quiet { background: #eef1f6; color: #222435; }
button.remove { padding: 6px 10px; background: transparent; color: #c0392b; font-size: 14px; }
.list { margin: 16px 0 0; padding: 0; list-style: none; }
.list li {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid #eef1f6;
}
.list li span { flex: 1; min-width: 0; overflow-wrap: anywhere; }
.list li.done span { color: #9aa2b4; text-decoration: line-through; }
.list input[type="checkbox"] { width: 20px; height: 20px; }
.hint { margin: 12px 0 0; font-size: 14px; line-height: 1.5; color: #5c6479; }
.settings { margin-top: 24px; font-size: 14px; color: #5c6479; }
.settings summary { padding: 8px 0; cursor: pointer; }
''';

const String _webJs = r'''// 调后端接口的小页面。后端地址可以在页面底部改，存在浏览器里。
const DEFAULT_API = 'http://localhost:__PORT__';
let api = localStorage.getItem('apiBase') || DEFAULT_API;

const $ = (id) => document.getElementById(id);

function setStatus(text, kind) {
  $('status').textContent = text;
  $('status').className = 'status' + (kind ? ' ' + kind : '');
}

// 发一次请求；失败时把原因显示出来，返回 null。
async function call(method, path, data) {
  try {
    const res = await fetch(api + path, {
      method,
      headers: data === undefined ? {} : { 'Content-Type': 'application/json' },
      body: data === undefined ? undefined : JSON.stringify(data),
    });
    const text = await res.text();
    const json = text ? JSON.parse(text) : null;
    if (!res.ok) {
      setStatus((json && json.error) || '后端回了 ' + res.status, 'bad');
      return null;
    }
    setStatus('已连上后端 ' + api, 'ok');
    return json;
  } catch (e) {
    setStatus('连不上后端 ' + api + '：先在终端里把后端启动起来（看 README）', 'bad');
    return null;
  }
}

function render(todos) {
  const list = $('list');
  list.replaceChildren();
  for (const todo of todos) {
    const li = document.createElement('li');
    if (todo.done) li.className = 'done';

    const box = document.createElement('input');
    box.type = 'checkbox';
    box.checked = Boolean(todo.done);
    box.addEventListener('change', async () => {
      await call('PATCH', '/todos/' + todo.id, { done: box.checked });
      load();
    });

    const title = document.createElement('span');
    title.textContent = String(todo.title ?? '');

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'remove';
    remove.textContent = '删除';
    remove.addEventListener('click', async () => {
      await call('DELETE', '/todos/' + todo.id);
      load();
    });

    li.append(box, title, remove);
    list.append(li);
  }
  $('empty').hidden = todos.length > 0;
}

async function load() {
  const todos = await call('GET', '/todos');
  if (Array.isArray(todos)) render(todos);
}

async function add() {
  const title = $('title').value.trim();
  if (!title) return;
  const created = await call('POST', '/todos', { title });
  if (created) {
    $('title').value = '';
    load();
  }
}

$('add').addEventListener('click', add);
$('title').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') add();
});
$('api').value = api;
$('save').addEventListener('click', () => {
  api = $('api').value.trim().replace(/\/+$/, '') || DEFAULT_API;
  $('api').value = api;
  localStorage.setItem('apiBase', api);
  load();
});

load();
''';

/// 全栈模板的根 README。`serverCommand`＝从项目根目录启动后端的一整行命令。
String fullstackReadme(String name, {required String languageLabel, required String serverCommand, required int port, required bool verified}) {
  final out = StringBuffer();
  out.writeln('# ${starterTitle(name)}');
  out.writeln();
  out.writeln('一个网页（`web/`）加一个用积木搭的后端（`server/`，$languageLabel）。网页通过接口找后端要数据：列出待办、添加、勾完成、删除。');
  if (!verified) {
    out.writeln();
    out.writeln('> 注意：$languageLabel 的后端代码**还没有在真机器上实际运行过**，只检查过结构。');
  }
  out.writeln();
  out.writeln('## 先启动后端，再开预览');
  out.writeln();
  out.writeln('1. 点底部导航的“终端”（第一次用要先在侧边栏“运行环境”里装好 Ubuntu 环境和 $languageLabel 的工具），输入：');
  out.writeln();
  out.writeln('   ```');
  out.writeln('   $serverCommand');
  out.writeln('   ```');
  out.writeln();
  out.writeln('   看到“后端已启动”那一行就好了。终端别关，想停下来按 Ctrl+C。');
  out.writeln('2. 打开预览：会自动跳到 `web/` 里的页面。页面上方显示“已连上后端”就对了。');
  out.writeln();
  out.writeln('## 要知道的几件事');
  out.writeln();
  out.writeln('- **手机上的 `localhost` 指的是手机自己。** 网页默认去 `http://localhost:$port` 找后端，所以后端要在这台手机上启动。');
  out.writeln('  后端跑在别的机器上时，在页面底部“后端地址”里改成那台机器的地址（比如 `http://192.168.1.20:$port`）再点保存。');
  out.writeln('- 待办存在后端的内存里：后端一重启数据就没了。');
  out.writeln('- 后端的每个响应都带 `Access-Control-Allow-Origin: *`，所以网页可以跨域调用它。');
  out.writeln();
  out.writeln('## 文件');
  out.writeln();
  out.writeln('| 位置 | 是什么 |');
  out.writeln('| --- | --- |');
  out.writeln('| `web/index.html`、`web/style.css`、`web/app.js` | 网页，随便改 |');
  out.writeln('| `server/backend.lc.json` | 后端的积木（接口都在这里） |');
  out.writeln('| `server/` 里其余的文件 | 积木生成的代码，重新生成会覆盖；接口清单和 curl 例子见 `server/README.md` |');
  out.writeln('| `index.html` | 只管把预览带到 `web/` |');
  return out.toString();
}
