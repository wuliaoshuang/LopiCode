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
- 模型列表：`GET {base}/models`，返回 `data[].id`。**未核对**（通行做法）。“获取模型”只请求这个接口，不产生对话费用；读得到就算连接正常（2026-11-24 起不再有单独的“测试连接”按钮——它原来发的就是同一个请求）。模型行上的“测试”发的是平时对话那个请求（一句 `hi`、不带工具、收到第一段回复就断开），没有新增接口用法，会花几个 token。

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
- **（2026-11-24 已核对并改掉，见文末「DeepSeek 思考模式与工具调用」）** 原来记的旧问题：第三方整理的 DeepSeek 指南说，思考模式下带工具调用的助手消息回传时要保留 `reasoning_content`；我们现在不保存也不回传它。真接口上会不会因此报错，没有 Key 验证不了。

# 2026-11-23 补充：服务商预设的接口地址（`lib/agent/provider_presets.dart`）

核对日期 2026-11-23。做法：当天用网页抓取打开各家**官方域名**的文档页，在正文里看到这个地址才算“已核对”。
没有 Key、没注册、**一个真实接口都没调用过**——“已核对”只表示官方文档上这么写，不表示实际连通过。
完整过程（每家转述了什么、哪些页面没打开）在 [provider-presets-research.md](provider-presets-research.md)。

地址怎么拼：我们的代码是 `{接口地址}/chat/completions`、`{接口地址}/messages`、`{接口地址}/models`，**不会自动补 `/v1`**，
所以预设里的地址是官方完整地址去掉最后那一段。Anthropic 协议的地址必须自己带 `/v1`。

## 放进预设的（18 家，地址均已核对官方文档）

| 服务商 | 协议 | 接口地址 | 官方来源（核对时打开的页面） |
| --- | --- | --- | --- |
| DeepSeek | OpenAI Chat Completions | `https://api.deepseek.com` | https://api-docs.deepseek.com/ |
| OpenAI | OpenAI Chat Completions | `https://api.openai.com/v1` | https://developers.openai.com/api/reference/resources/models/methods/list |
| Anthropic | Anthropic Messages | `https://api.anthropic.com/v1` | https://platform.claude.com/docs/en/api/http/models/retrieve |
| Google Gemini | OpenAI Chat Completions | `https://generativelanguage.googleapis.com/v1beta/openai` | https://aistudio.google.com/docs/openai?hl=pt |
| 智谱 BigModel | OpenAI Chat Completions | `https://open.bigmodel.cn/api/paas/v4` | https://docs.bigmodel.cn/cn/guide/develop/openai/introduction |
| 阿里云百炼 | OpenAI Chat Completions | `https://dashscope.aliyuncs.com/compatible-mode/v1` | https://help.aliyun.com/zh/model-studio/model-calling-in-sub-workspace |
| 月之暗面 Kimi | OpenAI Chat Completions | `https://api.moonshot.cn/v1` | https://platform.kimi.com/docs/api/overview |
| 火山方舟（豆包） | OpenAI Chat Completions | `https://ark.cn-beijing.volces.com/api/v3` | https://ark.volcengine.com/region:cn-beijing/docs/compatible-with-openai-sdk |
| 硅基流动 | OpenAI Chat Completions | `https://api.siliconflow.cn/v1` | https://docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-yan |
| OpenRouter | OpenAI Chat Completions | `https://openrouter.ai/api/v1` | https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties |
| MiniMax | OpenAI Chat Completions | `https://api.minimax.cn/v1` | https://platform.minimax.cn/docs/guides/quickstart-preparation |
| xAI | OpenAI Chat Completions | `https://api.x.ai/v1` | https://docs.x.ai/developers/model-capabilities/legacy/chat-completions.md |
| Groq | OpenAI Chat Completions | `https://api.groq.com/openai/v1` | https://console.groq.com/docs/openai |
| 腾讯混元 | OpenAI Chat Completions | `https://tokenhub.tencentmaas.com/v1` | https://cloud.tencent.com/document/product/1823/132252 |
| 百度千帆 | OpenAI Chat Completions | `https://qianfan.baidubce.com/v2` | https://cloud.baidu.com/doc/qianfan/s/Hmh4suq26 |
| 阶跃星辰 | OpenAI Chat Completions | `https://api.stepfun.com/v1` | https://platform.stepfun.com/docs/zh/guides/developer/openai |
| Cerebras | OpenAI Chat Completions | `https://api.cerebras.ai/v1` | https://inference-docs.cerebras.ai/resources/openai |
| Ollama（本机） | OpenAI Chat Completions | `http://localhost:11434/v1` | https://docs.ollama.com/api/openai-compatibility |

