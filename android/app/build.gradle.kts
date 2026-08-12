import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release-Signing aus android/key.properties (lokal bzw. von CI erzeugt);
// ohne die Datei fällt der Build auf Debug-Signing zurück.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

/// Flutters Plattformnamen auf Android-ABIs (dieselbe Zuordnung wie
/// `FlutterPluginConstants.PLATFORM_ARCH_MAP`; hier gespiegelt, weil das
/// Objekt intern ist).
val platformToAbi =
    mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )

android {
    namespace = "de.marcusbucher.pilzbuddy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ota_update (In-App-Update) benötigt Desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.marcusbucher.pilzbuddy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // `--target-platform android-arm64` beschränkt nur FLUTTERS eigene
        // Artefakte; die nativen Teile der Plugins packt Gradle weiter für
        // alle ABIs ein. In 1.42.0 waren das 22,4 MB von 66,7 MB — vor
        // allem `libmaplibre.so` dreimal, zweimal davon ohne passende
        // `libflutter.so` und damit nicht startfähig.
        //
        // Der Filter leitet sich aus derselben Eigenschaft ab, die Flutter
        // für `--target-platform` ohnehin an Gradle durchreicht. Damit gilt
        // er genau dort, wo er soll: Das AAB (ohne `--target-platform`)
        // bleibt vollständig, weil Play selbst pro Gerät splittet.
        //
        // Nicht `--split-per-abi` nehmen: Das überschreibt den versionCode
        // mit `ABI-Nummer * 1000 + versionCode` (FlutterPlugin.kt), aus 84
        // würde 2084 — dauerhaft, unumkehrbar (Android aktualisiert nur
        // aufwärts) und verschieden vom AAB.
        (project.findProperty("target-platform") as String?)
            ?.split(",")
            ?.mapNotNull { platformToAbi[it.trim()] }
            ?.takeIf { it.isNotEmpty() }
            ?.let { ndk.abiFilters.addAll(it) }
    }

    // Zwei Vertriebswege, EINE App: GitHub-APK und Play-Bundle tragen
    // dieselbe `applicationId` (bewusst kein `applicationIdSuffix` — sonst
    // wären es für Android zwei Apps, wie beim Bundle-ID-Umzug in
    // Mitfahrbar #87). Unterschieden wird allein der Update-Weg:
    //
    // Der Dart-Pfad ist im Play-Build längst aus
    // (`AppDistribution.showsUpdateHints` über `--dart-define=PLAY_BUILD=true`),
    // die Manifest-Zeile `REQUEST_INSTALL_PACKAGES` war es nicht und läge im
    // hochgeladenen AAB. Play verbietet Selbst-Updates („Device and Network
    // Abuse"), und eine Berechtigung ohne zugehörige Funktion ist in der
    // Review die schlechtestmögliche Antwort. Der `play`-Flavor nimmt sie
    // deshalb in `src/play/AndroidManifest.xml` per `tools:node="remove"`
    // wieder heraus — dasselbe Muster wie bei `RECEIVE_BOOT_COMPLETED`.
    //
    // Folge für jeden Build-Aufruf: Ab hier verlangt Flutter überall ein
    // `--flavor`, und die Ausgabepfade tragen den Flavor-Namen
    // (`app-github-release.apk`, `bundle/playRelease/app-play-release.aab`).
    // `test/release_build_test.dart` hält Aufruf und Pfad zusammen.
    flavorDimensions += "distribution"
    productFlavors {
        create("github") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
