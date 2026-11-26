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
| （2026-11-25 更正上一行）`budget_tokens` 写法已核对：下限 1024、必须小于 `max_tokens`，只适用于 4.5 及更早的 Claude；4.6 起改用 `adaptive` 写法，4.7 及以后发 `budget_tokens` 会 400 | 见文末「2026-11-25 思考档位」 | 已核对 |
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

- 思考档位：`reasoning_effort`。2026-11-25 已重新核对，各家的取值和专属参数见文末「2026-11-25 思考档位」。只在模型标了“可思考”时才发思考参数。
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
- 2026-11-25：语音入口暂时隐藏（霜霜定）。开关是 `lib/ui/chat_composer.dart` 的 `kChatVoiceEnabled`（默认关，设置页没有入口）；关着时不创建语音识别、不申请麦克风权限。`speech_to_text` 依赖和 `RECORD_AUDIO` 声明这一轮没动，去不去掉等霜霜定。

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

# 2026-11-26 补充（真机反馈第五轮）：正文里的 `<think>` 标签

记录时间：2026-11-26（北京时间下午）。

- 很多中转站 / 本机模型（Ollama、vLLM、各种 OpenAI 兼容网关转出来的 DeepSeek-R1、QwQ 等）不走单独的思考字段，
  而是把思考写在回复正文最开头的 `<think>…</think>` 里。**这是模型输出的习惯写法，不是哪家接口的规定，没有官方文档可对——未核对**；
  `<thinking>…</thinking>` 这种写法同样凭经验认，**未核对**。
- 我们的做法（`lib/agent/think_tags.dart`，三种协议都过这一层）：
  - 只认**回复最开头**的标签（前面只许有空白），不分大小写；标签里的字改走“思考增量”，不进正文；收尾标签后面紧跟的空行去掉。
  - 正文中间出现的标签不动（模型可能正在讲这个标签）。
  - 一直没等到收尾标签：后面全部算思考，正文为空。
  - 流式时标签可能被切开：还分不清是不是标签的那一小截先按住，分清再放行，正文里不会闪半截标签。
  - 存盘：正文存剥离后的文字；思考存 `_reasoning`，另加 `_reasoningTag: true`。
  - **带回规则**：带 `_reasoningTag` 的思考不作为 `reasoning_content` 带回（接口从没单独给过它）；接口自己给的 `reasoning_content`
    照旧带回，DeepSeek 官方地址“开着思考时缺的补空串”也照旧（上面「DeepSeek 思考模式与工具调用」那一节没动）。
  - 旧存档里连标签一起存进正文的回复：显示时剥出来，存档不改（下次发给模型的还是原样带标签的正文）。
- 判错的后果：回复开头恰好是字面的 `<think>` 且模型并不是在思考——那一段会被显示成思考。按上面的“只认最开头”已经把这种情况压到很低。
- 这一轮**没有加**的思考字段：OpenRouter 的 `reasoning_details`（数组）等。没打开文档核对，所以没写代码——**未核对**。
  现在认的仍是：`delta.reasoning_content`、`delta.reasoning`（字符串）、Anthropic `thinking_delta`、
  Responses 的 `response.reasoning_summary_text.delta` / `response.reasoning_text.delta`，加上正文标签。
- 没有用真实接口验证过。


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

## MCP（Model Context Protocol）远程连接（`lib/agent/mcp/`）

2026-11-25 新增。只做“远程”的两种连接方式（Streamable HTTP、旧的 HTTP+SSE），只用工具这一块（`tools/list`、`tools/call`）。
来源全部是官方站 modelcontextprotocol.io，核对日期都是 **2026-11-25**。**没有连过任何真实的 MCP 服务器**，只用本机假服务器（`test/support/fake_mcp_server.dart`）测过；
假服务器是照下面核对到的条文写的，所以“我们对规范的理解错了”这类问题测试抓不到。

**先说一件和原计划不一样的事**：官方现在的最新版规范是 `2026-07-28`，它把连接改成了“无状态”——**没有** `initialize` 握手、**没有** `notifications/initialized`、
**没有** `Mcp-Session-Id`、**没有** `ping`、没有 GET 长连接、没有 `Last-Event-ID` 续传。这些只存在于老版本（`2025-11-25` 及更早）。
所以客户端做成“新老都认”：先按新版问，服务器不认再退到握手版，再不行退到最老的 HTTP+SSE（规范的向后兼容一节就是这么要求的）。

