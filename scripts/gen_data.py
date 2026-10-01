"""
Genera 02_data.sql con datos FICTICIOS pero realistas para el proyecto.
Semilla fija (random.seed) => cada ejecución produce exactamente los mismos datos.

Uso:  python scripts/gen_data.py

Patrones de negocio simulados a propósito (para que el EDA tenga algo que descubrir):
  · estacionalidad (pico en primavera, valle en invierno y agosto), domingo cerrado
  · preferencia de segmento según la edad del cliente y el tipo de tienda
  · financiación más frecuente cuanto más cara es la moto; más cancelaciones al financiar
  · más descuento en temporada baja; un comercial con descuentos anómalos
  · provincias sin concesionario cuyos clientes compran en provincias vecinas
  · ventas de flotas a empresas, un modelo sin ventas, un comercial de baja
Errores introducidos en la exportación de ventas (se limpian en SQL):
  duplicados, ventas de prueba, filas sin fecha, coma decimal, texto sucio, erratas.
"""
import random, datetime as dt, math, os

AQUI = os.path.dirname(os.path.abspath(__file__))       # carpeta scripts/
RAIZ = os.path.dirname(AQUI)                             # raíz del repositorio

random.seed(2025)
D = dt.date

# ---------------------------------------------------------------- dimensiones fijas
PROVINCIAS = [  # INE, nombre, CCAA, población aprox. 2024, factor "cultura moto"
    (28, 'Madrid', 'Comunidad de Madrid', 7009000, 1.0),
    (8, 'Barcelona', 'Cataluña', 5878000, 1.3),
    (46, 'Valencia', 'Comunitat Valenciana', 2711000, 1.15),
    (3, 'Alicante', 'Comunitat Valenciana', 1981000, 1.05),
    (41, 'Sevilla', 'Andalucía', 1969000, 1.1),
    (29, 'Málaga', 'Andalucía', 1783000, 1.25),
    (30, 'Murcia', 'Región de Murcia', 1552000, 1.0),
    (11, 'Cádiz', 'Andalucía', 1253000, 1.05),
    (7, 'Illes Balears', 'Illes Balears', 1231000, 1.2),
    (48, 'Bizkaia', 'País Vasco', 1159000, 0.8),
    (15, 'A Coruña', 'Galicia', 1128000, 0.75),
    (33, 'Asturias', 'Principado de Asturias', 1010000, 0.65),
    (50, 'Zaragoza', 'Aragón', 989000, 0.9),
    (18, 'Granada', 'Andalucía', 931000, 1.0),
    (14, 'Córdoba', 'Andalucía', 784000, 1.05),
]
POB = {p[0]: p[3] for p in PROVINCIAS}
FACT = {p[0]: p[4] for p in PROVINCIAS}

MARCAS = [  # nombre, país, premium
    ('Honda', 'Japón', 0), ('Yamaha', 'Japón', 0), ('Kawasaki', 'Japón', 0), ('Suzuki', 'Japón', 0),
    ('BMW Motorrad', 'Alemania', 1), ('Ducati', 'Italia', 1), ('KTM', 'Austria', 0),
    ('Triumph', 'Reino Unido', 1), ('Harley-Davidson', 'Estados Unidos', 1), ('Kymco', 'Taiwán', 0),
    ('Piaggio', 'Italia', 0), ('CFMoto', 'China', 0),
]
MID = {m[0]: i + 1 for i, m in enumerate(MARCAS)}

