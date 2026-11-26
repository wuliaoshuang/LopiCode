# 开发机验证脚本（只在开发机上用，不进应用）

给测试用的几段 Node 脚本：把导出的 Vue / React 工程用官方编译器**真的编译**一遍，再在 Node 里做一次最小渲染。

环境装在 `~/workspace/tools/webdev/`（typescript、vue、@vue/compiler-sfc、@vue/server-renderer、react、react-dom、esbuild，
版本和来源见 `docs/api-notes.md` 的“开发机验证环境”一节）。测试找它的顺序：环境变量 `LOPI_WEBDEV` → `~/workspace/tools/webdev`。
找不到时相关测试明确跳过并打印原因，不算通过。

| 脚本 | 做什么 |
| --- | --- |
| `compile_vue.mjs <目录> <入口.vue>` | 每个 `.vue`：解析 → 编译脚本 → 编译模板（客户端、服务端两种）→ 编译样式；再打成一个包，在 Node 里服务端渲染入口组件 |
| `compile_react.mjs <目录> <入口.jsx>` | 用 esbuild 把 `.jsx`、`.css` 打成一个包（等于真编译）；再用 react-dom/server 渲染入口组件 |

两个脚本都只往标准输出写一行 JSON：`{ok, errors, warnings, html, ...}`。不联网。