**放进去了但要留意的**

- MiniMax：官方文档页今天写的是 `api.minimax.cn`；多篇第三方文章写 `api.minimaxi.com`（国内）、`api.minimax.io`（国际）。哪个现在能用没实测，预设里给了提示，图标两种主机名都认。
- 腾讯混元：放的是腾讯云 TokenHub 新地址（官方页已核对）。旧地址 `https://api.hunyuan.cloud.tencent.com/v1` 只在官方域名的搜索摘录里看到、官方页没打开成功，**没放进预设**（只用来认图标）；两边的 Key 不通用。
- 阿里云百炼：放的是北京地域；其他地域地址不同、Key 不通用；新加坡地址带 `{WorkspaceId}` 占位，做不成一键预设。
- Anthropic：地址已核对。但官方示例页现在用 `Authorization: Bearer` 加较新的 `anthropic-version`，我们的代码发的是 `x-api-key` 加自己的版本常量；旧写法是否仍被接受**没测**，要用真 Key 试一次。
- xAI：官方把 Chat Completions 标成旧接口、主推 Responses；预设仍用 Chat Completions（地址相同，可在编辑页改协议）。
- Ollama：官方文档说本机服务会忽略 Key，所以这个预设允许不填 Key。`localhost` 在手机上指手机自己（这句是我们自己的提醒，不是文档内容）。
- “获取模型”（`GET {地址}/models`）：只有 OpenAI、Anthropic、Gemini、Moonshot、OpenRouter、Ollama、阶跃星辰在官方文档里确认有这个接口；DeepSeek 是官方域名搜索摘录；其余各家**未确认**，按钮可能失败，失败时可以“手动添加模型 ID”。
- 各家“去哪拿 Key”的提示：只有 Gemini（aistudio.google.com/apikey）、xAI（console.x.ai）、硅基流动（cloud.siliconflow.cn）是官方页里看到的具体位置，其余是按文档里的文字描述写的，没有逐个打开核对。

## 没放进预设的（没能核对官方文档，不凭记忆放）

| 服务商 | 情况 |
| --- | --- |
| 讯飞星火 | 官方页打开了，但地址在代码块里没显示出来；地址只在第三方看到 |
| Mistral | 只在第三方看到，没拿到官方页 |
| Together AI | 只在第三方看到，而且有两种说法 |
| Fireworks | 只在第三方看到，而且两处说法不一致 |
| Perplexity | 只在一个预览文档站的搜索摘录里看到，没打开 |
| 零一万物、百川 | 没查 |

这些要用就走“自定义”。

## 图标

`@lobehub/icons-static-svg` 1.106.0（MIT，Copyright (c) 2023 LobeHub）。许可证取自 https://raw.githubusercontent.com/lobehub/lobe-icons/master/LICENSE （2026-11-23）。
包从 npm 镜像 registry.npmmirror.com 下载，sha512 与 npm 登记的一致。详见 `third_party/lobe-icons/README.md`。

## 聊天语音输入：speech_to_text 7.5.0

核对时间：2026-11-24。来源：https://pub.dev/packages/speech_to_text （官方包文档）。

- `initialize()` 返回设备是否可用；`listen()` 用 `SpeechListenOptions` 开启实时结果、听写模式和 60 秒上限；`stop()` 保留已识别文字，`cancel()` 用于页面销毁。
- Android 需要 `RECORD_AUDIO`，并在 `queries` 里声明 `android.speech.RecognitionService`；麦克风权限只在用户点语音按钮后请求。
- iOS / macOS 需要 `NSSpeechRecognitionUsageDescription` 和 `NSMicrophoneUsageDescription`。本仓库目前没有 iOS 目录，新增平台时须同时补这两项。
- 状态：官方 API 与权限配置已核对；Widget 测试用假识别器覆盖，**尚未在真机验证识别质量、权限弹窗和厂商语音服务**。

## 后端积木生成的代码里用到的接口（`lib/backend/runtime_*.dart`）

记录时间：2026-11-24。**这一节都没有对着官方文档逐条核对**（做的时候不许联网），是凭对标准库的了解写的，下面写明各自实际验证到什么程度。