# marca, modelo, segmento, cc, cv, carnet, precio 2024, lanzamiento, popularidad
MODELOS = [
    ('Honda', 'CBR650R', 'Sport', 649, 95, 'A', 9690, 2021, 1.3),
    ('Honda', 'CBR650R E-Clutch', 'Sport', 649, 95, 'A', 10290, 2024, 0.7),
    ('Honda', 'CB650R', 'Naked', 649, 95, 'A', 8990, 2021, 1.0),
    ('Honda', 'CB500 Hornet', 'Naked', 471, 48, 'A2', 6490, 2024, 1.5),
    ('Honda', 'NX500', 'Trail', 471, 48, 'A2', 7190, 2024, 1.2),
    ('Honda', 'CRF1100L Africa Twin', 'Trail', 1084, 102, 'A', 15900, 2020, 1.0),
    ('Honda', 'PCX125', 'Scooter', 125, 12.5, 'A1', 3690, 2021, 2.0),
    ('Honda', 'Forza 350', 'Scooter', 330, 29, 'A2', 6190, 2021, 1.2),
    ('Honda', 'Rebel 500', 'Custom', 471, 46, 'A2', 6690, 2020, 1.2),
    ('Yamaha', 'MT-07', 'Naked', 689, 73, 'A2', 7899, 2021, 2.0),
    ('Yamaha', 'MT-09', 'Naked', 890, 119, 'A', 10599, 2021, 1.2),
    ('Yamaha', 'Tracer 9', 'Touring', 890, 119, 'A', 13799, 2021, 1.3),
    ('Yamaha', 'Ténéré 700', 'Trail', 689, 73, 'A2', 10999, 2019, 1.4),
    ('Yamaha', 'NMAX 125', 'Scooter', 125, 12, 'A1', 3699, 2021, 1.8),
    ('Yamaha', 'TMAX 560', 'Scooter', 562, 47, 'A2', 13999, 2022, 0.9),
    ('Yamaha', 'R7', 'Sport', 689, 73, 'A2', 9299, 2022, 1.0),
    ('Kawasaki', 'Z650', 'Naked', 649, 68, 'A2', 7695, 2020, 1.2),
    ('Kawasaki', 'Z900', 'Naked', 948, 125, 'A', 10495, 2020, 1.0),
    ('Kawasaki', 'Ninja 650', 'Sport', 649, 68, 'A2', 7995, 2020, 0.9),
    ('Kawasaki', 'Versys 650', 'Touring', 649, 67, 'A2', 8795, 2022, 0.9),
    ('Kawasaki', 'Ninja 7 Hybrid', 'Sport', 451, 69, 'A2', 12495, 2024, 0.0),   # sin ventas
    ('Suzuki', 'GSX-8S', 'Naked', 776, 83, 'A', 9199, 2023, 0.8),
    ('Suzuki', 'V-Strom 800DE', 'Trail', 776, 84, 'A', 12499, 2023, 0.9),
    ('Suzuki', 'Burgman 400', 'Scooter', 400, 31, 'A2', 7299, 2018, 0.7),        # descatalogada 2025
    ('BMW Motorrad', 'R 1300 GS', 'Trail', 1300, 145, 'A', 22500, 2024, 1.3),
    ('BMW Motorrad', 'F 900 R', 'Naked', 895, 105, 'A', 10500, 2020, 0.7),
    ('BMW Motorrad', 'C 400 GT', 'Scooter', 350, 34, 'A2', 7900, 2021, 0.8),
    ('BMW Motorrad', 'S 1000 RR', 'Sport', 999, 210, 'A', 23500, 2023, 0.5),
    ('BMW Motorrad', 'R 1250 RT', 'Touring', 1254, 136, 'A', 24000, 2021, 0.8),
    ('Ducati', 'Monster', 'Naked', 937, 111, 'A', 12990, 2021, 0.8),
    ('Ducati', 'Panigale V2', 'Sport', 955, 155, 'A', 19990, 2020, 0.5),
    ('Ducati', 'Multistrada V4 S', 'Trail', 1158, 170, 'A', 28990, 2021, 0.5),
    ('Ducati', 'Scrambler Icon', 'Naked', 803, 73, 'A2', 9990, 2023, 0.8),
    ('KTM', '390 Duke', 'Naked', 399, 45, 'A2', 6299, 2024, 1.2),
    ('KTM', '790 Duke', 'Naked', 799, 105, 'A', 9499, 2023, 0.8),
    ('KTM', '890 Adventure', 'Trail', 889, 105, 'A', 13999, 2023, 0.8),
    ('Triumph', 'Trident 660', 'Naked', 660, 81, 'A2', 8395, 2021, 1.1),
    ('Triumph', 'Street Triple 765 R', 'Naked', 765, 120, 'A', 11395, 2023, 0.8),
    ('Triumph', 'Tiger 900 GT', 'Trail', 888, 108, 'A', 15895, 2024, 0.9),
    ('Triumph', 'Bonneville T120', 'Custom', 1200, 80, 'A', 14895, 2021, 0.7),
    ('Harley-Davidson', 'Sportster S', 'Custom', 1252, 121, 'A', 17990, 2021, 0.8),
    ('Harley-Davidson', 'Nightster', 'Custom', 975, 90, 'A', 15990, 2022, 0.6),
    ('Harley-Davidson', 'Street Glide', 'Touring', 1923, 105, 'A', 32900, 2024, 0.25),
    ('Kymco', 'Agility 125', 'Scooter', 125, 10, 'A1', 2099, 2020, 1.3),
    ('Kymco', 'People S 125', 'Scooter', 125, 12, 'A1', 2999, 2021, 1.0),
    ('Kymco', 'AK 550', 'Scooter', 550, 51, 'A', 11999, 2021, 0.4),
    ('Piaggio', 'Vespa Primavera 125', 'Scooter', 125, 11, 'A1', 4599, 2021, 1.2),
    ('Piaggio', 'Beverly 300', 'Scooter', 278, 25, 'A2', 5699, 2021, 0.9),
    ('CFMoto', '450NK', 'Naked', 449, 50, 'A2', 5190, 2023, 0.9),
    ('CFMoto', '800MT', 'Trail', 799, 95, 'A', 10990, 2023, 0.8),
    ('CFMoto', '450CL-C', 'Custom', 449, 44, 'A2', 5790, 2024, 0.8),
]
for i, m in enumerate(MODELOS): pass
MODEL_ID = {m[1]: i + 1 for i, m in enumerate(MODELOS)}
MODEL = {m[1]: m for m in MODELOS}
PREMIUM = {m[0]: m[2] for m in MARCAS}

