/// Endereços do cliente: lista e formulário.
library;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../comum/widgets.dart';
import '../dados/cep.dart';
import '../dados/enderecos.dart';
import '../dados/localizacao.dart';
import '../modelos/modelos.dart';
import '../tema.dart';

class TelaEnderecos extends StatefulWidget {
  const TelaEnderecos({super.key});

  @override
  State<TelaEnderecos> createState() => _TelaEnderecosState();
}

class _TelaEnderecosState extends State<TelaEnderecos> {
  List<Endereco> _enderecos = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final lista = await Enderecos.meus();
      if (mounted) {
        setState(() {
          _enderecos = lista;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        avisar(context, e.toString(), erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Endereços')),
        body: _carregando
            ? const Carregando()
            : _enderecos.isEmpty
                ? const Vazio(
                    icone: Icons.place_outlined,
                    titulo: 'Nenhum endereço salvo',
                    detalhe: 'Cadastre um para receber seus pedidos.',
                  )
                : ListView.separated(
                    itemCount: _enderecos.length,
                    separatorBuilder: (_, _) => const Divider(indent: 16),
                    itemBuilder: (_, i) {
                      final e = _enderecos[i];
                      return ListTile(
                        leading: Icon(
                          e.padrao ? Icons.home : Icons.place_outlined,
                          color: e.padrao ? Cores.marca : Cores.textoSuave,
                        ),
                        title: Row(
                          children: [
                            Text(e.rotulo,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (e.padrao) ...[
                              const SizedBox(width: 8),
                              const Etiqueta('Padrão', cor: Cores.marca),
                            ],
                          ],
                        ),
                        subtitle: Text(e.resumo),
                        trailing: PopupMenuButton<String>(
                          onSelected: (acao) async {
                            if (acao == 'padrao') {
                              await Enderecos.tornarPadrao(e.id);
                            } else if (acao == 'editar') {
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TelaEnderecoFormulario(endereco: e),
                                ),
                              );
                            } else if (acao == 'remover') {
                              await Enderecos.remover(e.id);
                            }
                            await _carregar();
                          },
                          itemBuilder: (_) => [
                            if (!e.padrao)
                              const PopupMenuItem(
                                  value: 'padrao',
                                  child: Text('Tornar padrão')),
                            const PopupMenuItem(
                                value: 'editar', child: Text('Editar')),
                            const PopupMenuItem(
                                value: 'remover', child: Text('Remover')),
                          ],
                        ),
                      );
                    },
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TelaEnderecoFormulario()),
            );
            await _carregar();
          },
          icon: const Icon(Icons.add),
          label: const Text('Novo endereço'),
        ),
      );
}

class TelaEnderecoFormulario extends StatefulWidget {
  const TelaEnderecoFormulario({super.key, this.endereco});
  final Endereco? endereco;

  @override
  State<TelaEnderecoFormulario> createState() => _TelaEnderecoFormularioState();
}

class _TelaEnderecoFormularioState extends State<TelaEnderecoFormulario> {
  final _formulario = GlobalKey<FormState>();
  late final _rotulo = TextEditingController(text: widget.endereco?.rotulo ?? 'Casa');
  late final _cep =
      TextEditingController(text: cepFormatado(widget.endereco?.cep ?? ''));
  late final _rua = TextEditingController(text: widget.endereco?.rua ?? '');
  late final _numero = TextEditingController(text: widget.endereco?.numero ?? '');
  late final _complemento =
      TextEditingController(text: widget.endereco?.complemento ?? '');
  late final _bairro = TextEditingController(text: widget.endereco?.bairro ?? '');
  late final _cidade = TextEditingController(text: widget.endereco?.cidade ?? '');
  late final _uf = TextEditingController(text: widget.endereco?.uf ?? '');
  late final _referencia =
      TextEditingController(text: widget.endereco?.referencia ?? '');
  late bool _padrao = widget.endereco?.padrao ?? false;
  late Ponto? _ponto = (widget.endereco?.latitude != null &&
          widget.endereco?.longitude != null)
      ? Ponto(widget.endereco!.latitude!, widget.endereco!.longitude!)
      : null;
  bool _salvando = false;
  bool _localizando = false;

  /// Quem recebe o foco depois que o CEP preenche o resto — é o único campo
  /// que a busca não tem como saber.
  final _focoDoNumero = FocusNode();

  bool _buscandoCep = false;
  String? _ultimoCepBuscado;
  String? _recadoDoCep;

  @override
  void initState() {
    super.initState();
    // Editando um endereço que já existe, o CEP dele não se busca de novo: os
    // campos ao lado podem ter sido ajustados à mão, e sobrescrevê-los seria
    // desfazer o trabalho de alguém.
    _ultimoCepBuscado = widget.endereco?.cep;
    // Busca assim que o oitavo dígito entra, sem esperar a pessoa sair do
    // campo: é o instante em que ela ainda está olhando para o CEP e entende
    // por que o resto se preencheu sozinho.
    _cep.addListener(_talvezBuscarCep);
  }

