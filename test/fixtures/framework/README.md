# “小框架”＋“小书店”（核心 2 的验收样例）

`bookshop.lc` 是从原型 `docs/blocks-v5-prototypes/02-web-framework/`（`libs/小框架/` 七个模块＋`app/main.lcx`）搬过来、加上类型的版本。
原型文件一个字没改；39 条请求（`cases.json`）和 39 行日志（`expected-logs.json`）测试直接读原型的。
测试：`test/lang_gen2_framework_test.dart`（39 条 × 五种语言）、`test/lang_gen2_framework_bad_test.dart`（故意写错的）。

## 换算表

### 宿主接口

| 原型 | 这里 | 说明 |
|---|---|---|
| `native log.error (值)` | `sys.print(文字, "err")` | 值先用“连”拼成文字 |
| `native time.ms ()` | `time.now()` | |
| `native store.get (名字)` | `store.read(名字)` | |
| `native store.update (名字 函数)` | `store.update(名字, 函数)` | 函数标成 (任意) → 任意 |
| `native url.decode (文字)` | 小库“网址解码”（urlDecode） | 小库的写坏了会出错，原型的宿主是原样交回；所以“上下文”模块里包了一个“解码”函数：出错就原样交回 |
| `native http.serve (端口 处理函数)` | `http.serve(端口, 主机, 处理函数)` | 按 C 分册 9.1 的三个参数；处理函数是“要等”的 |
| `native time.sleep (毫秒)` | `time.sleep(毫秒)` | “要等”的 |
| 宿主自己看环境变量 PORT、HOST | 库里“路由”模块的“用哪个端口”＋`sys.env` | C 分册 9.1：这两样从宿主搬到库里；规则不变（PORT 是 1–5 位数字且不超过 65535 才用，HOST 没有就是 0.0.0.0） |

### 要等的事

| 原型 | 这里 |
|---|---|
| `(spawn 语句…)` | `(开始做块 语句…)`：读入时包成一个“要等”的匿名函数再“开始做” |
| `(await 甲)` | `(等 甲)` |
| 原型手工标的 async | `要等函数`、`要等方法`、`要等λ`、`要等λ块`、类型 `(要等函数 (参数…) 返回)`、接口方法签名末尾写 `要等` |

标了“要等”的：下一步、中间件函数、接口“中间件.处理”、处理函数、“错误处理.处理”、“应用.找并处理 / 处理请求 / 开始服务”、“记日志”、“预检.处理”、“鉴权.处理”、`/slow`、`/parallel` 两个处理函数、作者组的中间件。
不要等的处理函数（别的路由）照旧写成普通的 λ：普通函数可以放在要“要等的函数”的地方。

### 小库名字（原型 `rt 名字` → 这里的写法）

dictGet→`取`、isNull→`是空`、size→`长`/`文长`、join→`连`、listPush→`加项`、isType→`是类`、substring→`截`、listConcat→`接`、dictMerge→`合并`、split→`切`、orElse→`或空`、toText→`文`、startsWith→`开头是`、replace→`换`、listSet→`改项`（语句）、listJoin→`拼`、listGet→`项`、listFilter→`调 筛选`、listContains→`列有`、dictHas→`有键`、toNumber→`转数`、toJson→`转JSON`、lower→`小写`、log→`打印`、listFind→`找`、isNumeric→`是数字`、indexOf→`位置`、fromJson→`读JSON`。
这一段给五种语言的版本 2 小库补了三个原来没有的：isType、toNumber、dictMerge。

### 加了类型以后改了写法的地方

1. 动态的值（请求字典、处理函数的返回、仓库里的行、上下文“数据”）都标成“任意”，用的地方先“转”成要的类型；往“任意”里放的地方写 `(标 任意 …)`。
2. “上下文.内容”：原型的 fromJson 遇到不是 JSON 交回空；小库的“读JSON”会出错，所以包了“试着做”，出错当成空。
3. “中间件”可以是对象也可以是函数：列表的类型是“列表〈任意〉”，“包一层”里用“是类 … "function"”分开，再各自“转”。
4. “路由器.全部路由”交回的每一项原型是字典，这里是一条记录“路由项”（路由＋它所在的路由器）；路由本身也是记录。
5. 仓库的编号：路径参数经“要数字”变成小数，和行里的 id（整数）比的时候两边都当“任意”比（3 和 3.0 算相等，原型也是这样）。
6. **请求数放进格子**（原型是入口模块顶上的一个变量）：PHP 的服务每来一个请求把程序从头跑一遍，模块顶上的变量留不住；C 分册 9.1 也说请求之间要留住的东西放格子。五种语言用的是同一份样例。
7. 积木外观写的那个接口（当收到 GET /hello/:name）照原型 `out/round2/expanded.lcx` 展开以后的样子写。
8. 抛文字（`/boom`）、小库自己抛错（`/boom/lib`，往空列表的第 5 项写）原样保留；这两个处理函数不交回东西，放在“交回任意”的地方（为此修了 Go、Java 生成器里函数换样子的一处错，见 B-gen-notes 第 12 节）。
