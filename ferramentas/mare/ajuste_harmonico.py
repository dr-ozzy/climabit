"""Constantes harmônicas a partir das preamares e baixa-mares da tábua oficial.

Uso: python ajuste.py <csv> <saida.json> [mes_corte]
Com mes_corte, ajusta só até esse mês e testa nos meses seguintes.
"""
import sys, json, math, datetime as dt
import numpy as np

# (nome, números de Doodson: tau, s, h, p, N', p1)
CONST = [
    ('Sa', (0, 0, 1, 0, 0, 0)), ('Ssa', (0, 0, 2, 0, 0, 0)), ('Mm', (0, 1, 0, -1, 0, 0)),
    ('MSf', (0, 2, -2, 0, 0, 0)), ('Mf', (0, 2, 0, 0, 0, 0)),
    ('2Q1', (1, -3, 0, 2, 0, 0)), ('Q1', (1, -2, 0, 1, 0, 0)), ('RHO1', (1, -2, 2, -1, 0, 0)),
    ('O1', (1, -1, 0, 0, 0, 0)), ('P1', (1, 1, -2, 0, 0, 0)), ('K1', (1, 1, 0, 0, 0, 0)),
    ('J1', (1, 2, 0, -1, 0, 0)), ('OO1', (1, 3, 0, 0, 0, 0)),
    ('2N2', (2, -2, 0, 2, 0, 0)), ('MU2', (2, -2, 2, 0, 0, 0)), ('N2', (2, -1, 0, 1, 0, 0)),
    ('NU2', (2, -1, 2, -1, 0, 0)), ('M2', (2, 0, 0, 0, 0, 0)), ('L2', (2, 1, 0, -1, 0, 0)),
    ('T2', (2, 2, -3, 0, 0, 1)), ('S2', (2, 2, -2, 0, 0, 0)), ('R2', (2, 2, -1, 0, 0, -1)),
    ('K2', (2, 2, 0, 0, 0, 0)), ('2SM2', (2, 4, -4, 0, 0, 0)),
    ('MO3', (3, -1, 0, 0, 0, 0)), ('M3', (3, 0, 0, 0, 0, 0)), ('MK3', (3, 1, 0, 0, 0, 0)),
    ('SK3', (3, 3, -2, 0, 0, 0)),
    ('MN4', (4, -1, 0, 1, 0, 0)), ('M4', (4, 0, 0, 0, 0, 0)), ('MS4', (4, 2, -2, 0, 0, 0)),
    ('MK4', (4, 2, 0, 0, 0, 0)), ('S4', (4, 4, -4, 0, 0, 0)),
    ('2MN6', (6, -1, 0, 1, 0, 0)), ('M6', (6, 0, 0, 0, 0, 0)), ('2MS6', (6, 2, -2, 0, 0, 0)),
    ('M8', (8, 0, 0, 0, 0, 0)),
    ('S1', (1, 1, -1, 0, 0, 0)), ('NO1', (1, 0, 0, 1, 0, 0)), ('SO1', (1, 3, -2, 0, 0, 0)),
    ('MKS2', (2, 0, 2, 0, 0, 0)), ('MSN2', (2, 3, -2, -1, 0, 0)), ('2MK5', (5, 1, 0, 0, 0, 0)), ('3MK7', (7, 1, 0, 0, 0, 0)),
]

J2000 = dt.datetime(2000, 1, 1, 12)


def astro(t):
    """Argumentos astronômicos (graus) para datas em UTC (array de horas desde J2000)."""
    T = t / (24 * 36525.0)
    s = 218.3165 + 481267.8813 * T
    h = 280.4661 + 36000.7698 * T
    p = 83.3535 + 4069.0137 * T
    N = 125.0445 - 1934.1363 * T
    p1 = 282.9384 + 1.7195 * T
    horaUT = np.mod(t + 12.0, 24.0)  # J2000 é meio-dia
    tau = 15.0 * horaUT + 180.0 + h - s
    return tau, s, h, p, N, p1