  @override
  void dispose() {
    _cep.removeListener(_talvezBuscarCep);
    _focoDoNumero.dispose();
    for (final c in [
      _rotulo, _cep, _rua, _numero, _complemento,
      _bairro, _cidade, _uf, _referencia,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _talvezBuscarCep() async {
    final texto = _cep.text;
    if (!cepCompleto(texto)) {
      if (_recadoDoCep != null) setState(() => _recadoDoCep = null);
      return;
    }

    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    // O listener dispara a cada tecla; sem esta guarda, apagar e redigitar o
    // último número buscaria de novo o mesmo CEP.
    if (digitos == _ultimoCepBuscado) return;
    _ultimoCepBuscado = digitos;

    setState(() {
      _buscandoCep = true;
      _recadoDoCep = null;
    });

    final achado = await Cep.buscar(digitos);
    if (!mounted) return;

    setState(() {
      _buscandoCep = false;
      if (achado == null) {
        // Sem drama: o endereço continua digitável.
        _recadoDoCep = 'Não achei esse CEP. Preencha à mão.';
        return;
      }
      if (achado.rua.isNotEmpty) _rua.text = achado.rua;
      if (achado.bairro.isNotEmpty) _bairro.text = achado.bairro;
      if (achado.cidade.isNotEmpty) _cidade.text = achado.cidade;
      _uf.text = achado.uf;
      _recadoDoCep = achado.temRua
          ? null
          // CEP de cidade inteira: achou, mas não tem rua para dar.
          : 'Esse CEP vale para a cidade toda. Escreva a rua.';
    });

    if (achado != null && achado.temRua && mounted) {
      _focoDoNumero.requestFocus();
    }
  }

  Future<void> _salvar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final salvo = await Enderecos.salvar(
        id: widget.endereco?.id,
        rotulo: _rotulo.text,
        rua: _rua.text,
        numero: _numero.text,
        bairro: _bairro.text,
        cidade: _cidade.text,
        uf: _uf.text,
        cep: _cep.text,
        complemento: _complemento.text,
        referencia: _referencia.text,
        padrao: _padrao,
        ponto: _ponto,
      );
      if (mounted) Navigator.of(context).pop(salvo);
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.endereco == null
                ? 'Novo endereço'
                : 'Editar endereço')),
        body: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _rotulo,
                decoration: const InputDecoration(
                    labelText: 'Nome do endereço', hintText: 'Casa, Trabalho…'),
                validator: _obrigatorio,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cep,
                keyboardType: TextInputType.number,
                inputFormatters: [_FormatadorDeCep()],
                decoration: InputDecoration(
                  labelText: 'CEP',
                  hintText: '00000-000',
                  helperText: _recadoDoCep,
                  helperMaxLines: 2,
                  helperStyle: const TextStyle(color: Cores.atencao),
                  suffixIcon: _buscandoCep
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : null,
                ),
                validator: (v) {
                  // O banco só aceita 8 dígitos, sem hífen
                  // (addresses_postal_code_digits). Recusar aqui é mais gentil
                  // do que deixar a gravação falhar no fim do formulário.
                  final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return d.length == 8 ? null : 'CEP com 8 dígitos';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rua,
                decoration: const InputDecoration(labelText: 'Rua'),
                validator: _obrigatorio,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _numero,
                      focusNode: _focoDoNumero,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(labelText: 'Número'),
                      validator: _obrigatorio,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _complemento,
                      decoration:
                          const InputDecoration(labelText: 'Complemento'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bairro,
                decoration: const InputDecoration(labelText: 'Bairro'),
                validator: _obrigatorio,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cidade,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                      validator: _obrigatorio,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _uf,
                      maxLength: 2,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'UF', counterText: ''),
                      validator: (v) =>
                          (v == null || v.length != 2) ? 'UF' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referencia,
                decoration: const InputDecoration(
                    labelText: 'Ponto de referência',
                    hintText: 'Ajuda o entregador a achar'),
              ),
              const SizedBox(height: 8),
              // O ponto no mapa é o que o entregador vê. Sem ele a corrida
              // funciona — o endereço está escrito — mas o mapa fica cego.
              OutlinedButton.icon(
                onPressed: _localizando ? null : _marcarNoMapa,
                icon: Icon(_ponto == null
                    ? Icons.my_location
                    : Icons.check_circle_outline),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ponto == null ? Cores.texto : Cores.sucesso,
                ),
                label: Text(_localizando
                    ? 'Procurando…'
                    : _ponto == null
                        ? 'Marcar no mapa com o GPS'
                        : 'Marcado no mapa'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _padrao,
                onChanged: (v) => setState(() => _padrao = v),
                title: const Text('Usar como endereço padrão'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _salvando ? null : _salvar,
                child: Text(_salvando ? 'Salvando…' : 'Salvar endereço'),
              ),
            ],
          ),
        ),
      );

  /// Pega a posição de quem está preenchendo.
  ///
  /// Só faz sentido quando a pessoa está *no* endereço — e é quase sempre o
  /// caso, porque endereço se cadastra na hora de pedir. Quando não for, o
  /// campo continua opcional.
  Future<void> _marcarNoMapa() async {
    setState(() => _localizando = true);
    final onde = await Localizacao.onde();
    if (!mounted) return;
    setState(() {
      _ponto = onde;
      _localizando = false;
    });
    if (onde == null && mounted) {
      avisar(context,
          'Não consegui pegar sua localização. O endereço escrito já serve.',
          erro: true);
    }
  }

  String? _obrigatorio(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Preencha este campo' : null;
}

/// Põe o hífen do CEP enquanto a pessoa digita, e não deixa passar de 8
/// dígitos. Formata na entrada, não na saída: o campo mostra 00000-000 e o
/// banco recebe só os dígitos.
class _FormatadorDeCep extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antes,
    TextEditingValue depois,
  ) {
    final formatado = cepFormatado(depois.text);
    return TextEditingValue(
      text: formatado,
      selection: TextSelection.collapsed(offset: formatado.length),
    );
  }
}
