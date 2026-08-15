allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugin modules (e.g. receive_sharing_intent) ship with inconsistent
// Java/Kotlin JVM-target defaults for their own Android module, which fails
// the build with "Inconsistent JVM-target compatibility detected". Force a
// consistent target across every subproject's compile tasks (task-level,
// not the Kotlin extension API, since a plugin's own build script may have
// already finalized that by the time this root script's subprojects block
// runs) rather than patching each plugin's own build files.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