| 项 | 核对到的事实 | 来源网址 | 状态 |
| --- | --- | --- | --- |
| 新版 `2026-07-28` 总览 | 无状态；每个请求自带协议版本和客户端能力 | https://modelcontextprotocol.io/specification/2026-07-28 | 已核对（页面更新于 2026-11-24） |
| 新版的传输 | 只用 POST；`Accept: application/json, text/event-stream`；通知回 202；回答是一段 JSON 或一条 SSE 流；流里服务器只许发通知，不许发请求；不能续传 | https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http | 已核对（2026-11-18 版） |
| 新版的请求头 | `MCP-Protocol-Version`（要和正文 `_meta` 里的版本一致）、`Mcp-Method`、`Mcp-Name`（`tools/call` 时是工具名）；值里有非 ASCII 等字符时包成 `=?base64?…?=` | 同上 | 已核对 |
| 新版 `x-mcp-header` | 工具参数说明里标了 `x-mcp-header` 的，参数值要同时放进 `Mcp-Param-{名字}` 头；只许字符串 / 整数 / 布尔；标得不合规矩的工具要从清单里去掉 | 同上 | 已核对；已实现 |
| 新版的错误 | 头和正文对不上 → 400 + `-32020`；版本不支持 → 400；方法不认识 → 404 + `-32601` | 同上 | 已核对 |
| 向后兼容（怎么探测） | 新版请求得到 400 且正文不是新版的错误 → 改发 `initialize`；POST 得到 400 / 404 / 405 → 改用 GET 等 `endpoint` 事件（最老的 HTTP+SSE） | 同上 | 已核对；已实现 |
| 版本怎么分 | “新”＝`2026-07-28` 及以后；“老”＝`2025-11-25` 及以前；版本不支持的错误会列出服务器支持哪些 | https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning | 已核对。错误里那个清单的字段名（我们读 `data.supported`）**未核对** |
| 新版的消息格式 | id 是字符串或整数；结果里 `resultType` 是 `complete` 或 `input_required`（不写＝complete）；`_meta` 里必带 `io.modelcontextprotocol/protocolVersion`、`io.modelcontextprotocol/clientCapabilities`，可带 `io.modelcontextprotocol/clientInfo`；错误码 `-32020` `-32021` `-32022` 和标准的 `-32700`、`-32600`～`-32603` | https://modelcontextprotocol.io/specification/2026-07-28/basic/index | 已核对。`input_required` 结果的具体形状**未核对**（我们遇到就报“不支持”） |
| `server/discover` | 新版服务器必须有；返回 `supportedVersions`、`capabilities`、`_meta` 里的服务器名字和版本、`instructions` | https://modelcontextprotocol.io/specification/2026-07-28/server/discover | 已核对；新版下用它当“连接测试”和 ping |
| 工具 | `tools/list` 分页（`cursor` / `nextCursor`）；`tools/call` 参数 `name`、`arguments`；结果 `content`（一组内容块）、`structuredContent`、`isError`；工具名建议 1–128 个字符、只用字母数字和 `_-.` | https://modelcontextprotocol.io/specification/2026-07-28/server/tools | 已核对 |
| 握手版的传输（`2025-06-18`） | POST + 可选 GET；回答是 JSON 或 SSE；SSE 里在回答之前可以夹带服务器的通知和请求；`Mcp-Session-Id` 在握手的回答头里给，之后每个请求都带；带着会话号得到 404 → 重新握手；结束时客户端应发 DELETE（服务器可以回 405）；之后的请求带 `MCP-Protocol-Version` 头；`Last-Event-ID` 续传是可选的 | https://modelcontextprotocol.io/specification/2025-06-18/basic/transports | 已核对 |
| 握手流程（`2025-06-18`） | `initialize` → 回答 → 发 `notifications/initialized`；服务器回的版本客户端不支持就断开；请求应该有超时 | https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle | 已核对 |
| 握手版的字段 | `initialize` 参数 `protocolVersion`、`capabilities`、`clientInfo`；回答 `protocolVersion`、`capabilities`、`serverInfo{name, title?, version}`、`instructions?`；`ping` 方法名；`Tool{name, title?, description?, inputSchema, …}`；内容块 `text` / `image` / `audio` / `resource_link` / `resource` | https://modelcontextprotocol.io/specification/2025-06-18/schema | 已核对。`ping` 回答的形状**未核对**（我们只看有没有回答） |
| 最老的 HTTP+SSE（`2024-11-05`） | GET 开一条 SSE 流；服务器先发 `endpoint` 事件，内容是之后 POST 用的地址；服务器的消息是 `message` 事件 | https://modelcontextprotocol.io/specification/2024-11-05/basic/transports | 已核对传输这一页；这一版的握手页、工具页**未核对**（按 `2025-06-18` 的写法处理） |
| `2025-11-25` 这一版自己的页面 | — | — | **未核对**。握手时我们报 `2025-06-18`；服务器回 `2025-06-18` / `2025-03-26` / `2024-11-05` 之一才接受，回别的（包括 `2025-11-25`）会报“版本对不上” |
| SSE 的格式细节 | 事件用空行分开、多行 `data:` 用换行拼起来、`:` 开头是注释、三种换行都认 | WHATWG HTML 标准的 server-sent events 一节 | **未核对**（照通用知识实现，`test/mcp_client_test.dart` 的“SSE 解析”一组守着行为） |
| 会话号的字符范围 | — | — | **未核对**。自己定的：只接受看得见的 ASCII 字符、最长 512 |
| 鉴权 / OAuth 那几页 | — | — | **未核对**，也没做 |

