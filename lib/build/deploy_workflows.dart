// 后端项目的 GitHub Actions 工作流模板：按语言生成，手动触发（workflow_dispatch）。
// 默认只“构建并上传产物”；部署那一步写在里面但要触发时把 deploy 打开、并且仓库里配好 Secrets 才会跑。
// 模板里只有 `${{ secrets.XXX }}` 占位，不写任何密钥。这些模板没有在真实的 GitHub Actions 上跑过。
import 'package:lopicode/build/deploy_project.dart';

/// 新工作流默认的文件名（和打 APK 的 android.yml 分开）。
const String kDeployWorkflowFile = 'deploy.yml';

String deployWorkflowPath(String file) => '.github/workflows/$file';

/// 要部署到服务器，得在 GitHub 仓库里配的 Secrets：名字 → 是什么。
const Map<String, String> kDeploySecrets = {'DEPLOY_HOST': '服务器地址（域名或 IP）', 'DEPLOY_USER': '登录用户名', 'DEPLOY_SSH_KEY': '登录用的 SSH 私钥全文', 'DEPLOY_PATH': '部署到服务器上的哪个目录（要已存在）'};

const String kDeploySecretsWhere = 'GitHub 仓库 › Settings › Secrets and variables › Actions › New repository secret';

/// 生成工作流全文。[name]＝产物的名字。
String deployWorkflow(DeployProject project, {required String name}) {
  final n = deploySafeName(name);
  final dir = project.dir.isEmpty ? '.' : project.dir;
  final (String setup, String build) = switch (project.lang) {
    DeployLang.go => (
      '''
      - uses: actions/setup-go@v5
        with:
          go-version: stable
''',
      'go build -buildvcs=false -o dist/$n .',
    ),
    DeployLang.java => (
      '''
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
''',
      switch (project.javaLayout) {
        JavaLayout.maven => 'mvn -B package\n          mkdir -p dist && cp target/*.jar dist/',
        JavaLayout.gradle => 'gradle build\n          mkdir -p dist && cp build/libs/*.jar dist/',
        JavaLayout.flat when project.javaMain != null =>
          'mkdir -p dist classes\n          javac -encoding UTF-8 -d classes *.java\n          jar --create --file dist/$n.jar --main-class ${project.javaMain} -C classes .',
        _ => 'echo "这里换成你的编译命令，把产物放进 dist/"\n          mkdir -p dist && tar -czf dist/$n.tar.gz --exclude=./dist --exclude=./.git .',
      },
    ),
    DeployLang.node => (
      '''
      - uses: actions/setup-node@v4
        with:
          node-version: 24
''',
      '${project.hasPackageJson ? 'npm install --omit=dev\n          ' : ''}'
          "find . -type f -name '*.js' -not -path './node_modules/*' -not -path './dist/*' -print0 | xargs -0 -r -n 1 node --check\n"
          '          mkdir -p dist && tar -czf dist/$n.tar.gz --exclude=./dist --exclude=./.git .',
    ),
    DeployLang.python => (
      '''
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
''',
      "${project.hasRequirements ? 'python -m pip install -r requirements.txt\n          ' : ''}"
          "find . -type f -name '*.py' -not -path './dist/*' -print0 | xargs -0 -r python -m py_compile\n"
          '          mkdir -p dist && tar -czf dist/$n.tar.gz --exclude=./dist --exclude=./.git --exclude=__pycache__ .',
    ),
    DeployLang.php => (
      '',
      "${project.hasComposer ? 'composer install --no-dev\n          ' : ''}"
          "find . -type f -name '*.php' -not -path './vendor/*' -not -path './dist/*' -print0 | xargs -0 -r -n 1 php -l\n"
          '          mkdir -p dist && tar -czf dist/$n.tar.gz --exclude=./dist --exclude=./.git .',
    ),
    DeployLang.other => ('', 'echo "没认出语言：这里换成你的编译命令，把产物放进 dist/"\n          mkdir -p dist && tar -czf dist/$n.tar.gz --exclude=./dist --exclude=./.git .'),
  };
  return '''
name: 构建与部署

on:
  workflow_dispatch:
    inputs:
      deploy:
        description: 构建完要不要部署到服务器（要先在仓库里配好 DEPLOY_ 开头的四个 Secrets）
        type: boolean
        required: false
        default: false

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: $dir
    steps:
      - uses: actions/checkout@v4

$setup
      - name: 构建
        run: |
          $build

      - uses: actions/upload-artifact@v4
        with:
          name: $n
          path: ${dir == '.' ? '' : '$dir/'}dist/
          if-no-files-found: error

      # 下面这一步默认不跑。要用它：触发时把 deploy 打开，并且先在
      # $kDeploySecretsWhere
      # 里配好 ${kDeploySecrets.keys.join('、')}。密钥只放在 Secrets 里，不要写进这个文件。
      - name: 部署到服务器（可选）
        if: \${{ inputs.deploy }}
        env:
          DEPLOY_HOST: \${{ secrets.DEPLOY_HOST }}
          DEPLOY_USER: \${{ secrets.DEPLOY_USER }}
          DEPLOY_SSH_KEY: \${{ secrets.DEPLOY_SSH_KEY }}
          DEPLOY_PATH: \${{ secrets.DEPLOY_PATH }}
        run: |
          test -n "\$DEPLOY_HOST" && test -n "\$DEPLOY_USER" && test -n "\$DEPLOY_SSH_KEY" && test -n "\$DEPLOY_PATH" || { echo "还没配好部署用的 Secrets"; exit 1; }
          mkdir -p ~/.ssh
          printf '%s\\n' "\$DEPLOY_SSH_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          ssh-keyscan -H "\$DEPLOY_HOST" >> ~/.ssh/known_hosts
          scp -i ~/.ssh/deploy_key -r dist/. "\$DEPLOY_USER@\$DEPLOY_HOST:\$DEPLOY_PATH/"
          # 需要重启服务的话，在下面加一行，例如：
          # ssh -i ~/.ssh/deploy_key "\$DEPLOY_USER@\$DEPLOY_HOST" "systemctl restart 你的服务名"
'''
      .trimLeft();
}
