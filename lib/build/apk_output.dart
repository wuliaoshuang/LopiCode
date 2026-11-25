// 打好的安装包另外放一份到“用户找得到”的位置。纯逻辑。
//
// 为什么要另放一份：工作区在应用自己的私有目录里（应用文档目录/projects/…），系统的文件管理器进不去，
// 只放在工作区 build/ 下她在系统里找不到、也就点不开安装。所以打完再抄一份到应用的外部目录
// （`Android/data/<包名>/files/apk/<工作区>/`，和远程打包下载 APK 用的是同一个位置，不需要任何权限）。
// 不是安卓（桌面调试、测试）时没有这个目录，就只有工作区里那一份。
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 测试用：换掉“外部目录在哪”。返回 null ＝ 没有。
Future<String?> Function()? externalFilesDirOverride;

Future<String?> _externalBase() async {
  final override = externalFilesDirOverride;
  if (override != null) return override();
  return Platform.isAndroid ? (await getExternalStorageDirectory())?.path : null;
}

/// 远程打包下载的 APK 放这里：有外部目录用外部目录，没有就放应用文档目录。
Future<Directory> apkDownloadDir(String projectId) async => Directory(p.join(await _externalBase() ?? (await getApplicationDocumentsDirectory()).path, 'apk', projectId));

/// 把 [apkPath]（安装包，或钥匙备份）抄一份到外部目录，返回新路径；这台设备没有外部目录返回 null。抄不成抛 [FileSystemException]。
Future<String?> copyApkToPublic(String apkPath, String projectId) async {
  final base = await _externalBase();
  if (base == null) return null;
  final dir = Directory(p.join(base, 'apk', projectId));
  await dir.create(recursive: true);
  final target = p.join(dir.path, p.basename(apkPath));
  await File(apkPath).copy(target);
  return target;
}