这一轮**没做、也没向服务器声明**的：resources、prompts、sampling、elicitation、roots、logging（握手和每个请求里的客户端能力都是空的 `{}`）。
服务器在流里夹带的通知一律忽略；夹带的请求：`ping` 回空结果，其余回 `-32601`（不支持）。`Last-Event-ID` 断线续传没做：流断了就报“连接中断”，不自动重发（重发可能让工具执行两遍）。
本机 stdio 方式没做（手机上没有通用的本机进程环境）。OAuth 没做（只支持用户自己填请求头）。

自己定的数值（`McpTimeouts`、`mcp_http.dart`、`mcp_client.dart`、`mcp_tools.dart`）：

- 超时：建立连接 10 秒；等响应头 20 秒（握手、列工具、ping）；调用工具等响应头 120 秒；流里连续 60 秒没有新内容算断；收尾 5 秒。
  对话开头自动刷新工具清单时用短的：6 秒 / 8 秒 / 8 秒。（RikkaHub 是连接 20 秒、读 10 分钟，我们收得更紧。）
- 上限：一次回答或一个 SSE 事件最多 4 MB；工具清单最多翻 20 页、200 个工具；最多配 20 个服务器；请求头的值最长 4096 个字符；
  工具说明给模型最多 600 字；工具名最长 64；确认卡上的参数最多显示 6000 字；结果超过 8000 字走“超长结果另存”。
- 重定向：不自动跟。同一个主机（协议、主机、端口都一样）的 307 / 308 最多跟 2 次；302 / 303 不跟（会把 POST 变成 GET）；转去别的主机一律不跟——请求头里带着令牌。
- 地址：外网必须 https；http 只能是本机或局域网（用现成的 `isLocalBaseUrl`）；地址里不许带账号密码。

## 2026-11-25 思考档位：各家到底用什么参数（`lib/agent/thinking_support.dart`、`lib/agent/build_chat_client.dart`）

核对时间：2026-11-25 约 11:56–12:00 UTC。**已核对**＝当天整页打开官方文档读到；**已核对（摘录）**＝官方页面抓不到全文，读的是搜索结果里摘出来的官方原文；**间接**＝只见第三方资料；**未核对**＝没找到出处。
全部只在本地用假的 http 客户端测过请求体（`test/thinking_support_test.dart`），**没有调用过任何真实接口**。

规矩：模型没标“可思考”→ 一个思考参数都不发（DeepSeek 官方地址例外，见下）。

**未核对的服务商 / 模型 → 不显示思考等级，也不发任何思考参数（2026-11-25 20:40 霜霜定，替换掉原来的“通用做法”）。**

- 原来的做法是：核对不了的也可以就地标“可思考”，显示“默认 / 低 / 中 / 高”，选了就发通用的 `reasoning_effort`。现在取消：
  `reasoning_effort` 在这些接口上认不认、认哪些值，我们没有出处，所以不发。
- 界面：选模型的面板里“思考深度”那一段只剩标题和一句灰色说明（为什么不能调、请求里不带思考参数），没有就地开关、没有档位；
  模型列表里不写“可思考”。设置 › 渠道 › 模型设置里“可以思考”同样只有标题和这一句说明，没有开关和档位。两处用的是同一句话
  （`ThinkingCaps.note`），不会出现“设置里能开、面板里说不能调”。
- 请求：`buildChatClient` 里只要 `ThinkingCaps.verified` 为 false，就当没标记、没选档位——`reasoning_effort`、`thinking`、
  `enable_thinking`、`output_config`、`reasoning` 一个都不出现。
- 旧存盘：这些服务商的模型如果已经标了“可思考”、在 `ai.thinkingLevels` 里记了档位，照常读进来，标记和记的档位都**原样留着不改不删**，
  只是解析时档位一律落回 `off`、不发参数；哪天这家核对过了，原来记的档位直接生效。
