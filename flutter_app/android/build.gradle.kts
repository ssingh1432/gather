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
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion(36)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
