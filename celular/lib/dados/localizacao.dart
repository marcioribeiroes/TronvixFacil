/// Onde a pessoa está.
///
/// Uma camada fina sobre o `geolocator` com uma regra: **nunca travar a tela**.
/// Localização negada, GPS desligado, aparelho sem sinal — tudo isso devolve
/// nulo, e quem chamou desenha o que der. Um entregador com a permissão negada
/// ainda precisa ver os endereços e aceitar a corrida.
library;

import 'package:geolocator/geolocator.dart';

class Ponto {
  const Ponto(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class Localizacao {
  /// Pede a permissão, se ainda não foi decidida. Devolve se dá para localizar.
  static Future<bool> podeLocalizar() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    return permissao == LocationPermission.always ||
        permissao == LocationPermission.whileInUse;
  }

  static Future<Ponto?> onde() async {
    try {
      if (!await podeLocalizar()) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Sem limite de tempo, uma corrida em prédio sem sinal deixaria a
          // tela girando para sempre.
          timeLimit: Duration(seconds: 12),
        ),
      );
      return Ponto(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Acompanha o deslocamento. Só emite a cada 25 metros: um mapa que se
  /// redesenha a cada metro come bateria de quem passa o dia na rua.
  static Stream<Ponto> acompanhar() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).map((p) => Ponto(p.latitude, p.longitude));

  /// Distância em quilômetros, em linha reta.
  ///
  /// É uma estimativa e a tela diz isso: a rua dá voltas que a reta não dá.
  static double distanciaKm(Ponto de, Ponto ate) =>
      Geolocator.distanceBetween(
        de.latitude,
        de.longitude,
        ate.latitude,
        ate.longitude,
      ) /
      1000;
}
