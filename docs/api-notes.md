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

---

# 2026-11-23 补充：多协议、模型列表、联网搜索

核对时间：2026-11-23 约 07:32–07:36 UTC。标注说明：**已核对** = 当天打开官方页面看到了原文；**间接** = 官方页面抓不到这一段，看的是官方文档的镜像或第三方资料；**未核对** = 没找到出处，按通行做法写的。全部只在本地假服务器上测过，没有调用过任何真实接口。

## Anthropic Messages（`lib/agent/protocols.dart` 的 `AnthropicChatClient`）

| 内容 | 出处 | 状态 |
| --- | --- | --- |
| 流式是带名字的 SSE 事件：`message_start` → 每个内容块 `content_block_start` / `content_block_delta`… / `content_block_stop`（都带 `index`）→ `message_delta` → `message_stop`；中间可能有 `ping`；可能在流里出现 `error` 事件；没见过的事件类型要跳过 | platform.claude.com/docs/en/api/streaming | 已核对 |
| 增量类型：`text_delta`（`text`）、`input_json_delta`（`partial_json`，攒到 `content_block_stop` 再解析）、`thinking_delta`（`thinking`）、`signature_delta`（`signature`）；工具块开头是 `content_block_start.content_block = {type:"tool_use", id, name, input:{}}`；结束原因在 `message_delta.delta.stop_reason` | 同一页的示例代码抓不到，看的是 GitHub 上官方文档的镜像（sullivan-street-projects/anthropic-docs-local，标明抓自同一网址） | 间接 |
| 请求：`POST {base}/messages`，请求头 `x-api-key`、`anthropic-version: 2023-06-01`、`content-type: application/json`；请求体 `model`、`max_tokens`（必填）、`stream`、`messages` | 同上镜像里的官方 cURL 示例 | 间接 |
| 工具定义：`tools[] = {name, description, input_schema}`；模型要用工具时 `stop_reason: "tool_use"`，内容里有 `tool_use` 块（`id`、`name`、`input`） | platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls（搜索结果里的官方原文摘录） | 已核对 |
| 回填结果：把模型那条回复的 `content` 原样作为 `assistant` 消息，再加一条 `user` 消息，里面每个 `tool_use` 对应一个 `{type:"tool_result", tool_use_id, content, is_error}`；`tool_result` 必须排在这条 user 消息的最前面，紧跟在对应的 assistant 消息后面 | 同上 | 已核对（“必须排最前”一句来自较早的官方页面存档，间接） |
| `system` 是请求体顶层字段，不是一条消息 | 没抓到原文 | 未核对 |
| 图片：`{type:"image", source:{type:"base64", media_type, data}}` | 没抓到原文 | 未核对 |
| 思考：`thinking: {type:"enabled", budget_tokens: N}`，N 必须小于 `max_tokens`；开了思考后，带工具调用的那条 assistant 消息必须把 `thinking` 块连同 `signature` 原样带回 | 镜像里只看到 `{"type":"adaptive","display":"summarized"}` 这种写法，`budget_tokens` 写法没抓到原文 | 未核对。代码里把模型回复的原始内容块整条存下来、下一轮原样发回，档位换算（低 4096 / 中 16384 / 高 32768）是自己定的 |
| 模型列表：`GET {base}/models`，返回 `data[].id`、`data[].display_name`、`has_more`、`last_id`；查询参数 `limit`（1–1000，默认 20）、`after_id` | platform.claude.com/docs/en/api/http/models/list | 已核对。官方示例用的是 `Authorization: Bearer` 加新的版本号；我们发 `x-api-key` 加 `anthropic-version: 2023-06-01`（间接） |

## OpenAI Responses（`OpenAiResponsesClient`）

| 内容 | 出处 | 状态 |
| --- | --- | --- |
| 接口是 `POST /responses` | platform.openai.com/docs/api-reference/responses-streaming（目录页） | 已核对 |
| 工具定义是“扁平”的：`{type:"function", name, description, parameters, strict}`（不像 Chat Completions 包在 `function` 里）；不想要严格模式要显式写 `strict: false` | developers.openai.com/api/docs/guides/function-calling | 已核对 |
| 模型的工具调用是输出里的一项：`{type:"function_call", id, call_id, name, arguments}`（`arguments` 是 JSON 字符串）；回填用 `{type:"function_call_output", call_id, output}`，并且要把模型的输出项原样留在 `input` 里 | 同上 | 已核对 |
| 流式事件：`response.output_item.added`（`output_index`、`item`）、`response.function_call_arguments.delta`（`item_id`、`output_index`、`delta`）、`response.function_call_arguments.done`、`response.output_item.done` | 同上（原文带示例） | 已核对 |
| 文字增量 `response.output_text.delta`（`delta`）；结束 `response.completed` / `response.incomplete` / `response.failed`；流里的 `error` 事件 | 官方页面抓不到这一段，多份第三方资料一致 | 间接 |
| 请求体 `model`、`input`（消息或输出项的列表）、`instructions`、`stream`、`max_output_tokens`、`tools`、`reasoning: {effort}` | 返回示例里能看到 `instructions`、`max_output_tokens`、`reasoning.effort`、`tools` 这些字段名（platform.openai.com/docs/api-reference/responses/create）；请求参数表本身没抓到 | 间接 |
| 消息内容块：用户 `input_text` / `input_image`（`image_url`），助手 `output_text` | 返回示例里有 `output_text`；`input_text`、`input_image` 没抓到原文 | 间接 / 未核对 |
| 我们每次都发 `store: false`、自己带全量历史，不用 `previous_response_id` | 设计选择 | — |

## Chat Completions 新用到的参数

- 思考档位：`reasoning_effort`（`low` / `medium` / `high`）。**未核对**（当天没有重新打开参数表），只在模型设置里开了“思考”并且选了档位时才发。
- 最大输出：只有在模型设置里改过默认值（32K）时才发 `max_tokens`。**未核对**各家兼容接口认不认；官方新模型用的是 `max_completion_tokens`，遇到报错把模型的最大输出改回 32K 就不会再发。
- 图片：`content: [{type:"text", text}, {type:"image_url", image_url:{url:"data:<mime>;base64,..."}}]`。**未核对**（当天没有重新打开）。
- 模型列表：`GET {base}/models`，返回 `data[].id`。**未核对**（通行做法）。“测试连接”和“获取模型”都只请求这个接口，不产生对话费用。

## 联网搜索：Tavily（`lib/agent/web_search.dart`）

选它的原因：有公开的官方文档（docs.tavily.com），一个接口、一个 Key。没有替她注册，也没有调用过。

| 内容 | 出处 | 状态 |
| --- | --- | --- |
| 返回：`query`、`answer`、`results[] = {title, url, content, score, raw_content, published_date, favicon}`、`response_time`、`request_id` | docs.tavily.com/documentation/api-reference/introduction | 已核对 |
| 请求：`POST https://api.tavily.com/search`，`Authorization: Bearer <key>`，请求体 `query`（必填）、`max_results`（0–20，默认 5）、`search_depth`（默认 `basic`，`advanced` 更贵） | 官方页面只抓到返回示例；请求参数来自多份第三方整理，说法一致 | 间接 |

我们只发 `query`、`max_results`（上限 10）、`search_depth: "basic"`，每次搜索按 Tavily 的说法消耗 1 个额度（间接，未核对价格）。