CONCES = [  # codigo, nombre, ciudad, prov, zona, m2, apertura
    ('CO-001', 'Motos Castellana', 'Madrid', 28, 'Centro urbano', 650, '2012-03-01'),
    ('CO-002', 'Motos Getafe', 'Getafe', 28, 'Periferia', 1800, '2016-09-15'),
    ('CO-003', 'Motos Diagonal', 'Barcelona', 8, 'Centro urbano', 700, '2010-05-10'),
    ('CO-004', 'Motos Vallès', 'Sabadell', 8, 'Periferia', 1500, '2018-02-01'),
    ('CO-005', 'Motos Turia', 'Valencia', 46, 'Centro urbano', 900, '2014-06-01'),
    ('CO-006', 'Motos Nervión', 'Sevilla', 41, 'Periferia', 1300, '2015-04-20'),
    ('CO-007', 'Motos Costa del Sol', 'Málaga', 29, 'Periferia', 1200, '2017-03-01'),
    ('CO-008', 'Motos Mezquita', 'Córdoba', 14, 'Periferia', 900, '2019-10-01'),
    ('CO-009', 'Motos Abando', 'Bilbao', 48, 'Centro urbano', 600, '2013-11-01'),
    ('CO-010', 'Motos Ebro', 'Zaragoza', 50, 'Periferia', 1000, '2016-01-15'),
    ('CO-011', 'Motos Segura', 'Murcia', 30, 'Periferia', 950, '2020-05-01'),
    ('CO-012', 'Motos Riazor', 'A Coruña', 15, 'Centro urbano', 550, '2021-09-01'),
]
CID = {c[0]: i + 1 for i, c in enumerate(CONCES)}
ZONA = {i + 1: c[4] for i, c in enumerate(CONCES)}
# provincia de residencia -> concesionarios a los que acude (con probabilidad)
AREA = {28: [(1, .45), (2, .55)], 8: [(3, .55), (4, .45)], 46: [(5, 1)], 41: [(6, 1)], 29: [(7, 1)],
        14: [(8, 1)], 48: [(9, 1)], 50: [(10, 1)], 30: [(11, 1)], 15: [(12, 1)],
        3: [(11, .55), (5, .45)], 11: [(6, .6), (7, .4)], 18: [(7, .55), (8, .45)],
        7: [(3, .7), (5, .3)], 33: [(12, .5), (9, .5)]}

NOMBRES = ['Antonio', 'Manuel', 'José', 'Francisco', 'David', 'Juan', 'Javier', 'Daniel', 'Carlos', 'Alejandro',
           'Miguel', 'Rafael', 'Pablo', 'Sergio', 'Álvaro', 'Adrián', 'Jorge', 'Raúl', 'Iván', 'Rubén', 'Hugo',
           'Marcos', 'Diego', 'Alberto', 'Luis', 'Fernando', 'Óscar', 'Andrés', 'Víctor', 'Mario', 'María',
           'Carmen', 'Ana', 'Laura', 'Lucía', 'Marta', 'Cristina', 'Paula', 'Sara', 'Elena', 'Irene', 'Raquel',
           'Nuria', 'Silvia', 'Patricia', 'Alba', 'Noelia', 'Rocío', 'Julia', 'Claudia', 'Andrea', 'Beatriz']
APELLIDOS = ['García', 'Rodríguez', 'González', 'Fernández', 'López', 'Martínez', 'Sánchez', 'Pérez', 'Gómez',
             'Martín', 'Jiménez', 'Ruiz', 'Hernández', 'Díaz', 'Moreno', 'Muñoz', 'Álvarez', 'Romero', 'Alonso',
             'Gutiérrez', 'Navarro', 'Torres', 'Domínguez', 'Vázquez', 'Ramos', 'Gil', 'Ramírez', 'Serrano',
             'Blanco', 'Molina', 'Morales', 'Suárez', 'Ortega', 'Delgado', 'Castro', 'Ortiz', 'Rubio', 'Marín',
             'Sanz', 'Núñez', 'Iglesias', 'Medina', 'Garrido', 'Cortés', 'Castillo', 'Santos', 'Lozano', 'Guerrero']