- Node.js “请求别的网址”：全局 `fetch(url, { method, body, headers, signal: AbortSignal.timeout(10000) })`，`res.ok` 判断 2xx，
  `res.arrayBuffer()` 取内容后自己用 `TextDecoder` 按 UTF-8 读（不用 `res.text()`：本机 Node 24 上实测它会去掉开头的**两个** BOM）。
  状态：**未核对官方文档**；在本机 Node 24.22.1 上实际跑过（请求自己的 GET / POST、对方回 404、连不上、不是 http 网址），结果符合预期。
  没有实际验证的：真的等满 10 秒超时、https、跳转。
- Python “请求别的网址”：`urllib.request.urlopen(urllib.request.Request(url, data=…, headers=…, method=…), timeout=10)`，4xx / 5xx 会抛 `HTTPError`（一律当失败）。
  状态：**未核对官方文档**；在本机 Python 3.12.3 上实际跑过同样几种情况。没有实际验证的同上。
- Node.js 服务：`node:http` 的 `createServer / listen / writeHead / end`，请求体用 `for await (const chunk of req)` 读；
  `String.prototype.toWellFormed()`（所以写了“需要 Node 20 或更新”）、`TextDecoder("utf-8", { fatal: true, ignoreBOM: true })`、`Number.prototype.toExponential(11)`。
  状态：**未核对官方文档**；本机一致性测试（现在 135 条请求）通过。更老的 Node 版本没试过。
- Python 服务：`http.server.ThreadingHTTPServer` + `BaseHTTPRequestHandler`（`do_GET` 等、`send_response / send_header / end_headers`），
  数字的写法用 `decimal.Context(prec=12, rounding=ROUND_HALF_UP)`，JSON 用 `json.loads(parse_int=float, parse_constant=…)`。
  状态：**未核对官方文档**；本机一致性测试通过。写了“需要 Python 3.8 或更新”是估计的，只在 3.12 上跑过。
  已知差别：`http.server` 不解分块传输（`Transfer-Encoding: chunked`）的请求内容——不带 `Content-Length` 的请求内容会被当成没有；Node 版能读。
- Go 服务（`runtime_go*.dart`）：`net/http` 的 `http.Server{Handler, ConnContext}`、`net.Listen`、`srv.SetKeepAlivesEnabled(false)`、`r.Host`；
  JSON 解析用 `encoding/json` 的 `Decoder.UseNumber()`；数字的写法用 `strconv.FormatFloat` 展开后手写进位；
  “请求别的网址”用 `http.Client{Timeout: 10 * time.Second}`。
  状态：**未核对官方文档**；本机 Go 1.25 上一致性测试（135 条请求）通过，`go vet` 没有意见。`go.mod` 里写的 `go 1.18` 是估计的最低版本
  （用了 `any`），**没有在更老的 Go 上试过**。没有实际验证的：真的等满 10 秒超时、https、跳转、Windows 上的 `./server` 写法。
- Java 服务（`runtime_java*.dart`）：`java.net.ServerSocket / Socket`（自己读 HTTP/1.1 请求）、`java.math.BigDecimal`（`MathContext(12, RoundingMode.HALF_UP)`）、
  `java.nio.charset.CharsetDecoder`（`CodingErrorAction.REPORT`）、`HttpURLConnection`（`setConnectTimeout / setReadTimeout` 各 10 秒、`setDoOutput`）、
  `Executors.newCachedThreadPool`。状态：**未核对官方文档**；本机 JDK 21 上一致性测试通过。README 写的“需要 JDK 11 或更新”是估计的
  （用了 `readNBytes`、`String.repeat` 之类），**只在 JDK 21 上跑过**。
  已知差别：只认 `Content-Length`，不解分块传输；“请求别的网址”的时限是连接、读各 10 秒；`HttpURLConnection` 默认会跟着跳转、
  对 `127.*` / `localhost` 不走系统代理（本机设了代理的情况下请求自己成功，算是验证了这一点）。
