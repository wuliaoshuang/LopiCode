# 模型渠道服务商预设调研

- 核对日期：2026-11-23（所有“已核对”都是当天用 browser_open 打开官方域名页面读到正文）
- 范围：只查资料，没改代码、没花钱、没注册账号、没实际调用任何接口（所以“能不能真连上”一概未实测）
- 不含模型名单（按要求不列）

## 0. 我们代码里 baseUrl 怎么拼（先看这个）

读自 `lib/agent/protocols.dart`、`lib/agent/model_config.dart`、`lib/agent/chat_client.dart`：

1. `_trimBase`：去首尾空白 → 去掉末尾 `/` → 如果用户把完整地址贴进来，会再剥掉已知后缀 `/chat/completions`、`/responses`、`/messages`、`/models`。
2. `_endpoint(base, path)` 就是字符串直接相接 `'$base$path'`，**不会自动补 `/v1`**。
3. 各协议实际请求：

| 协议 | 对话 | 列模型 / 测试连接 | 鉴权头 |
|---|---|---|---|
| openai | `POST {base}/chat/completions` | `GET {base}/models` | `Authorization: Bearer` |
| responses | `POST {base}/responses` | `GET {base}/models` | `Authorization: Bearer` |
| anthropic | `POST {base}/messages` | `GET {base}/models?limit=1000` | `x-api-key` + `anthropic-version` |

4. 结论：**base URL = 官方完整地址里 `/chat/completions` 之前的全部**；末尾带不带 `/` 都行。
5. **注意 anthropic**：代码是 `{base}/messages`，不是任务描述里说的 `{base}/v1/messages`。所以 anthropic 协议的 base **必须自己带 `/v1`**（如 `https://api.anthropic.com/v1`）。各家文档给的“Anthropic 兼容 base”（如 `…/anthropic`）是给官方 SDK 用的（SDK 会自己补 `/v1/messages`），填进我们应用要写成 `…/anthropic/v1`。这个 `/v1` 是按规则推出来的，只有 Moonshot 一家在官方文档里看到了完整路径 `/anthropic/v1/messages`，其余都标了“推导，未核对”。
6. 列模型接口期望返回 JSON 里有 `data` 数组（或顶层数组），元素带字符串 `id`。

## 1. 总表

状态说明：
- **已核对** = 当天打开了官方域名文档页，正文里看到了这个地址
- **官方摘录** = 只在官方域名页面的搜索摘录里看到，页面本身没打开成功/没打开
- **未核对** = 只在第三方文章看到，或官方页打开了但正文里看不到地址

| 服务商 | 推荐协议 | 可直接填的 base URL | 地址状态 | GET /models | 备注 |
|---|---|---|---|---|---|
| DeepSeek | openai | `https://api.deepseek.com` | 已核对 | 官方摘录（有） | 另有 Anthropic 兼容 |
| OpenAI | openai / responses | `https://api.openai.com/v1` | 已核对 | 已核对（有） | |
| Anthropic | anthropic | `https://api.anthropic.com/v1` | 已核对 | 已核对（有） | 官方示例的请求头与我们代码不同，见 2.3 |
| Google Gemini | openai | `https://generativelanguage.googleapis.com/v1beta/openai` | 已核对 | 已核对（有） | |
| 智谱 BigModel | openai | `https://open.bigmodel.cn/api/paas/v4` | 已核对 | 未确认 | 国际站 Z.ai 地址未核对 |
| 阿里云百炼 | openai | `https://dashscope.aliyuncs.com/compatible-mode/v1`（北京） | 已核对 | 未确认 | 分地域，Key 不通用 |
| Moonshot / Kimi | openai | `https://api.moonshot.cn/v1` | 已核对 | 已核对（有） | 国际站 `.ai` 仅官方摘录 |
| 火山方舟 | openai | `https://ark.cn-beijing.volces.com/api/v3` | 已核对 | 未确认 | model 填 Model ID 或接入点 |
| 硅基流动 | openai | `https://api.siliconflow.cn/v1` | 已核对 | 文档提到“获取列表”，接口本身未确认 | 国际站地址不同、未查到 |
| OpenRouter | openai | `https://openrouter.ai/api/v1` | 已核对 | 已核对（有） | |
| MiniMax | openai | `https://api.minimax.cn/v1` | 已核对（但与第三方说法不一致，见 2.11） | 未确认 | **域名有分歧，建议上线前实测** |
| xAI | openai（官方主推 responses） | `https://api.x.ai/v1` | 已核对 | 未确认 | 官方称 Chat Completions 为 legacy |
| Groq | openai | `https://api.groq.com/openai/v1` | 已核对 | 未确认 | |
| 腾讯混元 | openai | 新：`https://tokenhub.tencentmaas.com/v1`；旧：`https://api.hunyuan.cloud.tencent.com/v1` | 新地址已核对；旧地址官方摘录 | 未确认 | 官方说功能在迁往 TokenHub |
| 百度千帆 v2 | openai | `https://qianfan.baidubce.com/v2` | 已核对 | 未确认 | |
| Ollama（本机） | openai | `http://localhost:11434/v1` | 已核对 | 已核对（有） | 手机上 localhost 是手机自己，见 2.16 |
| 阶跃星辰 StepFun | openai | `https://api.stepfun.com/v1` | 已核对 | 已核对（列为兼容接口） | 顺手查的 |
| Cerebras | openai | `https://api.cerebras.ai/v1` | 已核对 | 文档说通过了“model listing”兼容测试 | 顺手查的 |
| 讯飞星火 | openai | `https://spark-api-open.xf-yun.com/v1` | **未核对**（官方页打开了但地址在代码块里没显示） | 未确认 | 鉴权用 APIPassword |
| Mistral | openai | `https://api.mistral.ai/v1` | **未核对**（仅第三方） | 未核对 | |
| Together AI | openai | `https://api.together.ai/v1`（也见过 `api.together.xyz/v1`） | **未核对**（仅第三方） | 未核对 | |
| Fireworks | openai | `https://api.fireworks.ai/inference/v1` | **未核对**（仅第三方，且另一处第三方写的是 `api.fireworks.ai/v1`） | 未核对 | |
| Perplexity | openai | `https://api.perplexity.ai` | **未核对**（见 2.23） | 未核对 | |
| 零一万物 | — | — | **未查** | — | |
| 百川 | — | — | **未查** | — | |