DOMINIOS = ['gmail.com', 'hotmail.com', 'yahoo.es', 'outlook.es', 'icloud.com', 'telefonica.net']

ASCII = str.maketrans('áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU')
def slug(s): return s.lower().translate(ASCII).replace(' ', '')
def q(v):
    if v is None: return 'NULL'
    if isinstance(v, (int, float)): return str(v)
    return "'" + str(v).replace("'", "''") + "'"
def wchoice(pairs):
    r = random.random() * sum(w for _, w in pairs); acc = 0
    for k, w in pairs:
        acc += w
        if r <= acc: return k
    return pairs[-1][0]

# ---------------------------------------------------------------- vendedores
VEND = []  # (id, conc, nombre, apellidos, fecha_contr, comision, desde, hasta, sesgo_desc, habilidad)
vid = 0
for c in range(1, 13):
    n = 4 if c in (1, 2, 3, 4) else 3
    for _ in range(n):
        vid += 1
        fc = D(2015 + random.randint(0, 8), random.randint(1, 12), random.randint(1, 28))
        VEND.append([vid, c, random.choice(NOMBRES), random.choice(APELLIDOS) + ' ' + random.choice(APELLIDOS),
                     fc, random.choice([1.5, 2.0, 2.0, 2.5, 3.0]), D(2024, 1, 1), D(2025, 12, 31), 0.0,
                     random.uniform(0.7, 1.4)])
# vendedor "descuentero" en Getafe (CO-002): más descuento sin vender más
descuentero = [v for v in VEND if v[1] == 2][1]; descuentero[8] = 4.0; descuentero[9] = 0.9; descuentero[2] = 'Sara'; descuentero[3] = 'González Pérez'
# baja en junio 2025 (Sevilla)
baja = [v for v in VEND if v[1] == 6][2]; baja[7] = D(2025, 6, 30); baja[2] = 'Óscar'; baja[3] = 'Delgado Ruiz'
# alta reciente sin ventas todavía (Valencia)
vid += 1
VEND.append([vid, 5, 'Irene', 'Castro Molina', D(2025, 12, 15), 2.0, D(2026, 1, 1), D(2026, 1, 1), 0, 0])

# ---------------------------------------------------------------- clientes particulares
CLIENTES = []  # dict
emails = set()
def nuevo_email(nom, ape):
    base = f"{slug(nom)}.{slug(ape.split()[0])}"
    e = f"{base}@{random.choice(DOMINIOS)}"; k = 1
    while e in emails:
        k += 1; e = f"{base}{k}@{random.choice(DOMINIOS)}"
    emails.add(e); return e

prov_w = [(p[0], p[3] * p[4]) for p in PROVINCIAS]
for i in range(2700):
    prov = wchoice(prov_w)
    nom = random.choice(NOMBRES); ape = random.choice(APELLIDOS) + ' ' + random.choice(APELLIDOS)
    edad = random.choices([random.randint(18, 25), random.randint(26, 35), random.randint(36, 50), random.randint(51, 72)],
                          [0.20, 0.30, 0.32, 0.18])[0]
    nac = D(2024 - edad, random.randint(1, 12), random.randint(1, 28))
    CLIENTES.append(dict(tipo='Particular', nombre=nom, apellidos=ape, email=nuevo_email(nom, ape), nac=nac,
                         prov=prov, peso=random.choice([1, 1, 1, 1, 2]), ventas=[]))
EMPRESAS = [('Reparto Express Madrid SL', 28, 'repartoexpress.es', 'flota'), ('Mensajería Diagonal SL', 8, 'mensadiagonal.com', 'flota'),
            ('Rider Food Valencia SL', 46, 'riderfood.es', 'flota'), ('Sevilla Delivery SL', 41, 'sevilladelivery.es', 'flota'),
            ('Moto Rent Mallorca SL', 7, 'motorentmallorca.com', 'alquiler'), ('Costa Bike Rental SL', 29, 'costabikerental.es', 'alquiler'),
            ('Policía Local Getafe (contrato)', 28, 'getafe-contratos.es', 'institucional'), ('Rutas Trail Aventura SL', 18, 'rutastrail.es', 'alquiler')]
for nom, prov, dom, perfil in EMPRESAS:
    CLIENTES.append(dict(tipo='Empresa', nombre=nom, apellidos=None, email=f"compras@{dom}", nac=None, prov=prov,
                         peso=0, perfil=perfil, ventas=[]))

