/// Cadastro do entregador autônomo.
///
/// Espelho de src/components/entregador/formulario-do-autonomo.tsx. As fotos
/// sobem direto do aparelho para o balde privado, na pasta da própria pessoa,
/// e o cadastro manda só os caminhos. Quem confere tudo — CPF, idade, cidade,
/// placa, documentos na pasta certa — é o banco, em
/// `cadastrar_entregador_autonomo`.
///
/// Serve também para reenviar: o recusado volta aqui, lê o motivo e corrige.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../comum/widgets.dart';
import '../dados/corridas.dart';
import '../sessao.dart';
import '../tema.dart';
import 'cadastro.dart';

const _veiculos = {
  'motorcycle': 'Moto',
  'car': 'Carro',
  'bicycle': 'Bicicleta',
  'foot': 'A pé',
};

enum _Documento { cnh, veiculo, selfie }

class TelaCadastroAutonomo extends StatefulWidget {
  const TelaCadastroAutonomo({super.key, this.motivoDaRecusa});

  /// Preenchido quando a pessoa volta para corrigir.
  final String? motivoDaRecusa;

  @override
  State<TelaCadastroAutonomo> createState() => _TelaCadastroAutonomoState();
}

class _TelaCadastroAutonomoState extends State<TelaCadastroAutonomo> {
  final _cpf = TextEditingController();
  final _nascimento = TextEditingController();
  final _placa = TextEditingController();
  final _modelo = TextEditingController();
  final _cor = TextEditingController();
  final _pix = TextEditingController();

  List<String> _cidades = const [];
  String? _cidade;
  String _veiculo = 'motorcycle';
  final Map<_Documento, String> _documentos = {};
  _Documento? _enviandoFoto;
  bool _carregando = true;
  bool _enviando = false;
  Object? _erro;

