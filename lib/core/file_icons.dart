// 文件 / 文件夹 / 语言 → 图标资源路径。图标来自 material-icon-theme（MIT），随安装包走，不联网取。
// 映射数据是 tool/gen_file_icons.py 从官方清单生成的（lib/core/file_icons_*_data.dart），这里只管查。
// 查法照 VS Code：先整名，再从最长的多段扩展名往短找（a.d.ts → d.ts → ts），都不区分大小写，找不到给默认图标。
import 'package:lopicode/core/file_icons_ext_data.dart';
import 'package:lopicode/core/file_icons_files_data.dart';
import 'package:lopicode/core/file_icons_folder_data.dart';
import 'package:lopicode/core/file_icons_name_data.dart';

const String kFileIconDir = 'assets/file_icons';

/// 默认图标（官方清单里的名字）。
const String kDefaultFileIcon = 'file';
const String kDefaultFolderIcon = 'folder';

/// 随包的图标文件名（不带 .svg）。
final Set<String> fileIconFiles = kFileIconFileList.split(' ').toSet();

Map<String, String> _reverse(Map<String, String> byIcon) => {
  for (final entry in byIcon.entries)
    for (final key in entry.value.split(' ')) key: entry.key,
};

final Map<String, String> _byExtension = _reverse(kFileIconExtensions);
final Map<String, String> _byName = _reverse(kFileIconNames);
final Map<String, String> _byLanguage = _reverse(kFileIconLanguages);

/// 文件夹：官方给每个名字配了五种写法（x .x _x -x __x__），数据里只存原名，这里展开；“=”开头的只按原样。
final Map<String, String> _byFolder = () {
  final out = <String, String>{};
  final exact = <String, String>{};
  for (final entry in kFolderIconNames.entries) {
    for (final key in entry.value.split(' ')) {
      if (key.startsWith('=')) {
        exact[key.substring(1)] = entry.key;
        continue;
      }
      for (final variant in [key, '.$key', '_$key', '-$key', '__${key}__']) {
        out[variant] = entry.key;
      }
    }
  }
  return out..addAll(exact);
}();

/// 模板列表、后端语言选择里常见的叫法 → 图标名。官方的语言 id 表里没有的才写在这里（这一小张是 LopiCode 自己定的）。
const Map<String, String> _languageAliases = {
  'node': 'nodejs',
  'node.js': 'nodejs',
  'js': 'javascript',
  'ts': 'typescript',
  'jsx': 'react',
  'tsx': 'react_ts',
  'reactjs': 'react',
  'vuejs': 'vue',
  'py': 'python',
  'golang': 'go',
  'c#': 'csharp',
  'cs': 'csharp',
  'dotnet': 'csharp',
  'c++': 'cpp',
  'rb': 'ruby',
  'rs': 'rust',
  'kt': 'kotlin',
  'objc': 'objective-c',
  'sh': 'console',
  'bash': 'console',
  'zsh': 'console',
  'shell': 'console',
  'yml': 'yaml',
  'md': 'markdown',
  'mysql': 'database',
  'postgresql': 'database',
  'sqlite': 'database',
  'flutter': 'dart',
};

String _asset(String icon, bool light) {
  // 官方的规矩：浅色主题下有 “名字_light” 就用它（原图标在浅色底上看不清的才有）。
  final name = light && fileIconFiles.contains('${icon}_light') ? '${icon}_light' : icon;
  return '$kFileIconDir/$name.svg';
}

/// 文件或文件夹的图标资源路径。[name] 可以带路径（只看最后一段）；[open] 只对文件夹有用；
/// [light] 表示界面是浅色主题。永远返回一个随包存在的文件。
String fileIconFor(String name, {bool isDir = false, bool open = false, bool light = false}) {
  var base = name.replaceAll('\\', '/');
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  base = base.substring(base.lastIndexOf('/') + 1).toLowerCase();
  if (isDir) {
    final icon = _byFolder[base] ?? kDefaultFolderIcon;
    return _asset(open ? '$icon-open' : icon, light);
  }
  final byName = _byName[base];
  if (byName != null) return _asset(byName, light);
  final parts = base.split('.');
  for (var i = 1; i < parts.length; i++) {
    final icon = _byExtension[parts.sublist(i).join('.')];
    if (icon != null) return _asset(icon, light);
  }
  return _asset(kDefaultFileIcon, light);
}

/// 语言 / 技术栈的图标资源路径：认 VS Code 的语言 id（javascript、python、csharp…）、
/// 常见叫法（node、react、vue、golang、c#…）、图标名本身（kotlin、nodejs、docker…），最后当扩展名再找一次。
/// 认不出给默认文件图标。
String languageIconFor(String id, {bool light = false}) {
  final key = id.trim().toLowerCase();
  final icon = _languageAliases[key] ?? _byLanguage[key] ?? (fileIconFiles.contains(key) && !key.startsWith('folder') ? key : null) ?? _byExtension[key];
  return _asset(icon ?? kDefaultFileIcon, light);
}

/// 给测试核对用：映射表里提到的全部图标名（文件夹的含 -open）。
Set<String> get fileIconsReferenced => {
  ..._byExtension.values,
  ..._byName.values,
  ..._byLanguage.values,
  ..._languageAliases.values,
  for (final icon in _byFolder.values) ...[icon, '$icon-open'],
  kDefaultFileIcon,
  kDefaultFolderIcon,
  '$kDefaultFolderIcon-open',
};