# ---------------------------------------------------------------- generación de ventas
MES_W = {1: .6, 2: .7, 3: 1.0, 4: 1.25, 5: 1.35, 6: 1.3, 7: 1.15, 8: .7, 9: 1.0, 10: .9, 11: .75, 12: .85}
DOW_W = {0: .9, 1: .85, 2: .9, 3: 1.0, 4: 1.2, 5: 1.45, 6: 0}   # domingo cerrado
BASE = 3.55
SEG_EDAD = {
    '18-25': {'Naked': .38, 'Sport': .15, 'Scooter': .35, 'Trail': .05, 'Custom': .07, 'Touring': 0},
    '26-35': {'Naked': .33, 'Sport': .14, 'Scooter': .23, 'Trail': .17, 'Custom': .08, 'Touring': .05},
    '36-50': {'Naked': .22, 'Sport': .08, 'Scooter': .22, 'Trail': .28, 'Custom': .10, 'Touring': .10},
    '51+':   {'Naked': .12, 'Sport': .04, 'Scooter': .18, 'Trail': .33, 'Custom': .15, 'Touring': .18}}
def grupo(e): return '18-25' if e <= 25 else '26-35' if e <= 35 else '36-50' if e <= 50 else '51+'

def disponible(mod, fecha):
    m = MODEL[mod]
    if m[8] == 0: return False
    if mod == 'CBR650R E-Clutch' and fecha < D(2024, 6, 1): return False
    if m[7] == 2024 and mod != 'CBR650R E-Clutch' and fecha < D(2024, 3, 1): return False
    if mod == 'Burgman 400' and fecha > D(2024, 12, 31): return False
    return True

def precio(mod, fecha):
    p = MODEL[mod][6]
    return round(p * 1.03, 2) if fecha.year == 2025 else float(p)

def elegir_modelo(edad, zona, fecha):
    segw = dict(SEG_EDAD[grupo(edad)])
    if zona == 'Centro urbano': segw['Scooter'] *= 1.6
    if fecha.year == 2025: segw['Trail'] *= 1.25; segw['Sport'] *= 0.8
    seg = wchoice(list(segw.items()))
    cands = []
    for m in MODELOS:
        if m[2] != seg or not disponible(m[1], fecha): continue
        w = m[8]
        if edad <= 23 and m[5] == 'A': w *= 0.2
        if edad <= 30 and PREMIUM[m[0]]: w *= 0.5
        if edad >= 45 and PREMIUM[m[0]]: w *= 1.4
        cands.append((m[1], w))
    return wchoice(cands)

def metodo(p, edad):
    if p < 5000: w = [('Contado', .70), ('Financiado', .28), ('Renting', .02)]
    elif p < 12000: w = [('Contado', .45), ('Financiado', .50), ('Renting', .05)]
    else: w = [('Contado', .30), ('Financiado', .58), ('Renting', .12)]
    if edad is not None and edad <= 25: w = [(k, v * (1.4 if k == 'Financiado' else 1)) for k, v in w]
    return wchoice(w)

VENTAS = []
part_idx = [i for i, c in enumerate(CLIENTES) if c['tipo'] == 'Particular']
part_w = [CLIENTES[i]['peso'] for i in part_idx]
d = D(2024, 1, 1)
while d <= D(2025, 12, 31):
    lam = BASE * MES_W[d.month] * DOW_W[d.weekday()] * (1.12 if d.year == 2025 else 1.0)
    n = 0; L = math.exp(-lam); p = 1.0
    while True:
        p *= random.random()
        if p < L: break
        n += 1
    for _ in range(n):
        k = random.choices(range(len(part_idx)), part_w)[0]; ci = part_idx[k]; cl = CLIENTES[ci]
        part_w[k] *= 0.07   # tras comprar una moto, es poco probable que compre otra pronto
        conc = wchoice(AREA[cl['prov']]) if random.random() > 0.03 else random.randint(1, 12)
        edad = (d - cl['nac']).days // 365
        mod = elegir_modelo(edad, ZONA[conc], d)
        vends = [v for v in VEND if v[1] == conc and v[6] <= d <= v[7]]
        v = wchoice([(x, x[9]) for x in vends])
        pr = precio(mod, d)
        desc = random.uniform(0, 6)
        if d.month in (11, 12, 1, 2): desc += 3
        if d.month == 8: desc += 2
        if PREMIUM[MODEL[mod][0]]: desc = max(0, desc - 1.5)
        desc += v[8]
        desc = min(25, round(desc * 2) / 2)
        mp = metodo(pr, edad)
        canc = {'Financiado': .06, 'Contado': .015, 'Renting': .03}[mp]
        est = 'Cancelada' if random.random() < canc else 'Completada'
        VENTAS.append(dict(fecha=d, conc=conc, vend=v[0], cli=ci, mod=mod, uds=1, precio=pr, desc=desc, mp=mp, est=est))
        cl['ventas'].append(d)
    d += dt.timedelta(days=1)

