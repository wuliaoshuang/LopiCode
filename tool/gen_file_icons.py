#!/usr/bin/env python3
"""从 npm 包 material-icon-theme 里挑一部分图标打进应用，并生成“文件名 → 图标”的映射表。

本脚本不联网。先自己把包下载好并核对校验值（见 third_party/material-icon-theme/README.md），然后：

    python3 tool/gen_file_icons.py 路径/material-icon-theme-版本.tgz
    dart format lib/core/file_icons_*_data.dart

它会重写：
  assets/file_icons/*.svg                         挑出来的图标，原样复制，不改内容
  third_party/material-icon-theme/SHA256SUMS      每个图标的 sha256
  third_party/material-icon-theme/LICENSE         包里的许可证全文
  assets/licenses/material-icon-theme-MIT.txt     同一份，给应用内“第三方声明”看
  lib/core/file_icons_{ext,name,folder,files}_data.dart 映射表与图标清单（Dart 常量）

映射数据取自包里的 dist/material-icons.json（官方生成的 VS Code 图标主题清单），只保留指向已打包图标的条目。
要加减图标就改下面的 FILE_ICONS / FOLDER_ICONS 再重跑；换版本后同时改 README 和 lib/core/third_party.dart。
"""
import hashlib
import json
import os
import shutil
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(ROOT, 'assets', 'file_icons')
TP_DIR = os.path.join(ROOT, 'third_party', 'material-icon-theme')
MAX_BYTES = 300 * 1024

# 要打包的文件图标（官方清单里的图标名）。有 _light 版本的会自动一起带上（浅色主题用）。
FILE_ICONS = """
file document readme license changelog authors contributing todo
html css sass less stylus postcss tailwindcss
javascript typescript typescript-def react react_ts vue vue-config svelte astro astro-config angular
next nuxt remix vite vitest webpack rollup esbuild babel jest test-js test-jsx test-ts
json json_schema hjson yaml toml xml markdown mdx settings tune lock log key certificate
nodejs npm yarn pnpm bun deno
eslint prettier stylelint editorconfig tsconfig jsconfig browserlist husky commitlint
python python-misc jupyter django poetry uv
go go-mod java javaclass jar kotlin scala groovy gradle maven
php laravel ruby gemfile rust c cpp h hpp csharp fsharp visualstudio
swift objective-c objective-cpp dart lua luau perl r julia
elixir erlang haskell ocaml clojure lisp zig nim crystal fortran pascal assembly
console powershell vim makefile cmake docker git github-actions-workflow gitlab
database prisma graphql proto nginx http openapi
terraform kubernetes hcl firebase vercel netlify
image svg font audio video pdf zip table word powerpoint
exe dll lib hex disc android webassembly
ejs handlebars pug twig nunjucks jinja liquid haml
tex asciidoc diff template i18n robots favicon url
solidity shader godot unity cuda matlab nix dotjs codeowners
coffee sbt cabal purescript elm reason rescript d vlang odin mojo cobol ada prolog scheme racket tcl verilog
applescript bazel meson xmake just taskfile renovate dependabot circleci azure-pipelines
playwright cypress storybook mocha karma phpunit rspec rubocop nuget razor xaml
capacitor ionic expo tauri supabase drizzle wrangler turborepo nx biome parcel gulp
nodemon serverless heroku mermaid drawio figma excalidraw epub email subtitles 3d blender
pytorch claude cursor gemini-ai markdownlint lintstaged
qwik unocss typst latex bibliography command search verified minecraft
""".split()

# 要打包的特殊文件夹图标（folder-名字 与 folder-名字-open 各一张）。默认文件夹与根文件夹总是带上。
FOLDER_ICONS = """
src lib test node dist docs images git github config public components api
scripts utils views css sass javascript typescript json android ios
font audio video server database content template layout routes hook
middleware controller app tools temp log examples mock i18n theme vscode
class client core shared helper plugin interface python java kotlin rust php vue react-components
flutter dart docker gradle download upload functions packages resource environment error event home keys
secure svg archive backup migrations store target markdown messages admin desktop mobile include
coverage ci debug generator animation base global lua less nginx next nuxt prisma proto graphql
terraform trash ui
""".split()


def die(msg):
    sys.exit('gen_file_icons: ' + msg)


def variants(base):
    """官方清单给每个文件夹名生成的五种写法。"""
    return [base, '.' + base, '_' + base, '-' + base, '__' + base + '__']


