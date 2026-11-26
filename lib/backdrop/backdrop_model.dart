// 背景图片的设置（全局外观设置，不属于某一套主题）。全部不可变；改就 copyWith 造一份新的交给 BackdropNotifier。
//
// 自定的数值（2026-11-26）都集中在这个文件开头，改这里就行。
import 'package:lopicode/backdrop/crop_math.dart';

/// 遮罩深浅：0–100（%），一步 5。默认 60：正文直接写在背景上时仍读得清（截图验过）。
const int kBackdropMaskDefault = 60;

/// 模糊：0–30（屏幕上的逻辑像素半径），一步 2。更大也只是更糊，而且预先算一张小图就够了，不费性能。
const int kBackdropBlurMax = 30;

/// 亮度：−100（全黑）到 +100（全白），0＝不动，一步 5。
const int kBackdropBrightnessRange = 100;

/// 表面（气泡、卡片、输入框）在有背景时的不透明度：40–100（%），一步 5。
/// 用户没动过滑杆时这一项是空的，用当前主题的“有背景图时卡片的不透明度”（metrics.surfaceOpacity）；
/// 动过以后滑杆说了算。[kBackdropSurfaceDefault] 只是不知道主题时的兜底值。
const int kBackdropSurfaceMin = 40;
const int kBackdropSurfaceDefault = 90;

/// 平铺时一格占屏幕宽度的百分之几：10–100，一步 5，默认 50。
const int kBackdropTileMin = 10;
const int kBackdropTileDefault = 50;

/// 适配方式。
enum BackdropFit {
  /// 铺满：按裁剪区域铺满屏幕（多出来的裁掉）。
  cover,

  /// 完整显示：整张图都露出来（不裁），四周空的地方是主题底色。
  contain,

  /// 平铺：把裁剪区域当一格，重复铺。
  tile,
}

/// 背景会铺到的地方。前两个是“范围”，后四个是“透出”（默认不透出，保证可读）。
enum BackdropArea { chat, pages, terminal, code, blocks, lowcode }

int _int(Object? v, int fallback, int min, int max) => v is num && v.isFinite ? v.round().clamp(min, max) : fallback;
bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

/// 一张背景图和它的样子（浅色、深色各一份）。
class BackdropLook {
  const BackdropLook({
    this.file,
    this.width = 0,
    this.height = 0,
    this.turns = 0,
    this.crop = CropRect.full,
    this.fit = BackdropFit.cover,
    this.tilePercent = kBackdropTileDefault,
    this.maskFollowsTheme = true,
    this.maskColor = 0xFF000000,
    this.maskOpacity = kBackdropMaskDefault,
    this.blur = 0,
    this.brightness = 0,
  });

  /// 图片文件名（只是名字，文件在应用私有的 appearance/background/ 下）。null＝还没选图。
  final String? file;

  /// 存下来的图片的像素宽高（没旋转时）。
  final int width;
  final int height;

  /// 顺时针转了几个 90°（0–3）。
  final int turns;

  /// 裁剪区域（相对旋转后的图片）。
  final CropRect crop;
  final BackdropFit fit;
  final int tilePercent;

  /// 遮罩颜色跟随主题底色；关掉就用 [maskColor]。
  final bool maskFollowsTheme;

  /// 自选的遮罩颜色（0xAARRGGBB，透明度位不用）。
  final int maskColor;
  final int maskOpacity;
  final int blur;
  final int brightness;

  bool get hasImage => file != null && width > 0 && height > 0;

  /// 旋转后的宽高。
  int get rotatedWidth => turns.isOdd ? height : width;
  int get rotatedHeight => turns.isOdd ? width : height;

  BackdropLook copyWith({CropRect? crop, int? turns, BackdropFit? fit, int? tilePercent, bool? maskFollowsTheme, int? maskColor, int? maskOpacity, int? blur, int? brightness}) => BackdropLook(
    file: file,
    width: width,
    height: height,
    turns: (turns ?? this.turns) % 4,
    crop: crop ?? this.crop,
    fit: fit ?? this.fit,
    tilePercent: (tilePercent ?? this.tilePercent).clamp(kBackdropTileMin, 100),
    maskFollowsTheme: maskFollowsTheme ?? this.maskFollowsTheme,
    maskColor: maskColor ?? this.maskColor,
    maskOpacity: (maskOpacity ?? this.maskOpacity).clamp(0, 100),
    blur: (blur ?? this.blur).clamp(0, kBackdropBlurMax),
    brightness: (brightness ?? this.brightness).clamp(-kBackdropBrightnessRange, kBackdropBrightnessRange),
  );