## 2. 逐家说明

### 2.1 DeepSeek
- 协议：openai（也提供 Anthropic 兼容）
- base：`https://api.deepseek.com`
- 来源（已打开）：https://api-docs.deepseek.com/
- 文档内容转述：表格写 base_url (OpenAI) 为 `https://api.deepseek.com`，base_url (Anthropic) 为 `https://api.deepseek.com/anthropic`；curl 示例请求 `https://api.deepseek.com/chat/completions`。
- /models：`GET https://api.deepseek.com/models` 只在官方域名搜索摘录里看到；页面 https://api-docs.deepseek.com/api/list-models 我打开时参数传错失败了，按规定没有重试 → 官方摘录。摘录里还说 `https://api.deepseek.com/v1` 仍兼容。
- Key：文档链接指向 platform.deepseek.com（具体页面地址正文没给）。
- anthropic 协议若要用：按我们的拼接规则应填 `https://api.deepseek.com/anthropic/v1`（**推导，未核对**）。

### 2.2 OpenAI
- 协议：openai 或 responses
- base：`https://api.openai.com/v1`
- 来源（已打开）：https://developers.openai.com/api/reference/resources/models/methods/list
- 转述：示例 `curl https://api.openai.com/v1/models`，Bearer 鉴权。
- /models：有（就是上面这页）。
- Responses：`POST https://api.openai.com/v1/responses` 只在官方域名搜索摘录里看到（官方摘录）。
- Key 页面：没在打开的页面里看到，未记录。

### 2.3 Anthropic
- 协议：anthropic
- base：`https://api.anthropic.com/v1`
- 来源（已打开）：https://platform.claude.com/docs/en/api/http/models/retrieve
- 转述：示例为 `curl https://api.anthropic.com/v1/models/$MODEL_ID`，带 `anthropic-version: 2026-10-21` 和 `Authorization: Bearer $ANTHROPIC_API_KEY`。
- /models：有（`/v1/models`；列表页本身没单独打开）。
- **需要你留意**：这页官方示例用的是 `Authorization: Bearer` 加 `anthropic-version: 2026-10-21`，而我们代码发的是 `x-api-key` 加自己的版本常量。`x-api-key` + `2023-06-01` 的写法我今天只在第三方/镜像摘录里看到。我没实测，不知道旧写法是否仍被接受——建议用真 Key 测一次。
- Key 页面：platform.claude.com/settings/keys 仅第三方提到（未核对）。

### 2.4 Google Gemini（OpenAI 兼容端点）
- 协议：openai
- base：`https://generativelanguage.googleapis.com/v1beta/openai`
- 来源（已打开）：https://aistudio.google.com/docs/openai?hl=pt
- 转述：`base_url="https://generativelanguage.googleapis.com/v1beta/openai/"`，Bearer 鉴权；同页有 `curl https://generativelanguage.googleapis.com/v1beta/openai/models`。
- /models：有。
- Key：https://aistudio.google.com/apikey

