/// Dinheiro, tempo e distância na forma como se lê em português.
///
/// Dinheiro **sempre** chega do banco em centavos, num inteiro. A conversão
/// para reais acontece só aqui, na borda de exibição, e nunca no sentido
/// contrário: nada neste aplicativo soma preço em `double`. É a mesma regra do
/// schema, e a razão está escrita lá — 0,1 + 0,2 não pode virar divergência de
/// caixa no fim do mês.
library;

import 'package:intl/intl.dart';


final _real = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

String emReais(int centavos) => _real.format(centavos / 100);

/// Para rótulos curtos onde o "R$" já está claro pelo contexto.
String emReaisCurto(int centavos) =>
    NumberFormat('#,##0.00', 'pt_BR').format(centavos / 100);

String distanciaKm(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

/// "há 3 min", "há 2 h", "ontem" — o balcão precisa saber há quanto tempo o
/// pedido está esperando, não em que instante exato ele nasceu.
String haQuantoTempo(DateTime quando) {
  final d = DateTime.now().difference(quando);
  if (d.inSeconds < 60) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  if (d.inDays < 7) return 'há ${d.inDays} dias';
  return DateFormat('d MMM', 'pt_BR').format(quando);
}

String dataHora(DateTime quando) =>
    DateFormat("d 'de' MMMM', às' HH:mm", 'pt_BR').format(quando);

/// A previsão de quando a comida fica pronta, para quem vai buscá-la.
///
/// É o número que decide se vale aceitar a corrida: com ele a pessoa sai na
/// hora de chegar junto com a comida, em vez de correr até a loja e esperar de
/// pé. O atraso aparece em vez de sumir — parar de mostrar bem na hora em que a
/// promessa furou seria esconder o que mais importa.
String prontoEmPalavras(DateTime previsao) {
  final d = previsao.difference(DateTime.now());
  if (d.inSeconds <= -60) {
    return 'Era para estar pronto há ${minutos(-d.inMinutes)}';
  }
  if (d.inSeconds < 60) return 'Fica pronto agora';
  return 'Fica pronto em ${minutos(d.inMinutes)}';
}

String minutos(int m) {
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// Faixa de tempo, do jeito que o cliente entende: "30–50 min".
String faixaDeMinutos(int preparo, int entrega) {
  final total = preparo + entrega;
  return '$total–${total + 20} min';
}

String telefone(String? digitos) {
  if (digitos == null || digitos.isEmpty) return '';
  final d = digitos.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  if (d.length == 10) return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  return d;
}
