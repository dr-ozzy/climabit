import 'package:flutter_test/flutter_test.dart';
import 'package:tempo_oficial/dados/astro.dart';

void main() {
  // Niterói, 14/11/2026, hora de Brasília (UTC-3). Referências: sol 05:02 e 18:14
  // (horário mostrado por outro app de tempo para Santa Rosa, Niterói); lua 09:00 e 22:51
  // e, em 3/11, 01:24 e 13:06 (tabela de time.tz/niteroi/moon, consultada em 14/11/2026).
  const lat = -22.905, lon = -43.105;
  final dia = DateTime.utc(2026, 11, 14, 15).toLocal();

  void perto(DateTime? t, DateTime ref, int minutos) {
    expect(t, isNotNull);
    final dif = t!.toUtc().difference(ref).inSeconds.abs() / 60;
    expect(dif, lessThanOrEqualTo(minutos), reason: 'calculado ${t.toUtc()}, referência $ref');
  }

  test('nascer e pôr do sol', () {
    final s = Astro.sol(dia, lat, lon);
    perto(s.nascer, DateTime.utc(2026, 11, 14, 8, 2), 3);
    perto(s.por, DateTime.utc(2026, 11, 14, 21, 14), 3);
  });

  test('nascer e pôr da lua', () {
    final l = Astro.lua(dia, lat, lon);
    perto(l.nascer, DateTime.utc(2026, 11, 14, 12, 0), 4);
    perto(l.por, DateTime.utc(2026, 11, 15, 1, 51), 4);
    final l3 = Astro.lua(DateTime.utc(2026, 11, 3, 15).toLocal(), lat, lon);
    perto(l3.nascer, DateTime.utc(2026, 11, 3, 4, 24), 4);
    perto(l3.por, DateTime.utc(2026, 11, 3, 16, 6), 4);
  });

  test('dia e noite', () {
    expect(Astro.noite(DateTime.utc(2026, 11, 14, 15), lat, lon), isFalse);
    expect(Astro.noite(DateTime.utc(2026, 11, 15, 2), lat, lon), isTrue);
  });
}