### 2.5 智谱 BigModel
- 协议：openai
- base：`https://open.bigmodel.cn/api/paas/v4`
- 来源（已打开）：https://docs.bigmodel.cn/cn/guide/develop/openai/introduction
- 转述：`base_url="https://open.bigmodel.cn/api/paas/v4/"`。
- /models：打开的页面里没提，未确认。
- Key：文档说在 bigmodel.cn 的“API Keys”管理页面创建（正文没给具体网址）。
- 备注：国际站 Z.ai 的 `https://api.z.ai/api/paas/v4` 只在第三方看到（未核对官方文档）。

### 2.6 阿里云百炼 DashScope
- 协议：openai
- base：北京 `https://dashscope.aliyuncs.com/compatible-mode/v1`；新加坡 `https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`
- 来源（已打开）：https://help.aliyun.com/zh/model-studio/model-calling-in-sub-workspace
- 转述：按地域给出兼容模式地址，并说明不同地域的 Key 不能混用。
- /models：未确认。
- 备注（未核对官方文档）：美国 `https://dashscope-us.aliyuncs.com/compatible-mode/v1`、德国 `https://{WorkspaceId}.eu-central-1.maas.aliyuncs.com/compatible-mode/v1` 只在 developer.aliyun.com 社区文章摘录里看到；`dashscope-intl` 只在第三方看到。
- 预设建议：新加坡地址含 `{WorkspaceId}` 占位，不能做成一键预设，只能当提示。

### 2.7 Moonshot / Kimi
- 协议：openai（也支持 responses、anthropic）
- base：`https://api.moonshot.cn/v1`（responses 同一个 base）
- 来源（已打开）：https://platform.kimi.com/docs/api/overview （页面标注更新于 2026-11-20）
- 转述：协议表与端点列表，列出 `/v1/models`（GET）与 `/anthropic/v1/messages`。
- /models：有。
- anthropic：文档给的 base 是 `https://api.moonshot.cn/anthropic`；按我们的规则填 `https://api.moonshot.cn/anthropic/v1`（完整路径 `/anthropic/v1/messages` 在官方页看到了，这条算已核对）。
- Key：Kimi 开放平台控制台（正文没给具体网址）。
- 备注：国际站 `https://api.moonshot.ai/v1`（platform.kimi.ai）只在 kimi.com 帮助页的搜索摘录里看到（官方摘录，页面 https://www.kimi.com/help/kimi-api/api-troubleshooting 没打开）；两边账号和 Key 不通用。

### 2.8 火山方舟（豆包）
- 协议：openai（官方也有 responses、Anthropic 兼容）
- base：`https://ark.cn-beijing.volces.com/api/v3`
- 来源（已打开）：https://ark.volcengine.com/region:cn-beijing/docs/compatible-with-openai-sdk （更新于 2026-11-19）
- /models：未确认。
- 备注：model 字段填 Model ID 或“接入点”ID。Anthropic 兼容 base `https://ark.cn-beijing.volces.com/api/compatible` 和“推荐 Responses API”只在官方域名搜索摘录里看到（官方摘录）；其中 …/docs/ai-tools-other-tools 我打开时参数传错失败、没有重试，…/ai-tools-codex、…/ai-tools-hermes-agent 没打开。

### 2.9 硅基流动 SiliconFlow
- 协议：openai
- base：`https://api.siliconflow.cn/v1`
- 来源（已打开）：https://docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-yan
- 转述：“Base URL 会自动填为 https://api.siliconflow.cn/v1”，并提到“获取列表”。
- /models：从“获取列表”推断有，但这页没写接口本身 → 未确认。（https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation 打开时参数传错失败、没有重试。）
- Key：cloud.siliconflow.cn 的“API 密钥”。
- 备注：文档说国际站 siliconflow.com 用另一个 base，但没给地址。

### 2.10 OpenRouter
- 协议：openai
- base：`https://openrouter.ai/api/v1`
- 来源（已打开）：https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties
- 转述：`GET https://openrouter.ai/api/v1/models`，Bearer。
- /models：有。
- Key 页面：openrouter.ai/settings/keys 仅第三方提到（未核对）。兼容性说明页 https://openrouter.ai/docs/guides/features/compatibility 打开时参数传错失败、没有重试。

