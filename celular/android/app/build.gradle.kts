import java.util.Properties

// A chave de assinatura fica fora do repositorio, em android/key.properties.
// Versiona-la deixaria qualquer um com o repositorio publicar em nome do dono.
// Sem o arquivo, o build de release cai na chave de depuracao — o que serve
// para rodar na propria maquina e o Play recusa.
val chaves = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.com.tronvix.tronvix_facil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.tronvix.tronvix_facil"
        // minSdk 24 (Android 7) cobre praticamente todo celular em uso; 
        // targetSdk e compileSdk vem do Flutter, que hoje aponta para o 36 —
        // acima do 35 que o Play exige.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("upload") {
            keyAlias = chaves.getProperty("keyAlias")
            keyPassword = chaves.getProperty("keyPassword")
            storeFile = chaves.getProperty("storeFile")?.let { file(it) }
            storePassword = chaves.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (chaves.getProperty("storeFile") != null) {
                signingConfigs.getByName("upload")
            } else {
                // Sem a chave, o release sai assinado para depuracao: roda na
                // maquina de quem clonou o projeto, e o Play recusa — que e
                // exatamente o que se quer, em vez de um build que parece
                // pronto e nao e.
                signingConfigs.getByName("debug")
            }

            // R8 corta o que nao e usado e embaralha os nomes. Sem isto o
            // pacote sai com o dobro do tamanho, e quem baixa no 4G paga.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
