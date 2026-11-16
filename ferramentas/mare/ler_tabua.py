"""Lê a tábua de marés (texto extraído com pdftotext -raw) e grava CSV: data_hora_local,altura_m."""
import re, sys, datetime as dt, collections

MESES = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto',
         'setembro', 'outubro', 'novembro', 'dezembro']
SEMANA = {'DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'}


def norm(t):
    return (t.replace('�', 'A').replace('ç', 'c').replace('Ç', 'C').replace('ã', 'a')
            .replace('Á', 'A').replace('á', 'a'))


def ler(caminho, ano):
    texto = open(caminho, encoding='latin-1').read()
    toks = texto.split()
    mes = None
    dia = None
    dados = []
    i = 0
    while i < len(toks):
        t = norm(toks[i])
        tl = t.lower().replace('mara', 'marc')  # "Mar?o" -> "Marao" -> ajuste abaixo
        if tl in MESES or t.lower() in ('marao',):
            mes = 3 if t.lower() == 'marao' else MESES.index(tl) + 1
            dia = None
            i += 1
            continue
        if re.fullmatch(r'\d{1,2}', t) and i + 1 < len(toks) and norm(toks[i + 1]).upper() in SEMANA:
            dia = int(t)
            i += 2
            continue
        if re.fullmatch(r'\d{4}', t) and i + 1 < len(toks) and re.fullmatch(r'-?\d\.\d\d', toks[i + 1]):
            if mes and dia:
                h, m = int(t[:2]), int(t[2:])
                dados.append((dt.datetime(ano, mes, dia, h, m), float(toks[i + 1])))
            i += 2
            continue
        i += 1
    return dados


if __name__ == '__main__':
    dados = ler(sys.argv[1], int(sys.argv[2]))
    dados.sort()
    porDia = collections.Counter(d.date() for d, _ in dados)
    print('marés lidas:', len(dados), 'dias:', len(porDia))
    print('dias com contagem estranha:', [(str(k), v) for k, v in porDia.items() if v < 2 or v > 5][:10])
    faltam = [str(dt.date(int(sys.argv[2]), 1, 1) + dt.timedelta(n)) for n in range(365)
              if dt.date(int(sys.argv[2]), 1, 1) + dt.timedelta(n) not in porDia]
    print('dias faltando:', len(faltam), faltam[:10])
    # alternância cheia/vazante
    ruins = 0
    for a, b, c in zip(dados, dados[1:], dados[2:]):
        if not ((b[1] > a[1] and b[1] > c[1]) or (b[1] < a[1] and b[1] < c[1])):
            ruins += 1
    print('pontos que não alternam:', ruins)
    gaps = [(str(a[0]), (b[0] - a[0]).total_seconds() / 3600) for a, b in zip(dados, dados[1:])
            if (b[0] - a[0]).total_seconds() / 3600 > 9 or (b[0] - a[0]).total_seconds() <= 0]
    print('intervalos estranhos:', len(gaps), gaps[:8])
    with open(sys.argv[3], 'w') as f:
        for d, h in dados:
            f.write(f'{d.isoformat()},{h}\n')
