# -*- coding: utf-8 -*-
"""Genera las fichas técnicas SIN IA: reglas sobre el nombre + datos de
modelos conocidos. Solo lo seguro; lo dudoso queda vacío. (Traído de
Brizuela; corre en la PC, no en el servidor.)

  python backend/herramientas_fichas/fichas_por_reglas.py backend/herramientas_fichas/respaldos/pendientes.json backend/herramientas_fichas/respaldos/lote.json

Primero: python backend/herramientas_fichas/fichas_sin_ia.py <correo> exportar.
Después: python backend/herramientas_fichas/fichas_sin_ia.py <correo> cargar backend/herramientas_fichas/respaldos/lote.json
"""
import json
import re
import sys

# ── Utilidades ──────────────────────────────────────────────────────────

def n(s):
    s = s.lower()
    for a, b in (('á', 'a'), ('é', 'e'), ('í', 'i'), ('ó', 'o'), ('ú', 'u'), ('ü', 'u'), ('ñ', 'n'), ('¨', '"'), ("''", '"')):
        s = s.replace(a, b)
    return s


def miles(x):
    """10000 → '10.000'"""
    return f'{int(x):,}'.replace(',', '.')


def dec(x):
    s = ('%g' % float(x)).replace('.', ',')
    return s


def gb(x):
    x = str(x).lower()
    return '1 TB' if x in ('1tb', '1024') else f'{x} GB'


def memoria(nombre):
    """(almacenamiento, ram) a partir de «256/8», «8/256», «128», «1TB/16»."""
    s = n(nombre).replace('//', '/')
    m = re.search(r'(\d+|1tb)\s*/\s*(\d+|1tb)', s)
    if m:
        a, b = m.group(1), m.group(2)
        va = 1024 if a == '1tb' else int(a)
        vb = 1024 if b == '1tb' else int(b)
        alm, ram = (a, b) if va >= vb else (b, a)
        return gb(alm), gb(ram)
    # Sin par: el mayor de los tamaños posibles. «iPhone 16 Pro 128» tiene
    # 16 y 128, y el 16 es el modelo.
    cands = re.findall(r'\b(1tb|1024|512|256|128|96|64|32|16)\b', s)
    if cands:
        mayor = max(cands, key=lambda x: 1024 if x == '1tb' else int(x))
        return gb(mayor), None
    return None, None


def titulo_modelo(t):
    """«iphone 13 pro max» → «iPhone 13 Pro Max»."""
    t = re.sub(r'\s+', ' ', t).strip(' -')
    pal = []
    for w in t.split(' '):
        wl = n(w)
        if wl in ('iphone',):
            pal.append('iPhone')
        elif wl in ('ip13',):
            pal.append('iPhone 13')
        elif wl in ('ipad',):
            pal.append('iPad')
        elif wl == 'xr':
            pal.append('XR')
        elif wl in ('y', 'de', 'para', 'con'):
            pal.append(wl)
        elif re.fullmatch(r'[a-z]\d+[a-z]*', wl):
            pal.append(w.upper())
        elif wl in ('5g', '4g'):
            pal.append(wl.upper())
        else:
            pal.append(w[:1].upper() + w[1:].lower())
    return ' '.join(pal)


def poner(f, grupo, campo, valor):
    if valor:
        f.setdefault(grupo, {})[campo] = valor


# ── Teléfonos y tablets: datos de modelos conocidos ─────────────────────
# Claves cortas → (grupo, campo) de la plantilla «equipo».
C = {
    'tam': ('Pantalla', 'Tamaño'), 'panel': ('Pantalla', 'Tipo de panel'),
    'res': ('Pantalla', 'Resolución'), 'hz': ('Pantalla', 'Frecuencia de actualización'),
    'cpu': ('Rendimiento', 'Procesador'), 'ram': ('Rendimiento', 'Memoria RAM'),
    'sd': ('Rendimiento', 'Memoria expandible'),
    'cam': ('Cámaras', 'Cámara principal'), 'adic': ('Cámaras', 'Cámaras adicionales'),
    'front': ('Cámaras', 'Cámara frontal'), 'video': ('Cámaras', 'Grabación de video'),
    'bat': ('Batería', 'Capacidad'), 'carga': ('Batería', 'Carga rápida'),
    'inal': ('Batería', 'Carga inalámbrica'),
    'so': ('Sistema', 'Sistema operativo'), 'capa': ('Sistema', 'Capa de personalización'),
    'red': ('Conectividad', 'Red'), 'sim': ('Conectividad', 'SIM'), 'wifi': ('Conectividad', 'Wi-Fi'),
    'bt': ('Conectividad', 'Bluetooth'), 'nfc': ('Conectividad', 'NFC'), 'puerto': ('Conectividad', 'Puerto'),
    'dim': ('Diseño', 'Dimensiones'), 'peso': ('Diseño', 'Peso'), 'ip': ('Diseño', 'Resistencia (IP)'),
    'desb': ('Seguridad', 'Desbloqueo'),
}

IP_LCD = 'Liquid Retina (IPS LCD)'
XDR = 'Super Retina XDR (OLED)'
APPLE = dict(so='iOS', sd='No', nfc='Sí (Apple Pay)', desb='Face ID')