- 怎么算“核对过”（`thinkingCaps`，按“协议 + 渠道地址 + 模型 ID”）：
  1. **地址是下表“已核对”的那几家官方地址**：按下表。其中百炼上不是 `qwen*` 的模型、Kimi 地址上不是 `kimi-k3* / kimi-k2.7-code* / kimi-k2.6*`
     的模型，官方文档没核对到 → 未核对（原来走通用做法，现在不发）。
  2. **地址是服务商预设里别的官方地址**（火山方舟、MiniMax、xAI、Groq、腾讯混元、百度千帆、阶跃星辰、Cerebras、Ollama）：未核对。
     这些地址上即使模型名叫 `deepseek-…`、`gpt-…` 也不发——参数得按这家自己的文档，不能按模型名猜。
  3. **本机 / 局域网地址**（`localhost`、`10.*`、`192.168.*` 等）：未核对。
  4. **其余自己填的地址（中转站）**：只能按模型 ID 认（`厂商/模型` 的写法看最后一段）。认得出是已核对那几家的模型，就按那家官方文档的写法发；
     认不出 → 未核对。认法：`deepseek-*` → DeepSeek；`glm-*` → 智谱；`kimi-k3* / kimi-k2.7-code* / kimi-k2.6*` → Kimi；`qwen*` → 千问；
     `gemini-*` → Gemini；`gpt-* / chatgpt-* / o<数字>*` → OpenAI。OpenAI Chat 协议下的 `claude-*` 不认（Anthropic 的 OpenAI 兼容写法没核对）。
     **注意：中转站会不会把这些参数原样转给上游，没有办法核对**；这里核对的只是“这个模型的官方接口认这个参数”。（按模型 ID 认中转站是自己定的，可改。）
     中转站上的 DeepSeek 模型和官方地址有一点不同：官方地址由客户端在没选档位时自动补 `thinking: {type: disabled}`（没标“可思考”也补）；
     中转站上只有标了“可思考”才发，关＝`thinking: {type: disabled}`，低 / 高 / 最高＝`thinking: {type: enabled}` 加 `reasoning_effort`
     （都是 DeepSeek 文档里的写法）。`reasoning_content` 回传规则没动（官方地址，或模型名里带 `deepseek` / `kimi`）。
  5. **Anthropic 协议**：不分官方地址还是中转站，模型 ID 认得出是哪一代 Claude 才算核对过；认不出的（原来按老写法发 `budget_tokens`）现在不发——
     新旧两种写法发错都会 400。
  6. **OpenAI Responses 协议**：OpenAI 官方地址算核对过；中转站上只有模型 ID 看着是 OpenAI 的才算；别的服务商官方地址、本机地址不算。
- 自动标“可思考”的规则（`knownThinkingModel`）没变，它标的都在“已核对”范围内（有测试守着）。

