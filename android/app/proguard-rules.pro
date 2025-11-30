# Flutter Secure Storage - keep Tink library classes
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class * {
    @com.google.crypto.tink.annotations.** *;
}

# Keep TypeToken for Gson (used by flutter_secure_storage)
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep generic signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
