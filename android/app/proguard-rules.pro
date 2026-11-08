# Huawei HMS Push Kit (huawei_push) — rules from Huawei's integration guide.
# The SDK refers to optional HMS modules (analytics, update, bouncycastle) that
# are not bundled; they are looked up at runtime only when present.
-ignorewarnings
-keepattributes *Annotation*
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-keep class com.hianalytics.android.**{*;}
-keep class com.huawei.updatesdk.**{*;}
-keep class com.huawei.hms.**{*;}
-keep class com.huawei.agconnect.**{*;}
-dontwarn com.huawei.**
-dontwarn org.bouncycastle.**
