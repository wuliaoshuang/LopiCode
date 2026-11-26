/// 规矩版本（设计 docs/blocks-v5-parts/B-type-system.md 5.1）：一份文档按哪一版的规矩检查和生成。
///
/// - **1**：老规矩。全是“任意”、全走小库、除以 0 得 0、文字自动变数字。旧文档没有这个字段，就是 1，行为一个字不变
///   （`test/rules_v1_frozen_test.dart` 钉着）。
/// - **2**：严格规矩。类型不对报错（T 开头的规则，typecheck.dart）、除以 0 报错、整数超范围报错、“等于”不再把 1 和 "1" 当一样。
///
/// 存盘：文档最外层的 [kLangRulesField]（一个整数）。是 1 就不写这个字段——旧文档存出来和以前一个字节都不差。
/// 1 → 2 是用户手动点的“升级到严格规矩”；不能自动降回去。
library;

const int kLangRulesLoose = 1;
const int kLangRulesStrict = 2;

/// 这个版本的应用认识的最高规矩版本。
const int kLangRulesLatest = kLangRulesStrict;

/// 存盘时的字段名。
const String kLangRulesField = 'rules';

/// **开关：新建的文档用哪个规矩版本。** 新建的入口（后端是 `backendStarterDocument`）都读它。
///
/// 现在是 1：严格规矩的生成路径（带类型的生成、运行时检查的小函数）还没接上，这时候把新文档标成 2，它实际还是按老规矩跑，
/// 等生成路径接上那天行为又会变——正好违反“版本号保证行为不变”。生成路径接上的那一段把它改成 [kLangRulesStrict]（就这一行）；
/// 改完以后哪几条现有断言要跟着改，见 docs/blocks-v5-parts/B-impl-notes.md 第 6 节。
const int kLangRulesForNewDocs = kLangRulesLoose;

/// **后端文档的严格生成接上了没有。** 现在没有：版本 2 的生成器（gen2_*.dart）还不认后端的宿主语句（返回响应、数据集合…），
/// 后端文档的代码还是版本 1 的生成器写的。它对严格规矩的文档会写出和严格规矩不符的代码（2026-11-26 用 Node 真跑过）：
/// 放在旧积木里的“把…变成整数 / …是空就用… / 一定不是空…”整格变成空（null）、照样回 200；放在新积木语句里的那个接口整段不生成、回 500；
/// 除以 0 还是得 0。所以是 false 的时候，严格规矩的后端文档**不生成、不启动**，并明说原因（backend_project.dart 的 `kBeStrictGenPending`）。
/// “库 1”把后端接上版本 2 生成的那个提交里改成 true。
const bool kLangStrictBackendGen = false;

/// **开关：后端积木页“⋯”菜单里出不出现“升级到严格规矩…”。** 默认关：等后端接上版本 2 生成（库 1）再打开——
/// 现在让用户升级，得到的是一份“按严格规矩查、但生成不了代码”的文档（见 [kLangStrictBackendGen]）。
/// 已经是严格规矩的文档（现在只可能来自测试或手改文件）照常标红、一键修、显示类型。
/// 界面读的是 backend_screen.dart 的 `beStrictUpgradeEntry`（测试里可以打开）。
const bool kStrictRulesUpgradeEnabled = false;

/// 从存盘的值读规矩版本：没有、不是整数、小于 1 → 1。比 [kLangRulesLatest] 大的原样留着（可能是新版本的应用写的）。
int langRulesFromJson(Object? raw) => raw is int && raw >= 1 ? raw : kLangRulesLoose;

/// 这份文档走不走严格规矩。
bool langRulesStrict(int rules) => rules >= kLangRulesStrict;