| 服务商（怎么认出来） | 官方怎么写 | 来源 | 状态 | 我们发什么（界面上的档位） |
|---|---|---|---|---|
| DeepSeek（地址 `api.deepseek.com`） | 开关 `thinking: {type: enabled / disabled}`，默认开；`reasoning_effort: low / high / max`，默认 high；`medium`、`xhigh` 会被当成 `high`，`minimal` 当 `low`。带 tools 的对话必须把 `reasoning_content` 带回，否则 400 | https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/ | 已核对 | 关＝`thinking: {type: disabled}`；低 / 高 / 最高＝`reasoning_effort: low / high / max`（不再给“中”，它和“高”是同一档）。没标“可思考”也照旧发 disabled（不然默认开着白花钱） |
| OpenAI Chat Completions（地址 `api.openai.com`） | `reasoning_effort`：`none / minimal / low / medium / high / xhigh / max`，默认 medium；“Not all reasoning models support every value” | https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create | 已核对（摘录）。哪些模型 ID 是推理模型、不支持的模型传了会怎样：**未核对** | 默认＝不发；低 / 中 / 高＝`reasoning_effort`。`none / minimal / xhigh / max` 因为按模型不同、没核对到清单，不给。不自动标“可思考” |
| OpenAI Responses | `reasoning.effort` 同上七个值；`reasoning.summary: concise / detailed / auto` | developers.openai.com 的 Responses 参数说明 | 已核对（摘录）。没验证过的组织发 `summary` 会不会 400：**未核对**（保留原来“400 就去掉 summary 重发”的退路） | 默认＝不发；低 / 中 / 高＝`reasoning: {effort, summary: "auto"}` |
| Anthropic Messages（协议选 Anthropic，按模型 ID 认版本） | 老写法 `thinking: {type: "enabled", budget_tokens}`：下限 1024、必须小于 `max_tokens`；4.6 上已弃用，**4.7 及以后直接 400**。新写法 `thinking: {type: "adaptive"}` 加 `output_config: {effort: low / medium / high / xhigh / max}`；4.5 及更早发 adaptive 会 400。Fable / Mythos 5.x、Opus 5.5、Sonnet 5.5 一直开着（`disabled` 会 400）；Opus 5、Sonnet 5、Haiku 5.5 默认开、可以 `disabled`；Opus 4.8 / 4.7 / 4.6、Sonnet 4.6 默认关。`display: "summarized"` 才有思考文字（5 代和 4.7 / 4.8 默认不给）。多轮要把 thinking 块原样带回 | https://platform.claude.com/docs/en/build-with-claude/extended-thinking 、同目录的 effort 、thinking-troubleshooting 、thinking 页 | 已核对。旧模型 ID 的写法（`claude-opus-4-8`、`claude-sonnet-4-5-日期`）：**间接** | 认不出版本的：未核对，不显示、不发（2026-11-25 20:40 改，原来按老写法发）。4.5 及更早：老写法，预算低 4096 / 中 16384 / 高 32768（自己定的），压到 `[1024, max_tokens-1024]`，`max_tokens ≤ 2048` 时不发。4.6 起：`thinking: {type: adaptive, display: summarized}` 加 `output_config: {effort}`。“关”：默认关的不发；Opus 5 / Sonnet 5 / Haiku 5.5 发 `{type: disabled}`；一直开着的和没见过的更新版本显示成“默认”，只发 `thinking: {type: adaptive, display: summarized}`、并把历史里的 thinking 块带回。`xhigh / max` 按模型不同，不给 |
| Gemini 的 OpenAI 兼容接口（地址 `generativelanguage.googleapis.com`） | `reasoning_effort: minimal / low / medium / high`；不传用模型默认；`"none"` 只有 2.5 系列（非 Pro）能关，2.5 Pro、3、4 关不掉 | https://aistudio.google.com/docs/openai | 已核对 | `gemini-2.5*` 且名字里没有 `pro`：关＝`reasoning_effort: "none"`；其余“默认”＝不发。低 / 中 / 高照发 |
| 阿里云百炼（地址 `dashscope.aliyuncs.com`） | 千问的混合思考模型用 `enable_thinking: true / false`；“控制参数因模型而异” | https://help.aliyun.com/zh/model-studio/deep-thinking | 已核对（摘录）。哪些模型 ID 支持没逐个核对 | 模型 ID 以 `qwen` 开头：关 / 开＝`enable_thinking: false / true`，不发 `reasoning_effort`。其它模型：未核对，不显示、不发。不自动标“可思考” |
| 智谱（地址 `open.bigmodel.cn`） | `thinking.type: enabled / disabled`，默认 enabled；GLM-5.3 系列传 disabled 报错、`reasoning_effort` 只收 `max / high / low`；GLM-5.2 收的值多但 low、medium 都当 high；支持思考的有 5.3、5.2、5.1、5、4.7、4.6、4.5 各系列 | https://docs.bigmodel.cn/cn/guide/capabilities/thinking | 已核对（摘录） | `glm-5.3*`：默认＝不发；低 / 高 / 最高＝`reasoning_effort`。`glm-5.2*`：关＝`thinking: {type: disabled}`；高 / 最高＝`thinking: {type: enabled}` 加 `reasoning_effort: high / max`。其余：关 / 开＝`thinking: {type: disabled / enabled}` |
| Kimi（地址 `api.moonshot.cn` / `api.moonshot.ai`） | `kimi-k3*`：一直思考、不认 `thinking`，`reasoning_effort: low / high / max`，默认 max；`kimi-k2.7-code`：一直思考、不能调；`kimi-k2.6`：默认开，`thinking: {type: "disabled"}` 可关。多轮和工具调用必须把 assistant 消息连同 `reasoning_content` 原样带回 | https://platform.kimi.com/docs/guide/use-thinking-models | 已核对（摘录） | `kimi-k3*`：默认＝不发；低 / 高 / 最高＝`reasoning_effort`。`kimi-k2.7-code*`：什么都不发，界面写明调不了。`kimi-k2.6*`：关＝`thinking: {type: disabled}`，开＝不发。其它 ID：未核对，不显示、不发。官方地址或模型名带 `kimi` 时带回 `reasoning_content`（和 DeepSeek 用同一段代码） |
| 硅基流动（地址 `api.siliconflow.cn`） | `enable_thinking: boolean`（“适用于大多数推理模型”）；`reasoning_effort` 只适用于个别列出的模型 | https://docs.siliconflow.cn/docs/api/chat-completions-post | 已核对（摘录）。不支持的模型传了会怎样：**未核对** | 关 / 开＝`enable_thinking: false / true`，不发 `reasoning_effort`。不自动标“可思考” |
| OpenRouter（地址 `openrouter.ai`） | 认顶层 `reasoning_effort`，也有统一的 `reasoning: {effort, …}`；`GET /api/v1/models` 里能思考的模型带 `reasoning` 对象 | https://openrouter.ai/docs/guides/best-practices/reasoning-tokens | 已核对（摘录） | 默认＝不发；低 / 中 / 高＝`reasoning_effort`。“获取模型”时带 `reasoning` 对象的自动标“可思考” |
| 火山方舟、MiniMax、xAI、Groq、腾讯混元、百度千帆、阶跃星辰、Cerebras、Ollama、本机 / 局域网地址、自己填的中转站上认不出的模型 | — | — | **未核对** | 不显示思考等级，不发任何思考参数（含 `reasoning_effort`），不自动标 |

