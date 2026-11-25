# 零散小实验（各部分写文档时跑过的脚本，原样留档）

这些是 A1、A2、C、D 四位写各自部分时放在 `/tmp` 下的小实验源码，协调者在合稿时原样拷进来，防止机器重启后丢失。
**协调者没有重新跑它们**；“跑出来什么”以各自 parts 文档里记的为准：

| 目录 | 是什么 | 结果记在哪 |
|---|---|---|
| `A1-generators/` | “生成器＝收一个回调的函数”在 Node / Python / Java / Go 各写一份 | `../../blocks-v5-parts/A1-features-basics.md` 第 13 节 |
| `A1-negative-probes/` | 核对“某语言没有某特性”时写的小探针 | 同上，各表里标“跑” 的格子 |
| `A2-go-experiments/` | Go 的类（嵌入＋接口＋指回自己）与“试着做”口里的返回/跳出 | `A2-features-advanced.md` 第 10 节 a、e |
| `C-mini-router/` | 示例库 `demo/mini-router` 的完整文件夹（只被 `json.load` 读过，没被生成过代码） | `C-library-system.md` 第 3 节 |
| `C-go-export/` | Go 包里大写名可用、小写名编译报未导出 | `C-library-system.md` 文末 |
| `D-frontend/` | 小运行时 10 项（`sig.js`）、两示例库 16 项（`libs.js`）、新旧数字规矩对比（`cmp.js`、`diff2.js`） | `D-frontend-logic.md` 4.6、6.3、8.5 |

跑法：`node 文件.js` / `python3 文件.py` / `javac X.java && java X` / `go run .`（Go 要先把 `~/workspace/tools/gosdk/go/bin` 加进 PATH）。
