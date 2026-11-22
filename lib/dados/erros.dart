/// Explica em português a causa provável de uma falha de consulta, a partir do texto do
/// erro guardado em `EstadoFonte.erro` (ideia tirada de outro app de clima: dizer a causa
/// em vez de só "não respondeu").
String causaDoErro(String? erro) {
  if (erro == null) return 'sem resposta';
  final e = erro.toLowerCase();
  if (e.contains('sem cópia guardada')) return 'sem internet e sem dados guardados';
  if (e.contains('handshake') || e.contains('certificate') || e.contains('certificado')) {
    return 'conexão segura recusada; confira se a data e a hora do celular estão certas';
  }
  if (e.contains('failed host lookup') ||
      e.contains('socketexception') ||
      e.contains('network is unreachable') ||
      e.contains('connection refused') ||
      e.contains('no address associated') ||
      e.contains('clientexception')) {
    return 'sem internet (ou a rede bloqueou o endereço)';
  }
  if (e.contains('timeout')) return 'demorou demais para responder';
  final codigo = RegExp(r'código (\d{3})').firstMatch(e)?.group(1);
  if (codigo != null) {
    if (codigo.startsWith('5')) return 'o site da fonte está fora do ar (erro $codigo)';
    if (codigo == '403' || codigo == '429') {
      return 'a fonte recusou o acesso automático agora (erro $codigo); tente mais tarde';
    }
    if (codigo == '404') return 'a fonte mudou de endereço (erro 404)';
    return 'a fonte respondeu com erro $codigo';
  }
  if (e.contains('formato inesperado')) return 'a fonte mudou o formato dos dados';
  return 'sem resposta';
}
