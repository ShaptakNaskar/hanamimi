# R8 was stripping/obfuscating parts of media3 (ExoPlayer) that are
# reached reflectively, causing an NPE inside ExoPlayerImplInternal on
# every track load in release builds. Keep the audio stack intact.
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }

# just_audio + audio_service plugin channels
-keep class com.ryanheise.** { *; }

# Kotlin platform channels in this app
-keep class com.hanamimi.app.** { *; }

# M28 — youtubedl-android + its Jackson JSON mapping (VideoInfo etc. are
# populated reflectively from yt-dlp's --dump-json output; R8 renaming
# the fields yields all-null info). Keep the library and its models.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# youtubedl-android unpacks its bundled Python payload with Apache
# Commons Compress (ZipUtils.unzip). The AAR's consumer rule only keeps
# archivers.zip, but R8 class-merging abstracts a helper elsewhere in
# the package ("class ... is not a concrete class" at init). Keep the
# whole library as a root so it can't be merged/renamed away.
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
-keep class org.tukaani.xz.** { *; }
-dontwarn org.tukaani.xz.**
