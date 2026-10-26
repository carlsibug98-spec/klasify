allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// paddle_ocr_native 0.1.1 registers its vendored ppocr-sdk Kotlin sources
// through `java.srcDirs`. The legacy Kotlin Gradle Plugin picked `.kt` files
// up from there, but AGP 9 built-in Kotlin only compiles the `kotlin` source
// set, so :paddle_ocr_native:compileDebugKotlin fails with unresolved
// references to the vendored `com.paddle.ocr` package. Mirror the directories
// into the kotlin source set when this app builds with built-in Kotlin.
// Only legacy-tracked Android source sets have `kotlin`; AGP 9's
// AndroidSource-directorySet exposes it under both DSLs, so guard on the
// property instead of the extension.
subprojects {
    if (name != "paddle_ocr_native") return@subprojects
    val builtInKotlin = providers.gradleProperty("android.builtInKotlin").orNull
    if (builtInKotlin?.toBoolean() != true) return@subprojects
    afterEvaluate {
        val libraryExtension = extensions.findByType(
            com.android.build.gradle.LibraryExtension::class.java,
        ) ?: return@afterEvaluate
        libraryExtension.sourceSets.named("main") {
            kotlin.srcDirs("src/main/kotlin", "ppocr-sdk/src/main/java")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
