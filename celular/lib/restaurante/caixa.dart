/// O caixa do balcão: fundo de caixa, recebimentos e sangrias do dia, e o
/// dinheiro que tem de estar na gaveta.
library;

import 'package:flutter/material.dart';

import '../comum/widgets.dart';
import '../dados/balcao.dart';
import '../dados/caixa.dart';
import '../dados/supabase.dart';
import '../formato.dart';
import '../modelos/modelos.dart';
import '../sessao.dart';
import '../tema.dart';

/// Pergunta quanto e como o cliente pagou, e registra o recebimento.
///
/// O valor já vem com tudo o que falta, porque quase sempre é isso: um
/// cliente, uma forma, a conta inteira. A mesa que divide troca o valor e
/// recebe uma parte; a próxima parte — até a mesma, cinquenta e cinquenta —
/// entra como outro recebimento.
///
/// A forma já vem marcada com o que foi escolhido no aplicativo, mas fica
/// trocável: quem pediu em dinheiro e passou o cartão tem de entrar no caixa
/// como cartão, senão a gaveta não bate.
///
/// Devolve true quando recebeu alguma coisa (a conta inteira ou uma parte).
Future<bool> receberPagamento(
  BuildContext context, {
  required String pedidoId,
  required int numero,
  required int faltaCentavos,
  int recebidoCentavos = 0,
  FormaDePagamento? formaPedida,
}) async {
  final escolha = await showModalBottomSheet<(FormaDePagamento, int)>(
    context: context,
    showDragHandle: true,
    // O teclado sobe por cima do campo de valor sem isto.
    isScrollControlled: true,
    builder: (_) => _FolhaDeRecebimento(
      numero: numero,
      faltaCentavos: faltaCentavos,
      recebidoCentavos: recebidoCentavos,
      formaPedida: formaPedida,
    ),
  );

  if (escolha == null) return false;
  final (forma, valor) = escolha;

  try {
    final falta = await Balcao.receberParte(pedidoId, forma, valor);
    if (context.mounted) {
      avisar(
        context,
        falta == 0
            ? 'Recebido: ${emReais(valor)} em ${forma.rotulo.toLowerCase()}. Conta fechada.'
            : 'Recebido: ${emReais(valor)} em ${forma.rotulo.toLowerCase()}. '
                'Falta ${emReais(falta)}.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) avisar(context, e.toString(), erro: true);
    return false;
  }
}

class _FolhaDeRecebimento extends StatefulWidget {
  const _FolhaDeRecebimento({
    required this.numero,
    required this.faltaCentavos,
    required this.recebidoCentavos,
    this.formaPedida,
  });

  final int numero;
  final int faltaCentavos;
  final int recebidoCentavos;
  final FormaDePagamento? formaPedida;

  @override
  State<_FolhaDeRecebimento> createState() => _FolhaDeRecebimentoState();
}

class _FolhaDeRecebimentoState extends State<_FolhaDeRecebimento> {
  late final _valor =
      TextEditingController(text: emReaisCurto(widget.faltaCentavos));
  late FormaDePagamento _forma = widget.formaPedida ?? FormaDePagamento.values.first;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  int? get _centavos => paraCentavos(_valor.text);

  void _confirmar() {
    final valor = _centavos;
    final erro = erroDaParte(valor, widget.faltaCentavos);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(context, (_forma, valor!));
  }

  @override
  Widget build(BuildContext context) {
    final valor = _centavos;
    final tudo = valor == widget.faltaCentavos;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Receber · nº ${widget.numero}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  widget.recebidoCentavos > 0
                      ? 'Já recebido ${emReais(widget.recebidoCentavos)} · '
                          'falta ${emReais(widget.faltaCentavos)}'
                      : 'Conta de ${emReais(widget.faltaCentavos)}',
                  style: const TextStyle(color: Cores.textoSuave),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _valor,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quanto o cliente pagou',
                    prefixText: 'R\$ ',
                    errorText: _erro,
                  ),
                  onChanged: (_) => setState(() => _erro = null),
                  onTap: () => _valor.selection =
                      TextSelection(baseOffset: 0, extentOffset: _valor.text.length),
                ),
              ),
              // Os atalhos da mesa que divide: a conta toda, ou a metade dela.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: Text('Tudo · ${emReais(widget.faltaCentavos)}'),
                      onPressed: () => setState(() {
                        _valor.text = emReaisCurto(widget.faltaCentavos);
                        _erro = null;
                      }),
                    ),
                    if (widget.faltaCentavos >= 2)
                      ActionChip(
                        label: Text('Metade · ${emReais(widget.faltaCentavos ~/ 2)}'),
                        onPressed: () => setState(() {
                          _valor.text = emReaisCurto(widget.faltaCentavos ~/ 2);
                          _erro = null;
                        }),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Como o cliente pagou?',
                  style: TextStyle(color: Cores.textoSuave),
                ),
              ),
              for (final f in FormaDePagamento.values)
                ListTile(
                  leading: Icon(
                    f == _forma ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: Cores.marca,
                  ),
                  title: Text(f.rotulo),
                  subtitle: f == widget.formaPedida
                      ? const Text('O que o cliente escolheu')
                      : null,
                  onTap: () => setState(() => _forma = f),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _confirmar,
                    child: Text(
                      tudo
                          ? 'Receber ${emReais(widget.faltaCentavos)}'
                          : valor != null && valor > 0
                              ? 'Receber parte de ${emReais(valor)}'
                              : 'Receber',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hora(DateTime quando) {
  final local = quando.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class TelaCaixa extends StatefulWidget {
  const TelaCaixa({super.key});

  @override
  State<TelaCaixa> createState() => _TelaCaixaState();
}

class _TelaCaixaState extends State<TelaCaixa> {
  MovimentoDoCaixa? _movimento;
  RealtimeChannel? _canal;
  bool _carregando = true;
  Object? _erro;

  String? get _restauranteId => Sessao.instancia.vinculo?.restauranteId;
  bool get _gerencia => Sessao.instancia.vinculo?.papel.gerencia == true;

  @override
  void initState() {
    super.initState();
    _carregar();
    final id = _restauranteId;
    if (id != null) _canal = Caixa.acompanhar(id, _carregar);
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) banco.removeChannel(canal);
    super.dispose();
  }

  Future<void> _carregar() async {
    final id = _restauranteId;
    if (id == null) return;
    try {
      final movimento = await Caixa.movimento(id);
      if (!mounted) return;
      setState(() {
        _movimento = movimento;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _movimento;

    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
      body: _carregando
          ? const Carregando()
          : _erro != null
          ? Falhou(erro: _erro!, aoTentarDeNovo: _carregar)
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _placar(m!),
                  _acoes(m),
                  _titulo('A receber', m.aReceber.length),
                  if (m.aReceber.isEmpty)
                    _vazio(
                      'Nada pendente. Todo pedido de hoje já foi recebido.',
                    )
                  else
                    for (final r in m.aReceber) _aReceber(r),
                  _titulo('Fundo e sangrias', m.lancamentos.length),
                  if (m.lancamentos.isEmpty)
                    _vazio('Nada lançado hoje. Comece pelo fundo de caixa.')
                  else
                    for (final l in m.lancamentos.reversed) _lancamento(l),
                  _titulo('Recebidos', m.recebimentos.length),
                  if (m.recebimentos.isEmpty)
                    _vazio('Nenhum pagamento recebido hoje.')
                  else
                    for (final r in m.recebimentos.reversed) _recebido(r),
                ],
              ),
            ),
    );
  }

  Widget _placar(MovimentoDoCaixa m) => Container(
    margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Cores.suave,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dinheiro na gaveta',
          style: TextStyle(
            fontSize: 12,
            color: Cores.textoSuave,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          emReais(m.dinheiroNaGavetaCentavos),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _linha('Fundo de caixa', m.fundoCentavos),
        _linha('Recebido em dinheiro', m.porForma(FormaDePagamento.dinheiro)),
        _linha('Sangrias', -m.sangriasCentavos),
        const Divider(height: 20),
        for (final f in FormaDePagamento.values)
          _linha(f.rotulo, m.porForma(f)),
        _linha('Total recebido', m.recebidoCentavos, forte: true),
        _linha('A receber', m.aReceberCentavos),
      ],
    ),
  );

  Widget _linha(String rotulo, int centavos, {bool forte = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            rotulo,
            style: TextStyle(fontWeight: forte ? FontWeight.w800 : null),
          ),
        ),
        Text(
          centavos < 0 ? '− ${emReais(-centavos)}' : emReais(centavos),
          style: TextStyle(
            fontWeight: forte ? FontWeight.w800 : FontWeight.w700,
            color: centavos < 0 ? Cores.perigo : null,
          ),
        ),
      ],
    ),
  );

  Widget _acoes(MovimentoDoCaixa m) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        if (!m.temFundo) ...[
          Expanded(
            child: FilledButton.icon(
              onPressed: _registrarFundo,
              icon: const Icon(Icons.savings_outlined),
              label: const Text('Fundo de caixa'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _registrarSangria,
            icon: const Icon(Icons.output_outlined),
            label: const Text('Sangria'),
          ),
        ),
      ],
    ),
  );

  Widget _titulo(String texto, int quantos) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(
      '$texto · $quantos',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
  );

  Widget _vazio(String texto) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Text(texto, style: const TextStyle(color: Cores.textoSuave)),
  );

  Widget _aReceber(PedidoNoCaixa r) => ListTile(
    title: Text(
      'nº ${r.numero} · ${r.cliente}',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(
      r.recebidoCentavos > 0
          ? '${r.destino} · já recebido ${emReais(r.recebidoCentavos)}'
          : '${r.destino} · pediu em ${r.forma.rotulo.toLowerCase()}',
    ),
    trailing: FilledButton(
      onPressed: () async {
        final recebeu = await receberPagamento(
          context,
          pedidoId: r.pedidoId,
          numero: r.numero,
          faltaCentavos: r.valorCentavos,
          recebidoCentavos: r.recebidoCentavos,
          formaPedida: r.forma,
        );
        if (recebeu) _carregar();
      },
      child: Text('Receber ${emReais(r.valorCentavos)}'),
    ),
  );

  Widget _lancamento(LancamentoDoCaixa l) {
    final riscado = TextStyle(
      decoration: l.cancelado ? TextDecoration.lineThrough : null,
      color: l.cancelado ? Cores.textoSuave : null,
    );
    final sangria = l.tipo == TipoDeLancamento.sangria;
    return ListTile(
      dense: true,
      leading: Text(
        _hora(l.feitoEm),
        style: const TextStyle(color: Cores.textoSuave),
      ),
      title: Text(l.tipo.rotulo, style: riscado),
      subtitle: Text(
        [
          if (l.observacao != null) l.observacao!,
          if (l.feitoPor != null) l.feitoPor!,
          if (l.cancelado) 'cancelado',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sangria ? '− ' : ''}${emReais(l.valorCentavos)}',
            style: riscado.copyWith(
              fontWeight: FontWeight.w700,
              color: l.cancelado
                  ? Cores.textoSuave
                  : (sangria ? Cores.perigo : null),
            ),
          ),
          // Cancelar é da gestão; o banco confere de novo.
          if (_gerencia && !l.cancelado)
            IconButton(
              tooltip: 'Cancelar lançamento',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: () => _cancelar(l),
            ),
        ],
      ),
    );
  }

  Widget _recebido(PedidoNoCaixa r) => ListTile(
    dense: true,
    leading: Text(
      r.pagoEm == null ? '' : _hora(r.pagoEm!),
      style: const TextStyle(color: Cores.textoSuave),
    ),
    title: Text('nº ${r.numero} · ${r.cliente}'),
    subtitle: Text(r.forma.rotulo + (r.pelaInternet ? ' · pelo app' : '')),
    trailing: Text(
      emReais(r.valorCentavos),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  /// Valor (e, na sangria, motivo) num diálogo só.
  Future<({int centavos, String motivo})?> _perguntar({
    required String titulo,
    required String explicacao,
    required bool pedeMotivo,
  }) {
    final valor = TextEditingController();
    final motivo = TextEditingController();
    String? erro;

    return showDialog<({int centavos, String motivo})>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, mudar) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                explicacao,
                style: const TextStyle(fontSize: 13.5, color: Cores.textoSuave),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: valor,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'Valor',
                  prefixText: 'R\$ ',
                  errorText: erro,
                ),
              ),
              if (pedeMotivo)
                TextField(
                  controller: motivo,
                  decoration: const InputDecoration(hintText: 'Motivo'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () {
                final centavos = paraCentavos(valor.text);
                if (centavos == null || centavos <= 0) {
                  mudar(() => erro = 'Informe um valor maior que zero.');
                  return;
                }
                if (pedeMotivo && motivo.text.trim().length < 3) {
                  mudar(() => erro = 'Diga o motivo — vai para o relatório.');
                  return;
                }
                Navigator.pop(contexto, (
                  centavos: centavos,
                  motivo: motivo.text.trim(),
                ));
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registrarFundo() async {
    final id = _restauranteId;
    if (id == null) return;
    final r = await _perguntar(
      titulo: 'Fundo de caixa',
      explicacao:
          'O dinheiro que fica na gaveta para troco, antes do primeiro cliente.',
      pedeMotivo: false,
    );
    if (r == null) return;
    await _executar(
      () => Caixa.registrarFundo(id, r.centavos),
      'Fundo de ${emReais(r.centavos)} registrado.',
    );
  }

  Future<void> _registrarSangria() async {
    final id = _restauranteId;
    if (id == null) return;
    final r = await _perguntar(
      titulo: 'Sangria',
      explicacao:
          'Dinheiro que sai da gaveta — para o cofre, para o banco, para um '
          'fornecedor. Na gaveta agora: '
          '${emReais(_movimento?.dinheiroNaGavetaCentavos ?? 0)}.',
      pedeMotivo: true,
    );
    if (r == null) return;
    await _executar(
      () => Caixa.registrarSangria(id, r.centavos, r.motivo),
      'Sangria de ${emReais(r.centavos)} registrada.',
    );
  }

  Future<void> _cancelar(LancamentoDoCaixa l) async {
    final certeza = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cancelar lançamento'),
        content: Text(
          'Cancelar ${l.tipo.rotulo.toLowerCase()} de '
          '${emReais(l.valorCentavos)}? Ele continua no relatório, riscado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.perigo),
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Cancelar lançamento'),
          ),
        ],
      ),
    );
    if (certeza != true) return;
    await _executar(() => Caixa.cancelar(l.id), 'Lançamento cancelado.');
  }

  Future<void> _executar(Future<void> Function() acao, String sucesso) async {
    try {
      await acao();
      if (mounted) avisar(context, sucesso);
      await _carregar();
    } catch (e) {
      if (mounted) avisar(context, e.toString(), erro: true);
    }
  }
}
