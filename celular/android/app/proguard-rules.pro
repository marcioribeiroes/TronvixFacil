# O R8 corta o que nao encontra referencia no codigo Dart compilado.
#
# Estas classes sao alcancadas por reflexao ou pelo lado nativo, e o R8 nao tem
# como enxergar isso. Sem as regras, o aplicativo compila, instala, e quebra na
# hora de ler o QR ou de tocar o som — sempre no aparelho do cliente, nunca no
# de quem desenvolveu.

# Flutter e os canais de plataforma.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Leitura de QR: o mobile_scanner chama o MLKit, que carrega modelos por nome.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# Play Core: o Flutter referencia as classes de entrega diferida mesmo quando o
# aplicativo nao as usa, e o R8 reclama de cada uma.
-dontwarn com.google.android.play.core.**
