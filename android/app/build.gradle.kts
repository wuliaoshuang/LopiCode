plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lopicode.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lopicode.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // flutter_secure_storage 11 需要 Android 7.0 以上
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // PRoot 是以 lib*.so 的名字放在原生库目录里的可执行文件：必须真的解到磁盘上才能执行，
    // 所以原生库不能压在安装包里直接映射（配合清单里的 extractNativeLibs="true"）。
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // 这四个文件是 Termux 官方包里的原样文件：不让打包工具再“瘦身”改动它们，
            // 这样安装包里的文件和 third_party/termux/SHA256SUMS 里的校验值逐字节一致。
            keepDebugSymbols += setOf(
                "**/libproot.so",
                "**/libproot-loader.so",
                "**/libtalloc.so",
                "**/libandroid-shmem.so",
            )
        }
    }

    // 发布签名固定用一把（2026-11-25 霜霜定：以后一直沿用，不许换；换了手机上装不了升级包）。
    // 密钥文件不进仓库：路径和口令从 Gradle 属性读（放在打包机的 GRADLE_USER_HOME/gradle.properties）。
    // 没配这些属性的机器退回调试签名——那样打出来的包和正式包签名不同，不能覆盖安装。
    val lopiKeystore = providers.gradleProperty("lopicode.keystore").orNull
    signingConfigs {
        if (lopiKeystore != null) {
            create("lopicode") {
                storeFile = file(lopiKeystore)
                storePassword = providers.gradleProperty("lopicode.storePassword").get()
                keyAlias = providers.gradleProperty("lopicode.keyAlias").get()
                keyPassword = providers.gradleProperty("lopicode.keyPassword").get()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (lopiKeystore != null) "lopicode" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