def dart_map(name, doc, groups):
    """groups: 图标文件名（不带 .svg）→ 一组键。写成“图标 → 用空格隔开的键”的 Dart 常量。"""
    lines = ['// 由 tool/gen_file_icons.py 生成，不要手改。', '// 数据取自 material-icon-theme 的 dist/material-icons.json，只留指向已打包图标的条目。', '', doc, 'const Map<String, String> %s = {' % name]
    for icon in sorted(groups):
        keys = sorted(groups[icon])
        for k in keys:
            if any(ch in k for ch in " '\\$\n"):
                die('键里有不能直接写进字符串的字符：%r' % k)
        lines.append("  '%s': '%s'," % (icon, ' '.join(keys)))
    lines.append('};')
    return '\n'.join(lines) + '\n'


def main():
    if len(sys.argv) != 2:
        die('用法：python3 tool/gen_file_icons.py 路径/material-icon-theme-版本.tgz')
    tmp = tempfile.mkdtemp(prefix='mit-')
    try:
        with tarfile.open(sys.argv[1]) as tar:
            tar.extractall(tmp)
        pkg = os.path.join(tmp, 'package')
        manifest = json.load(open(os.path.join(pkg, 'dist', 'material-icons.json'), encoding='utf-8'))
        version = json.load(open(os.path.join(pkg, 'package.json'), encoding='utf-8'))['version']
        defs = {name: os.path.basename(d['iconPath'])[: -len('.svg')] for name, d in manifest['iconDefinitions'].items()}

        # 1. 定下要带哪些图标（图标名）。
        wanted = set(FILE_ICONS)
        for base in ['folder', 'folder-root'] + ['folder-' + f for f in FOLDER_ICONS]:
            wanted.update([base, base + '-open'])
        missing = sorted(w for w in wanted if w not in defs)
        if missing:
            die('这个版本的包里没有这些图标：' + ' '.join(missing))
        for name in list(wanted):
            if name + '_light' in defs:
                wanted.add(name + '_light')
        for must in (manifest['file'], manifest['folder'], manifest['folderExpanded']):
            if must not in wanted:
                die('默认图标 %s 没在清单里' % must)

        # 2. 先看大小够不够（超了就什么都不动），再原样复制、记校验值。
        size = sum(os.path.getsize(os.path.join(pkg, 'icons', defs[name] + '.svg')) for name in wanted)
        if size > MAX_BYTES:
            die('图标一共 %d 字节，超过上限 %d' % (size, MAX_BYTES))
        if os.path.isdir(ASSET_DIR):
            shutil.rmtree(ASSET_DIR)
        os.makedirs(ASSET_DIR)
        os.makedirs(TP_DIR, exist_ok=True)
        sums, total = [], 0
        for name in sorted(wanted):
            data = open(os.path.join(pkg, 'icons', defs[name] + '.svg'), 'rb').read()
            if not data.lstrip().startswith(b'<svg'):
                die(name + ' 不是 SVG')
            open(os.path.join(ASSET_DIR, defs[name] + '.svg'), 'wb').write(data)
            sums.append('%s  %s.svg' % (hashlib.sha256(data).hexdigest(), defs[name]))
            total += len(data)
        open(os.path.join(TP_DIR, 'SHA256SUMS'), 'w', encoding='utf-8').write('\n'.join(sorted(sums, key=lambda s: s.split('  ')[1])) + '\n')
        license_text = open(os.path.join(pkg, 'LICENSE'), 'rb').read()
        open(os.path.join(TP_DIR, 'LICENSE'), 'wb').write(license_text)
        open(os.path.join(ROOT, 'assets', 'licenses', 'material-icon-theme-MIT.txt'), 'wb').write(license_text)

        # 3. 浅色主题的规矩：官方清单里浅色条目永远是“原图标名 + _light”，查的时候按这个规矩找就行。先核实。
        for section in ('fileExtensions', 'fileNames', 'folderNames', 'folderNamesExpanded', 'languageIds'):
            for key, icon in manifest['light'].get(section, {}).items():
                base = manifest[section].get(key)
                expect = None if base is None else base + '_light'
                if icon != expect:
                    die('浅色条目不符合“加 _light”的规矩：%s %s → %s（默认 %s）' % (section, key, icon, base))

        # 4. 映射表：只留指向已打包图标的条目；键一律小写；带路径的文件名（.config/xxx）不要。
        def keep(section, skip=lambda k: False):
            groups = {}
            for key, icon in manifest[section].items():
                if icon in wanted and not skip(key):
                    low = key.lower()
                    for other, ks in groups.items():
                        if low in ks and other != defs[icon]:
                            die('%s 里 %s 小写后对到两个图标' % (section, key))
                    groups.setdefault(defs[icon], set()).add(low)
            return groups

        exts = keep('fileExtensions')
        names = keep('fileNames', skip=lambda k: '/' in k)
        langs = keep('languageIds')

        # 文件夹：官方给每个名字生成五种写法（x .x _x -x __x__）。只存原名，查的时候去掉前后缀再找；
        # 这里核实“只存原名”能还原出和官方完全一样的结果，还原不了的单独原样存。
        folder_all = {k.lower(): defs[v] for k, v in manifest['folderNames'].items() if v in wanted}
        for key, icon in manifest['folderNames'].items():
            if manifest['folderNamesExpanded'].get(key) != icon + '-open':
                die('文件夹 %s 的展开图标不是“加 -open”' % key)
        folders = {}
        covered = set()
        for key, icon in folder_all.items():
            if all(folder_all.get(v) == icon for v in variants(key)):
                folders.setdefault(icon, set()).add(key)
                covered.update(variants(key))
        base_keys = {k for ks in folders.values() for k in ks}
        # 是别的原名的变体（比如 .git 是 git 的变体）就不用再存。
        for icon in list(folders):
            folders[icon] = {k for k in folders[icon] if not any(k != b and k in variants(b) for b in base_keys)}
        rebuilt = {}
        for icon, ks in folders.items():
            for k in ks:
                for v in variants(k):
                    rebuilt[v] = icon
        extra = {k: i for k, i in folder_all.items() if rebuilt.get(k) != i}
        for k, i in extra.items():
            folders.setdefault(i, set()).add('=' + k)  # “=”开头：只按原样匹配，不展开变体
            rebuilt[k] = i
        if rebuilt != folder_all:
            die('文件夹映射还原不回官方结果：多 %s 少 %s' % (sorted(set(rebuilt) - set(folder_all))[:5], sorted(set(folder_all) - set(rebuilt))[:5]))

        core = os.path.join(ROOT, 'lib', 'core')
        head = '/// material-icon-theme %s。' % version
        open(os.path.join(core, 'file_icons_ext_data.dart'), 'w', encoding='utf-8').write(
            dart_map('kFileIconExtensions', head + '图标 → 扩展名（空格隔开，小写，不带开头的点；可以是多段的，如 d.ts）。', exts)
        )
        open(os.path.join(core, 'file_icons_name_data.dart'), 'w', encoding='utf-8').write(
            dart_map('kFileIconNames', head + '图标 → 完整文件名（空格隔开，小写）。', names)
            + '\n'
            + dart_map('kFileIconLanguages', head + '图标 → VS Code 语言 id（空格隔开，小写）。', langs).split('\n', 3)[3]
        )
        open(os.path.join(core, 'file_icons_folder_data.dart'), 'w', encoding='utf-8').write(
            dart_map('kFolderIconNames', head + '文件夹图标 → 文件夹名（空格隔开，小写）。查的时候 .x _x -x __x__ 都算 x；“=”开头的只按原样匹配。', folders)
        )
        packed = sorted(defs[n] for n in wanted)
        rows = [' '.join(packed[i : i + 10]) for i in range(0, len(packed), 10)]
        files_src = '// 由 tool/gen_file_icons.py 生成，不要手改。\n\n/// 图标包版本。\nconst String kFileIconPackVersion = \'%s\';\n' % version
        files_src += '\n/// 随包的全部图标文件名（不带 .svg），空格隔开。\nconst String kFileIconFileList =\n' + '\n'.join("    '%s%s'" % (r, '' if i == len(rows) - 1 else ' ') for i, r in enumerate(rows)) + ';\n'
        open(os.path.join(core, 'file_icons_files_data.dart'), 'w', encoding='utf-8').write(files_src)
        n_keys = lambda g: sum(len(v) for v in g.values())
        print('版本 %s：图标 %d 个，共 %d 字节（%.1f KB）' % (version, len(wanted), total, total / 1024))
        print('映射：扩展名 %d，文件名 %d，语言 id %d，文件夹名 %d（展开变体后 %d）' % (n_keys(exts), n_keys(names), n_keys(langs), n_keys(folders), len(folder_all)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