### 2.11 MiniMax（有分歧，请留意）
- 协议：openai（官方文档更推荐 Anthropic SDK）
- base：`https://api.minimax.cn/v1`
- 来源（已打开）：https://platform.minimaxi.com/docs/api-reference/text-openai-api （代码块没显示）→ 它的“配置环境变量”链接落在 https://platform.minimax.cn/docs/guides/quickstart-preparation#env-vars ，正文写 `OPENAI_BASE_URL=https://api.minimax.cn/v1`、`ANTHROPIC_BASE_URL=https://api.minimax.cn/anthropic`。
- **分歧**：多篇第三方文章写的是国内 `https://api.minimaxi.com/v1`、国际 `https://api.minimax.io/v1`（未核对官方文档）。今天官方页显示的是 `api.minimax.cn`。两者哪个现在可用我没实测，建议做预设前用真 Key 试一下。
- anthropic：按规则填 `https://api.minimax.cn/anthropic/v1`（推导，未核对）。
- /models：未确认。

### 2.12 xAI
- 协议：openai 能用；官方主推 responses
- base：`https://api.x.ai/v1`
- 来源（已打开）：https://docs.x.ai/developers/model-capabilities/legacy/chat-completions.md
- 转述：页首警告 Chat Completions 是 legacy 端点、新功能先上 Responses；示例 `base_url="https://api.x.ai/v1"`，`curl https://api.x.ai/v1/chat/completions`，Bearer。
- 另外打开过 https://docs.x.ai/docs/ 和 https://docs.x.ai/docs/api-reference （都以 Responses 为主，但正文里没显示地址）。
- /models：官方页没看到，未确认（第三方说有）。
- Key：https://console.x.ai/team/default/api-keys （上面那页里的链接）。

### 2.13 Groq
- 协议：openai
- base：`https://api.groq.com/openai/v1`
- 来源（已打开）：https://console.groq.com/docs/openai
- 转述：把 base_url 改成 `https://api.groq.com/openai/v1`。
- /models：打开的页面没写，未确认。
- 备注：Responses 同一个 base 的说法来自官方域名搜索摘录 https://console.groq.com/docs/responses-api （没打开）。Key 页面是 console.groq.com 上的链接，网址正文没显示。

### 2.14 腾讯混元
- 协议：openai
- base（新，TokenHub）：`https://tokenhub.tencentmaas.com/v1`
  - 来源（已打开）：https://cloud.tencent.com/document/product/1823/132252 （更新于 2026-11-16）
  - 转述：示例 `curl -X POST 'https://tokenhub.tencentmaas.com/v1/chat/completions'`，`base_url="https://tokenhub.tencentmaas.com/v1"`，Bearer；Key 在 TokenHub 控制台（console.cloud.tencent.com）创建；并称部分模型兼容 Chat Completions、Responses、Anthropic Messages 三种协议（后两种的路径这页没写）。
- base（旧，混元原平台）：`https://api.hunyuan.cloud.tencent.com/v1`
  - 状态：**官方摘录**。官方文档页 https://cloud.tencent.com/document/product/1729/111007 打开失败（抓取报错，没重试），内容只从搜索摘录读到：base_url 为上述地址，完整路径 `…/v1/chat/completions`；并有公告说混元功能将逐步迁到 TokenHub，原平台不再新增模型、停止新购，已购的可继续用。
- /models：两边都未确认。
- 预设建议：两个地址的 Key 不是一回事（一个是混元 API Key，一个是 TokenHub Key），如果只放一个，新用户应放 TokenHub。

### 2.15 百度千帆（v2）
- 协议：openai
- base：`https://qianfan.baidubce.com/v2`
- 来源（已打开）：https://cloud.baidu.com/doc/qianfan/s/Hmh4suq26 （更新于 2026-11-07）
- 转述：“需要配置的 base_url 如下：`https://qianfan.baidubce.com/v2`”。
- /models：未确认。
- Key：文档写“登录百度千帆-系统管理-创建 API Key”（链接指向 console.bce.baidu.com）；可选用自定义 header 传 appid。

### 2.16 Ollama（本机）
- 协议：openai（也支持 responses）
- base：`http://localhost:11434/v1`
- 来源（已打开）：
  - https://ollama.com/blog/openai-compatibility ：`base_url = 'http://localhost:11434/v1'`，api_key 必填但不使用；`curl http://localhost:11434/v1/chat/completions`。（这是 2024 年的官方博客）
  - https://docs.ollama.com/api/openai-compatibility （更新于 2026-11-12）：端点列表含 `/v1/chat/completions`、`/v1/models`、`/v1/models/{model}`、`POST /v1/responses`（只支持无状态）；本机服务“客户端要求有 Key 值，但 Ollama 会忽略”。
