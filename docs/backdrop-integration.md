# 背景图片：怎么接（给合并的人）

2026-11-26。背景图片是独立的全局外观设置（不属于某套主题），代码在 `lib/backdrop/`、`lib/state/backdrop_state.dart`、
`lib/ui/app_backdrop.dart` 和 `lib/ui/backdrop_*.dart`。聊天页已经接好；下面是其余要接的地方。

## 1. 外观页那一行

```dart
// 状态文字：未设置 / 已启用 / 已关闭
final status = ref.watch(backdropStatusProvider);            // lib/state/backdrop_state.dart
// 点了进设置页
Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackdropSettingsScreen()));  // lib/ui/backdrop_settings_screen.dart
```

## 2. 表面透明度、遮罩颜色的统一入口（`lib/ui/app_backdrop.dart`）

- `backdropSurfaceAlpha(settings)`：有背景时气泡 / 卡片 / 输入框有多不透明。现在读背景设置里的“表面不透明度”（40–100%，默认 90%）。
  主题那边有 `metrics.surfaceOpacity`（0.3–1，默认 0.88）。两个只能留一个说了算，合并时在这个函数里定：
  建议保留背景设置页的滑杆（用户改得到、实时看得到），主题的那个数只在“用户没动过滑杆”时当默认值。
- `backdropMaskBase(context)`：“遮罩颜色跟随主题”时用的颜色，现在是主题底色 `c.bg`。主题有 `ui.backdropScrim`，要换就改这一处
  （注意它带透明度，这里只要色相，深浅由背景设置的“遮罩”滑杆定）。
- 页面里的表面一律写 `BackdropScope.surface(context, 原来的颜色)`；没背景时原样返回。

## 3. 和主题导入导出对接（`lib/backdrop/backdrop_theme_bridge.dart`，Notifier 上各有一个方法）

```dart
// 导出：把现在的背景变成数据；data 为 null 时 error 是原因（人话），notes 是成功但要告诉用户的话
final r = await ref.read(backdropProvider.notifier).exportForTheme(dark: false);
final d = r.data;
final bg = d == null ? null : ThemeBackground(
  mime: d['mime']! as String, bytes: d['bytes']! as Uint8List,
  cropX: d['cropX']! as double, cropY: d['cropY']! as double, cropW: d['cropW']! as double, cropH: d['cropH']! as double,
  dim: d['dim']! as double, blur: d['blur']! as double);
themes.exportText(id, background: bg);

// 导入：ThemeOpResult.background 不为空时（要不要用先问用户）
final error = await ref.read(backdropProvider.notifier).applyThemeBackground({
  'mime': b.mime, 'bytes': b.bytes, 'cropX': b.cropX, 'cropY': b.cropY, 'cropW': b.cropW, 'cropH': b.cropH, 'dim': b.dim, 'blur': b.blur,
}, dark: theme.dark);   // 成功返回 null；dark: true 会放到深色那一份并打开“深色单独设置”
```

逐项对过主题分支（themes，HEAD 45d79ae）的 `ThemeBackground`、`encodeTheme` / `_decodeBackground`（`lib/appearance/theme_json.dart`）和 `docs/themes-design.md` 第四、六节：

| 主题那边 | 我们交出去 / 收进来 | 对上了吗 |
|---|---|---|
| `mime`：`image/jpeg` / `image/png` / `image/webp` | 同样三种；按文件头认，GIF 不给也不收；收进来时文件头和 `mime` 对不上就拒 | 对上 |
| `bytes`（文件里是 base64 的 `data`，编解码在主题那边） | `Uint8List` 原始字节 | 对上 |
| 图最多 8MB | 导出超了就缩小长边（2048 → 1600 → 1280 → 1024）重存成 PNG 再试，还放不下就不带图并说明；导入超了拒收 | 对上 |
| `cropX/Y/W/H`：占原图的比例，0–1 | 同；交出去之前收进 0–1。我们内部的裁剪是相对“转过以后的图”，所以**转过的图导出时把旋转直接画进图里**（重存成 PNG），那边不用知道转没转过 | 对上 |
| `dim` 0–1 | ＝遮罩深浅 ÷ 100；收进来超范围收回 | 对上 |
| `blur` 0–40 | 我们最多 30：交出去 0–30；收进来超过 30 的收到 30 | 上限不同（见下） |

差异（主题那边的格式装不下的；导出的 Map 里多带了这几项，`ThemeBackground` 现在没有对应字段，不带也能导入，只是这几项保持导入方原样）：

| 键 | 含义 | 不带的后果 |
|---|---|---|
| `fit` | `cover` / `contain` / `tile` | 保持导入方现在的适配方式 |
| `tile` | 平铺时一格占屏幕宽的百分之几 | 同上 |
| `maskColor` | 自选遮罩色（0xRRGGBB）；`null`＝跟随主题 | 保持导入方现在的 |
| `brightness` | −100…100 | 保持导入方现在的 |
| `turns` | 现在交出去一律是 0（旋转已经画进图里）；收进来带了就按它转 | 没有后果 |