- PHP（`runtime_php*.dart`、`target_php.dart`）：**整份没有实际运行过**（本机没有 php，也不许联网查文档），下面每一条都是凭记忆写的，**全部未核对**：
  - 自带开发服务器 `php -S 地址:端口 路由脚本`：每个请求跑一遍路由脚本；`$_SERVER['REQUEST_METHOD']`、`$_SERVER['REQUEST_URI']`（假定是没解码的原样地址，含 `?` 后面的部分）、
    `$_SERVER['CONTENT_LENGTH']`、`file_get_contents('php://input')`、`getallheaders()`（假定开发服务器下可用，没有就退回 `$_SERVER['HTTP_*']`）。
    **没法确认**：它对 `/a/%zz`、开头 `//`、带扩展名的路径（`/a.css`）是不是原样交给路由脚本；重名请求头怎么合并；`HEAD` 怎么处理。
  - 响应：`http_response_code()`、`header()`、`header_remove('X-Powered-By')`、`ini_set('default_mimetype', '')`（为了 204 不带 Content-Type——**没法确认**这样够不够）。
  - 数字的写法：`sprintf('%.40e', …)`（假定给的是精确展开后正确舍入的 41 位、指数形如 `e+3` / `e-10`）、`sprintf('%.0F', …)`、`sprintf('%.16e', …)`（存文件用）；
    `(float) "1e3"` 文字转数字、`fmod()`（符号跟被除数）、`is_finite()`。
  - 文字：`preg_match('//u', $s) === 1` 判断合法 UTF-8、`strtr()` 做 JSON 转义、`strspn / strcspn`（带起点参数）、`rawurldecode()`、`preg_replace_callback()`、
    `sort($keys, SORT_STRING)`（按字节比＝按码点比）、数组键 `"12"` 会变成整数 12（读键时一律 `(string)` 转回）。
  - 数据文件：`fopen($f, 'c+')`、`flock($h, LOCK_EX / LOCK_UN)`、`stream_get_contents()`、`rewind()`、`ftruncate()`、`fwrite()`、`fflush()`。
  - “请求别的网址”：`file_get_contents($url, false, stream_context_create(['http' => ['method', 'header', 'content', 'timeout', 'ignore_errors']]))`，
    状态码从 `$http_response_header`（PHP 8.4 起 `http_get_last_response_headers()`）最后一行状态行里取。需要 `allow_url_fopen` 开着；`timeout` 假定是读超时（连接超时可能另算）。
  - “写到日志”：`fopen('php://stdout', 'w')`（假定开发服务器下写到它所在的终端），打不开退回 `error_log()`。
  - 语法：`final class`、`...$items` 不定参数、`??`、`catch (Throwable $e)`、`"\u{feff}"` 转义、顶层 `const X = __DIR__ . '…'`——据此估计“需要 PHP 7.4 或更新”，**没有验证**。
  - 已知和别的语言不一样：集合存文件（见设计文档）；用到集合的接口请求自己会等到超时（开发服务器默认单进程）；不打印“后端已启动”。
- 跨域：所有响应带 `Access-Control-Allow-Origin: *`；`OPTIONS` 回 204 并带 `Access-Control-Allow-Methods`、`Access-Control-Allow-Headers: *`。
  状态：**未核对**（没有用真浏览器试过跨域调用）。

# 2026-11-24 补充：DeepSeek 思考模式与工具调用（`lib/agent/chat_client.dart`、`lib/agent/agent_runner.dart`）

来源（都是 2026-11-24 抓的官方页面；页面上没有“最后更新”日期）：
- https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/
- https://api-docs.deepseek.com/zh-cn/api/create-chat-completion

| 事实 | 状态 |
| --- | --- |
| 现在的模型是 `deepseek-flash`、`deepseek-v4-pro`；**思考模式默认是开的** | 已核对 |
| 开关：`thinking: {"type": "enabled" \| "disabled"}`，优先级高于 `reasoning_effort` | 已核对 |
| `reasoning_effort`：`none / low / high / max`；`none` 等于关；默认 `high`；`minimal` 当 `low`，`medium`、`xhigh` 当 `high` | 已核对 |
| **带了 `tools` 参数的请求，之后所有请求都必须把 `reasoning_content` 完整带回——哪怕那一轮模型没有真的调用工具；没带回会返回 400。** 之后新的用户轮次也要继续带着之前各轮的 | 已核对（原文意思如此） |
| 没带 `tools` 的对话，带回的 `reasoning_content` 会被忽略 | 已核对 |
| assistant 消息要带回的字段：`content`、`reasoning_content`、`tool_calls`；工具调用那一轮 `content` 可以是空字符串 | 已核对 |
| 非流式返回里的位置：`choices[0].message.reasoning_content` | 已核对 |
| 流式返回里的字段名 `delta.reasoning_content` | **未核对**：官方正文没写到流式字段名，只有第三方镜像这么写。我们按这个名字读，读不到就当没有 |
| 400 报错的具体文字 | **未核对**（官方没给） |
| 思考模式下 `tool_choice` 传 `required` 或指定函数会 400；`none` / `auto` 可以 | 已核对（我们一直只发 `auto`） |
| 思考模式下 `temperature` 不起作用 | 已核对（我们不发） |
| 旧对话里没存过思考内容的 assistant 消息该怎么带 | **未核对**：官方没写。第三方说补空字符串能过，不是官方说法 |

