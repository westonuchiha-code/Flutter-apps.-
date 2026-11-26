# Comics: junrar logs through slf4j, which isn't in the app (no logger bound).
-dontwarn org.slf4j.**
# Commons Compress / xz load some codecs by name.
-dontwarn org.apache.commons.compress.**
-keep class org.tukaani.xz.** { *; }
-keep class com.github.junrar.** { *; }
-keep class org.apache.commons.compress.archivers.sevenz.** { *; }