def nodal(nome, N):
    n = np.radians(N)
    c, s_ = np.cos, np.sin
    fM2 = 1.0004 - 0.0373 * c(n) + 0.0002 * c(2 * n)
    uM2 = -2.14 * s_(n)
    fO1 = 1.0089 + 0.1871 * c(n) - 0.0147 * c(2 * n) + 0.0014 * c(3 * n)
    uO1 = 10.80 * s_(n) - 1.34 * s_(2 * n) + 0.19 * s_(3 * n)
    fK1 = 1.0060 + 0.1150 * c(n) - 0.0088 * c(2 * n) + 0.0006 * c(3 * n)
    uK1 = -8.86 * s_(n) + 0.68 * s_(2 * n) - 0.07 * s_(3 * n)
    fK2 = 1.0241 + 0.2863 * c(n) + 0.0083 * c(2 * n) - 0.0015 * c(3 * n)
    uK2 = -17.74 * s_(n) + 0.68 * s_(2 * n) - 0.04 * s_(3 * n)
    fJ1 = 1.0129 + 0.1676 * c(n) - 0.0170 * c(2 * n) + 0.0016 * c(3 * n)
    uJ1 = -12.94 * s_(n) + 1.34 * s_(2 * n) - 0.19 * s_(3 * n)
    fOO1 = 1.1027 + 0.6504 * c(n) + 0.0317 * c(2 * n) - 0.0014 * c(3 * n)
    uOO1 = -36.68 * s_(n) + 4.02 * s_(2 * n) - 0.57 * s_(3 * n)
    fMf = 1.0429 + 0.4135 * c(n) - 0.004 * c(2 * n)
    uMf = -23.74 * s_(n) + 2.68 * s_(2 * n) - 0.38 * s_(3 * n)
    fMm = 1.0 - 0.1300 * c(n) + 0.0013 * c(2 * n)
    um = 0 * n
    um1 = 1 + 0 * n
    tabela = {
        'Sa': (um1, um), 'Ssa': (um1, um), 'Mm': (fMm, um), 'MSf': (fM2, -uM2), 'Mf': (fMf, uMf),
        '2Q1': (fO1, uO1), 'Q1': (fO1, uO1), 'RHO1': (fO1, uO1), 'O1': (fO1, uO1),
        'P1': (um1, um), 'K1': (fK1, uK1), 'J1': (fJ1, uJ1), 'OO1': (fOO1, uOO1),
        '2N2': (fM2, uM2), 'MU2': (fM2, uM2), 'N2': (fM2, uM2), 'NU2': (fM2, uM2),
        'M2': (fM2, uM2), 'L2': (fM2, uM2), 'S2': (um1, um), 'T2': (um1, um), 'R2': (um1, um), 'K2': (fK2, uK2),
        '2SM2': (fM2, -uM2),
        'MO3': (fM2 * fO1, uM2 + uO1), 'M3': (fM2 ** 1.5, 1.5 * uM2),
        'MK3': (fM2 * fK1, uM2 + uK1), 'SK3': (fK1, uK1),
        'MN4': (fM2 ** 2, 2 * uM2), 'M4': (fM2 ** 2, 2 * uM2), 'MS4': (fM2, uM2),
        'MK4': (fM2 * fK2, uM2 + uK2), 'S4': (um1, um),
        '2MN6': (fM2 ** 3, 3 * uM2), 'M6': (fM2 ** 3, 3 * uM2), '2MS6': (fM2 ** 2, 2 * uM2),
        'M8': (fM2 ** 4, 4 * uM2), 'S1': (um1, um), 'NO1': (fM2 * fO1, uM2 - uO1), 'SO1': (fO1, -uO1),
        'MKS2': (fM2 * fK2, uM2 + uK2), 'MSN2': (fM2 ** 2, 0 * n), '2MK5': (fM2 ** 2 * fK1, 2 * uM2 + uK1), '3MK7': (fM2 ** 3 * fK1, 3 * uM2 + uK1),
    }
    return tabela[nome]


VEL = None


def velocidades():
    # graus por hora, derivada numérica
    t0 = np.array([0.0, 1.0])
    a0 = astro(t0)
    d = [a[1] - a[0] for a in a0]
    d[0] = 15.0 + d[2] - d[1]
    return d