我们现在的做法：
- 流里有 `delta.reasoning_content` 就累加起来，存在那条 assistant 消息的内部字段 `_reasoning` 上（跟着对话记录存盘；不显示在聊天里）。
- 发请求时，**接口地址是 `api.deepseek.com`，或模型名里带 `deepseek`（中转站）**：把 `_reasoning` 以 `reasoning_content` 的名字带回去。别的服务商一律不带（内部字段照旧去掉）。
- 只对官方地址多做两件事：思考档位选“关”时明说 `thinking: {"type": "disabled"}`（以前什么都不发，等于默认开着）；
  思考开着而某条旧 assistant 消息没存思考内容时，补 `reasoning_content: ""`（**未核对**的权宜做法：不补的话按文档一定 400）。
- **没有用真实接口验证过**（没有 Key，也不许花钱）。以前的写法（不读、不存、不带回）按官方文档在“思考默认开 + 带工具”的第二次请求就会 400。

# 2026-11-24 补充：模型接口临时出错的自动重试（`lib/agent/agent_runner.dart`、`lib/agent/loop_guard.dart`）

这是我们自己定的规矩，不是哪家接口的要求：
- 只在**一个字都还没回**的时候重试（已经开始回话就不重试，避免重复内容和重复扣费）。
- 值得重试的：连不上、等响应头超时，以及状态码 408、429、500、502、503、504、529。401、403、400、404 这些重试也没用，直接报错。
  （其余是通用的 HTTP 含义；529 凭印象是 Anthropic 的“过载”，**未核对**。各家有没有 `Retry-After` 头没查，我们也不读它——**未核对**。）
- 最多重试 2 次，间隔 1.5 秒、6 秒；等的时候点停止立刻生效。每次重试在聊天里出一行提示，写明真正的原因。

# 2026-11-24 补充（第二轮）：思考过程显示用到的字段

核对时间：2026-11-24 约 07:38 UTC。

| 来源 | 我们读 / 发的 | 依据 | 状态 |
| --- | --- | --- | --- |
| Anthropic | 流里 `content_block_delta`，`delta.type == "thinking_delta"`，文字在 `delta.thinking`；`signature_delta` 在这个块结束前到 | 官方流式文档 `platform.claude.com/docs/en/api/streaming` 原文 | 已核对 |
| Anthropic | `display: "omitted"` 时会来一个 `thinking` 为空串的 `thinking_delta`（我们遇到空串不显示）；`display: "summarized"` 给的是压缩过的摘要 | 同上 | 已核对 |
| OpenAI Responses | 返回对象里有 `reasoning: {effort, summary, …}`（说明 `summary` 这个字段存在） | 官方接口参考 `developers.openai.com/api/reference/resources/responses/methods/create` 的返回示例 | 已核对（只核对到字段存在） |
| OpenAI Responses | 请求里发 `reasoning.summary: "auto"` 来要一份可读的思考摘要 | 只在第三方资料里看到这个取值 | **未核对** |
| OpenAI Responses | 流事件 `response.reasoning_summary_text.delta`（摘要增量，文字在 `delta`）、`response.reasoning_summary_part.added`（摘要新起一段）、`response.reasoning_text.delta`（有的兼容接口直接给思考原文） | 只在第三方资料里看到 | **未核对** |
| OpenAI Responses | 没验证过的组织发 `reasoning.summary` 会被拒绝（400） | 第三方说法 | **未核对** |
| DeepSeek / 兼容接口 | 流里 `delta.reasoning_content` | 见上面「DeepSeek 思考模式与工具调用」 | **未核对**（官方正文没写流式字段名） |
| 其他兼容接口（OpenRouter 等） | 流里 `delta.reasoning`（没有 `reasoning_content` 时才读它） | 凭印象，没有打开任何文档 | **未核对** |

我们的做法：

- 三种来源都变成同一种“思考增量”，聊天页显示成一行“正在思考… / 思考了 N 秒”，点开看全文；存在 assistant 消息的内部字段
  `_reasoning`（想了多久存在 `_reasoningMs`）上，发给接口前去掉（DeepSeek 的带回规则不变）。
