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

// Inject fallback namespace and force compileSdkVersion 36 for third-party plugins
subprojects {
    fun fixSubproject() {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (android != null) {
                if (android.namespace == null) {
                    android.namespace = project.group.toString()
                }
                android.compileSdkVersion(36)
            }
        }
    }

    if (project.state.executed) {
        fixSubproject()
    } else {
        project.afterEvaluate {
            fixSubproject()
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}