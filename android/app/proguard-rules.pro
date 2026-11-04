# kotlinx.serialization keeps what it needs through its own rules; these are for osmdroid.
-dontwarn org.osmdroid.**
-keep class org.osmdroid.** { *; }
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class win.tbsgaming.tracklap.** {
    *** Companion;
}
-keepclasseswithmembers class win.tbsgaming.tracklap.** {
    kotlinx.serialization.KSerializer serializer(...);
}