- Responses：只有模型设置里开了思考档位才发 `reasoning`，这时顺带发 `summary: "auto"`。**如果接口回 400 且报错里提到 summary**，
  去掉它重发一次，这个客户端之后都不再带（聊天里就没有思考可显示，其余照常）。这条退路是因为上面两条未核对。
- 事件名如果不对，后果只是“聊天里不显示思考”，不影响回答和工具调用。
- 自动压缩那一次请求：只发一条 system + 一条 user 的纯文字，不带 `tools`，三种协议都是最普通的请求形状；用量照常从各自的用量字段读。
- **都没有用真实接口验证过**（没有 Key，也不许花钱）。


## 语言工具的一键安装（`lib/runtime/runtime_sources.dart` 的 `runtimePacks`、`lib/runtime/pack_install.dart`）

2026-11-25 加（真机反馈第三轮第 3 条：后端“运行”时所选语言的工具没装就自动装）。核对方式：只读了下面这些网页的文字，
**没有下载任何安装包，也没有在 PRoot arm64 里真装过**（开发机是 x86 的 Linux，没有那个环境）。

生成的后端代码要什么版本（读 `lib/backend/target_*.dart` 和设计文档得来）：Node 20+、Python 3.8+、Go 1.18+、JDK 11+（要 javac）、
PHP 估计 7.4+（PHP 那份代码从没运行过）。下面选的版本都够。

| 项 | 装法 | 来源网址 | 核对日期 | 状态 |
| --- | --- | --- | --- | --- |
| Go | 官方包 `go1.26.11.linux-arm64.tar.gz`，61MB，sha256 `6c2f29b458b5add0835f18b776f69c8881a6d88428f1484a6da55755e620757e` | https://go.dev/dl/ | 2026-11-25 | 下载页上有这一行（文件名、大小、校验值）。**文件本身没下载过**；下载地址按 `https://go.dev/dl/<文件名>` 拼，未实测 |
| Go 的国内源 | 同一个文件，从 `https://golang.google.cn/dl/<文件名>` 下 | https://golang.google.cn/dl/ | 2026-11-25 | 页面列出的版本、文件、校验值和 go.dev 一致。**下载地址未实测** |
| Go 的阿里云镜像 | 没用 | https://mirrors.aliyun.com/golang/ | 2026-11-25 | 页面打不开（超时），**未核对**，所以没用它 |
| Go 用 apt 装（`golang-go`） | 没用 | packages.ubuntu.com 的 `golang-go`、`golang-1.22-go` 页 | 2026-11-25 | 页面打不开，**未核对**包体积，所以没选这条路 |
| Go 装好后占多少 | 界面写“约 240 MB” | — | 2026-11-25 | **估的**：开发机上 Go 1.25 amd64 解开是 236MB；arm64 的 1.26.11 没量过 |
| JDK | `apt install openjdk-21-jdk-headless` | https://packages.ubuntu.com/noble/openjdk-21-jdk-headless | 2026-11-25 | 包存在；arm64 包 79,697.7 kB、装好 94,118 kB（页面上是 21.0.3+9-1ubuntu1 这一版的数，现在源里的版本可能更新） |
| JDK 的依赖 | `openjdk-21-jre-headless` | https://packages.ubuntu.com/noble/openjdk-21-jre-headless | 2026-11-25 | arm64 包 44,765.0 kB、装好 198,195 kB。它自己的依赖（ca-certificates-java、java-common、libnss3 等）体积**未核对** |
| JDK 总下载量、占用 | 界面写“下载约 130 MB，装好后占约 300 MB” | 上面两页 | 2026-11-25 | **估的**：79.7 + 44.8 = 124.5MB，加依赖按 130 算；占用 94 + 198 = 292MB，按 300 算 |
| OpenJDK 17 | 没用 | packages.ubuntu.com 的 `openjdk-17-jdk-headless` 页 | 2026-11-25 | 页面打不开，**未核对**是否更小，所以用了核对得到的 21 |
| PHP | `apt install php-cli` | https://packages.ubuntu.com/noble/php-cli | 2026-11-25 | 包存在（2:8.3+93ubuntu2，4.5 kB，依赖 php8.3-cli） |
| PHP 的依赖 | `php8.3-cli` | https://packages.ubuntu.com/noble/php8.3-cli | 2026-11-25 | arm64 包 1,808.1 kB、装好 5,759 kB；再依赖 php8.3-common、php8.3-opcache、php8.3-readline。`php8.3-common` 的页面打不开，**总量未核对**，所以界面上 PHP 不写体积、也不弹确认 |
| Node.js、Python、Git | 沿用原来的装法，没有改 | 见 [linux-runtime.md](linux-runtime.md) | — | 这次没有重新核对；体积没有数据，界面上不写数字 |

