/// 现成的 GitHub Actions 工作流模板，应用里可以查看、复制、写进项目。
/// 放到仓库的 `.github/workflows/android.yml`，用 workflow_dispatch 手动触发。
/// 注意：这两份模板没有在真实的 GitHub Actions 上跑过（开发环境不允许推送）。
library;

const String kWorkflowPath = '.github/workflows/android.yml';

/// Flutter 项目：仓库根目录就是一个 Flutter 工程。
const String flutterWorkflowTemplate = r'''
name: Android APK

on:
  workflow_dispatch:
    inputs:
      mode:
        description: 构建类型（debug 或 release）
        required: false
        default: debug

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - run: flutter pub get

      - run: flutter build apk --${{ inputs.mode }}

      - uses: actions/upload-artifact@v4
        with:
          name: app-${{ inputs.mode }}
          path: build/app/outputs/flutter-apk/*.apk
          if-no-files-found: error
''';

/// 网页项目：仓库里是 HTML / CSS / JS（根目录有 index.html）。
/// 在 CI 里现建一个 Flutter 壳工程，把网页打进 assets，用 WebView 打开。
const String webShellWorkflowTemplate = r'''
name: Android APK (网页套壳)

on:
  workflow_dispatch:
    inputs:
      mode:
        description: 构建类型（debug 或 release）
        required: false
        default: debug
      app_name:
        description: 应用名
        required: false
        default: 我的网页

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: 生成 WebView 壳工程
        run: |
          flutter create --platforms android --org com.lopicode.web --project-name webshell "$RUNNER_TEMP/shell"
          cd "$RUNNER_TEMP/shell"
          flutter pub add webview_flutter
          mkdir -p assets/www
          rsync -a --exclude .git --exclude .github --exclude .lopicode "$GITHUB_WORKSPACE/" assets/www/
          test -f assets/www/index.html || { echo "仓库根目录没有 index.html"; exit 1; }
          # Flutter 的 assets 不会递归包含子目录，逐个目录登记
          echo "  assets:" >> pubspec.yaml
          find assets/www -type d | sed 's|$|/|; s|^|    - |' >> pubspec.yaml
          sed -i "s|android:label=\"[^\"]*\"|android:label=\"${{ inputs.app_name }}\"|" android/app/src/main/AndroidManifest.xml
          cat > lib/main.dart <<'DART'
          import 'package:flutter/material.dart';
          import 'package:webview_flutter/webview_flutter.dart';

          void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Shell()));

          class Shell extends StatefulWidget {
            const Shell({super.key});
            @override
            State<Shell> createState() => _ShellState();
          }

          class _ShellState extends State<Shell> {
            late final WebViewController controller = WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadFlutterAsset('assets/www/index.html');

            @override
            Widget build(BuildContext context) =>
                Scaffold(body: SafeArea(child: WebViewWidget(controller: controller)));
          }
          DART

      - name: 构建 APK
        run: |
          cd "$RUNNER_TEMP/shell"
          flutter build apk --${{ inputs.mode }}
          mkdir -p "$GITHUB_WORKSPACE/out"
          cp build/app/outputs/flutter-apk/*.apk "$GITHUB_WORKSPACE/out/"

      - uses: actions/upload-artifact@v4
        with:
          name: app-${{ inputs.mode }}
          path: out/*.apk
          if-no-files-found: error
''';
