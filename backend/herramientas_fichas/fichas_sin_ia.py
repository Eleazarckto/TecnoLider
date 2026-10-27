# -*- coding: utf-8 -*-
"""
fichas_sin_ia.py — Fichas técnicas escritas fuera del servidor, sin IA
(traído de Brizuela). Corre en la PC; NO se sube al servidor.

El primer argumento es SIEMPRE el correo de un usuario de Tecno Líder con
permiso para guardar fichas (Dueño, Administrador, Gerente, Encargado,
Activador o el maestro de soporte): el servidor lo comprueba al guardar.

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> exportar
      Baja los productos que todavía no tienen ficha y los deja, con su
      plantilla, en backend/herramientas_fichas/respaldos/pendientes.json.
      Después: fichas_por_reglas.py pendientes.json lote.json

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> cargar lote.json [...]
      Sube las fichas de uno o más archivos {codigo: {grupo: {campo: valor}}}.
      Salta los productos que ya tienen ficha (no pisa nada) y las deja
      marcadas «auto» (para revisar).

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> exportar --todos
      Igual, pero con TODOS los productos (para completar fichas existentes).

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> exportar-fichas
      Baja la ficha actual de cada producto a respaldos/actuales.json.

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> cargar --completar archivo.json
      Llena solo los campos VACÍOS de las fichas que ya existen. No pisa
      ningún dato ni toca las fichas corregidas a mano.

  python backend/herramientas_fichas/fichas_sin_ia.py <correo> cargar --corregir archivo.json
      Como --completar, pero también reemplaza un dato distinto (salvo en
      las fichas corregidas a mano).

La API de Tecno Líder no lleva clave: no hace falta ninguna.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
URL_API = 'https://sistemasceccato.com/tecnolider/api.php'
CLAVE_CATEGORIAS = 'cfg_categorias_productos'
CARPETA = os.path.join(AQUI, 'respaldos')

CORREO = ''


def pedir(recurso, params=None, cuerpo=None):
    q = {'resource': recurso}
    q.update(params or {})
    url = URL_API + '?' + urllib.parse.urlencode(q)
    if cuerpo is not None:
        cuerpo = dict(cuerpo, usuario_correo=CORREO)
    datos = json.dumps(cuerpo, ensure_ascii=False).encode('utf-8') if cuerpo is not None else None
    req = urllib.request.Request(url, data=datos, method='POST' if datos else 'GET',
                                 headers={'Content-Type': 'application/json', 'Accept': 'application/json'})
    # Hasta 3 intentos si se corta la conexión (pasa con cientos de pedidos
    # seguidos). Guardar la misma ficha dos veces no hace daño.
    for intento in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                texto = r.read().decode('utf-8')
            break
        except urllib.error.HTTPError as e:
            texto = e.read().decode('utf-8', 'replace')
            break
        except (urllib.error.URLError, ConnectionError, OSError):
            if intento == 2:
                raise
            time.sleep(3 * (intento + 1))
    j = json.loads(texto)
    if isinstance(j, dict) and 'ok' in j:
        if not j['ok']:
            raise RuntimeError(j.get('error', 'error sin detalle'))
        return j.get('data')
    if isinstance(j, dict) and 'error' in j:
        raise RuntimeError(j['error'])
    return j


def productos():
    """Una fila por código (en `productos` hay una por tienda), sin los
    que no tienen nombre. El listado de la API ya viene sin los borrados."""
    vistos = {}
    for p in pedir('productos') or []:
        codigo = str(p.get('codigo', '')).strip()
        if not codigo or not str(p.get('nombre', '')).strip() or p.get('eliminado_en'):
            continue
        vistos.setdefault(codigo, p)
    return list(vistos.values())


def categorias():
    """[{nombre, usa_imei}] tal como la app los guarda en configuracion."""
    try:
        cfg = pedir('configuracion') or {}
        lista = json.loads(cfg.get(CLAVE_CATEGORIAS) or '[]')
        return lista if isinstance(lista, list) else []
    except Exception:
        return []


def con_ficha():
    r = pedir('ficha_tecnica') or {}
    return {f['codigo'] for f in r.get('fichas', []) if int(f.get('llenos') or 0) > 0}


def guardar_json(nombre, datos):
    os.makedirs(CARPETA, exist_ok=True)
    destino = os.path.join(CARPETA, nombre)
    with open(destino, 'w', encoding='utf-8') as f:
        json.dump(datos, f, ensure_ascii=False, indent=1)
    return destino


def exportar_fichas():
    """Baja la ficha ACTUAL de cada producto, con sus campos vacíos."""
    prods = productos()
    salida = []
    for i, p in enumerate(prods, 1):
        codigo = str(p.get('codigo', ''))
        try:
            f = pedir('ficha_tecnica', {'codigo': codigo})
        except Exception as e:
            print('  ERROR %-12s %s' % (codigo, e))
            continue
        salida.append({'codigo': codigo, 'nombre': f.get('nombre', ''), 'categoria': p.get('categoria', ''),
                       'marca': p.get('marca', ''), 'plantilla': f.get('plantilla', ''), 'origen': f.get('origen', ''),
                       'campos': f.get('campos', [])})
        if i % 50 == 0:
            print('  %d de %d' % (i, len(prods)))
    destino = guardar_json('actuales.json', salida)
    vacios = sum(1 for x in salida for c in x['campos'] if not str(c.get('valor', '')).strip())
    print('Fichas: %d · campos vacíos: %d' % (len(salida), vacios))
    print('Guardado en %s' % destino)


def exportar(todos=False):
    prods = productos()
    ya = con_ficha()
    faltan = [p for p in prods if todos or str(p.get('codigo', '')) not in ya]
    entrada = json.dumps({'productos': faltan, 'categorias': categorias()}, ensure_ascii=False)
    php = subprocess.run(['php', os.path.join(AQUI, 'plantillas_cli.php')],
                         input=entrada.encode('utf-8'), capture_output=True, check=True)
    salida = json.loads(php.stdout.decode('utf-8'))
    destino = guardar_json('pendientes.json', salida)
    print('Productos: %d · con ficha: %d · a exportar: %d' % (len(prods), len(ya), len(faltan)))
    print('Guardado en %s' % destino)


def completar(archivos, corregir=False):
    """Llena SOLO los campos vacíos de cada ficha con los del archivo. No pisa
    ningún dato que ya esté, ni toca las fichas corregidas a mano."""
    hechas = sin_cambio = manuales = errores = 0
    for archivo in archivos:
        with open(archivo, encoding='utf-8') as f:
            fichas = json.load(f)
        for codigo, grupos in fichas.items():
            try:
                actual = pedir('ficha_tecnica', {'codigo': codigo})
            except Exception as e:
                errores += 1
                print('  ERROR %-12s %s' % (codigo, e))
                continue
            if actual.get('origen') == 'manual':
                manuales += 1
                continue
            campos = [dict(c) for c in actual.get('campos', [])]
            idx = {(c['grupo'].lower(), c['campo'].lower()): c for c in campos}
            nuevos = 0
            for g, cs in grupos.items():
                for c, v in cs.items():
                    v = str(v).strip()
                    if not v:
                        continue
                    hay = idx.get((g.lower(), c.lower()))
                    if hay is None:
                        campos.append({'grupo': g, 'campo': c, 'valor': v})
                        nuevos += 1
                    elif not str(hay.get('valor', '')).strip() or (corregir and hay.get('valor') != v):
                        hay['valor'] = v
                        nuevos += 1
            if nuevos == 0:
                sin_cambio += 1
                continue
            try:
                pedir('ficha_tecnica_guardar', cuerpo={'codigo': codigo, 'campos': campos, 'por_revisar': True})
                hechas += 1
                print('  ok    %-12s +%d datos' % (codigo, nuevos))
            except Exception as e:
                errores += 1
                print('  ERROR %-12s %s' % (codigo, e))
    print('Completadas: %d · sin nada que agregar: %d · corregidas a mano (no se tocaron): %d · errores: %d'
          % (hechas, sin_cambio, manuales, errores))
    return 0 if errores == 0 else 1


def cargar(archivos):
    ya = con_ficha()
    subidas = saltadas = errores = 0
    for archivo in archivos:
        with open(archivo, encoding='utf-8') as f:
            fichas = json.load(f)
        for codigo, grupos in fichas.items():
            if codigo in ya:
                saltadas += 1
                continue
            campos = [{'grupo': g, 'campo': c, 'valor': str(v)}
                      for g, cs in grupos.items() for c, v in cs.items() if str(v).strip()]
            if not campos:
                continue
            try:
                pedir('ficha_tecnica_guardar', cuerpo={'codigo': codigo, 'campos': campos, 'por_revisar': True})
                subidas += 1
                print('  ok    %-12s %d datos' % (codigo, len(campos)))
            except Exception as e:
                errores += 1
                print('  ERROR %-12s %s' % (codigo, e))
    print('Subidas: %d · ya tenían ficha (no se tocaron): %d · errores: %d' % (subidas, saltadas, errores))
    return 0 if errores == 0 else 1


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    if len(sys.argv) < 3 or '@' not in sys.argv[1]:
        print(__doc__.strip())
        sys.exit(1)
    CORREO = sys.argv[1].strip()
    args = sys.argv[2:]
    if args[0] == 'exportar':
        exportar('--todos' in args)
    elif args[0] == 'exportar-fichas':
        exportar_fichas()
    elif len(args) >= 3 and args[0] == 'cargar' and args[1] == '--completar':
        sys.exit(completar(args[2:]))
    elif len(args) >= 3 and args[0] == 'cargar' and args[1] == '--corregir':
        sys.exit(completar(args[2:], corregir=True))
    elif len(args) >= 2 and args[0] == 'cargar':
        sys.exit(cargar(args[1:]))
    else:
        print(__doc__.strip())
        sys.exit(1)