自己定的：

- **要先问一次的门槛：下载量 100 MB**（`kPackConfirmBytes`）。现在只有 JDK 过线。没有体积数据的（Node.js、Python、Git、PHP）不问。
- Go 选官方包不选 apt：官方包的大小和校验值核对得到，apt 那条路核对不了；而且 Go 向后兼容，1.26 编得了 `go 1.18` 的工程。
- Go 的版本和校验值写死在代码里（不从下载源取校验值）。以后要升版本：改 `goVersion` 和 `goArchiveSha256`，两个都从 go.dev/dl 抄。

**未实测**（都要等真机）：

- 六项的安装脚本在 PRoot 里能不能跑完；`openjdk-21` 装完时 `ca-certificates-java` 的收尾脚本在 PRoot 里会不会出错；Go 的工具链在 PRoot 里能不能编译。
- 失败原因的分类（`classifyPackFailure`）认的是 apt、dpkg、curl、tar、sha256sum 报错的原话，是照这些工具的常见输出写的，**没有在真机上一条条触发过**；
  认不出来时归到“别的原因”，把退出码和最后三行输出原样给她。
- 取消安装是杀掉 PRoot 进程（带 `--kill-on-exit`）；apt 的子进程是不是都跟着停、被打断后 dpkg 的状态要不要收拾，没实测。
  脚本开头加了 `dpkg --configure -a`（失败不管）来收拾上次被打断的安装。

## 工具结果带图片（`view_image`；`lib/agent/tool_images.dart`）

核对日期：2026-11-25。三家的写法不一样，下面是各家官方文档怎么说、我们最后怎么做。

| 协议 | 官方怎么说 | 出处 | 状态 |
| --- | --- | --- | --- |
| OpenAI Chat Completions | `tool` 消息的 `content` 是字符串，或内容块数组；内容块“对 tool 消息只支持 `text` 类型”——也就是 **tool 消息里不能放图片** | developers.openai.com 的 API 参考（chat.completions › chat_completion_message_param 的 schema 页；搜索结果里的官方原文摘录，页面本身没能直接打开） | 已核对（间接：官方页的搜索摘录） |
| Anthropic Messages | `tool_result` 的 `content` 可以是字符串，或内容块列表；内容块可以是 `text`、`image`、`document`、`search_result`——**可以带图片** | platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls（直接打开官方页读到） | 已核对 |
| Anthropic Messages | 同一条 `user` 消息里 `tool_result` 块要排在最前面，文字、图片排在后面 | 较早的官方页面存档（见上面“Anthropic Messages”一节同一条） | 间接 |
| OpenAI Responses | `function_call_output` 的 `output` 通常是字符串；“返回图片或文件的函数，可以传一个图片或文件对象的数组来代替字符串” | OpenAI 官方 function calling 指南“Formatting results”一段（直接打开读到；这一句链到 API 参考 `responses/create` 里 `function_tool_call_output.output` 的定义） | 已核对（有这个能力）；数组里每一项的确切字段（第三方资料写的是 `input_text` / `input_image` / `input_file`）在 API 参考里没读到原文：**未核对** |

**我们的做法（三家都用同一种，最保守）**：工具结果只回文字（“已读取图片 路径（类型，大小）”），图片放在**紧跟在这一批工具结果后面的一条 `user` 消息**里，
走的是用户发图片附件的那条已有的路（内部是 `image_url` 的 data URL；Anthropic 转成 `{type:"image", source:{type:"base64"…}}`，Responses 转成 `input_image`）。

- 为什么不用各家自己的写法：Chat Completions 明文不许；Responses 的数组项字段没核对到原文；我们的历史统一存成 Chat Completions 的样子，三家用同一种写法最不容易出错。
- Anthropic 那边相邻的 `user` 消息会被我们合并成一条：结果是 `[tool_result…, text, image]`，`tool_result` 仍在最前面，符合上面的顺序要求。
- 代价（已知）：模型看到的图片名义上在一条 user 消息里，所以那条消息的文字开头写明“这不是用户说的话，是你刚才用 view_image 查看的图片”。
- 聊天记录里只存路径、类型、大小（`_images`），不存图片内容；每次请求现读文件。只带最近 3 次看图的图片（`kToolImagesKept`），更早的不再带。
- 没在任何一家的真实接口上发过带图的请求：**真实接口未验证**（测试用的是本地假服务器，只核对了我们发出去的请求体）。