# Orden: los nombres más largos primero (Pro Max antes que Pro).
MODELOS = [
    # ── iPhone ──
    (r'iphone 11 pro max', dict(APPLE, tam='6,5 pulgadas', panel=XDR, res='2688 × 1242', hz='60 Hz', cpu='Apple A13 Bionic', ram='4 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (2x)', front='12 MP', video='4K a 60 fps',
        bat='3.969 mAh', carga='18 W', inal='Sí (Qi)', red='4G LTE', puerto='Lightning', ip='IP68', peso='226 g', dim='158 × 77,8 × 8,1 mm')),
    (r'iphone 11 pro', dict(APPLE, tam='5,8 pulgadas', panel=XDR, res='2436 × 1125', hz='60 Hz', cpu='Apple A13 Bionic', ram='4 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (2x)', front='12 MP', video='4K a 60 fps',
        bat='3.046 mAh', carga='18 W', inal='Sí (Qi)', red='4G LTE', puerto='Lightning', ip='IP68', peso='188 g', dim='144 × 71,4 × 8,1 mm')),
    (r'iphone 11', dict(APPLE, tam='6,1 pulgadas', panel=IP_LCD, res='1792 × 828', hz='60 Hz', cpu='Apple A13 Bionic', ram='4 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps',
        bat='3.110 mAh', carga='18 W', inal='Sí (Qi)', red='4G LTE', puerto='Lightning', ip='IP68', peso='194 g', dim='150,9 × 75,7 × 8,3 mm')),
    (r'iphone 12 pro max', dict(APPLE, tam='6,7 pulgadas', panel=XDR, res='2778 × 1284', hz='60 Hz', cpu='Apple A14 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (2,5x) + LiDAR', front='12 MP', video='4K a 60 fps, Dolby Vision',
        bat='3.687 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='228 g', dim='160,8 × 78,1 × 7,4 mm')),
    (r'iphone 12 pro', dict(APPLE, tam='6,1 pulgadas', panel=XDR, res='2532 × 1170', hz='60 Hz', cpu='Apple A14 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (2x) + LiDAR', front='12 MP', video='4K a 60 fps, Dolby Vision',
        bat='2.815 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='189 g', dim='146,7 × 71,5 × 7,4 mm')),
    (r'iphone 12', dict(APPLE, tam='6,1 pulgadas', panel=XDR, res='2532 × 1170', hz='60 Hz', cpu='Apple A14 Bionic', ram='4 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps, Dolby Vision',
        bat='2.815 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='164 g', dim='146,7 × 71,5 × 7,4 mm')),
    (r'iphone 13 pro max', dict(APPLE, tam='6,7 pulgadas', panel=XDR + ', ProMotion', res='2778 × 1284', hz='120 Hz', cpu='Apple A15 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (3x) + LiDAR', front='12 MP', video='4K a 60 fps, modo Cine',
        bat='4.352 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='238 g', dim='160,8 × 78,1 × 7,65 mm')),
    (r'iphone 13 pro', dict(APPLE, tam='6,1 pulgadas', panel=XDR + ', ProMotion', res='2532 × 1170', hz='120 Hz', cpu='Apple A15 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular + 12 MP teleobjetivo (3x) + LiDAR', front='12 MP', video='4K a 60 fps, modo Cine',
        bat='3.095 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='203 g', dim='146,7 × 71,5 × 7,65 mm')),
    (r'iphone 13', dict(APPLE, tam='6,1 pulgadas', panel=XDR, res='2532 × 1170', hz='60 Hz', cpu='Apple A15 Bionic', ram='4 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps, modo Cine',
        bat='3.240 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='173 g', dim='146,7 × 71,5 × 7,65 mm')),
    (r'iphone 14 pro max', dict(APPLE, tam='6,7 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2796 × 1290', hz='120 Hz', cpu='Apple A16 Bionic', ram='6 GB',
        cam='48 MP', adic='12 MP ultra gran angular + 12 MP teleobjetivo (3x) + LiDAR', front='12 MP', video='4K a 60 fps, modo Acción',
        bat='4.323 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='240 g', dim='160,7 × 77,6 × 7,85 mm')),
    (r'iphone 14 pro', dict(APPLE, tam='6,1 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2556 × 1179', hz='120 Hz', cpu='Apple A16 Bionic', ram='6 GB',
        cam='48 MP', adic='12 MP ultra gran angular + 12 MP teleobjetivo (3x) + LiDAR', front='12 MP', video='4K a 60 fps, modo Acción',
        bat='3.200 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='206 g', dim='147,5 × 71,5 × 7,85 mm')),
    (r'iphone 14 plus', dict(APPLE, tam='6,7 pulgadas', panel=XDR, res='2778 × 1284', hz='60 Hz', cpu='Apple A15 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps, modo Acción',
        bat='4.325 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='203 g', dim='160,8 × 78,1 × 7,8 mm')),
    (r'iphone 14', dict(APPLE, tam='6,1 pulgadas', panel=XDR, res='2532 × 1170', hz='60 Hz', cpu='Apple A15 Bionic', ram='6 GB',
        cam='12 MP gran angular', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps, modo Acción',
        bat='3.279 mAh', carga='20 W', inal='MagSafe 15 W', red='5G', puerto='Lightning', ip='IP68', peso='172 g', dim='146,7 × 71,5 × 7,8 mm')),
    (r'iphone 15 pro max', dict(APPLE, tam='6,7 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2796 × 1290', hz='120 Hz', cpu='Apple A17 Pro', ram='8 GB',
        cam='48 MP', adic='12 MP ultra gran angular + 12 MP teleobjetivo (5x) + LiDAR', front='12 MP', video='4K a 60 fps, ProRes',
        bat='4.441 mAh', carga='Sí (USB-C)', inal='MagSafe 15 W', red='5G', puerto='USB-C (USB 3)', ip='IP68', peso='221 g', dim='159,9 × 76,7 × 8,25 mm')),
    (r'iphone 15 pro', dict(APPLE, tam='6,1 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2556 × 1179', hz='120 Hz', cpu='Apple A17 Pro', ram='8 GB',
        cam='48 MP', adic='12 MP ultra gran angular + 12 MP teleobjetivo (3x) + LiDAR', front='12 MP', video='4K a 60 fps, ProRes',
        bat='3.274 mAh', carga='Sí (USB-C)', inal='MagSafe 15 W', red='5G', puerto='USB-C (USB 3)', ip='IP68', peso='187 g', dim='146,6 × 70,6 × 8,25 mm')),
    (r'iphone 15', dict(APPLE, tam='6,1 pulgadas', panel=XDR + ', Dynamic Island', res='2556 × 1179', hz='60 Hz', cpu='Apple A16 Bionic', ram='6 GB',
        cam='48 MP', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps',
        bat='3.349 mAh', carga='Sí (USB-C)', inal='MagSafe 15 W', red='5G', puerto='USB-C (USB 2)', ip='IP68', peso='171 g', dim='147,6 × 71,6 × 7,8 mm')),
    (r'iphone 16 pro max', dict(APPLE, tam='6,9 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2868 × 1320', hz='120 Hz', cpu='Apple A18 Pro', ram='8 GB',
        cam='48 MP Fusion', adic='48 MP ultra gran angular + 12 MP teleobjetivo (5x) + LiDAR', front='12 MP', video='4K a 120 fps, Dolby Vision',
        bat='4.685 mAh', carga='Sí (USB-C)', inal='MagSafe 25 W', red='5G', puerto='USB-C (USB 3)', ip='IP68', peso='227 g', dim='163 × 77,6 × 8,25 mm')),
    (r'iphone 16 pro', dict(APPLE, tam='6,3 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', res='2622 × 1206', hz='120 Hz', cpu='Apple A18 Pro', ram='8 GB',
        cam='48 MP Fusion', adic='48 MP ultra gran angular + 12 MP teleobjetivo (5x) + LiDAR', front='12 MP', video='4K a 120 fps, Dolby Vision',
        bat='3.582 mAh', carga='Sí (USB-C)', inal='MagSafe 25 W', red='5G', puerto='USB-C (USB 3)', ip='IP68', peso='199 g', dim='149,6 × 71,5 × 8,25 mm')),
    (r'iphone 16', dict(APPLE, tam='6,1 pulgadas', panel=XDR + ', Dynamic Island', res='2556 × 1179', hz='60 Hz', cpu='Apple A18', ram='8 GB',
        cam='48 MP Fusion', adic='12 MP ultra gran angular', front='12 MP', video='4K a 60 fps',
        bat='3.561 mAh', carga='Sí (USB-C)', inal='MagSafe 25 W', red='5G', puerto='USB-C (USB 2)', ip='IP68', peso='170 g', dim='147,6 × 71,6 × 7,8 mm')),
    (r'iphone 17 pro max', dict(APPLE, tam='6,9 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', hz='120 Hz', cpu='Apple A19 Pro', ram='12 GB',
        cam='48 MP Fusion', adic='48 MP ultra gran angular + 48 MP teleobjetivo (4x)', front='18 MP Center Stage', red='5G', puerto='USB-C', ip='IP68')),
    (r'iphone 17 pro', dict(APPLE, tam='6,3 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', hz='120 Hz', cpu='Apple A19 Pro', ram='12 GB',
        cam='48 MP Fusion', adic='48 MP ultra gran angular + 48 MP teleobjetivo (4x)', front='18 MP Center Stage', red='5G', puerto='USB-C', ip='IP68')),
    (r'iphone 17', dict(APPLE, tam='6,3 pulgadas', panel=XDR + ', ProMotion, Dynamic Island', hz='120 Hz', cpu='Apple A19', ram='8 GB',
        cam='48 MP Fusion', adic='48 MP ultra gran angular', front='18 MP Center Stage', red='5G', puerto='USB-C', ip='IP68')),

    # ── Samsung ──
    (r'samsung s24 ultra', dict(tam='6,8 pulgadas', panel='Dynamic AMOLED 2X', res='QHD+ (3120 × 1440)', hz='120 Hz',
        cpu='Snapdragon 8 Gen 3 for Galaxy', ram='12 GB', sd='No', cam='200 MP', adic='12 MP ultra gran angular + 50 MP teleobjetivo (5x) + 10 MP teleobjetivo (3x)',
        front='12 MP', video='8K a 30 fps', bat='5.000 mAh', carga='45 W', inal='15 W', red='5G', nfc='Sí', puerto='USB-C',
        ip='IP68', peso='232 g', dim='162,3 × 79 × 8,6 mm', desb='Huella ultrasónica en pantalla y reconocimiento facial')),
    (r'samsung s25 ultra', dict(tam='6,9 pulgadas', panel='Dynamic AMOLED 2X', res='QHD+ (3120 × 1440)', hz='120 Hz',
        cpu='Snapdragon 8 Elite for Galaxy', sd='No', cam='200 MP', adic='50 MP ultra gran angular + 50 MP teleobjetivo (5x) + 10 MP teleobjetivo (3x)',
        front='12 MP', video='8K a 30 fps', bat='5.000 mAh', carga='45 W', inal='15 W', red='5G', nfc='Sí', puerto='USB-C',
        ip='IP68', peso='218 g', dim='162,8 × 77,6 × 8,2 mm', desb='Huella ultrasónica en pantalla y reconocimiento facial')),
    (r'samsung a56', dict(tam='6,7 pulgadas', panel='Super AMOLED', res='FHD+ (2340 × 1080)', hz='120 Hz', cpu='Exynos 1580',
        cam='50 MP (OIS)', adic='12 MP ultra gran angular + 5 MP macro', front='12 MP', bat='5.000 mAh', carga='45 W', inal='No',
        red='5G', nfc='Sí', puerto='USB-C', ip='IP67', peso='198 g', desb='Huella en pantalla y reconocimiento facial')),
    (r'samsung a36', dict(tam='6,7 pulgadas', panel='Super AMOLED', res='FHD+ (2340 × 1080)', hz='120 Hz', cpu='Snapdragon 6 Gen 3',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular + 5 MP macro', front='12 MP', bat='5.000 mAh', carga='45 W', inal='No',
        red='5G', nfc='Sí', puerto='USB-C', ip='IP67', desb='Huella en pantalla y reconocimiento facial')),
    (r'samsung a26', dict(tam='6,7 pulgadas', panel='Super AMOLED', res='FHD+ (2340 × 1080)', hz='120 Hz', cpu='Exynos 1380',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular + 2 MP macro', front='13 MP', bat='5.000 mAh', carga='25 W', inal='No',
        red='5G', puerto='USB-C', ip='IP67', desb='Huella lateral y reconocimiento facial')),
    (r'samsung a16', dict(tam='6,7 pulgadas', panel='Super AMOLED', res='FHD+ (2340 × 1080)', hz='90 Hz',
        cam='50 MP', adic='5 MP ultra gran angular + 2 MP macro', front='13 MP', bat='5.000 mAh', carga='25 W', inal='No',
        puerto='USB-C', ip='IP54', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'samsung a06', dict(tam='6,7 pulgadas', panel='PLS LCD', res='HD+ (1600 × 720)', cpu='MediaTek Helio G85',
        cam='50 MP', adic='2 MP de profundidad', front='8 MP', bat='5.000 mAh', carga='25 W', inal='No', red='4G LTE',
        puerto='USB-C', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),

    # ── Xiaomi / Redmi / Poco ──
    (r'redmi note 14 pro\+? ?\+ 5g|redmi note 14 pro\+ 5g', dict(tam='6,67 pulgadas', panel='AMOLED', res='1.5K (2712 × 1220)', hz='120 Hz',
        cpu='Snapdragon 7s Gen 3', cam='200 MP (OIS)', adic='8 MP ultra gran angular + 2 MP macro', front='20 MP',
        bat='5.110 mAh', carga='120 W', red='5G', nfc='Sí', puerto='USB-C', ip='IP68', desb='Huella en pantalla')),
    (r'redmi note 14(?! pro)', dict(tam='6,67 pulgadas', panel='AMOLED', res='FHD+ (2400 × 1080)', hz='120 Hz',
        cpu='MediaTek Helio G99-Ultra', cam='108 MP', adic='2 MP macro + 2 MP de profundidad', front='20 MP',
        bat='5.500 mAh', carga='33 W', red='4G LTE', puerto='USB-C', ip='IP54', sd='Sí (microSD)', desb='Huella en pantalla')),
    (r'poco x7 pro', dict(tam='6,67 pulgadas', panel='AMOLED', res='1.5K (2712 × 1220)', hz='120 Hz', cpu='MediaTek Dimensity 8400-Ultra',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='20 MP', bat='6.000 mAh', carga='90 W', red='5G', nfc='Sí',
        puerto='USB-C', ip='IP68', desb='Huella en pantalla')),
    (r'poco c71', dict(tam='6,88 pulgadas', panel='LCD', hz='120 Hz', cpu='Unisoc T7250', cam='32 MP', front='8 MP',
        bat='5.200 mAh', carga='15 W', red='4G LTE', puerto='USB-C', sd='Sí (microSD)', desb='Huella lateral')),
    (r'redmi a5', dict(tam='6,88 pulgadas', panel='LCD', hz='120 Hz', cpu='Unisoc T7250', cam='32 MP', front='8 MP',
        bat='5.200 mAh', carga='15 W', red='4G LTE', puerto='USB-C', sd='Sí (microSD)', desb='Huella lateral')),

    # ── Honor ──
    (r'honor magic 7 lite', dict(tam='6,78 pulgadas', panel='AMOLED', res='1.5K (2700 × 1224)', hz='120 Hz', cpu='Snapdragon 6 Gen 1',
        cam='108 MP (OIS)', adic='5 MP ultra gran angular', front='16 MP', bat='6.600 mAh', carga='66 W', red='5G',
        puerto='USB-C', ip='IP65', peso='189 g', desb='Huella en pantalla')),

    # ── Infinix ──
    (r'infinix gt 30 pro', dict(tam='6,78 pulgadas', panel='AMOLED', res='1.5K', hz='144 Hz', cpu='MediaTek Dimensity 8350 Ultimate',
        cam='108 MP', adic='8 MP ultra gran angular', front='13 MP', bat='5.500 mAh', carga='45 W', inal='30 W', red='5G',
        puerto='USB-C', desb='Huella en pantalla')),

    # ── Motorola ──
    (r'motorola edge 50 fusion', dict(tam='6,7 pulgadas', panel='pOLED', res='FHD+ (2400 × 1080)', hz='120 Hz (versión de Latinoamérica)', cpu='Snapdragon 7s Gen 2',
        cam='50 MP (OIS)', adic='13 MP ultra gran angular', front='32 MP', bat='5.000 mAh', carga='68 W', red='5G', nfc='Sí',
        puerto='USB-C', ip='IP68', desb='Huella en pantalla')),
    (r'moto g85', dict(tam='6,67 pulgadas', panel='pOLED curva', res='FHD+ (2400 × 1080)', hz='120 Hz', cpu='Snapdragon 6s Gen 3',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='32 MP', bat='5.000 mAh', carga='30 W', red='5G', nfc='Sí',
        puerto='USB-C', ip='IP52', desb='Huella en pantalla')),
    (r'moto g75', dict(tam='6,78 pulgadas', panel='LCD', res='FHD+ (2388 × 1080)', hz='120 Hz', cpu='Snapdragon 6 Gen 3',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='16 MP', bat='5.000 mAh', carga='30 W', red='5G', nfc='Sí',
        puerto='USB-C', ip='IP68', desb='Huella lateral')),

    # ── Más modelos (segunda tanda, 14/10/2026) ──
    (r'samsung a07', dict(tam='6,7 pulgadas', panel='PLS LCD', res='HD+ (1600 × 720)', hz='90 Hz', cpu='MediaTek Helio G99',
        cam='50 MP', adic='2 MP de profundidad', front='8 MP', bat='5.000 mAh', carga='25 W', inal='No', red='4G LTE',
        puerto='USB-C', ip='IP54', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'samsung a17(?! 5g)', dict(tam='6,7 pulgadas', panel='Super AMOLED', res='FHD+ (2340 × 1080)', hz='90 Hz', cpu='MediaTek Helio G99',
        cam='50 MP (OIS)', adic='5 MP ultra gran angular + 2 MP macro', front='13 MP', bat='5.000 mAh', carga='25 W', inal='No',
        red='4G LTE', puerto='USB-C', ip='IP54', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'redmi 15c', dict(tam='6,9 pulgadas', panel='LCD', res='HD+', hz='120 Hz', cpu='MediaTek Helio G81-Ultra', cam='50 MP',
        front='8 MP', bat='6.000 mAh', carga='33 W', red='4G LTE', puerto='USB-C', sd='Sí (microSD)', desb='Huella lateral')),
    (r'redmi 15 (?!c)|redmi 15$', dict(tam='6,9 pulgadas', panel='LCD', res='FHD+', hz='144 Hz', cpu='Snapdragon 685', cam='50 MP',
        front='8 MP', bat='7.000 mAh', carga='33 W', red='4G LTE', puerto='USB-C', sd='Sí (microSD)',
        desb='Huella lateral')),
    (r'infinix note 50 pro', dict(tam='6,78 pulgadas', panel='AMOLED', hz='144 Hz', cpu='MediaTek Helio G100 Ultimate',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='32 MP', bat='5.200 mAh', carga='90 W', inal='30 W',
        red='4G LTE', nfc='Sí', puerto='USB-C', desb='Huella en pantalla')),
    (r'infinix hot 60 pro plus', dict(tam='6,78 pulgadas', panel='AMOLED curva', hz='144 Hz', cpu='MediaTek Helio G200',
        cam='50 MP', bat='5.160 mAh', carga='45 W', red='4G LTE', puerto='USB-C', desb='Huella en pantalla')),
    (r'infinix smart 10', dict(tam='6,67 pulgadas', panel='LCD', res='HD+', hz='120 Hz', cpu='Unisoc T7250', cam='8 MP',
        front='8 MP', bat='5.000 mAh', carga='15 W', red='4G LTE', puerto='USB-C', sd='Sí (microSD)', desb='Huella lateral')),
    (r'moto g05', dict(tam='6,67 pulgadas', panel='LCD', res='HD+', hz='90 Hz', cpu='MediaTek Helio G81 Extreme', cam='50 MP',
        front='8 MP', bat='5.200 mAh', carga='20 W', red='4G LTE', puerto='USB-C', ip='IP52', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'moto g15', dict(tam='6,72 pulgadas', panel='LCD', res='FHD+', hz='60 Hz', cpu='MediaTek Helio G81 Extreme', cam='50 MP',
        adic='5 MP ultra gran angular', front='8 MP', bat='5.200 mAh', carga='18 W', red='4G LTE', puerto='USB-C', ip='IP52',
        sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'moto g35', dict(tam='6,72 pulgadas', panel='LCD', res='FHD+', hz='120 Hz', cpu='Unisoc T760', cam='50 MP',
        adic='8 MP ultra gran angular', front='16 MP', bat='5.000 mAh', carga='20 W', red='5G', puerto='USB-C', ip='IP52',
        sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'moto g06', dict(tam='6,88 pulgadas', panel='LCD', res='HD+', hz='120 Hz', cpu='MediaTek Helio G81 Extreme', cam='50 MP',
        front='8 MP', bat='5.200 mAh', red='4G LTE', puerto='USB-C', ip='IP64', sd='Sí (microSD)', desb='Huella lateral y reconocimiento facial')),
    (r'moto g 56|moto g56', dict(tam='6,72 pulgadas', panel='LCD', res='FHD+', hz='120 Hz', cpu='MediaTek Dimensity 7060',
        cam='50 MP', adic='8 MP ultra gran angular', front='32 MP', bat='5.200 mAh', carga='30 W', red='5G', puerto='USB-C',
        ip='IP68 / IP69', desb='Huella lateral')),
    (r'g86 power', dict(tam='6,67 pulgadas', panel='pOLED', res='1.5K', hz='120 Hz', cpu='MediaTek Dimensity 7300',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='32 MP', bat='6.720 mAh', carga='30 W', red='5G', puerto='USB-C',
        ip='IP68 / IP69', desb='Huella en pantalla')),
    (r'moto g86|moto g 86', dict(tam='6,67 pulgadas', panel='pOLED', res='1.5K', hz='120 Hz', cpu='MediaTek Dimensity 7300',
        cam='50 MP (OIS)', adic='8 MP ultra gran angular', front='32 MP', carga='30 W', red='5G', puerto='USB-C',
        ip='IP68 / IP69', desb='Huella en pantalla')),
    (r'motorola edge 60 fusion', dict(tam='6,67 pulgadas', panel='pOLED', res='1.5K', hz='120 Hz', cpu='MediaTek Dimensity 7300',
        cam='50 MP (OIS)', adic='13 MP ultra gran angular', front='32 MP', bat='5.200 mAh', carga='68 W', red='5G', nfc='Sí',
        puerto='USB-C', ip='IP68 / IP69', desb='Huella en pantalla')),
    (r'motorola edge 60 pro', dict(tam='6,67 pulgadas', panel='pOLED', res='1.5K', hz='120 Hz', cpu='MediaTek Dimensity 8350 Extreme',
        cam='50 MP (OIS)', adic='50 MP ultra gran angular + 10 MP teleobjetivo (3x)', front='50 MP', bat='6.000 mAh',
        inal='15 W', red='5G', nfc='Sí', puerto='USB-C', ip='IP68 / IP69', desb='Huella en pantalla')),
    (r'poco f8 ultra', dict(cpu='Snapdragon 8 Elite Gen 5', red='5G', nfc='Sí', puerto='USB-C')),
    (r'poco f8 pro', dict(cpu='Snapdragon 8 Elite', red='5G', nfc='Sí', puerto='USB-C')),
    (r'samsung s26', dict(red='5G', nfc='Sí', puerto='USB-C', sd='No')),
    (r'samsung a(27|37|57)', dict(red='5G', puerto='USB-C')),
    (r'xiaomi 17', dict(red='5G', nfc='Sí', puerto='USB-C')),

    # ── Tablets ──
    (r'ipad 11" a16', dict(APPLE, tam='11 pulgadas', panel=IP_LCD, res='2360 × 1640', hz='60 Hz', cpu='Apple A16', ram='6 GB',
        cam='12 MP', front='12 MP (horizontal)', red='Solo Wi-Fi', wifi='Wi-Fi 6', puerto='USB-C', so='iPadOS',
        desb='Touch ID (botón superior)', nfc='')),
    (r'redmi pad se 8\.?7', dict(tam='8,7 pulgadas', panel='LCD', res='HD+ (1340 × 800)', hz='90 Hz', cpu='MediaTek Helio G85',
        cam='8 MP', front='5 MP', bat='6.650 mAh', carga='18 W', puerto='USB-C', sd='Sí (microSD)')),
    (r'redmi pad 2 pro', dict(tam='12,1 pulgadas', panel='LCD', res='2.5K', hz='120 Hz', cpu='Snapdragon 7s Gen 4',
        bat='12.000 mAh', carga='33 W', puerto='USB-C')),
    (r'redmi pad 2 9\.?7', dict(tam='9,7 pulgadas', puerto='USB-C')),
    (r'redmi pad 2', dict(tam='11 pulgadas', panel='LCD', res='2.5K (2560 × 1600)', hz='90 Hz', cpu='MediaTek Helio G100-Ultra',
        cam='8 MP', front='5 MP', bat='9.000 mAh', carga='18 W', puerto='USB-C', sd='Sí (microSD)')),
    (r'xiaomi pad 7', dict(tam='11,2 pulgadas', panel='LCD', res='3.2K (3200 × 2136)', hz='144 Hz', cpu='Snapdragon 7+ Gen 3',
        cam='13 MP', front='8 MP', bat='8.850 mAh', carga='45 W', puerto='USB-C')),
]

CAPAS = [('apple', 'iOS', ''), ('iphone', 'iOS', ''), ('ipad', 'iPadOS', ''), ('samsung', 'Android', 'One UI'), ('samsumg', 'Android', 'One UI'),
         ('redmi', 'Android', 'HyperOS'), ('poco', 'Android', 'HyperOS'), ('xiaomi', 'Android', 'HyperOS'),
         ('honor', 'Android', 'MagicOS'), ('infinix', 'Android', 'XOS'), ('tecno', 'Android', 'HiOS'),
         ('itel', 'Android', ''), ('motorola', 'Android', ''), ('moto', 'Android', ''), ('oukitel', 'Android', ''),
         ('blu', 'Android', ''), ('yezz', 'Android', ''), ('zte', 'Android', ''), ('tcl', 'Android', ''),
         ('meizu', 'Android', ''), ('olax', 'Android', ''), ('maxwest', 'Android', ''), ('dialn', 'Android', '')]


def ficha_equipo(p):
    f = {}
    nom = n(p['nombre'])
    full = n(p['marca'] + ' ' + p['nombre'])
    for patron, datos in MODELOS:
        if re.search(patron, nom) or re.search(patron, full):
            for k, v in datos.items():
                if v:
                    g, c = C[k]
                    poner(f, g, c, v)
            break
    alm, ram = memoria(p['nombre'])
    poner(f, 'Rendimiento', 'Almacenamiento', alm)
    if ram:
        poner(f, 'Rendimiento', 'Memoria RAM', ram)
    if '5g' in nom:
        poner(f, 'Conectividad', 'Red', '5G')
    m = re.search(r'(\d{1,2}(?:[.,]\d)?)\s*(?:"|\'\'|pulgadas)', nom)
    if m and 'Tamaño' not in f.get('Pantalla', {}):
        poner(f, 'Pantalla', 'Tamaño', dec(m.group(1).replace(',', '.')) + ' pulgadas')
    if 'wifi' in nom.replace('-', ''):
        poner(f, 'Conectividad', 'Red', f.get('Conectividad', {}).get('Red') or 'Solo Wi-Fi')
    for clave, so, capa in CAPAS:
        if clave in full:
            if 'Sistema operativo' not in f.get('Sistema', {}):
                poner(f, 'Sistema', 'Sistema operativo', so)
            # Los de gama de entrada de Xiaomi traen Android Go, sin HyperOS.
            if re.search(r'redmi a5|redmi a7(?! pro)|poco c71', nom):
                capa = 'Android 15 Go Edition (sin HyperOS)'
            if re.search(r'honor play 10|honor (choice )?t10', nom):
                capa = 'Android 15 Go Edition (sin MagicOS)'
            poner(f, 'Sistema', 'Capa de personalización', capa)
            break
    # ── Lo que vale para cualquier equipo de su tipo ──
    es_tablet = p['categoria'].lower() == 'tablet' or re.search(r'\bpad\b|tablet|table olax|ipad|xpad', nom)
    es_iphone = 'iphone' in nom
    con = f.setdefault('Conectividad', {})
    if es_iphone:
        gen = re.search(r'iphone (\d+)', nom)
        g = int(gen.group(1)) if gen else 0
        con.setdefault('SIM', 'Nano SIM + eSIM' if g <= 13 else 'eSIM (los de EE. UU. no traen bandeja SIM) o nano SIM + eSIM')
        wifi = 'Wi-Fi 7' if g >= 16 else ('Wi-Fi 6E' if g == 15 and 'pro' in nom else 'Wi-Fi 6')
        con.setdefault('Wi-Fi', wifi)
        con.setdefault('Bluetooth', '5.0' if g <= 13 else ('6.0' if g >= 17 else '5.3'))
    else:
        con.setdefault('Wi-Fi', 'Sí')
        con.setdefault('Bluetooth', 'Sí')
        con.setdefault('Puerto', 'USB-C')
        if not es_tablet:
            con.setdefault('SIM', 'Dual SIM (nano)')

    if p['categoria'].lower() == 'tablet' or 'pad' in nom:
        # Tablets: el SO de Apple es iPadOS.
        if f.get('Sistema', {}).get('Sistema operativo') == 'iOS':
            f['Sistema']['Sistema operativo'] = 'iPadOS'
    return f


# ── Laptops ─────────────────────────────────────────────────────────────

def ficha_computadora(p):
    f = {}
    nom = n(p['nombre'])
    alm, ram = memoria(p['nombre'].replace('CORE 13', '').replace('CORE 17', '').replace(' 13 ', ' ').replace('Core 13', ''))
    poner(f, 'Rendimiento', 'Almacenamiento', alm)
    poner(f, 'Rendimiento', 'Memoria RAM', ram)
    cpu = ''
    if re.search(r'core 13|\b13 8/|athlon', nom) and 'athlon' not in nom:
        cpu = 'Intel Core i3'
    if re.search(r'core 17', nom):
        cpu = 'Intel Core i7'
    if 'i5' in nom:
        cpu = 'Intel Core i5'
    if 'ryzen 5' in nom:
        cpu = 'AMD Ryzen 5'
    if 'athlon' in nom:
        cpu = 'AMD Athlon'
    if 'a18 pro' in nom:
        cpu = 'Apple A18 Pro'
    if '15ian8' in nom:
        cpu = 'Intel Core i3-N305'
    if 'x1404v' in nom or 'v14 g4 iru' in nom:
        cpu = (cpu + ' (13.ª generación)') if cpu else ''
    poner(f, 'Rendimiento', 'Procesador', cpu)
    tam = ''
    if re.search(r'hp 15|hp athlon|ideapad slim 3 15|idealpad slim 3 15|arce 3 15|dell dc15', nom):
        tam = '15,6 pulgadas'
    if re.search(r'hp 14|x1404|v14', nom):
        tam = '14 pulgadas'
    if 'macbook neo 13' in nom:
        tam = '13 pulgadas'
    if 'hp athlon' in nom:
        tam = ''
    poner(f, 'Pantalla', 'Tamaño', tam)
    if 'macbook' in nom:
        poner(f, 'Sistema', 'Sistema operativo', 'macOS')
    # Los HP terminados en WM/DX son de venta en EE. UU. y vienen con Windows 11.
    if re.search(r'hp 15-\w+(wm|dx)\b', nom):
        poner(f, 'Sistema', 'Sistema operativo', 'Windows 11 Home')
    poner(f, 'Conectividad', 'Wi-Fi', 'Sí')
    poner(f, 'Conectividad', 'Bluetooth', 'Sí')
    if 'Procesador' in f.get('Rendimiento', {}) and 'Apple' not in f['Rendimiento']['Procesador']:
        poner(f, 'Rendimiento', 'Gráficos', 'Integrados')
    return f


# ── Accesorios ──────────────────────────────────────────────────────────

def compat_de(resto):
    r = resto
    r = re.sub(r'\b(unicolor|borde color|color)\b', '', r, flags=re.I)
    r = re.sub(r'\s+', ' ', r).strip(' -')
    if not r:
        return ''
    t = titulo_modelo(r)
    fixes = [(r'^Hot ', 'Infinix Hot '), (r'^Note 60 Pro Infinix$', 'Infinix Note 60 Pro'), (r'^Spark ', 'Tecno Spark '),
             (r'^Tecno Canon 50 Pro /canon 50 Ultra$', 'Tecno Camon 50 Pro y Camon 50 Ultra'), (r'^Tecno 40C$', 'Tecno Spark 40C'),
             (r'^Iphone', 'iPhone'), (r'Pro Mas$', 'Pro Max'), (r'^IP13/14$', 'iPhone 13 y 14'), (r'^Iphone 17 Air$', 'iPhone Air'),
             (r'^Samsung A16- A17$', 'Samsung A16 y A17'), (r' - 12 Pro$', ' y 12 Pro'), (r'- 15 Pro$', ' y 15 Pro'),
             (r'^iPhone 17 Air$', 'iPhone Air'), (r'^Poco X7$', 'Poco X7'), (r'^C21 y Realme$', 'Realme C21')]
    for a, b in fixes:
        t = re.sub(a, b, t)
    t = t.replace('Iphone', 'iPhone').replace('Pro Max- 15 Pro', 'Pro Max y 15 Pro')
    t = re.sub(r'(?i)^ip13/14$', 'iPhone 13 y 14', t)
    t = re.sub(r'(\d+)pro\b', r'\1 Pro', t)
    t = re.sub(r'\b(\d+)c\b', r'\1C', t)
    return t


CONECTORES = [(r'c a c|tipo c a c|tipo cac|c ac|c-c|c to c', 'USB-C a USB-C'), (r'lightning', 'USB-C a Lightning'),
              (r'type-c|tipo c|t/c|usb-c|puerto c', 'USB-C'), (r'micro|tipo m\b', 'Micro USB')]


def conector(nom):
    for pat, txt in CONECTORES:
        if re.search(pat, nom):
            return txt
    return ''


def ficha_accesorio(p):
    f = {}
    nom = n(p['nombre'])
    orig = p['nombre']
    G = 'General'
    tipo = compat = material = ''

    # Forros
    m = re.match(r'(?i)forros?\s+(.*)', orig.strip())
    if m and 'agua' not in nom and 'tablet' not in nom:
        resto = m.group(1)
        if re.match(r'(?i)360', resto):
            tipo = 'Forro 360'
            resto = resto[3:]
        elif re.match(r'(?i)magsafe', resto):
            tipo = 'Forro compatible con MagSafe'
            resto = resto[7:]
        elif re.match(r'(?i)silicone case', resto):
            tipo, material = 'Forro Silicone Case', 'Silicona'
            resto = resto[13:]
        elif re.match(r'(?i)una capa', resto):
            tipo = 'Forro de una capa'
            resto = resto[8:]
        elif re.match(r'(?i)transformers', resto):
            tipo = 'Forro Transformers'
            resto = resto[12:]
        elif re.match(r'(?i)transpa', resto):
            tipo = 'Forro transparente compatible con MagSafe'
            resto = re.sub(r'(?i)transpa\s+magsefe', '', resto)
        if re.search(r'(?i)unicolor\s+magsafe', resto):
            tipo = 'Forro 360 compatible con MagSafe'
            resto = re.sub(r'(?i)unicolor\s+magsafe', '', resto)
        if 'unicolor' in n(resto):
            poner(f, G, 'Colores', 'Un solo color')
        compat = compat_de(resto)
    elif 'forros de agua' in nom:
        tipo = 'Forro contra agua (bolsa impermeable)'
    elif 'forro tablet' in nom:
        tipo = 'Forro para tablet'
        compat = 'iPad 11" (A16)' if 'ipad' in nom else ('Redmi Pad SE 8,7"' if 'redmi pad se' in nom else '')
    elif nom.startswith('vidrio'):
        tipo = 'Vidrio templado'
        if 'privacy' in nom or 'anti espia' in nom:
            tipo = 'Vidrio templado de privacidad (antiespía)'
        if 'blindado' in nom:
            tipo = 'Vidrio templado blindado'
        if 'instalador' in nom:
            tipo = 'Vidrio templado con instalador'
        if 'tecno go3' in nom:
            compat = 'Tecno Spark Go3, Honor Play 10 y Honor X5C Plus'
    elif 'protector de camara' in nom:
        tipo = 'Protector de cámara'
    elif nom.startswith('cable') or nom.startswith('cargador') or nom.startswith('taco') or 'car charger' in nom \
            or 'cargador' in nom or re.search(r'adapta|adapter|adpater', nom):
        w = re.search(r'(\d{2,3})\s*w\b', nom)
        a = re.search(r'(\d[.,]\d)\s*a\b', nom)
        if nom.startswith('cable'):
            tipo = 'Cable de carga y datos'
            if 'audio' in nom:
                tipo = 'Cable de audio'
            if 'convertidor' in nom:
                tipo = 'Cable convertidor USB de 5 V a 9 V'
            con = conector(nom)
            if con == 'USB-C':
                con = 'USB-A a USB-C'
            if con == 'Micro USB':
                con = 'USB-A a Micro USB'
            if re.search(r'c a c|c ac', nom):
                con = 'USB-C a USB-C'
            poner(f, 'Conexión', 'Conector', con if 'audio' not in nom and 'convertidor' not in nom else '')
            lm = re.search(r'(\d)\s*mts?\b', nom)
            if lm:
                poner(f, 'Conexión', 'Longitud del cable', lm.group(1) + ' m')
            if 'trenzado' in nom:
                material = 'Trenzado'
            for marca in ('infinix', 'samsung', 'tecno', 'xiaomi'):
                if marca in nom and 'xia/tecno' not in nom:
                    compat = marca.capitalize()
            if 'xia/tecno/infi/sams' in nom:
                compat = 'Xiaomi, Tecno, Infinix y Samsung (Micro USB)'
            if 'convertidor' in nom:
                compat = 'Routers y equipos de 9 V'
        else:
            tipo = 'Cargador de pared'
            if 'carro' in nom or 'car charger' in nom:
                tipo = 'Cargador de carro'
            if 'mp3' in nom:
                tipo = 'Cargador de carro con reproductor MP3'
            if 'laptop' in nom:
                tipo = 'Cargador para laptop'
                vm = re.search(r'(\d+)v-?(\d[.,]\d+)a', nom)
                if vm:
                    poner(f, 'Eléctrico', 'Voltaje / corriente', vm.group(1) + ' V / ' + vm.group(2).replace('.', ',') + ' A')
                    poner(f, 'Eléctrico', 'Potencia', '%d W' % round(int(vm.group(1)) * float(vm.group(2).replace(',', '.'))))
                v2 = re.search(r'(\d+)w/(\d+)v', nom)
                if v2:
                    poner(f, 'Eléctrico', 'Voltaje / corriente', v2.group(2) + ' V')
                pm = re.search(r'punta (\w)\b', nom)
                if pm:
                    poner(f, 'Conexión', 'Conector', 'Punta ' + pm.group(1).upper())
                for marca, txt in (('arce', 'Laptops Acer'), ('toshiba', 'Laptops Toshiba'), ('asus', 'Laptops Asus'), ('lenovo', 'Laptops Lenovo')):
                    if marca in nom:
                        compat = txt
            else:
                con = conector(nom)
                if 'c/iph' in nom:
                    con = 'USB-C a Lightning'
                if '2 en 1' in nom:
                    tipo = 'Cargador de pared con cable (2 en 1)'
                poner(f, 'Conexión', 'Conector', con)
                if 'pd' in nom.split() or 'pps' in nom:
                    poner(f, 'Eléctrico', 'Voltaje / corriente', 'Carga rápida PD' + (' / PPS' if 'pps' in nom else ''))
                if 'doble puerto' in nom:
                    poner(f, 'Conexión', 'Conector', (con + ', ' if con else '') + 'doble puerto')
                for marca, txt in (('samsung', 'Samsung'), ('samsumg', 'Samsung'), ('xiaomi', 'Xiaomi'),
                                   ('infinix / tecno', 'Infinix y Tecno'), ('infinix', 'Infinix'), ('tecno', 'Tecno'),
                                   ('iphone 14 pro max', 'iPhone'), ('iphone', 'iPhone'), ('apple', 'iPhone')):
                    if marca in nom:
                        compat = txt
                        break
        if w:
            poner(f, 'Eléctrico', 'Potencia', w.group(1) + ' W')
        if a and 'laptop' not in nom:
            poner(f, 'Eléctrico', 'Voltaje / corriente', a.group(1).replace('.', ',') + ' A')
        if nom.strip() == 'cargador':
            tipo = 'Cargador'
    elif 'power bank' in nom or 'powerbank' in nom or 'power band' in nom or 'battery pack' in nom:
        tipo = 'Power bank (batería externa)'
        if 'battery pack iphone' in nom:
            tipo, compat = 'Batería externa (battery pack)', 'iPhone'
        if 'magnetic' in nom:
            tipo = 'Power bank magnético'
        if 'solar' in nom:
            tipo = 'Power bank con carga solar'
        cap = None
        for m in re.finditer(r'(\d{1,2})[.,]000|(\d{4,5})(?=\s*(?:mah|\b))', nom):
            v = int(m.group(1)) * 1000 if m.group(1) else int(m.group(2))
            if 1000 <= v <= 60000 and v % 500 == 0:
                cap = v
        if cap:
            poner(f, 'Eléctrico', 'Capacidad', miles(cap) + ' mAh')
        if '22.5' in nom:
            poner(f, 'Eléctrico', 'Potencia', '22,5 W')
        if 'tipo-c' in nom or 'tipo c' in nom:
            poner(f, 'Conexión', 'Conector', 'USB-C')
    elif 'ups' in nom.split() or 'ups' in nom:
        tipo = 'Mini UPS (batería de respaldo para router)'
        cm = re.search(r'(\d{4,5})\s*mah', nom)
        if cm:
            poner(f, 'Eléctrico', 'Capacidad', miles(cm.group(1)) + ' mAh')
        if 'poe' in nom:
            poner(f, 'Conexión', 'Conector', 'Salidas DC y PoE')
    elif 'tarjeta de memoria' in nom:
        tipo = 'Tarjeta de memoria microSD Clase 10'
        cm = re.search(r'(\d+)gb', nom)
        poner(f, G, 'Capacidad', cm.group(1) + ' GB' if cm else '')
    elif 'pendrive' in nom:
        tipo = 'Pendrive USB'
        cm = re.search(r'(\d+)gb', nom)
        poner(f, G, 'Capacidad', cm.group(1) + ' GB' if cm else '')
    elif 'router' in nom or 'repetidor' in nom or 'extensor' in nom:
        tipo = 'Router Wi-Fi' if 'router' in nom else ('Extensor de rango Wi-Fi' if 'extensor' in nom else 'Repetidor Wi-Fi')
        if 'wifi 6' in nom or re.search(r'\bax\d', nom):
            tipo += ' 6'
        vm = re.search(r'\b(ax|ac)(\d{3,4})', nom)
        ant = re.search(r'(\d) antenas', nom)
        if vm:
            poner(f, G, 'Velocidad', vm.group(1).upper() + vm.group(2) + ' (doble banda 2,4 GHz y 5 GHz)')
        mb = re.search(r'(\d{3,4})\s*mbps', nom.replace('mps', 'mbps'))
        if mb and not vm:
            poner(f, G, 'Velocidad', 'Hasta ' + mb.group(1) + ' Mbps')
        if ant:
            poner(f, G, 'Antenas', ant.group(1) + ' antenas externas')
        if 'sin antena' in nom:
            poner(f, G, 'Antenas', 'Internas (sin antenas externas)')
        if 're305' in nom:
            poner(f, G, 'Antenas', '2 antenas externas')
    elif 'soporte' in nom or 'estuche soporte' in nom or 'base movile' in nom:
        tipo = 'Soporte para celular'
        if 'carro' in nom:
            tipo = 'Soporte de celular para carro'
        if 'moto' in nom:
            tipo = 'Soporte de celular para moto'
        if 'multifuncional' in nom:
            tipo = 'Soporte de celular multifuncional'
        if 'estuche' in nom:
            tipo = 'Estuche con soporte'
        if 'tv' in nom:
            tipo = 'Soporte para TV'
            sm = re.search(r'(\d{2}) a (\d{2}) pulgadas', nom)
            if 'base movile' in nom:
                tipo = 'Base móvil (con ruedas) para TV' + (', con nivelador' if 'nivelador' in nom else '')
            if sm:
                compat = 'Televisores de %s a %s pulgadas' % (sm.group(1), sm.group(2))
    else:
        simples = [
            ('correa smart watch', 'Correa deportiva para reloj inteligente', 'Relojes inteligentes'),
            ('control play 3', 'Control para PlayStation 3', 'PlayStation 3'),
            ('control play 4', 'Control para PlayStation 4', 'PlayStation 4'),
            ('control play 5', 'Control para PlayStation 5', 'PlayStation 5'),
            ('control gamepad para celular', 'Control gamepad para celular', 'Celulares'),
            ('control game pad', 'Control gamepad', ''),
            ('gamepad s10', 'Control gamepad', ''),
            ('dedales gamer', 'Dedales para jugar en el celular', 'Celulares'),
            ('playstation 5', 'Consola de videojuegos PlayStation 5', ''),
            ('consola sup', 'Consola de juegos portátil (500 juegos)', ''),
            ('consola portatil', 'Consola de juegos portátil retro', ''),
            ('consola k8', 'Consola de juegos portátil', ''),
            ('game stick', 'Consola de juegos retro en stick (HDMI)', 'Televisores con HDMI'),
            ('game proyect', 'Consola de juegos', ''),
            ('proyector', 'Proyector', ''),
            ('amplificador de pantalla', 'Amplificador de pantalla para celular', 'Celulares'),
            ('camara impresora', 'Cámara instantánea con impresora para niños', ''),
            ('llavero', 'Llavero para AirTag', 'Apple AirTag'),
            ('magnetic wallwt', 'Cartera magnética con soporte', 'iPhone con MagSafe'),
            ('mouse inalambrico', 'Mouse inalámbrico', ''),
            ('mouse', 'Mouse', ''),
            ('teclado', 'Teclado', ''),
            ('microfono inalambrico', 'Micrófono inalámbrico', ''),
            ('wireless microphone', 'Micrófono inalámbrico', ''),
            ('patineta electrica', 'Patineta eléctrica con luces LED', ''),
            ('plancha de vapor', 'Plancha de vapor para ropa', ''),
            ('plancha remington', 'Plancha para el cabello (Remington Keratin Therapy Pro)', ''),
            ('trnsmisor inalambrico para casco', 'Transmisor inalámbrico (intercomunicador) para casco', 'Cascos de moto'),
            ('smarth wacht', 'Reloj inteligente', ''),
            ('combo', 'Combo', ''),
            ('pluse', 'Corneta portátil', ''),
            ('xtreeme', 'Corneta portátil', ''),
            ('m90 pro', 'Audífonos inalámbricos (TWS)', ''),
            ('m19', 'Audífonos inalámbricos (TWS)', ''),
        ]
        for clave, t, c in simples:
            if clave in nom:
                tipo, compat = t, c
                break
        if 'plancha de vapor' in nom and 'antiadherente' in nom:
            material = 'Superficie antiadherente'
        if 'llavero' in nom and 'silicone' in nom:
            material = 'Silicona'
        if 'proyector' in nom and '720p' in nom:
            poner(f, G, 'Características', 'Resolución 720p')
        if 'usb' in nom and 'microfono' in nom:
            poner(f, 'Conexión', 'Conector', 'Receptor USB')
    poner(f, G, 'Tipo', tipo)
    poner(f, G, 'Compatible con', compat)
    poner(f, G, 'Material', material)
    return f


# ── Audio ───────────────────────────────────────────────────────────────

def ficha_audio(p):
    f = {}
    nom = n(p['nombre'])
    if 'corneta' in nom:
        tipo = 'Corneta'
        if 'bt' in nom or 'bluetooth' in nom:
            tipo = 'Corneta Bluetooth'
            poner(f, 'General', 'Conexión', 'Bluetooth')
        if 'vaso' in nom:
            tipo = 'Vaso térmico con corneta Bluetooth'
            poner(f, 'General', 'Capacidad', '420 ml')
        poner(f, 'General', 'Tipo', tipo)
        pm = re.search(r'(\d{1,2})\s*(?:"|pulgadas)', nom)
        if pm:
            poner(f, 'Sonido', 'Controladores', pm.group(1) + ' pulgadas')
    elif 'glasses' in nom:
        poner(f, 'General', 'Tipo', 'Lentes con audífonos Bluetooth')
        poner(f, 'General', 'Conexión', 'Bluetooth')
    elif 'tws' in nom or 'auriculares' in nom:
        poner(f, 'General', 'Tipo', 'Audífonos inalámbricos (TWS)')
        poner(f, 'General', 'Conexión', 'Bluetooth')
    elif re.search(r'audifon|airpods|airposd|pods|buds', nom):
        G = 'General'
        if 'wh-ch520' in nom:
            poner(f, G, 'Tipo', 'Audífonos de diadema inalámbricos (Sony WH-CH520)')
            poner(f, G, 'Conexión', 'Bluetooth')
            poner(f, G, 'Versión de Bluetooth', '5.2')
            poner(f, 'Batería', 'Duración', 'Hasta 50 horas')
            poner(f, 'Sonido', 'Micrófono', 'Sí')
        elif 'onikuma' in nom:
            # Audífonos gamer: el nombre no siempre dice si son con cable.
            poner(f, G, 'Tipo', 'Audífonos gamer de diadema (Onikuma)' + (' con sonido 7.1' if '7.1' in nom else ''))
            poner(f, 'Sonido', 'Micrófono', 'Sí')
        elif 'manos libre' in nom:
            poner(f, G, 'Tipo', 'Audífonos manos libres con cable')
            poner(f, G, 'Conexión', 'Cable USB-C' if 'tipo c' in nom else 'Cable')
            poner(f, 'Sonido', 'Micrófono', 'Sí')
        elif 'alambrico' in nom and 'inalambrico' not in nom:
            poner(f, G, 'Tipo', 'Audífonos con cable')
            poner(f, G, 'Conexión', 'Cable')
        elif re.search(r'casco|headphone|diadema|\bmax\b|700bt', nom):
            poner(f, G, 'Tipo', 'Audífonos de diadema inalámbricos')
            poner(f, G, 'Conexión', 'Bluetooth')
        elif re.search(r'inalambric|wireless|pods|buds|airpods|airposd|\bf9\b|\bm10|\bm19|\bm20', nom):
            poner(f, G, 'Tipo', 'Audífonos inalámbricos (TWS)')
            poner(f, G, 'Conexión', 'Bluetooth')
        else:
            poner(f, G, 'Tipo', 'Audífonos')
    return f


# ── Línea blanca ────────────────────────────────────────────────────────

def ficha_linea_blanca(p):
    f = {}
    nom = n(p['nombre'])
    G = 'General'
    tipo = cap = func = ''
    if 'aire' in nom and 'freidora' not in nom:
        tipo = 'Aire acondicionado'
        if 'ventana' in nom:
            tipo = 'Aire acondicionado de ventana'
        if 'split' in nom:
            tipo = 'Aire acondicionado split'
        bm = re.search(r'(\d+)\s*btu', nom)
        if bm:
            cap = miles(int(bm.group(1)) * 1000) + ' BTU'
        if 'con control' in nom:
            func = 'Control remoto'
    elif 'cafetera' in nom:
        tipo = 'Cafetera'
        cap = '12 tazas' if '12 tazas' in nom else ''
        func = 'Jarra de vidrio' + ('; programable' if 'progr' in nom else '; encendido/apagado')
        if 'negro+acero' in nom:
            poner(f, G, 'Color / acabado', 'Negro y acero')
    elif 'congelador' in nom:
        tipo = 'Congelador'
        lm = re.search(r'(\d{3})\s*l', nom)
        pm = re.search(r'(\d+) pies', nom)
        cap = ' / '.join(x for x in [(lm.group(1) + ' L') if lm else '', (pm.group(1) + ' pies') if pm else ''] if x)
    elif 'freidora' in nom:
        tipo = 'Freidora de aire'
        cap = '3,5 L' if '3.5' in nom else ''
        func = 'Panel digital' if 'digital' in nom else ''
        if 'mate' in nom:
            poner(f, G, 'Color / acabado', 'Mate')
    elif 'microondas' in nom:
        tipo = 'Horno de microondas'
        cap = '0,7 pies³' + (' (20 L)' if '20lts' in nom else '')
        if 'espejo' in nom:
            poner(f, G, 'Color / acabado', 'Acabado espejo, agarradera de acero inoxidable')
        if 'negro' in nom:
            poner(f, G, 'Color / acabado', 'Negro')
    elif 'lavadora' in nom:
        tipo = 'Lavadora'
        if 'doble tina' in nom:
            tipo = 'Lavadora de doble tina'
        if 'secadora' in nom:
            tipo = 'Lavadora y secadora'
        km = re.search(r'(\d+)\s*kg', nom)
        cap = (km.group(1) + ' kg') if km else ''
    elif 'nevera' in nom:
        tipo = 'Nevera'
        if 'exhibidora' in nom:
            tipo = 'Nevera exhibidora'
            func = 'Con cerradura' if 'cerradura' in nom else ''
        lm = re.search(r'(\d{3})\s*l', nom)
        pm = re.search(r'(\d+(?:\.\d)?)\s*(?:"|p\b)', nom)
        partes = []
        if pm:
            partes.append(pm.group(1).replace('.', ',') + ' pies')
        if lm:
            partes.append(lm.group(1) + ' L')
        cap = ' / '.join(partes)
        if 'dispensador' in nom:
            func = 'Dispensador de agua'
        if 'una puerta' in nom:
            func = (func + '; ' if func else '') + 'Una puerta'
    vm = re.search(r'(\d{3})v', nom)
    if vm:
        poner(f, 'Energía', 'Voltaje', vm.group(1) + ' V')
    poner(f, G, 'Tipo', tipo)
    poner(f, G, 'Capacidad', cap)
    poner(f, G, 'Funciones / programas', func)
    return f


# ── Televisores y afines ────────────────────────────────────────────────

def ficha_televisor(p):
    f = {}
    nom = n(p['nombre'])
    tm = re.search(r'\b(\d{2})\s*(?:"|pulgadas|\b)', nom)
    es_tv = re.search(r'\btv (de )?\d{2}|smart tv|tv smart|tv maspower', nom)
    if 'stick' in nom or 'box' in nom:
        poner(f, 'General', 'Tipo', 'Reproductor de streaming para TV')
        if 'fire tv' in nom and 'amazon' in nom:
            poner(f, 'Smart TV', 'Sistema', 'Fire TV')
        if 'mx10' in nom:
            poner(f, 'Smart TV', 'Sistema', 'Android (TV box)')
        if '4k' in nom:
            poner(f, 'Pantalla', 'Resolución', 'Hasta 4K')
        poner(f, 'Conexiones', 'HDMI', 'Sí')
        return f
    if es_tv and tm:
        poner(f, 'Pantalla', 'Tamaño', tm.group(1) + ' pulgadas')
    if 'full hd' in nom:
        poner(f, 'Pantalla', 'Resolución', 'Full HD (1920 × 1080)')
    elif re.search(r'\bhd\b', nom):
        poner(f, 'Pantalla', 'Resolución', 'HD (1366 × 768)')
    if 'qled' in nom:
        poner(f, 'Pantalla', 'Tipo de panel', 'QLED')
    if 'google tv' in nom:
        poner(f, 'Smart TV', 'Sistema', 'Google TV')
    elif 'smart' in nom:
        poner(f, 'Smart TV', 'Sistema', 'Smart TV')
    return f


def ficha_reloj(p):
    f = {}
    nom = n(p['nombre'])
    poner(f, 'General', 'Tipo', 'Reloj inteligente')
    if 'honor' in nom or 'redmi' in nom:
        poner(f, 'Conectividad', 'Bluetooth', 'Sí')
        poner(f, 'Conectividad', 'Compatibilidad', 'Android y iOS (app ' + ('Honor Health' if 'honor' in nom else 'Mi Fitness') + ')')
    return f


def ficha_linea(p):
    f = {}
    nom = n(p['nombre'])
    if 'movistar' in nom:
        poner(f, 'General', 'Operadora', 'Movistar')
    if 'chip' in nom:
        poner(f, 'General', 'Formato de SIM', 'SIM física (chip)')
    return f


def ficha_servicio(p):
    return {'Servicio': {'Descripción': 'Servicio técnico: diagnóstico y reparación de equipos'}}


GEN = {'equipo': ficha_equipo, 'computadora': ficha_computadora, 'accesorio': ficha_accesorio, 'audio': ficha_audio,
       'forro': ficha_accesorio, 'carga': ficha_accesorio, 'bateria': ficha_accesorio, 'vidrio': ficha_accesorio,
       'red': ficha_accesorio, 'memoria': ficha_accesorio,
       'linea_blanca': ficha_linea_blanca, 'televisor': ficha_televisor, 'reloj': ficha_reloj, 'linea': ficha_linea,
       'servicio': ficha_servicio}


def main():
    entrada, salida = sys.argv[1], sys.argv[2]
    d = json.load(open(entrada, encoding='utf-8'))
    out = {}
    vacios = []
    for p in d['productos']:
        f = GEN.get(p['plantilla'], lambda _: {})(p)
        f = {g: {c: v for c, v in cs.items() if v} for g, cs in f.items()}
        f = {g: cs for g, cs in f.items() if cs}
        if f:
            out[p['codigo']] = f
        else:
            vacios.append(p['nombre'])
    json.dump(out, open(salida, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    sys.stdout.reconfigure(encoding='utf-8')
    print('Con datos: %d · sin nada seguro: %d' % (len(out), len(vacios)))
    for v in vacios:
        print('   vacío:', v)


if __name__ == '__main__':
    main()
