/// Cadastro de entregador.
///
/// A pessoa escolhe para qual estabelecimento quer levar comida, e o cadastro
/// nasce pendente. Quem aprova é o estabelecimento — está no banco, em
/// `app.guard_courier_platform_fields`, e a razão é simples: é ele quem conhece
/// a pessoa e é o dinheiro dele que vai na mochila.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';

const _veiculos = {
  'motorcycle': 'Moto',
  'bicycle': 'Bicicleta',
  'car': 'Carro',
  'foot': 'A pé',
};

class TelaCadastroDeEntregador extends StatefulWidget {
  const TelaCadastroDeEntregador({super.key});

  @override
  State<TelaCadastroDeEntregador> createState() =>
      _TelaCadastroDeEntregadorState();
}

class _TelaCadastroDeEntregadorState extends State<TelaCadastroDeEntregador> {
  final _placa = TextEditingController();

  List<Restaurante> _estabelecimentos = const [];
  String? _escolhido;
  String _veiculo = 'motorcycle';
  bool _carregando = true;
  bool _enviando = false;
  Object? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _placa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final lista = await Corridas.estabelecimentosParaCadastro();
      if (!mounted) return;
      setState(() {
        _estabelecimentos = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  Future<void> _enviar() async {
    if (_escolhido == null) {
      avisar(context, 'Escolha para onde você quer entregar.', erro: true);
      return;
    }

    setState(() => _enviando = true);
    try {
      await Corridas.cadastrar(
        restauranteId: _escolhido!,
        tipoDeVeiculo: _veiculo,
        placa: _placa.text,
      );
      await Sessao.instancia.carregar();
      if (mounted) avisar(context, 'Cadastro enviado. Aguarde a aprovação.');
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Scaffold(body: Carregando());
    if (_erro != null) {
      return Scaffold(body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Entregar pelo Tronvix Fácil')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Você entrega para um estabelecimento. É ele que aprova seu '
              'cadastro e é dele que vêm as corridas.',
              style: TextStyle(color: Cores.textoSuave, height: 1.45),
            ),
          ),
          _titulo('Para onde você quer entregar'),
          if (_estabelecimentos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhum estabelecimento aprovado ainda.',
                  style: TextStyle(color: Cores.textoSuave)),
            )
          else
            RadioGroup<String>(
              groupValue: _escolhido,
              onChanged: (v) => setState(() => _escolhido = v),
              child: Column(
                children: [
                  for (final r in _estabelecimentos)
                    RadioListTile<String>(
                      value: r.id,
                      title: Text(r.nome,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [r.bairro, r.cidade].whereType<String>().join(', '),
                        style: const TextStyle(fontSize: 13),
                      ),
                      secondary: Foto(
                          url: r.logoUrl,
                          largura: 40,
                          altura: 40,
                          icone: Icons.storefront),
                    ),
                ],
              ),
            ),
          _titulo('Como você entrega'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final v in _veiculos.entries)
                  ChoiceChip(
                    label: Text(v.value),
                    selected: _veiculo == v.key,
                    onSelected: (_) => setState(() => _veiculo = v.key),
                  ),
              ],
            ),
          ),
          if (_veiculo == 'motorcycle' || _veiculo == 'car')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _placa,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Placa', hintText: 'ABC1D23'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar cadastro'),
        ),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(texto,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}