def matriz(t):
    """Colunas cos/sen de cada constituinte e derivadas (por hora)."""
    tau, s, h, p, N, p1 = astro(t)
    args = [tau, s, h, p, -N, p1]
    v = velocidades()
    cols, dcols = [], []
    for nome, d in CONST:
        V = sum(di * a for di, a in zip(d, args))
        f, u = nodal(nome, N)
        fi = np.radians(V + u)
        w = np.radians(sum(di * vi for di, vi in zip(d, [v[0], v[1], v[2], v[3], -v[4], v[5]])))
        cols += [f * np.cos(fi), f * np.sin(fi)]
        dcols += [-f * w * np.sin(fi), f * w * np.cos(fi)]
    return np.array(cols).T, np.array(dcols).T


def horas(datas_locais):
    return np.array([((d + dt.timedelta(hours=3)) - J2000).total_seconds() / 3600 for d in datas_locais])


def prever(coef, z, t):
    C, _ = matriz(t)
    return z + C @ coef


def extremos(coef, z, inicio, fim):
    passo = 1 / 60
    t = np.arange(horas([inicio])[0], horas([fim])[0], passo)
    y = prever(coef, z, t)
    r = []
    for i in range(1, len(y) - 1):
        if (y[i] > y[i - 1] and y[i] >= y[i + 1]) or (y[i] < y[i - 1] and y[i] <= y[i + 1]):
            r.append((t[i], y[i]))
    return r


def main():
    linhas = [l.strip().split(',') for l in open(sys.argv[1]) if l.strip()]
    datas = [dt.datetime.fromisoformat(a) for a, _ in linhas]
    alt = np.array([float(b) for _, b in linhas])
    corte = int(sys.argv[3]) if len(sys.argv) > 3 else 13
    sel = np.array([d.month <= corte for d in datas])
    t = horas(datas)
    C, D = matriz(t[sel])
    peso = 1.5  # metros por (metro/hora): equilibra as duas equações
    A = np.vstack([np.hstack([np.ones((C.shape[0], 1)), C]),
                   np.hstack([np.zeros((D.shape[0], 1)), peso * D])])
    b = np.concatenate([alt[sel], np.zeros(D.shape[0])])
    x, *_ = np.linalg.lstsq(A, b, rcond=None)
    z, coef = x[0], x[1:]
    res = alt[sel] - prever(coef, z, t[sel])
    print(f'ajuste: Z0={z:.3f} m, erro de altura nos pontos ajustados: {np.sqrt(np.mean(res ** 2)) * 100:.1f} cm')
    for i, (nome, _) in enumerate(CONST):
        amp = math.hypot(coef[2 * i], coef[2 * i + 1])
        if amp > 0.02:
            print(f'  {nome:5s} {amp * 100:5.1f} cm')
    if corte < 12:
        teste = [(d, a) for d, a in zip(datas, alt) if d.month > corte]
        ext = extremos(coef, z, teste[0][0] - dt.timedelta(hours=3), teste[-1][0] + dt.timedelta(hours=3))
        et = np.array([e[0] for e in ext])
        ey = np.array([e[1] for e in ext])
        dtm, dal = [], []
        for d, a in teste:
            th = horas([d])[0]
            j = np.argmin(np.abs(et - th))
            dtm.append((et[j] - th) * 60)
            dal.append((ey[j] - a) * 100)
        dtm, dal = np.abs(np.array(dtm)), np.abs(np.array(dal))
        print(f'teste meses {corte + 1}-12 ({len(teste)} marés): horário mediana {np.median(dtm):.0f} min, '
              f'90% até {np.percentile(dtm, 90):.0f} min; altura mediana {np.median(dal):.0f} cm, '
              f'90% até {np.percentile(dal, 90):.0f} cm')
        print(f'  preditos {len(ext)} extremos x oficiais {len(teste)}')
    if len(sys.argv) > 2 and sys.argv[2] != '-':
        json.dump({'z0': round(float(z), 4),
                   'constituintes': [{'nome': n, 'a': round(float(coef[2 * i]), 5),
                                      'b': round(float(coef[2 * i + 1]), 5)}
                                     for i, (n, _) in enumerate(CONST)]},
                  open(sys.argv[2], 'w'), indent=1)


main()