添加模型时自动标“可思考”的规则（`knownThinkingModel`，只标上表核对到的）：DeepSeek 官方地址的 `deepseek-*`；Anthropic 协议下认得出版本的 Opus 4 / 4.1 / 4.5、Sonnet 4 / 4.5、Haiku 4.5、4.6 及以后、Fable、Mythos；Gemini 官方地址的 `gemini-2.5 / 3 / 4`；智谱地址的 `glm-4.5 / 4.6 / 4.7 / 5*`；Kimi 地址的 `kimi-k3*`、`kimi-k2.7-code*`、`kimi-k2.6*`；OpenRouter 模型列表里带 `reasoning` 对象的。其余一律不自动标；思考参数核对过的服务商 / 模型，用户可以在选模型的面板里自己打开，没核对过的打不开。

每个模型上次设的档位存在设置键 `ai.thinkingLevels`（`{"渠道 id/模型 id": 档位}`）；档位值有 `off / on / low / medium / high / max`。旧存盘里某个模型现在不支持的档位，按“先往高找最近的一档”落（例如 DeepSeek 的 `medium` → `high`，和官方的映射一致）。

## 2026-11-26 应用内安装 APK（`android/…/ApkInstallChannel.kt`、`ApkFileProvider.kt`、`lib/build/apk_installer.dart`）

核对日期 2026-11-26（当天下午又对着 developer.android.com 补核了一遍，升级了几行的状态）。能打开原文的写“已核对”，只看到搜索摘录的写“摘录”，没查到的写“未核对”。