  bool get _motorizado => _veiculo == 'motorcycle' || _veiculo == 'car';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_cpf, _nascimento, _placa, _modelo, _cor, _pix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final cidades = await Corridas.cidadesAtendidas();
      if (!mounted) return;
      setState(() {
        _cidades = cidades;
        _cidade = cidades.isEmpty ? null : cidades.first;
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

  Future<void> _fotografar(_Documento tipo) async {
    // Câmera, e não galeria, por padrão: a foto tirada agora é a do documento
    // que está na mão. Quem já tem a foto escolhe "galeria" na folha.
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(folha, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(folha, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origem == null) return;

    final foto = await ImagePicker().pickImage(
      source: origem,
      // 1600 px e 85%: o bastante para ler o número da CNH, sem subir os
      // megabytes da câmera pelo 4G de quem está na rua.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      preferredCameraDevice: tipo == _Documento.selfie
          ? CameraDevice.front
          : CameraDevice.rear,
    );
    if (foto == null) return;

    setState(() => _enviandoFoto = tipo);
    try {
      final caminho = await Corridas.enviarDocumento(
        await foto.readAsBytes(),
        tipo.name,
      );
      if (mounted) setState(() => _documentos[tipo] = caminho);
    } catch (e) {
      if (mounted) {
        avisar(
          context,
          'Não consegui enviar a foto. Tente de novo.',
          erro: true,
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoFoto = null);
    }
  }

  /// "31/12/1995" para "1995-12-31". Nulo se a data não existe.
  String? _dataNoBanco(String texto) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(texto.trim());
    if (m == null) return null;
    final data = DateTime.tryParse('${m[3]}-${m[2]}-${m[1]}');
    if (data == null || data.day != int.parse(m[1]!)) return null;
    return '${m[3]}-${m[2]}-${m[1]}';
  }

  Future<void> _enviar() async {
    final nascimento = _dataNoBanco(_nascimento.text);
    final faltando = [
      if (_cpf.text.replaceAll(RegExp(r'\D'), '').length != 11) 'o CPF',
      if (nascimento == null) 'a data de nascimento (dd/mm/aaaa)',
      if (_cidade == null) 'a cidade',
      if (_motorizado && _placa.text.trim().isEmpty) 'a placa',
      if (_motorizado && _modelo.text.trim().isEmpty) 'o modelo',
      if (_motorizado && _cor.text.trim().isEmpty) 'a cor',
      if (_pix.text.trim().length < 5) 'a chave Pix',
      if (_documentos[_Documento.cnh] == null) 'a foto do documento',
      if (_motorizado && _documentos[_Documento.veiculo] == null)
        'a foto do documento do veículo',
      if (_documentos[_Documento.selfie] == null) 'a selfie',
    ];
    if (faltando.isNotEmpty) {
      avisar(context, 'Falta ${faltando.first}.', erro: true);
      return;
    }

    setState(() => _enviando = true);
    try {
      await Corridas.cadastrarAutonomo(
        cpf: _cpf.text,
        nascimento: nascimento!,
        tipoDeVeiculo: _veiculo,
        placa: _placa.text,
        modelo: _modelo.text,
        cor: _cor.text,
        cidade: _cidade!,
        chavePix: _pix.text,
        cnh: _documentos[_Documento.cnh]!,
        documentoDoVeiculo: _motorizado
            ? _documentos[_Documento.veiculo]
            : null,
        selfie: _documentos[_Documento.selfie]!,
      );
      await Sessao.instancia.carregar();
      if (mounted) cadastroEnviado(context);
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
      return Scaffold(
        body: Falhou(erro: _erro!, aoTentarDeNovo: _carregar),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Entregador autônomo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.motivoDaRecusa != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Cores.perigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Cores.perigo.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Seu cadastro precisa de correção: ${widget.motivoDaRecusa}',
                style: const TextStyle(height: 1.4),
              ),
            ),
          const Text(
            'Você entrega para os estabelecimentos da sua cidade que aceitam '
            'entregadores da plataforma. A equipe do Tronvix Fácil confere os '
            'documentos e aprova o cadastro.',
            style: TextStyle(color: Cores.textoSuave, height: 1.45),
          ),
          _titulo('Seus dados'),
          TextField(
            controller: _cpf,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
            ],
            decoration: const InputDecoration(
              labelText: 'CPF',
              hintText: '000.000.000-00',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nascimento,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Data de nascimento',
              hintText: 'dd/mm/aaaa',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cidade,
            decoration: const InputDecoration(
              labelText: 'Cidade onde vai entregar',
            ),
            items: [
              for (final c in _cidades)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _cidade = v),
          ),
          _titulo('Como você entrega'),
          Wrap(
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
          if (_motorizado) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _placa,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Placa',
                hintText: 'ABC1D23',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelo,
                    decoration: const InputDecoration(
                      labelText: 'Modelo',
                      hintText: 'CG 160',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cor,
                    decoration: const InputDecoration(
                      labelText: 'Cor',
                      hintText: 'Vermelha',
                    ),
                  ),
                ),
              ],
            ),
          ],
          _titulo('Documentos'),
          const Text(
            'As fotos ficam guardadas em sigilo: só você e a equipe que aprova '
            'o cadastro veem.',
            style: TextStyle(color: Cores.textoSuave, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _foto(
            _Documento.cnh,
            _motorizado ? 'CNH' : 'Documento com foto',
            _motorizado ? 'Foto da CNH aberta, legível' : 'RG ou CNH, legível',
          ),
          if (_motorizado)
            _foto(
              _Documento.veiculo,
              'Documento do veículo (CRLV)',
              'Foto do documento da moto ou do carro',
            ),
          _foto(
            _Documento.selfie,
            'Selfie segurando o documento',
            'Seu rosto e o documento aparecendo juntos',
          ),
          _titulo('Para receber'),
          TextField(
            controller: _pix,
            decoration: const InputDecoration(
              labelText: 'Chave Pix',
              hintText: 'CPF, celular, e-mail ou chave aleatória',
            ),
          ),
        ],
      ),
      bottomNavigationBar: BarraDeAcao(
        filho: FilledButton(
          onPressed: _enviando || _enviandoFoto != null ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar cadastro para análise'),
        ),
      ),
    );
  }

  Widget _foto(_Documento tipo, String rotulo, String dica) {
    final enviada = _documentos[tipo] != null;
    final enviando = _enviandoFoto == tipo;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: enviando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Icon(
                enviada ? Icons.check_circle : Icons.photo_camera_outlined,
                color: enviada ? Cores.sucesso : Cores.textoSuave,
              ),
        title: Text(
          rotulo,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(enviada ? 'Enviada. Toque para trocar.' : dica),
        onTap: _enviandoFoto != null ? null : () => _fotografar(tipo),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
    child: Text(
      texto,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
