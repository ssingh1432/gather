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

// receive_sharing_intent's own build.gradle hardcodes compileSdk 37, which
// isn't an actual installable SDK platform yet (sdkmanager: "Failed to find
// package"). It has no real API dependency on SDK 37 -- this is almost
// certainly just a bumped dependency-version bookkeeping number, not a
// functional requirement -- so force every subproject back down to 36,
// which is installed and sufficient.
//
// This MUST be registered before evaluationDependsOn(":app") below --
// that call eagerly evaluates :app and, transitively, every other
// subproject right then and there, so an afterEvaluate registered after
// it fails with "already evaluated" for any subproject caught in that
// cascade.
subprojects {
    afterEvaluate {
        // Newer Android plugin subprojects (e.g. shared_preferences_android) expose the
        // new DSL only; calling the legacy BaseExtension API on them throws a
        // LinkageError (NoSuchMethodError) and failed the whole build. Only
        // receive_sharing_intent needs the override, so never let it break others.
        try {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion(36)
        } catch (e: Throwable) {
            logger.info("compileSdk override skipped for ${project.name}: ${e.message}")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
