/// O mapa.
///
/// OpenStreetMap, sem chave de API. O produto é vendido a restaurantes; exigir
/// que cada um abra conta num provedor de mapas antes de o primeiro entregador
/// sair seria um degrau a mais para nada.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../dados/localizacao.dart';
import '../tema.dart';

/// Um alfinete no mapa.
class Alfinete {
  const Alfinete({
    required this.ponto,
    required this.icone,
    this.cor = Cores.marca,
    this.rotulo,
  });

  final Ponto ponto;
  final IconData icone;
  final Color cor;
  final String? rotulo;
}

class Mapa extends StatefulWidget {
  const Mapa({
    super.key,
    required this.alfinetes,
    this.eu,
    this.altura,
    this.interativo = true,
  });

  final List<Alfinete> alfinetes;

  /// Onde está quem olha. Nulo quando não há permissão ou sinal — o mapa
  /// continua funcionando, só sem o ponto azul.
  final Ponto? eu;
  final double? altura;
  final bool interativo;

  @override
  State<Mapa> createState() => _MapaState();
}

class _MapaState extends State<Mapa> {
  final _controle = MapController();
  bool _pronto = false;

  List<LatLng> get _todos => [
        for (final a in widget.alfinetes) LatLng(a.ponto.latitude, a.ponto.longitude),
        if (widget.eu != null) LatLng(widget.eu!.latitude, widget.eu!.longitude),
      ];

  @override
  void didUpdateWidget(covariant Mapa anterior) {
    super.didUpdateWidget(anterior);
    // Chegou ponto novo — do GPS ou de uma corrida aceita — e o enquadramento
    // de antes pode ter deixado alguém de fora.
    if (_pronto && _todos.length != _pontosDe(anterior).length) _enquadrar();
  }

  List<LatLng> _pontosDe(Mapa w) => [
        for (final a in w.alfinetes) LatLng(a.ponto.latitude, a.ponto.longitude),
        if (w.eu != null) LatLng(w.eu!.latitude, w.eu!.longitude),
      ];

  void _enquadrar() {
    final pontos = _todos;
    if (pontos.isEmpty) return;
    if (pontos.length == 1) {
      _controle.move(pontos.first, 15);
      return;
    }
    _controle.fitCamera(
      CameraFit.coordinates(
        coordinates: pontos,
        padding: const EdgeInsets.all(56),
        maxZoom: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pontos = _todos;
    final centro = pontos.isEmpty
        // Goiânia: onde a base de demonstração vive. Só decide o enquadramento
        // inicial de um mapa ainda sem nada para mostrar.
        ? const LatLng(-16.6869, -49.2648)
        : pontos.first;

    final mapa = FlutterMap(
      mapController: _controle,
      options: MapOptions(
        initialCenter: centro,
        initialZoom: 14,
        interactionOptions: InteractionOptions(
          flags: widget.interativo
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onMapReady: () {
          _pronto = true;
          _enquadrar();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // A política de uso do OSM pede identificação de quem consome.
          userAgentPackageName: 'br.com.tronvix.tronvixFacil',
        ),
        MarkerLayer(
          markers: [
            for (final a in widget.alfinetes)
              Marker(
                point: LatLng(a.ponto.latitude, a.ponto.longitude),
                width: 40,
                height: 40,
                child: _Pino(icone: a.icone, cor: a.cor),
              ),
            if (widget.eu != null)
              Marker(
                point: LatLng(widget.eu!.latitude, widget.eu!.longitude),
                width: 24,
                height: 24,
                child: const _Eu(),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap'),
          ],
        ),
      ],
    );

    return widget.altura == null
        ? mapa
        : SizedBox(height: widget.altura, child: mapa);
  }
}

class _Pino extends StatelessWidget {
  const _Pino({required this.icone, required this.cor});
  final IconData icone;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: cor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icone, color: Colors.white, size: 20),
      );
}

class _Eu extends StatelessWidget {
  const _Eu();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
      );
}