# ventas a empresas (flotas / alquiler)
for ci, c in enumerate(CLIENTES):
    if c['tipo'] != 'Empresa': continue
    for _ in range(random.randint(3, 6)):
        fecha = D(random.choice([2024, 2025]), random.choice([2, 3, 4, 5, 9, 10]), random.randint(1, 28))
        if fecha.weekday() == 6: fecha += dt.timedelta(days=1)
        conc = wchoice(AREA[c['prov']])
        if c['perfil'] == 'flota': mod = random.choice(['PCX125', 'NMAX 125', 'Agility 125', 'People S 125']); uds = random.randint(4, 12)
        elif c['perfil'] == 'alquiler': mod = random.choice(['PCX125', 'Vespa Primavera 125', 'NX500', 'MT-07', 'Ténéré 700']); uds = random.randint(3, 8)
        else: mod = random.choice(['R 1250 RT', 'Tracer 9']); uds = random.randint(2, 4)
        vends = [v for v in VEND if v[1] == conc and v[6] <= fecha <= v[7]]
        v = random.choice(vends)
        VENTAS.append(dict(fecha=fecha, conc=conc, vend=v[0], cli=ci, mod=mod, uds=uds, precio=precio(mod, fecha),
                           desc=float(random.choice([8, 10, 12, 12.5, 15])),
                           mp=random.choice(['Renting', 'Renting', 'Financiado', 'Contado']), est='Completada'))
        c['ventas'].append(fecha)

VENTAS.sort(key=lambda x: (x['fecha'], x['conc']))
cnt = {2024: 0, 2025: 0}
for v in VENTAS:
    cnt[v['fecha'].year] += 1
    v['codigo'] = f"V{v['fecha'].year % 100}-{cnt[v['fecha'].year]:06d}"

# fecha de alta de clientes
for c in CLIENTES:
    if c['ventas']:
        c['alta'] = min(c['ventas']) - dt.timedelta(days=random.randint(0, 120))
    else:
        c['alta'] = D(2024, 1, 1) + dt.timedelta(days=random.randint(0, 720))
# ordenar clientes por fecha de alta (como en un CRM real) y asignar id
orden = sorted(range(len(CLIENTES)), key=lambda i: CLIENTES[i]['alta'])
for new_id, i in enumerate(orden, start=1): CLIENTES[i]['id'] = new_id

# ---------------------------------------------------------------- suciedad controlada en la exportación
raw = []
for v in VENTAS:
    cl = CLIENTES[v['cli']]
    precio_txt = f"{v['precio']:.2f}"
    if random.random() < 0.05: precio_txt = precio_txt.replace('.', ',')          # coma decimal
    mp = v['mp']
    r = random.random()
    if r < 0.04: mp = '  ' + mp.lower() + ' '                                        # espacios + minúsculas
    elif r < 0.08: mp = mp.upper()
    raw.append([v['codigo'], v['fecha'].strftime('%d/%m/%Y'), CONCES[v['conc'] - 1][0], str(v['vend']),
                cl['email'], MODEL[v['mod']][0], v['mod'], str(v['uds']), precio_txt, f"{v['desc']:.1f}", mp, v['est']])
# erratas en el nombre del modelo (se CORRIGEN con UPDATE)
typos = {'MT-07': 'MT07', 'PCX125': 'PCX 125', 'Ténéré 700': 'Tenere-700'}
hechas = set()
for row in raw:
    if row[6] in typos and row[6] not in hechas:
        hechas.add(row[6]); row[6] = typos[row[6]]
# duplicados exactos (la exportación del ERP envió dos veces algunas ventas)
dups = [list(r) for r in random.sample(raw, 14)]
# filas sin fecha (inválidas, se ELIMINAN)
sinfecha = []
for r in random.sample(raw, 3):
    x = list(r); x[0] = x[0].replace('-', '-9'); x[0] = x[0][:10]; x[1] = ''; sinfecha.append(x)
# ventas de prueba del ERP (se ELIMINAN)
test = [['TEST-000001', '15/01/2024', 'CO-001', '1', CLIENTES[orden[0]]['email'], 'Honda', 'PCX125', '1', '1.00', '0.0', 'Contado', 'Completada'],
        ['TEST-000002', '15/01/2024', 'CO-001', '1', CLIENTES[orden[0]]['email'], 'Honda', 'PCX125', '1', '1.00', '0.0', 'Contado', 'Completada']]
raw_all = raw + dups + sinfecha + test
random.shuffle(raw_all)

# ---------------------------------------------------------------- escritura del SQL
out = []
W = out.append
W(open(os.path.join(AQUI, 'data_header.sql'), encoding='utf-8').read())