- /models：有。
- 备注：
  - 我们应用如果 Key 为空就不让保存，预设里要允许空 Key 或自动填个占位值。
  - LopiCode 跑在手机上，`localhost` 指手机自己。要连电脑上的 Ollama 得填电脑的局域网 IP（这是常识提醒，不是文档内容）。
  - 文档还提到“直连云端”（用 `OLLAMA_API_KEY`），但云端 base 地址在页面代码块里没显示；`https://ollama.com/v1` 只在第三方看到（未核对）。Anthropic 兼容也只在第三方看到。

### 2.17 阶跃星辰 StepFun（顺手）
- 协议：openai
- base：`https://api.stepfun.com/v1`
- 来源（已打开）：https://platform.stepfun.com/docs/zh/guides/developer/openai （更新于 2026-11-05）
- 转述：“新增 base_url 设置为 `https://api.stepfun.com/v1`”；兼容的接口清单里有“获取模型列表”“查询单个模型信息”。
- /models：有（列在兼容清单里）。
- 备注（官方摘录）：订阅制 Step Plan 用另一个 base `https://api.stepfun.com/step_plan/v1`，同时有 Anthropic 路径 `…/step_plan/v1/messages`（那页没打开）。

### 2.18 Cerebras（顺手）
- 协议：openai
- base：`https://api.cerebras.ai/v1`
- 来源（已打开）：https://inference-docs.cerebras.ai/resources/openai （更新于 2026-11-17）
- 转述：给第三方工具的配置表里 Base URL 为 `https://api.cerebras.ai/v1`，并说多数工具会自动补 `/chat/completions`；称 OpenAI SDK 通过了 model listing、Chat Completions 等兼容测试。
- /models：按上面那句应当有，但没看到接口页 → 基本可信、未逐字确认。

### 2.19 讯飞星火（未核对）
- 试过：打开了官方文档 https://www.xfyun.cn/doc/spark/HTTP%E8%B0%83%E7%94%A8%E6%96%87%E6%A1%A3.html ，页面写“兼容 openAI SDK”，但请求地址在代码块里、抓到的正文没显示。
- 第三方说法：base `https://spark-api-open.xf-yun.com/v1`，Bearer 后面放控制台里的 **APIPassword**（不同模型版本的 APIPassword 不同——这句是官方页正文里有的）。
- /models：未确认。

### 2.20 Mistral（未核对）
- 试过：搜了一次，结果全是第三方文章，没拿到官方文档页网址，所以没打开。
- 第三方说法：`https://api.mistral.ai/v1`，有 `GET /v1/models`，Key 在 console.mistral.ai。

### 2.21 Together AI（未核对）
- 没专门搜；之前搜别家时第三方提到 `https://api.together.ai/v1`，也见过 `https://api.together.xyz/v1`。

### 2.22 Fireworks（未核对）
- 没专门搜；第三方提到 `https://api.fireworks.ai/inference/v1`，另一处第三方清单写的是 `https://api.fireworks.ai/v1`，两者不一致。

### 2.23 Perplexity（未核对）
- 试过：搜了一次。摘录来自 private-preview.docs.perplexity.ai（像是官方的预览文档站，不是正式文档站，页面没打开）：把 base_url 设为 `https://api.perplexity.ai`。
- 第三方对路径说法不一（有的写 `/chat/completions`，有的写 `/v1/chat/completions`），所以填哪个能用不确定。

### 2.24 零一万物、百川（未查）
- 这两家没来得及搜，什么都没核对。

## 3. 我打开失败、没有重试的页面

以下是我自己传错参数或抓取报错导致失败的，按规定都没有重试：

- https://api-docs.deepseek.com/api/list-models
- https://ark.volcengine.com/region:cn-beijing/docs/ai-tools-other-tools
- https://docs.siliconflow.cn/docs/userguide/capabilities/text-generation
- https://openrouter.ai/docs/guides/features/compatibility
- https://cloud.tencent.com/document/product/1729/111007

## 4. 做预设前建议先定/先测的事

1. anthropic 协议 base 要带 `/v1`（见第 0 节）；任务描述与代码不一致，以代码为准写的本文。
2. Anthropic 官方示例的请求头变了（2.3），需要真 Key 实测。
3. MiniMax 域名分歧（2.11），需要实测。
4. 腾讯混元放哪个地址（2.14）。
5. Ollama 允许空 Key、以及手机上 localhost 的提示文案（2.16）。
6. 标“未确认 /models”的服务商，“获取模型”按钮可能失败，预设里最好允许手填模型名。