- 模糊上限：主题 0–40，我们 0–30。别人导出的 31–40 到我们这里是 30。
- 表面不透明度：主题 `metrics.surfaceOpacity` 0.3–1、默认 0.88；我们 40–100%、默认 90%（见第 2 节，合并时定谁说了算）。
- 遮罩颜色：主题有 `ui.backdropScrim`（带透明度）；我们“跟随主题”时现在用主题底色（见第 2 节）。
- 主题文件只能带一张图：浅色、深色各一张时只能导出其中一份（`exportForTheme(dark:)` 选哪份由调用方定）。

建议在主题格式第 1 版的 `background` 里加上 `fit`、`tile`、`maskColor`、`brightness` 四个可选字段（那边的文档说不认识的字段会跳过，旧文件不受影响）。

## 4. 其余页面接背景（现在只有聊天页接了）

“范围 › 其它页面”和“透出背景”四个开关**现在点了没有效果**，接上下面这些才有。写法都一样：

```dart
// 页面：把 Scaffold 包起来；Scaffold 原来写死了底色的，on 时改成透明（PageBar 的 background 参数不用动）
AppBackdrop(area: BackdropArea.pages, builder: (context, on) => Scaffold(backgroundColor: on ? Colors.transparent : 原来的, …))
// 区域底色：对应的“透出”开关开着、而且这一页画着背景时才变透
BackdropScope.surface(context, c.codeBg, seeThrough: BackdropArea.terminal)
```

| 开关 | 文件 | 位置 |
|---|---|---|
| 其它页面 | `lib/ui/project_shell.dart` | `page(d, body)` 里的 `Scaffold`（文件、终端、预览三页） |
| 其它页面 | `lib/ui/project_list_screen.dart` | `final page = Scaffold(` |
| 其它页面 | `lib/ui/settings_widgets.dart` | `SettingsPage.build` 的 `Scaffold(backgroundColor: c.canvas …)`（所有设置页）；`SettingsGroup` 的卡片底色包 `BackdropScope.surface` |
| 其它页面 | `lib/ui/builder_hub_screen.dart`、`lib/ui/favorites_screen.dart`、`lib/build/build_screen.dart`、`lib/runtime/runtime_screen.dart` | 各自的 `Scaffold` |
| 终端 | `lib/ui/terminal_tab.dart` | `_theme()` 里 `background: c.codeBg` 和 `ColoredBox(color: c.codeBg` 两处 |
| 代码区 | `lib/ui/code_editor.dart`（`backgroundColor: c.codeBg`）、`lib/ui/code_view.dart`、聊天里的代码块 | 底色 |
| 积木画布 | `lib/blocks/block_canvas_view.dart` | 两处 `ColoredBox` |
| 低代码画布 | `lib/lowcode/canvas_view.dart` | `ColoredBox(color: c.surfaceMuted` |

注意：背景不透明的页面里面如果还有整块实底的容器（列表底、页签条），接上后要截图看一遍，哪块挡住了就给哪块包 `BackdropScope.surface`。
没接完之前，建议先把还没效果的开关藏起来（`lib/ui/backdrop_settings_groups.dart` 的 `BackdropScopeGroups`）。

## 5. 上限和自定的数

| 项 | 值 | 在哪 |
|---|---|---|
| 原图文件上限 | 20MB | `kBackdropMaxFileBytes` |
| 存下来的长边上限 | 2560 像素（超了缩小，Dart 这头缩的存成 PNG；安卓原生那头缩的存 JPG 质量 90，有透明存 PNG） | `kBackdropMaxSide` |
| 收的格式 | JPG / PNG / WebP；GIF 不收（安卓原生那头会把 GIF、HEIC 取第一帧转成静态图再交过来） | `backdrop_store.dart` |
| 遮罩 | 0–100%，一步 5，默认 60%；颜色默认跟随主题，另有 8 个固定色可选 | `backdrop_model.dart` |
| 模糊 | 0–30，一步 2，默认 0 | 同上 |
| 亮度 | −100…+100，一步 5，默认 0 | 同上 |
| 表面不透明度 | 40–100%，一步 5，默认 90% | 同上 |
| 平铺一格 | 屏幕宽的 10–100%，一步 5，默认 50% | 同上 |
| 裁剪最大放大 | 8 倍，滑杆一档 0.25 倍 | `crop_math.dart` |
| 解码缓存 | 最多 3 张原图、6 张模糊小图；解码时长边不超过屏幕物理像素的长边（不低于 1280） | `backdrop_images.dart` |
| 主题文件里带图的上限 | 8MB（主题那边定的） | `backdrop_theme_bridge.dart` |