| 事实 | 来源 | 状态 | 我们怎么用 |
|---|---|---|---|
| Android 8（API 26）起没有全局的“未知来源”开关，改成按应用给“安装未知应用”；targetSdk ≥ 26 的应用要让用户装别的应用，清单里必须声明 `REQUEST_INSTALL_PACKAGES`，没声明的装不了 | Android Developers Blog《Making it safer to get apps on Android O》 https://android-developers.googleblog.com/2017/08/making-it-safer-to-get-apps-on-android-o.html?hl=bn | 摘录 | 清单加这一项（霜霜 2026-11-26 同意，只这一项） |
| 可以用 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` 把用户带到这个应用的“安装未知应用”设置页；可以用 `PackageManager.canRequestPackageInstalls()` 查现在让不让 | 同上 | 摘录 | 交给安装器之前先查；不让就回“还没允许”，界面给“去设置里允许” |
| `canRequestPackageInstalls()`：返回 false 时安装请求会被系统安装器拦下并弹框带用户去设置；应用必须 target O 以上并声明 `REQUEST_INSTALL_PACKAGES` 才能用这个方法 | developer.android.com 的 PackageManager 参考页 https://developer.android.com/reference/kotlin/android/content/pm/PackageManager?authuser=2 （搜索摘录里是官方原文；和微软转载 https://learn.microsoft.com/en-us/dotnet/api/android.content.pm.packagemanager.canrequestpackageinstalls?view=net-android-35.0 一字不差） | 摘录（官方页） | 只在 API ≥ 26 时调用；更低版本当作“允许” |
| `Intent.ACTION_INSTALL_PACKAGE` 在 API 29 弃用（“use PackageInstaller instead”） | developer.android.com 的 Intent 参考页常量表 https://developer.android.com/reference/android/content/Intent.html?authuser=6 | 摘录（官方页） | **不用它**。用没被弃用的 `ACTION_VIEW` + 类型 `application/vnd.android.package-archive` |
| `ACTION_VIEW` + APK 的 MIME 类型能拉起系统安装器 | 没找到 developer.android.com 上的明文说明；是多年通行做法 | **未核对** | 自己选的。真机没验证；拉不起来会回“没有找到系统安装器” |
| `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 带 `package:<包名>` 可以直达本应用那一页（原文：“Input: Optionally, the Intent's data URI can specify the application package name to directly invoke the management GUI specific to the package name. For example "package:com.my.app". Output: Nothing.”） | developer.android.com 的 Settings 参考页 https://developer.android.com/reference/kotlin/android/provider/Settings?authuser=166 | 摘录（官方页） | 先带包名试，系统不认（`ActivityNotFoundException`）就退成不带包名的总列表。“Output: Nothing”＝设置页不回结果，所以回到应用时自己再问一次 `canRequestPackageInstalls()` |
| `FileProvider`：给文件生成 `content://` 地址；只能给事先在 `<paths>` 里登记过的目录；`<files-path>`＝`Context.getFilesDir()`，`<cache-path>`＝`getCacheDir()`，`<external-files-path>`＝`Context.getExternalFilesDir(null)` | https://developer.android.com/reference/androidx/core/content/FileProvider?authuser=002 | 已核对（打开了原文） | `res/xml/apk_install_paths.xml` 只登记三处，见下 |
| `FileProvider` 必须 `exported=false`、`grantUriPermissions=true`，路径表用 meta-data `android.support.FILE_PROVIDER_PATHS` 指过去；登记目录时会把路径规范化（`getCanonicalFile`） | `exported=false`、`grantUriPermissions=true`、meta-data 名字：FileProvider 参考页“Defining a FileProvider”“Specifying Available Files”两节（同上网址）；规范化：直接看开发机上 androidx.core 1.18.0 的 `FileProvider` 类（`addRoot` 里的 `getCanonicalFile` 调用），文档没提 | 前三项已核对（原文）；规范化只对过实现 | 清单照这个写；`../app_flutter/projects/` 这种写法靠的就是规范化 |
| 给安装器读文件要在 Intent 上加 `FLAG_GRANT_READ_URI_PERMISSION` | FileProvider 参考页的“Granting Temporary Permissions to a URI › Include the Permission in an Intent”一节（同上网址）：把 content 地址 `setData()` 进 Intent，再加 `FLAG_GRANT_READ_URI_PERMISSION`；这样给的权限在接收方那个界面栈还在时有效，栈结束自动收回 | 已核对（打开了原文） | 加了 |
| 官方建议自己继承 `FileProvider` 而不是直接登记它（原文：直接用“is not reliable and will causes crashes on some devices”） | 同上，“Defining a FileProvider”一节 | 已核对（打开了原文） | 用的是自己的子类 `ApkFileProvider` |
| 系统安装器装完会不会告诉发起的应用 | — | — | `ACTION_VIEW` 不带回结果。所以界面只说“已经交给系统安装器”，不说“装好了” |

**登记给 FileProvider 的目录**（authorities 是 `${applicationId}.apkinstall`，跟着包名走）：

1. `<external-files-path path="apk/">`：`Android/data/<包名>/files/apk/`，本地打包抄出来的那一份和远程打包下载的 APK 都在这。
2. `<files-path path="../app_flutter/projects/">`：应用文档目录下的 `projects/`（应用目录里的工作区）。应用文档目录是 path_provider 的
   `getApplicationDocumentsDirectory()`，在安卓上是 `<数据目录>/app_flutter`，不在 `files/` 下面，而 FileProvider 没有直接指它的写法，所以从 `files/` 退一层。
   这是靠实现细节（规范化），真机没验证；所以原生那头做了兜底：`getUriForFile` 说“不在登记的目录里”时，改走第 3 条。
3. `<cache-path path="apk_install/">`：上面两处都不包含的文件（Ubuntu 环境里的工作区在 `files/runtime/rootfs/…`，故意没登记，免得把整个 Linux 根目录都列进去），
   先抄一份到缓存目录的 `apk_install/` 再交出去。每次安装前清空这个目录，只留当次的一份；缓存目录系统空间紧张时会自己清。

自己定的数值：问系统一句话的超时 10 秒；交给安装器的超时 2 分钟（可能要先抄一份大文件）。

## 消息里的 Markdown / HTML 渲染（2026-11-26）

**`markdown` 包**（Dart 官方，pub.dev，BSD-3-Clause，纯 Dart）：版本 7.3.1。只用它的解析器（`Document.parse` / `parseInline` 拿语法树），不用它的 HTML 输出。
下面几条是 2026-11-26 直接读包的源码（`~/.pub-cache` 里的 7.3.1）核对的：

