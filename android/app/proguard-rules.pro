# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Gson specific classes
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.examples.android.model.** { *; }

# HTTP client
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Shared Preferences
-keep class androidx.preference.** { *; }

# HTML parser
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**

# Networking
-keep class java.net.** { *; }
-keep class android.net.** { *; }

# Keep model classes for serialization
-keep class com.saveit.app.models.** { *; }

# General Android rules
-keep class androidx.** { *; }
-keep class android.support.** { *; }

# Remove debug logs in release
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}

# Keep intent filter classes
-keep class androidx.core.content.** { *; }

# Prevent obfuscation of intent actions
-keepclassmembers class * {
    @android.annotation.SuppressLint *;
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator *;
}