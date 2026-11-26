package com.lopicode.app

import androidx.core.content.FileProvider

/**
 * 把安装包交给系统安装器用的文件提供者（content:// 地址）。
 * 单独起一个子类而不是直接登记 androidx 的 FileProvider：别的插件也可能登记那个类，同名会在合并清单时打架。
 * 能给出哪些目录写在 res/xml/apk_install_paths.xml 里；不对外公开（exported=false），只在发起安装时临时授权读那一个文件。
 */
class ApkFileProvider : FileProvider()
