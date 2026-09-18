import 'package:flutter/material.dart';

import 'ambiente.dart';

/// As cores.
///
/// As três da marca vêm da configuração, com o vermelho do Tronvix Fácil como
/// padrão — é o que faz o mesmo aplicativo virar o de outro restaurante sem
/// tocar em tela nenhuma. Os valores padrão são os de `src/app/globals.css` do
/// projeto Next, repetidos aqui porque um app compilado não importa CSS.
///
/// Continuam `const`: `Ambiente` usa `int.fromEnvironment`, que é constante de
/// compilação. Fosse lido em tempo de execução, todo `const TextStyle(color:
/// Cores.marca)` do aplicativo teria de deixar de ser const.
class Cores {
  static const marca = Color(Ambiente.corDaMarca);
  static const marcaEscura = Color(Ambiente.corDaMarcaEscura);
  static const realce = Color(Ambiente.corDeRealce);
  static const sobreMarca = Color(0xFFFFFFFF);
  static const fundo = Color(0xFFFFFFFF);
  static const texto = Color(0xFF121214);
  static const suave = Color(0xFFF4F4F5);
  static const textoSuave = Color(0xFF71717A);
  static const borda = Color(0xFFE4E4E7);
  static const perigo = Color(0xFFDC2626);
  static const sucesso = Color(0xFF16A34A);
  static const atencao = Color(0xFFCA8A04);
}

ThemeData temaClaro() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Cores.marca,
      primary: Cores.marca,
      onPrimary: Cores.sobreMarca,
      surface: Cores.fundo,
      onSurface: Cores.texto,
      error: Cores.perigo,
    ),
    scaffoldBackgroundColor: Cores.fundo,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Cores.fundo,
      foregroundColor: Cores.texto,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Cores.texto,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Cores.borda,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Cores.suave,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Cores.marca, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Cores.marca,
        foregroundColor: Cores.sobreMarca,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Cores.texto,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Cores.borda),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: Cores.fundo,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Cores.borda),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Cores.texto,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
