# Constructed from JNI via FindClass/NewObject (AssKt.c).
-keep class app.encorr.encorr.libass.AssAtlasFrame { *; }
# JNI exports bind by name (Java_app_encorr_encorr_libass_*); keep the names stable.
-keepclasseswithmembernames class app.encorr.encorr.libass.* {
    native <methods>;
}