W("""
/* =====================================================================
   BLOQUE 1 · DIMENSIONES MAESTRAS  (una única transacción)
   Si falla cualquier INSERT, no se confirma nada (atomicidad): no
   queremos, por ejemplo, modelos cargados sin sus marcas.
   ===================================================================== */
START TRANSACTION;

-- 1.1 Provincias (código INE; población aproximada INE 2024)
INSERT INTO dim_provincia (id_provincia, nombre, comunidad_autonoma, poblacion) VALUES""")
W(',\n'.join(f"    ({p[0]}, {q(p[1])}, {q(p[2])}, {p[3]})" for p in PROVINCIAS) + ';\n')

W("-- 1.2 Marcas\nINSERT INTO dim_marca (nombre, pais_origen, es_premium) VALUES")
W(',\n'.join(f"    ({q(m[0])}, {q(m[1])}, {'TRUE' if m[2] else 'FALSE'})" for m in MARCAS) + ';\n')

W("""-- 1.3 Modelos. El id_marca se obtiene con una SUBCONSULTA por nombre de
--     marca, en lugar de escribir números "mágicos" a mano: si cambia el
--     orden de carga de las marcas, el script sigue siendo correcto.
INSERT INTO dim_modelo (id_marca, nombre, segmento, cilindrada_cc, potencia_cv, carnet_minimo, precio_base, anio_lanzamiento) VALUES""")
W(',\n'.join(f"    ((SELECT id_marca FROM dim_marca WHERE nombre = {q(m[0])}), {q(m[1])}, {q(m[2])}, {m[3]}, {m[4]}, {q(m[5])}, {m[6]:.2f}, {m[7]})"
             for m in MODELOS) + ';\n')

W("-- 1.4 Concesionarios\nINSERT INTO dim_concesionario (codigo, nombre, ciudad, id_provincia, tipo_zona, superficie_m2, fecha_apertura) VALUES")
W(',\n'.join(f"    ({q(c[0])}, {q(c[1])}, {q(c[2])}, {c[3]}, {q(c[4])}, {c[5]}, {q(c[6])})" for c in CONCES) + ';\n')

W("""-- 1.5 Vendedores. En el último se omite comision_pct y activo para que
--     actúen los DEFAULT (2.00 % y TRUE).""")
W("INSERT INTO dim_vendedor (id_concesionario, nombre, apellidos, fecha_contratacion, comision_pct) VALUES")
W(',\n'.join(f"    ({v[1]}, {q(v[2])}, {q(v[3])}, {q(v[4].isoformat())}, {v[5]:.2f})" for v in VEND[:-1]) + ';\n')
last = VEND[-1]
W(f"INSERT INTO dim_vendedor (id_concesionario, nombre, apellidos, fecha_contratacion) VALUES\n    ({last[1]}, {q(last[2])}, {q(last[3])}, {q(last[4].isoformat())});\n")
W("COMMIT;\n")

W("""
/* =====================================================================
   BLOQUE 2 · CALENDARIO GENERADO CON SQL (CTE recursiva + funciones de fecha)
   No se escriben 731 INSERT a mano: una CTE recursiva genera un día por
   iteración y las funciones de fecha calculan cada atributo.
   lc_time_names = 'es_ES' hace que DATE_FORMAT devuelva 'enero', 'lunes'...
   ===================================================================== */
SET SESSION lc_time_names = 'es_ES';
SET SESSION cte_max_recursion_depth = 5000;   -- por defecto son 1.000 iteraciones

START TRANSACTION;
INSERT INTO dim_calendario
    (id_fecha, fecha, fecha_texto, dia, mes, anio, trimestre,
     nombre_mes, dia_semana, nombre_dia, es_fin_semana, temporada)
WITH RECURSIVE dias AS (
    SELECT DATE('2024-01-01') AS fecha
    UNION ALL
    SELECT fecha + INTERVAL 1 DAY FROM dias WHERE fecha < '2025-12-31'
)
SELECT
    CAST(DATE_FORMAT(fecha, '%Y%m%d') AS UNSIGNED),          -- 20240101 (CAST texto → número)
    fecha,
    DATE_FORMAT(fecha, '%d/%m/%Y'),                          -- '01/01/2024'
    DAY(fecha),
    MONTH(fecha),
    YEAR(fecha),
    QUARTER(fecha),
    CONCAT(UPPER(LEFT(MONTHNAME(fecha), 1)), SUBSTRING(MONTHNAME(fecha), 2)),  -- 'Enero'
    WEEKDAY(fecha) + 1,                                      -- WEEKDAY: 0 = lunes → 1..7
    CONCAT(UPPER(LEFT(DAYNAME(fecha), 1)), SUBSTRING(DAYNAME(fecha), 2)),      -- 'Lunes'
    WEEKDAY(fecha) >= 5,                                     -- sábado o domingo
    CASE WHEN MONTH(fecha) IN (12, 1, 2) THEN 'Invierno'
         WHEN MONTH(fecha) IN (3, 4, 5)  THEN 'Primavera'
         WHEN MONTH(fecha) IN (6, 7, 8)  THEN 'Verano'
         ELSE 'Otoño' END
FROM dias;
COMMIT;
""")

