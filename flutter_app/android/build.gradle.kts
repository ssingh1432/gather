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

// receive_sharing_intent's own build.gradle hardcodes compileSdk 37, which
// isn't an actual installable SDK platform yet (sdkmanager: "Failed to find
// package"). It has no real API dependency on SDK 37 -- this is almost
// certainly just a bumped dependency-version bookkeeping number, not a
// functional requirement -- so force every subproject back down to 36,
// which is installed and sufficient.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion(36)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
