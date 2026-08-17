// Root build file. Versions are pinned to match the toolchain build.sh provisions
// (Gradle 8.7, JDK 17, compileSdk 34 / build-tools 34.0.0).
plugins {
    id("com.android.application") version "8.4.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