  /// 换一张图（效果参数保留，裁剪和旋转用新给的）。
  BackdropLook withImage({required String file, required int width, required int height, required CropRect crop, int turns = 0}) => BackdropLook(
    file: file,
    width: width,
    height: height,
    turns: turns % 4,
    crop: crop,
    fit: fit,
    tilePercent: tilePercent,
    maskFollowsTheme: maskFollowsTheme,
    maskColor: maskColor,
    maskOpacity: maskOpacity,
    blur: blur,
    brightness: brightness,
  );

  /// 去掉图（效果参数保留，下次选图还是这套）。
  BackdropLook withoutImage() =>
      BackdropLook(fit: fit, tilePercent: tilePercent, maskFollowsTheme: maskFollowsTheme, maskColor: maskColor, maskOpacity: maskOpacity, blur: blur, brightness: brightness);

  Map<String, dynamic> toJson() => {
    'file': ?file,
    'width': width,
    'height': height,
    'turns': turns,
    'crop': crop.toJson(),
    'fit': fit.name,
    'tilePercent': tilePercent,
    'maskFollowsTheme': maskFollowsTheme,
    'maskColor': maskColor,
    'maskOpacity': maskOpacity,
    'blur': blur,
    'brightness': brightness,
  };

  static BackdropLook fromJson(Object? j) {
    if (j is! Map) return const BackdropLook();
    final file = j['file'];
    // 文件名只认“纯名字”：带路径分隔符的（想指到外面去的）一律不要
    final safeFile = file is String && file.isNotEmpty && !file.contains('/') && !file.contains(r'\') && !file.startsWith('.') ? file : null;
    final fit = j['fit'];
    return BackdropLook(
      file: safeFile,
      width: safeFile == null ? 0 : _int(j['width'], 0, 0, 100000),
      height: safeFile == null ? 0 : _int(j['height'], 0, 0, 100000),
      turns: _int(j['turns'], 0, 0, 3),
      crop: CropRect.fromJson(j['crop']),
      fit: BackdropFit.values.where((f) => f.name == fit).firstOrNull ?? BackdropFit.cover,
      tilePercent: _int(j['tilePercent'], kBackdropTileDefault, kBackdropTileMin, 100),
      maskFollowsTheme: _bool(j['maskFollowsTheme'], true),
      maskColor: _int(j['maskColor'], 0xFF000000, 0, 0xFFFFFFFF),
      maskOpacity: _int(j['maskOpacity'], kBackdropMaskDefault, 0, 100),
      blur: _int(j['blur'], 0, 0, kBackdropBlurMax),
      brightness: _int(j['brightness'], 0, -kBackdropBrightnessRange, kBackdropBrightnessRange),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackdropLook &&
      other.file == file &&
      other.width == width &&
      other.height == height &&
      other.turns == turns &&
      other.crop == crop &&
      other.fit == fit &&
      other.tilePercent == tilePercent &&
      other.maskFollowsTheme == maskFollowsTheme &&
      other.maskColor == maskColor &&
      other.maskOpacity == maskOpacity &&
      other.blur == blur &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(file, width, height, turns, crop, fit, tilePercent, maskFollowsTheme, maskColor, maskOpacity, blur, brightness);
}

/// 背景设置的整张快照。
class BackdropSettings {
  const BackdropSettings({
    this.enabled = true,
    this.light = const BackdropLook(),
    this.dark = const BackdropLook(),
    this.darkSeparate = false,
    this.onChat = true,
    this.onPages = false,
    this.terminal = false,
    this.code = false,
    this.blocks = false,
    this.lowcode = false,
    int? surfaceOpacity,
    this.loaded = false,
  }) : surfaceOverride = surfaceOpacity;

  /// 总开关（有图也可以先关掉，不用删图）。
  final bool enabled;

  /// 浅色外观用的；[darkSeparate] 关着时深色也用它。
  final BackdropLook light;

  /// 深色外观单独的一份（[darkSeparate] 开着才用）。
  final BackdropLook dark;
  final bool darkSeparate;

  /// 范围：聊天页 / 其它主要页面（项目列表、文件、设置等）。
  final bool onChat;
  final bool onPages;

  /// 透出：这些区域默认自己有实底色，开了才半透明露出背景。
  final bool terminal;
  final bool code;
  final bool blocks;
  final bool lowcode;

  /// 用户用滑杆定的表面不透明度（40–100）。null＝没动过，跟随当前主题的数。
  final int? surfaceOverride;

  /// 不看主题时的值（没动过滑杆就是兜底的 [kBackdropSurfaceDefault]）。界面上要用 [surfaceAlpha]。
  int get surfaceOpacity => surfaceOverride ?? kBackdropSurfaceDefault;

  /// 表面有多不透明（0–1）：滑杆动过就用滑杆的；没动过用 [themeOpacity]（当前主题的数，0–1）。
  double surfaceAlpha(double themeOpacity) => surfaceOverride != null ? surfaceOverride! / 100 : themeOpacity.clamp(0.0, 1.0);

  /// 滑杆上该显示几（没动过时把主题的数凑到滑杆的档位上）。
  int surfaceShown(double themeOpacity) => surfaceOverride ?? ((themeOpacity * 100 / 5).round() * 5).clamp(kBackdropSurfaceMin, 100);

  /// 存盘文件读完了没有（没读完之前一律当“没有背景”，免得先闪一下默认值）。
  final bool loaded;

  /// 现在这个外观（浅 / 深）用哪一份。
  BackdropLook lookFor({required bool dark}) => dark && darkSeparate ? this.dark : light;

  bool _areaOn(BackdropArea a) => switch (a) {
    BackdropArea.chat => onChat,
    BackdropArea.pages => onPages,
    BackdropArea.terminal => terminal,
    BackdropArea.code => code,
    BackdropArea.blocks => blocks,
    BackdropArea.lowcode => lowcode,
  };

  /// [area] 上现在要不要画 / 透出背景。
  bool showsOn(BackdropArea area, {required bool dark}) => loaded && enabled && lookFor(dark: dark).hasImage && _areaOn(area);

  /// 还被引用着的图片文件名（清理旧文件时别删它们）。
  Set<String> get files => {?light.file, ?dark.file};

  BackdropSettings copyWith({
    bool? enabled,
    BackdropLook? light,
    BackdropLook? dark,
    bool? darkSeparate,
    bool? onChat,
    bool? onPages,
    bool? terminal,
    bool? code,
    bool? blocks,
    bool? lowcode,
    int? surfaceOpacity,
    bool surfaceFromTheme = false,
    bool? loaded,
  }) => BackdropSettings(
    enabled: enabled ?? this.enabled,
    light: light ?? this.light,
    dark: dark ?? this.dark,
    darkSeparate: darkSeparate ?? this.darkSeparate,
    onChat: onChat ?? this.onChat,
    onPages: onPages ?? this.onPages,
    terminal: terminal ?? this.terminal,
    code: code ?? this.code,
    blocks: blocks ?? this.blocks,
    lowcode: lowcode ?? this.lowcode,
    surfaceOpacity: surfaceFromTheme ? null : (surfaceOpacity ?? surfaceOverride)?.clamp(kBackdropSurfaceMin, 100),
    loaded: loaded ?? this.loaded,
  );

  BackdropSettings withArea(BackdropArea a, bool on) => switch (a) {
    BackdropArea.chat => copyWith(onChat: on),
    BackdropArea.pages => copyWith(onPages: on),
    BackdropArea.terminal => copyWith(terminal: on),
    BackdropArea.code => copyWith(code: on),
    BackdropArea.blocks => copyWith(blocks: on),
    BackdropArea.lowcode => copyWith(lowcode: on),
  };

  bool area(BackdropArea a) => _areaOn(a);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'enabled': enabled,
    'light': light.toJson(),
    'dark': dark.toJson(),
    'darkSeparate': darkSeparate,
    'onChat': onChat,
    'onPages': onPages,
    'terminal': terminal,
    'code': code,
    'blocks': blocks,
    'lowcode': lowcode,
    'surfaceOpacity': ?surfaceOverride,
  };

  /// 从存盘读；每个字段类型不对就用默认值，绝不抛错。读出来的一律算“已读完”。
  static BackdropSettings fromJson(Object? j) {
    if (j is! Map) return const BackdropSettings(loaded: true);
    return BackdropSettings(
      enabled: _bool(j['enabled'], true),
      light: BackdropLook.fromJson(j['light']),
      dark: BackdropLook.fromJson(j['dark']),
      darkSeparate: _bool(j['darkSeparate'], false),
      onChat: _bool(j['onChat'], true),
      onPages: _bool(j['onPages'], false),
      terminal: _bool(j['terminal'], false),
      code: _bool(j['code'], false),
      blocks: _bool(j['blocks'], false),
      lowcode: _bool(j['lowcode'], false),
      surfaceOpacity: j['surfaceOpacity'] is num ? _int(j['surfaceOpacity'], kBackdropSurfaceDefault, kBackdropSurfaceMin, 100) : null,
      loaded: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackdropSettings &&
      other.enabled == enabled &&
      other.light == light &&
      other.dark == dark &&
      other.darkSeparate == darkSeparate &&
      other.onChat == onChat &&
      other.onPages == onPages &&
      other.terminal == terminal &&
      other.code == code &&
      other.blocks == blocks &&
      other.lowcode == lowcode &&
      other.surfaceOverride == surfaceOverride &&
      other.loaded == loaded;

  @override
  int get hashCode => Object.hash(enabled, light, dark, darkSeparate, onChat, onPages, terminal, code, blocks, lowcode, surfaceOverride, loaded);
}
