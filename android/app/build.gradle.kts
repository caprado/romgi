plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.caprado.romgi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.caprado.romgi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Release ships arm64 only — every supported device is arm64-v8a,
            // and dropping x86/armv7 keeps the APK ~40 MB smaller.
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
        debug {
            // Debug also bundles x86_64 so we can run on the Windows
            // emulator (where qemu2 can only run x86 guests on x86 hosts).
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    packaging {
        // libtorrent4j's sub-jars contain duplicate license files;
        // exclude them so the resource merger doesn't fail.
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
        // libtorrent4j's loader uses System.loadLibrary which needs the
        // .so extracted from the APK. The newer "compressed in-APK" mode
        // (default for release) breaks that load with
        // UnsatisfiedLinkError. Force the older extract-on-install mode.
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // libtorrent4j: torrent runtime. Maintained fork/successor of
    // jlibtorrent by the same author, wrapping libtorrent 2.x. Used
    // by LibreTorrent and most current Android torrent clients.
    // Verify before bumping at:
    //   https://central.sonatype.com/artifact/org.libtorrent4j/libtorrent4j
    val libtorrent4jVersion = "2.1.0-32"
    implementation("org.libtorrent4j:libtorrent4j:$libtorrent4jVersion")
    implementation("org.libtorrent4j:libtorrent4j-android-arm64:$libtorrent4jVersion")
    // Only included in debug APKs so emulator testing on x86 hosts works.
    debugImplementation("org.libtorrent4j:libtorrent4j-android-x86_64:$libtorrent4jVersion")

    // Apache Commons Compress: 7z extraction for disc-based ROM archives.
    implementation("org.apache.commons:commons-compress:1.27.1")
    // XZ (LZMA2) decoder — required by commons-compress for 7z extraction.
    implementation("org.tukaani:xz:1.10")
}