## 各家的提示词缓存规则（压缩请求“同前缀”依据的就是这些；`lib/agent/context_relief.dart`、`lib/agent/auto_compact.dart`）

2026-11-25 核对。压缩对话的那一次请求现在和正常对话发的一模一样（同样的系统提示词、工具定义、历史消息顺序），只在末尾多一条“按栏目写摘要”的指令，
为的是让下面这些缓存能命中。**这一轮没有往请求里加任何缓存参数**（没有 `cache_control`、没有 `prompt_cache_key`），只保证前缀一致。

| 哪家 | 规则（只记和我们有关的） | 来源网址 | 核对日期 | 状态 |
| --- | --- | --- | --- | --- |
| DeepSeek | 磁盘缓存默认对所有人开着，不用改代码。命中的条件：请求的开头要和已经存下来的“缓存前缀单元”**完全一样**。单元在这些位置存：一次请求的边界（用户输入结束、模型输出结束）、检测到多次请求的公共前缀、长内容里每隔固定 token 数。文档的例子：先发 A+B，再发 A+B+C，第二次能命中 A+B。用量里 `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` 分别是命中 / 没命中的输入。缓存是“尽力而为”，不保证命中；建好要几秒，不用了几小时到几天后清掉 | https://api-docs.deepseek.com/guides/kv_cache/ | 2026-11-25 | 已核对 |
| OpenAI（Chat Completions / Responses） | 支持的模型自动缓存，不用加参数。要求整段渲染出来的前缀一致——**工具定义、系统 / 开发者消息、历史消息都算在前缀里**。有最小长度（文档写较新的模型是 1,024 token，早先的模型各不相同）。命中数在用量的 `cached_tokens` 里。`prompt_cache_key` 是可选参数，我们没用 | https://developers.openai.com/api/docs/guides/prompt-caching?site_locale=en | 2026-11-25 | 已核对 |
| OpenAI Responses 的 `instructions` | 文档写：较新的模型上，顶层的 `instructions` 会被接在 `input` 后面并且按没缓存计费。我们的 `OpenAiResponsesClient` 是用 `instructions` 发系统提示词的——这一轮**没有改**，只记下来 | 同上 | 2026-11-25 | 已核对文档；对我们实际命中率的影响**未实测** |
| Anthropic | **要显式加 `cache_control` 才缓存**（顶层自动式，或者在内容块上逐块标）。前缀的顺序是 tools → system → messages；默认存 5 分钟；回看最多 20 个块；改工具定义会让全部缓存失效，改 `tool_choice` 会让消息部分的缓存失效；最小可缓存长度随模型不同（512 或 1,024 token 起） | https://platform.claude.com/docs/en/build-with-claude/prompt-caching | 2026-11-25 | 已核对 |
| 别家的 OpenAI 兼容接口、中转站 | 有没有前缀缓存、规则是什么 | — | — | **未核对**（各家不一样；前缀一致对它们没有坏处） |

对我们意味着什么：

- DeepSeek、OpenAI：压缩请求的前缀和上一条正常请求逐字节一致（`test/context_compact_test.dart` 用假模型服务器守着：消息数组前 N 项、`tools`、system、其余参数），
  所以按文档这次请求的大部分输入应当按“缓存命中”计。**真实接口上命中了多少没有实测**（要真 Key、要花钱）。
- Anthropic：这一轮**没有加 `cache_control`**，所以在 Anthropic 上压缩请求（和正常请求一样）**不会被缓存**；我们只做到了“以后加上 `cache_control` 时前缀已经是一致的”。
  压缩请求特意不改 `tool_choice`、不去掉工具定义（去掉会让前缀变样）；模型要是在压缩请求里调了工具，由代码按失败处理、不执行。
- 上下文快满时“省略较早的工具结果”会改动前面的消息，前缀从第一处被改的地方断开。所以现在的顺序是：省略就够用时只省略（不发请求）；
  要压缩时用**没省略过**的原样历史发；原样的加上余量放不进上下文才退到省略过的，再放不下退到纯文字记录的老办法（那种没有前缀可言）。三种都只发一次请求。
- DeepSeek 思考模式的规矩不变：`reasoning_content` 照旧随 assistant 消息带回（压缩请求走的是同一个客户端、同一个 `withReasoningContent`）。
