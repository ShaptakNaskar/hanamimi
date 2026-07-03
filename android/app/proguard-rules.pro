# R8 was stripping/obfuscating parts of media3 (ExoPlayer) that are
# reached reflectively, causing an NPE inside ExoPlayerImplInternal on
# every track load in release builds. Keep the audio stack intact.
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }

# just_audio + audio_service plugin channels
-keep class com.ryanheise.** { *; }

# Kotlin platform channels in this app
-keep class com.hanamimi.app.** { *; }