W("""
/* =====================================================================
   BLOQUE 3 · CLIENTES (exportación del CRM)
   Particulares y empresas. Las empresas no tienen apellidos ni fecha
   de nacimiento (lo permite el CHECK condicional ck_cli_nacimiento).
   Algunos emails llegan del CRM en MAYÚSCULAS: se normalizan en el
   bloque 5. También vienen 2 registros de prueba que se borran después.
   ===================================================================== */
START TRANSACTION;
""")
cli_sorted = sorted(CLIENTES, key=lambda c: c['id'])
rows = []
for c in cli_sorted:
    em = c['email']
    if c['tipo'] == 'Particular' and random.random() < 0.02: em = em.upper()
    rows.append(f"    ({q(c['tipo'])}, {q(c['nombre'])}, {q(c['apellidos'])}, {q(em)}, "
                f"{q(c['nac'].isoformat() if c['nac'] else None)}, {c['prov']}, {q(c['alta'].isoformat())})")
for i in range(0, len(rows), 500):
    W("INSERT INTO dim_cliente (tipo_cliente, nombre, apellidos, email, fecha_nacimiento, id_provincia, fecha_alta) VALUES")
    W(',\n'.join(rows[i:i + 500]) + ';')
W("""-- Registros de prueba que el CRM exportó por error. Sin fecha_alta:
-- se aplica el DEFAULT (CURRENT_DATE).
INSERT INTO dim_cliente (nombre, apellidos, email, fecha_nacimiento, id_provincia) VALUES
    ('Test', 'Usuario Prueba', 'test1@motos-dw.test', '1990-01-01', 28),
    ('Test', 'Usuario Prueba', 'test2@motos-dw.test', '1990-01-01', 28);
COMMIT;
""")

W("""
/* =====================================================================
   BLOQUE 4 · STAGING: exportación "en bruto" de ventas del ERP
   ---------------------------------------------------------------------
   Patrón ETL habitual: los datos llegan primero a una tabla de paso
   (staging) con TODO en texto, tal cual vienen del origen. Así ningún
   dato se rechaza al cargar, y la limpieza y conversión de tipos (CAST)
   se hacen en SQL de forma controlada antes de pasar a fact_ventas.
   Problemas conocidos de esta exportación:
     · ventas duplicadas (el ERP reenvió algunas)
     · 2 ventas de prueba ('TEST-...')
     · filas sin fecha
     · precios con coma decimal ('9690,00')
     · método de pago con espacios y mayúsculas/minúsculas mezcladas
     · erratas en el nombre de algunos modelos ('MT07')
   ===================================================================== */
DROP TABLE IF EXISTS stg_ventas_raw;
CREATE TABLE IF NOT EXISTS stg_ventas_raw (
    id_raw             INT AUTO_INCREMENT PRIMARY KEY,   -- solo para poder distinguir duplicados
    codigo_venta       VARCHAR(20),
    fecha_txt          VARCHAR(10),                      -- 'dd/mm/aaaa'
    cod_concesionario  VARCHAR(10),
    id_vendedor_txt    VARCHAR(10),
    email_cliente      VARCHAR(100),
    marca_txt          VARCHAR(40),
    modelo_txt         VARCHAR(50),
    unidades_txt       VARCHAR(5),
    precio_txt         VARCHAR(15),
    descuento_txt      VARCHAR(6),
    metodo_pago_txt    VARCHAR(20),
    estado_txt         VARCHAR(15)
) ENGINE=InnoDB;
""")
cols = "(codigo_venta, fecha_txt, cod_concesionario, id_vendedor_txt, email_cliente, marca_txt, modelo_txt, unidades_txt, precio_txt, descuento_txt, metodo_pago_txt, estado_txt)"
rows = ["    (" + ", ".join(q(x) for x in r) + ")" for r in raw_all]
for i in range(0, len(rows), 500):
    W(f"INSERT INTO stg_ventas_raw {cols} VALUES")
    W(',\n'.join(rows[i:i + 500]) + ';')

W(open(os.path.join(AQUI, 'data_footer.sql'), encoding='utf-8').read())
open(os.path.join(RAIZ, '02_data.sql'), 'w', encoding='utf-8').write('\n'.join(out))

print('ventas', len(VENTAS), cnt, 'raw', len(raw_all), 'typos', hechas, 'clientes', len(CLIENTES),
      'sin compras', sum(1 for c in CLIENTES if not c['ventas']))
