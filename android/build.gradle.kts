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

subprojects {
    // 1. Inject the missing Kotlin plugin specifically for flutter_midi_pro
    if (project.name == "flutter_midi_pro") {
        apply(plugin = "kotlin-android")
    }

    // 2. Safely enforce compileSdk 36 on all Flutter plugin modules
    if (project.state.executed) {
        project.extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36
    } else {
        project.afterEvaluate {
            project.extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}