| 事实 | 来源 | 状态 | 我们怎么用 |
|---|---|---|---|
| `Document(withDefaultBlockSyntaxes: false, blockSyntaxes: […])` 可以只挑要的块语法；默认那一组里有“下一行 === 变标题”（`SetextHeaderSyntax`）、“缩进 4 格是代码”（`CodeBlockSyntax`）、原始 HTML 块（`HtmlBlockSyntax`） | 包源码 `lib/src/block_parser.dart`、`document.dart` | 已核对（读源码） | 这三样不要，其余照 GitHub 那一组（表格、任务列表、围栏） |
| 自己加的行内语法排在内置的前面先试 | `lib/src/inline_parser.dart` 构造函数 | 已核对（读源码） | 整个 HTML 标签先被我们的规则吃掉，标签属性里的网址、星号不会被当成 Markdown |
| 表格单元格的对齐写在 `th` / `td` 的 `align` 属性里；任务项是 `li` 里一个 `input`（`checked` 属性）；有序列表起始号在 `ol` 的 `start` | `block_syntaxes/table_syntax.dart`、`list_syntax.dart` | 已核对（读源码＋测试） | 转成我们自己的节点 |
| 很长的一串不断开的字母数字（10 万字）会让行内解析慢到跑不完 | 自己测出来的（`test/md_parse_test.dart` 第一次跑卡死） | 实测 | 一块里有超过 2000 个连着的字母数字就不交给它，按纯文字显示；消息里的 `data:image/…;base64,…` 先换成短记号再解析 |

**网页视图（HTML 预览）**：

| 事实 | 来源 | 状态 | 我们怎么用 |
|---|---|---|---|
| `WebSettings.setAllowFileAccess`：开关 WebView 里读 `file://`；targetSdk ≥ 30 默认关、≤ 29 默认开，官方建议明确设成 false | developer.android.com 的 WebSettings 参考页 https://developer.android.com/reference/kotlin/android/webkit/WebSettings （2026-11-26 看的搜索摘录） | 摘录 | 预览视图里明确关掉 |
| `WebSettings.setAllowContentAccess`：开关 WebView 里读 `content://`（内容提供者），**默认开** | 同上 | 摘录 | 预览视图里关掉 |
| 这两个开关在 Flutter 这边只有安卓那一层有：`AndroidWebViewController.setAllowFileAccess` / `setAllowContentAccess`；另有 `setGeolocationEnabled`、`setMediaPlaybackRequiresUserGesture`、`setOnShowFileSelector`、`setOnPlatformPermissionRequest` | `webview_flutter_android` 4.14.1 源码 `lib/src/android_webview_controller.dart` | 已核对（读源码） | 所以 pubspec 里点名了 `webview_flutter_android`（原本就由 `webview_flutter` 带进来，版本没变） |
| `WebViewController.loadHtmlString(html)` 在安卓上是 `loadDataWithBaseUrl(null, html, 'text/html', …)` | 同上源码 | 已核对（读源码） | 不传基准地址，页面不属于应用的任何地址 |
| 不传基准地址时页面地址是 `about:blank`、没有自己的存储 | — | **未核对**（没翻到官方原文；真机也没验证） | 跳转拦截里只放行 `about:blank`。即使实际不是这个地址，也只是更严（都拦） |
| `<meta http-equiv="Content-Security-Policy">` 可以给一份文档加内容安全策略；`default-src` 是其余取资源指令的后备；`'none'` 表示完全不许；多条策略只会越加越严，后加的放不宽先前的 | MDN https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy （2026-11-26 看的搜索摘录） | 摘录 | 我们的那条放在文档最前面；页面自己再写也放不宽 |
| meta 写法的策略从解析到这个标签起生效；`sandbox`、`frame-ancestors`、`report-uri` 在 meta 里无效 | 非官方文章摘录（jsonmind.com 的 CSP 指南），MDN 原文没逐字核对 | **未核对** | 所以放在最前面；不依赖 `sandbox` |
| 系统 WebView 是否完整执行这条策略（拦外部图片 / 脚本 / fetch） | — | **没在真机验证** | 测试里只能证明“交给视图的文档开头带着这条策略” |

自己定的数值见各文件开头：解析上限 20 万字、缓存 200 万字、代码块 30 行折叠、流式不上色 2 万字、单词串 2000、图片（网络 5MB / 15 秒 / 3 次跳转、本机 20MB、data: 2MB、内存缓存 24MB、最高 320）、表格一格最宽 240、预览高 120–360、同时 2 个预览、HTML 嵌套 12 层、解析嵌套 6 层。
