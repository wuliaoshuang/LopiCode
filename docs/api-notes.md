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

# 2026-11-23 补充：DeepSeek 余额、各协议的用量（usage）

核对时间 2026-11-23（北京时间 18:19–18:40）。没有 Key，一个真实接口都没调用过；下面写“已核对”只表示在官方文档页面上看到了，不表示在真接口上验证过。

## DeepSeek 余额（`lib/agent/quota.dart`）

| 内容 | 出处 | 状态 |
| --- | --- | --- |
| 返回字段：`is_available`（布尔，余额够不够调用接口）；`balance_infos[]`，每条 `currency`（`CNY` / `USD`）、`total_balance`（总余额＝赠送＋充值）、`granted_balance`（没过期的赠送余额）、`topped_up_balance`（充值余额），金额都是**字符串** | https://api-docs.deepseek.com/api/get-user-balance | 已核对 |
| **没有任何“限额 / 额度上限”字段**。所以“额度上限”是我们自己的设计：用户填上限，已用＝设上限之后余额减少的累计 | 同上 | 已核对 |
| 地址 `GET https://api.deepseek.com/user/balance`，鉴权 `Authorization: Bearer <key>` | 官方页面抓到的正文里没有地址和鉴权那两行；地址与鉴权来自官方页面的 GitHub 镜像（pocketllm 仓库）、deepseek.apidog.io，以及 dsh-Go 源码的做法，三处一致 | 间接 |
| 401 / 403 当作“Key 无效，查不到余额” | 通行做法 | 未核对 |
| 充值页 `https://platform.deepseek.com/top_up`（“去充值”复制的网址） | 只在 dsh-Go 源码里看到 | 未核对 |

## 用量字段（`lib/agent/usage.dart`）

统一口径：输入 = 未缓存输入 + 缓存读取 + 缓存写入；合计 = 输入 + 输出；缓存命中率 = 缓存读取 ÷ 输入。

| 协议 | 字段与映射 | 出处 | 状态 |
| --- | --- | --- | --- |
| DeepSeek（Chat Completions） | `usage.prompt_cache_hit_tokens` → 缓存读取；`usage.prompt_cache_miss_tokens` → 未缓存输入 | https://api-docs.deepseek.com/guides/kv_cache（“Checking Cache Hit Status”一节） | 已核对 |
| DeepSeek | `prompt_tokens` = hit + miss；`completion_tokens`；`total_tokens`；`completion_tokens_details.reasoning_tokens` → 推理 | 官方 Chat Completions 页面抓到的正文只有请求参数，没有返回字段；这几项来自 NVIDIA AIPerf 的厂商 usage 对照表（docs.nvidia.com/aiperf/v0.13.0/reference/vendor-usage-field-reference，注明对照 DeepSeek 官方文档）和 deepseek-sdk-go 的注释 | 间接 |
| DeepSeek 流式 | `stream_options.include_usage`（布尔，必须和 `stream: true` 一起用）。**不管设不设，`data: [DONE]` 之前最后一块的 `usage` 都带整次请求的用量**；设为 true 时前面每一块也带 `usage: null`。**不会单独发一个只有 usage 的块**：用量附在最后一个内容块上，那一块 `choices` 只有一个元素、没有新内容、`finish_reason` 非空 | https://api-docs.deepseek.com/zh-cn/api/create-chat-completion | 已核对 |
| OpenAI Chat Completions | `stream_options: {"include_usage": true}` 后，最后多一块 `choices: []`、带 `usage`：`prompt_tokens`、`completion_tokens`、`total_tokens`、`prompt_tokens_details.cached_tokens`（是 prompt_tokens 的一部分）→ 缓存读取、`completion_tokens_details.reasoning_tokens` → 推理 | 第三方整理 + openai-python 的类型定义（经 NVIDIA 对照表转述） | 间接 |
| OpenAI Responses | `response.usage`：`input_tokens`（含缓存）、`input_tokens_details.cached_tokens` → 缓存读取、`output_tokens`、`output_tokens_details.reasoning_tokens` → 推理、`total_tokens` | developers.openai.com 的 Responses 参考页（返回示例） | 已核对 |
| OpenAI Responses 流式 | 用量在 `response.completed`（和 `response.incomplete`）事件的 `response.usage` 里 | 第三方整理 | 间接 |
| Anthropic Messages 流式 | `message_start.message.usage`：`input_tokens`（**不含缓存**）→ 未缓存输入、`cache_read_input_tokens` → 缓存读取、`cache_creation_input_tokens` → 缓存写入；`message_delta.usage`（和 `delta` 平级）：`output_tokens` 是累计值（覆盖，不相加），也可能重复给输入各项（非空以它为准） | SDK 类型定义的第三方转述、NVIDIA 对照表 | 间接 |

我们的客户端两种流式形状都认：用量附在最后一个内容块上（DeepSeek），或者单独一块 `choices: []`（OpenAI）。

**没核对的风险**

- 有些 OpenAI 兼容的中转站可能不认 `stream_options`。我们的处理：接口回 400 / 422 且报错里提到 `stream_options` 时，去掉它重发一次，这个客户端之后不再带（那就拿不到用量，界面如实写“接口没返回用量”）。别的报错方式认不出来。
- 接口不给缓存字段时，我们不显示命中率（显示“—”），不当成 0%。
- DeepSeek 默认开思考模式；思考内容走 `delta.reasoning_content`，我们的客户端目前不读它，所以步骤详情里的“首字”是第一个**回答字或工具调用**到达的时间，思考时间算在首字之前。
- **待核实的旧问题**（不是这次改的）：第三方整理的 DeepSeek 指南说，思考模式下带工具调用的助手消息回传时要保留 `reasoning_content`；我们现在不保存也不回传它。真接口上会不会因此报错，没有 Key 验证不了。
