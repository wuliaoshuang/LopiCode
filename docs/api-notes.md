# 接口核对笔记

写客户端之前先对着官方文档核对字段名（不凭记忆写）。核对时间：2026-11-22 约 19:35–19:41 UTC。

## OpenAI Chat Completions（来源：developers.openai.com 官方文档）

`lib/agent/chat_client.dart` 用到的字段：

- 请求：`POST {base}/chat/completions`，`Authorization: Bearer <key>`；请求体 `model`、`messages`、`stream: true`、`tools`（每项 `{"type":"function","function":{name, description, parameters}}`）。
- 流式响应：SSE，每行 `data: {...}`，以 `data: [DONE]` 结束；内容在 `choices[0].delta.content`。
- 工具调用是分片到达的：`choices[0].delta.tool_calls[]`，每片带 `index`，首片带 `id` 和 `function.name`，`function.arguments` 是字符串片段，要按 `index` 拼起来。
- 结束原因：`choices[0].finish_reason`（`stop` / `tool_calls` / `length`）。
- 把工具结果发回去：先一条 `role: assistant` 带 `tool_calls`，再每个调用一条 `role: tool`，带 `tool_call_id` 和 `content`。

没有核对、也没有用到的：各家“兼容接口”的私有参数。只在本地假服务器上测过，没有调用过任何真实的模型接口。

## GitHub REST API（来源：docs.github.com，API 版本 `2022-11-28`）

`lib/build/github_client.dart` 用到的接口：

| 用途 | 接口 | 核对结果 |
| --- | --- | --- |
| 触发工作流 | `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches`，请求体 `ref`、`inputs`、`return_run_details` | 已核对。带 `return_run_details: true` 时返回运行 ID；老行为是 204 无内容，代码两种都处理，服务器不认这个字段（422）时去掉重试 |
| 查运行状态 | `GET /repos/{owner}/{repo}/actions/runs/{run_id}`（`status`、`conclusion`、`html_url`） | 已核对 |
| 列出产物 | `GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts` | 已核对 |
| 下载产物 | `GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip` | 已核对：返回 302，`Location` 里的下载地址 1 分钟内有效；产物过期返回 410。跟随跳转时不带 `Authorization` |
| 推送文件 | Git Data API：`git/ref/heads/{branch}` → `git/commits/{sha}` → `POST git/blobs` → `POST git/trees` → `POST git/commits` → `PATCH git/refs/heads/{branch}` | 已核对 |
| 找刚触发的那次运行（仅老行为回退时用） | `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs?event=workflow_dispatch&branch=…` | **没有核对到**：2026-11-22 再次打开文档页，抓到的文本里看不到接口路径。按记忆实现，首次真实使用时要留意 |

没有对真实的 GitHub 发过任何请求，全部在本地假服务器上测。`.github/workflows/android.yml` 两份模板也没有在真实的 Actions 上跑过。
