/* =====================================================================
   PROYECTO MÓDULO 2 · SQL
   03_eda.sql  →  Análisis Exploratorio de Datos (EDA) en SQL
   Motor: MySQL 8.0+   ·   Requiere 01_schema.sql y 02_data.sql
   ---------------------------------------------------------------------
   PREGUNTAS DE NEGOCIO QUE RESPONDE ESTE ANÁLISIS
     1. ¿Cuánto vendemos y cómo evoluciona? (KPIs, año contra año)
     2. ¿Cuándo vendemos? (estacionalidad, día de la semana)
     3. ¿Dónde vendemos y dónde deberíamos abrir? (geografía)
     4. ¿Qué concesionarios y comerciales rinden mejor?
     5. ¿Qué vendemos y a quién? (segmentos, marcas, modelos, edad)
     6. ¿Cómo pagan los clientes y por qué se caen ventas?
     7. ¿Estamos regalando margen con los descuentos?
   Criterio general: salvo que se indique, se analizan solo las ventas
   con estado = 'Completada' (una cancelada no genera ingreso).
   ===================================================================== */

USE motos_dw;
SET NAMES utf8mb4;
SET lc_time_names = 'es_ES';


/* =====================================================================
   1. KPIs GLOBALES
   ===================================================================== */

-- 1.1 Cuadro de mando general del periodo 2024-2025.
--     SUBCONSULTAS escalares para el total de clientes del CRM y el rango
--     de fechas; CAST para mostrar la tasa de conversión como porcentaje.
SELECT
    COUNT(*)                                                    AS lineas_venta,
    SUM(v.estado = 'Completada')                                AS ventas_completadas,
    SUM(v.estado = 'Cancelada')                                 AS ventas_canceladas,
    SUM(CASE WHEN v.estado = 'Completada' THEN v.unidades END)  AS motos_vendidas,
    SUM(CASE WHEN v.estado = 'Completada' THEN v.importe_total END) AS facturacion_eur,
    ROUND(AVG(CASE WHEN v.estado = 'Completada' THEN v.importe_total END), 2) AS ticket_medio_eur,
    COUNT(DISTINCT CASE WHEN v.estado = 'Completada' THEN v.id_cliente END) AS clientes_compradores,
    (SELECT COUNT(*) FROM dim_cliente)                          AS clientes_en_crm,
    CAST(COUNT(DISTINCT CASE WHEN v.estado = 'Completada' THEN v.id_cliente END) * 100.0
         / (SELECT COUNT(*) FROM dim_cliente) AS DECIMAL(5,1))  AS pct_conversion_crm,
    (SELECT DATE_FORMAT(MIN(c.fecha), '%d/%m/%Y') FROM fact_ventas f
       JOIN dim_calendario c ON c.id_fecha = f.id_fecha)        AS primera_venta,
    (SELECT DATE_FORMAT(MAX(c.fecha), '%d/%m/%Y') FROM fact_ventas f
       JOIN dim_calendario c ON c.id_fecha = f.id_fecha)        AS ultima_venta
FROM fact_ventas v;
/* INSIGHT 1.1
   · 2.405 operaciones en 2 años: 2.304 completadas y 101 canceladas (4,2 %).
   · 2.530 motos vendidas y 23,79 M€ facturados, con un ticket medio de 10.327 €.
   · 2.111 de los 2.708 contactos del CRM han comprado (78,0 %).
   → Estas cifras son la "línea base" contra la que se compara todo lo demás. */


/* =====================================================================
   2. EVOLUCIÓN ANUAL
   ===================================================================== */

-- 2.1 Crecimiento año contra año (YoY). CTE + función ventana LAG():
--     LAG trae el valor del año anterior a la fila actual para comparar.
WITH ventas_anio AS (
    SELECT c.anio,
           SUM(v.unidades)       AS motos,
           SUM(v.importe_total)  AS facturacion,
           AVG(v.importe_total)  AS ticket_medio
    FROM fact_ventas    v
    INNER JOIN dim_calendario c ON c.id_fecha = v.id_fecha
    WHERE v.estado = 'Completada'
    GROUP BY c.anio
)
SELECT anio,
       motos,
       facturacion,
       ROUND(ticket_medio, 2)                                          AS ticket_medio,
       ROUND((motos / LAG(motos) OVER (ORDER BY anio) - 1) * 100, 1)   AS crec_motos_pct,
       ROUND((facturacion / LAG(facturacion) OVER (ORDER BY anio) - 1) * 100, 1) AS crec_facturacion_pct,
       ROUND((ticket_medio / LAG(ticket_medio) OVER (ORDER BY anio) - 1) * 100, 1) AS crec_ticket_pct
FROM ventas_anio
ORDER BY anio;
/* INSIGHT 2.1
   · 2025 crece un 15,3 % en motos y un 19,6 % en facturación.
   · El ticket medio sube un 5,1 %, más que la subida de tarifa (3 %): el
     cliente está comprando moto más cara (lo explica el auge del segmento
     Trail, ver 6.1).
   → El negocio crece en volumen Y en valor: buen momento para invertir. */


/* =====================================================================
   3. ESTACIONALIDAD
   ===================================================================== */

-- 3.1 Ventas por mes, peso de cada mes dentro de su año, acumulado anual
--     y media móvil de 3 meses. Varias funciones ventana:
--       · SUM() OVER (PARTITION BY anio)            → total del año
--       · SUM() OVER (PARTITION BY anio ORDER BY mes) → acumulado (YTD)
--       · AVG() OVER (... ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
WITH ventas_mes AS (
    SELECT c.anio, c.mes, c.nombre_mes,
           SUM(v.unidades) AS motos
    FROM fact_ventas v
    INNER JOIN dim_calendario c ON c.id_fecha = v.id_fecha
    WHERE v.estado = 'Completada'
    GROUP BY c.anio, c.mes, c.nombre_mes
)
SELECT anio, mes, nombre_mes, motos,
       ROUND(motos * 100 / SUM(motos) OVER (PARTITION BY anio), 1)       AS pct_del_anio,
       SUM(motos) OVER (PARTITION BY anio ORDER BY mes)                  AS acumulado_anio,
       ROUND(AVG(motos) OVER (ORDER BY anio, mes
                              ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS media_movil_3m
FROM ventas_mes
ORDER BY anio, mes;
/* INSIGHT 3.1
   · Estacionalidad muy marcada y repetida los dos años: mayo es el mejor
     mes (12,6 % y 13,7 % del año) y enero el peor (4,9 % y 3,8 %).
   · Marzo a julio concentran más de la mitad de las ventas; agosto cae
     (vacaciones) y octubre tiene un segundo repunte.
   · La media móvil de 3 meses alcanza su máximo en junio de 2025 (160,7).
   → Decisiones: pedir stock en febrero para llegar lleno a primavera,
     lanzar campañas en marzo y concentrar vacaciones del personal en
     enero y agosto. */

-- 3.2 Ventas por temporada (atributo del calendario) y descuento medio.
SELECT c.temporada,
       SUM(v.unidades)                AS motos,
       ROUND(AVG(v.descuento_pct), 2) AS descuento_medio_pct
FROM fact_ventas v
INNER JOIN dim_calendario c ON c.id_fecha = v.id_fecha
WHERE v.estado = 'Completada'
  AND v.unidades = 1                    -- excluye flotas (descuento pactado aparte)
GROUP BY c.temporada
ORDER BY FIELD(c.temporada, 'Invierno', 'Primavera', 'Verano', 'Otoño');
/* INSIGHT 3.2
   · En invierno se concede el DOBLE de descuento que en primavera
     (5,86 % vs 2,74 %) y aun así se venden casi la mitad de motos (397 vs 725).
   → La caída de invierno es climática y el descuento no la compensa.
     Alternativas a probar: financiación sin intereses, reserva en invierno
     con entrega en primavera o regalo de equipación, en lugar de bajar precio. */

-- 3.3 Día de la semana. LEFT JOIN desde el calendario: así aparecen
--     también los días SIN ventas (con INNER JOIN el domingo desaparecería
--     y no veríamos que la red está cerrada ese día).
SELECT c.dia_semana,
       c.nombre_dia,
       CASE WHEN c.es_fin_semana THEN 'Fin de semana' ELSE 'Laborable' END AS tipo_dia,
       COUNT(DISTINCT c.id_fecha)                              AS dias_en_periodo,
       COUNT(v.id_venta)                                       AS ventas,
       ROUND(COUNT(v.id_venta) / COUNT(DISTINCT c.id_fecha), 2) AS ventas_por_dia
FROM dim_calendario c
LEFT JOIN fact_ventas v ON v.id_fecha = c.id_fecha
                       AND v.estado = 'Completada'   -- el filtro va en el ON, no en el WHERE,
                                                      -- para no convertir el LEFT en INNER
GROUP BY c.dia_semana, c.nombre_dia, c.es_fin_semana
ORDER BY c.dia_semana;
/* INSIGHT 3.3
   · El sábado es el mejor día: 4,86 ventas/día, un 62 % más que el
     miércoles (3,00). El viernes es el segundo (4,22).
   · El domingo tiene 0 ventas: la red está cerrada.
   → Reforzar plantilla y pruebas de moto en viernes y sábado. Valorar un
     piloto de apertura de domingos en primavera en los concesionarios grandes. */


/* =====================================================================
   4. GEOGRAFÍA
   ===================================================================== */

-- 4.1 Ventas por comunidad y provincia DEL CONCESIONARIO (INNER JOIN en
--     cadena: hechos → concesionario → provincia) y peso sobre el total.
SELECT p.comunidad_autonoma,
       p.nombre                          AS provincia,
       COUNT(DISTINCT co.id_concesionario) AS concesionarios,
       SUM(v.unidades)                   AS motos,
       SUM(v.importe_total)              AS facturacion,
       ROUND(SUM(v.importe_total) * 100 / SUM(SUM(v.importe_total)) OVER (), 1) AS pct_facturacion
FROM fact_ventas v
INNER JOIN dim_concesionario co ON co.id_concesionario = v.id_concesionario
INNER JOIN dim_provincia     p  ON p.id_provincia      = co.id_provincia
WHERE v.estado = 'Completada'
GROUP BY p.comunidad_autonoma, p.nombre
ORDER BY facturacion DESC;
/* INSIGHT 4.1
   · Barcelona (25,0 %) y Madrid (20,5 %) generan el 45,5 % de la
     facturación con solo 4 de los 12 concesionarios.
   · Andalucía suma un 24,4 % entre Málaga, Sevilla y Córdoba.
   → La red depende mucho de dos mercados: cualquier problema en Barcelona
     o Madrid afecta a casi la mitad del negocio. */

-- 4.2 Penetración de mercado: motos vendidas por cada 100.000 habitantes
--     según la provincia DE RESIDENCIA del cliente. Doble LEFT JOIN para
--     no perder ninguna provincia; CASE para marcar si tiene concesionario
--     (subconsulta EXISTS).
SELECT p.nombre AS provincia_residencia,
       p.poblacion,
       CASE WHEN EXISTS (SELECT 1 FROM dim_concesionario co
                         WHERE co.id_provincia = p.id_provincia)
            THEN 'Sí' ELSE 'NO' END                         AS tiene_concesionario,
       COUNT(v.id_venta)                                    AS motos_particulares,
       ROUND(COUNT(v.id_venta) * 100000 / p.poblacion, 1)   AS motos_por_100k_hab
FROM dim_provincia p
LEFT JOIN dim_cliente cl ON cl.id_provincia = p.id_provincia
                        AND cl.tipo_cliente = 'Particular'
LEFT JOIN fact_ventas v  ON v.id_cliente = cl.id_cliente
                        AND v.estado = 'Completada'
GROUP BY p.id_provincia, p.nombre, p.poblacion
ORDER BY motos_por_100k_hab DESC;
/* INSIGHT 4.2
   · Mayor penetración: Málaga (9,0 motos/100k hab.), Barcelona (8,7) y
     Sevilla (8,4): clima y cultura de la moto.
   · Cádiz (7,6) y Alicante (7,2) NO tienen concesionario y aun así compran
     más por habitante que Madrid (6,4).
   · El norte queda a la cola: A Coruña (3,9) y Asturias (3,7).
   → Hay demanda sin cubrir en provincias sin tienda propia (ver 4.3). */

-- 4.3 Clientes de provincias SIN concesionario: ¿dónde compran?
--     Mide la "fuga" hacia otras provincias y dimensiona una apertura.
SELECT pcl.nombre AS provincia_cliente,
       co.nombre  AS concesionario_donde_compra,
       pco.nombre AS provincia_concesionario,
       COUNT(*)   AS ventas,
       SUM(v.importe_total) AS facturacion
FROM fact_ventas v
INNER JOIN dim_cliente       cl  ON cl.id_cliente        = v.id_cliente
INNER JOIN dim_provincia     pcl ON pcl.id_provincia     = cl.id_provincia
INNER JOIN dim_concesionario co  ON co.id_concesionario  = v.id_concesionario
INNER JOIN dim_provincia     pco ON pco.id_provincia     = co.id_provincia
WHERE v.estado = 'Completada'
  AND cl.id_provincia NOT IN (SELECT id_provincia FROM dim_concesionario)   -- subconsulta
GROUP BY pcl.nombre, co.nombre, pco.nombre
HAVING COUNT(*) >= 5                     -- se ignoran compras sueltas (viajes, segundas residencias)
ORDER BY pcl.nombre, ventas DESC;
/* INSIGHT 4.3
   · Los clientes de Alicante compran 139 motos (1,51 M€) desplazándose a
     Murcia y Valencia. Baleares aporta 1,10 M€ comprando en Barcelona y
     Valencia (cruzando en barco), Granada 0,87 M€ y Cádiz 0,84 M€.
   · Un concesionario en Alicante ya facturaría como uno "B · En media"
     (ver 5.1), sin contar la demanda nueva que capte por cercanía.
   → Recomendación de expansión: 1º Alicante, 2º Baleares.
     Riesgo: canibalización. 75 de las 187 ventas de Motos Segura (Murcia),
     un 40 %, son de clientes alicantinos. */


/* =====================================================================
   5. CONCESIONARIOS
   ===================================================================== */

-- 5.1 CTEs ENCADENADAS: cada CTE usa el resultado de la anterior.
--     (1) facturación por concesionario → (2) media de la red →
--     (3) clasificación de cada concesionario frente a la media.
WITH fact_concesionario AS (                                  -- paso 1
    SELECT co.id_concesionario,
           co.nombre,
           co.tipo_zona,
           co.superficie_m2,
           SUM(v.unidades)      AS motos,
           SUM(v.importe_total) AS facturacion
    FROM fact_ventas v
    INNER JOIN dim_concesionario co ON co.id_concesionario = v.id_concesionario
    WHERE v.estado = 'Completada'
    GROUP BY co.id_concesionario, co.nombre, co.tipo_zona, co.superficie_m2
),
media_red AS (                                                -- paso 2 (usa el paso 1)
    SELECT AVG(facturacion) AS media_facturacion
    FROM fact_concesionario
),
clasificacion AS (                                            -- paso 3 (usa 1 y 2)
    SELECT f.*,
           ROUND(f.facturacion / m.media_facturacion * 100, 0) AS indice_vs_media,
           ROUND(f.facturacion / f.superficie_m2, 0)           AS eur_por_m2,
           CASE
               WHEN f.facturacion >= m.media_facturacion * 1.25 THEN 'A · Líder'
               WHEN f.facturacion >= m.media_facturacion * 0.75 THEN 'B · En media'
               ELSE                                                  'C · A revisar'
           END AS categoria
    FROM fact_concesionario f
    CROSS JOIN media_red m
)
SELECT RANK() OVER (ORDER BY facturacion DESC) AS ranking,
       nombre, tipo_zona, motos, facturacion, indice_vs_media, eur_por_m2, categoria
FROM clasificacion
ORDER BY ranking;
/* INSIGHT 5.1
   · Motos Diagonal (Barcelona) lidera: 3,52 M€, un 77 % por encima de la
     media, y es el más eficiente (5.022 €/m²).
   · Los locales de centro urbano facturan más por m² (Turia 3.336,
     Castellana 3.331) que los de periferia, que son más grandes.
   · 4 concesionarios están en categoría C (menos del 75 % de la media):
     Mezquita, Abando, Riazor y Ebro. Motos Ebro es el más ineficiente:
     1.000 m² y solo 640 €/m².
   → Revisar Motos Ebro: ¿local sobredimensionado? (ver también 5.2 y 9.3). */

-- 5.2 Crecimiento 2024 → 2025 por concesionario usando la FUNCIÓN
--     fn_facturacion_concesionario (definida en 01_schema.sql).
SELECT co.codigo,
       co.nombre,
       fn_facturacion_concesionario(co.id_concesionario, 2024) AS facturacion_2024,
       fn_facturacion_concesionario(co.id_concesionario, 2025) AS facturacion_2025,
       ROUND((fn_facturacion_concesionario(co.id_concesionario, 2025)
            / fn_facturacion_concesionario(co.id_concesionario, 2024) - 1) * 100, 1) AS crecimiento_pct
FROM dim_concesionario co
ORDER BY crecimiento_pct DESC;
/* INSIGHT 5.2
   · 11 de 12 concesionarios crecen. Abando (+89,2 %) crece mucho pero
     partía de una base pequeña.
   · Motos Ebro es el único que cae: −28,6 %. En 9.3 aparece una posible
     causa: una de sus 3 comerciales no registra ventas desde mayo de 2025.
   → Plan de acción específico para Zaragoza. */

-- 5.3 Centro urbano vs periferia: ¿cambia el mix de producto?
SELECT co.tipo_zona,
       COUNT(*)                                          AS ventas,
       ROUND(AVG(mo.segmento = 'Scooter') * 100, 1)       AS pct_scooter,
       ROUND(AVG(mo.segmento IN ('Trail','Touring')) * 100, 1) AS pct_trail_touring,
       ROUND(AVG(v.importe_total), 0)                    AS ticket_medio
FROM fact_ventas v
INNER JOIN dim_concesionario co ON co.id_concesionario = v.id_concesionario
INNER JOIN dim_modelo        mo ON mo.id_modelo        = v.id_modelo
WHERE v.estado = 'Completada'
  AND v.unidades = 1                                     -- solo particulares, sin flotas
GROUP BY co.tipo_zona;
/* INSIGHT 5.3
   · En centro urbano el 32,0 % de las ventas son scooters, frente al
     23,7 % en periferia. En periferia pesan más trail y touring
     (29,9 % vs 26,9 %). El ticket medio es parecido.
   → Surtido distinto por tipo de tienda: más scooters y movilidad urbana
     en el centro; más exposición de trail (y zona de pruebas) en periferia. */


/* =====================================================================
   6. PRODUCTO
   ===================================================================== */

-- 6.1 Segmentos: 2024 vs 2025 en columnas ("pivot" con CASE dentro de SUM)
SELECT mo.segmento,
       SUM(CASE WHEN c.anio = 2024 THEN v.unidades ELSE 0 END) AS motos_2024,
       SUM(CASE WHEN c.anio = 2025 THEN v.unidades ELSE 0 END) AS motos_2025,
       ROUND((SUM(CASE WHEN c.anio = 2025 THEN v.unidades ELSE 0 END)
            / SUM(CASE WHEN c.anio = 2024 THEN v.unidades ELSE 0 END) - 1) * 100, 1) AS crec_pct,
       SUM(v.importe_total)                                    AS facturacion_total,
       ROUND(SUM(v.importe_total) * 100 / SUM(SUM(v.importe_total)) OVER (), 1) AS pct_facturacion
FROM fact_ventas v
INNER JOIN dim_calendario c  ON c.id_fecha   = v.id_fecha
INNER JOIN dim_modelo     mo ON mo.id_modelo = v.id_modelo
WHERE v.estado = 'Completada'
GROUP BY mo.segmento
ORDER BY facturacion_total DESC;
/* INSIGHT 6.1
   · Trail es el segmento estrella: 32,7 % de la facturación y +43,1 % de
     unidades en 2025.
   · Scooter es el que más unidades mueve (806) pero solo aporta el 16,5 %
     de la facturación: mucho volumen a precio bajo.
   · Sport cae un 28,7 %: el mercado se aleja de las deportivas.
   → Ampliar gama y stock de trail, reducir exposición de sport. */

-- 6.2 Marcas: cuota en unidades vs cuota en facturación. Una marca con
--     más cuota de € que de unidades vende producto caro (y al revés).
SELECT ma.nombre AS marca,
       CASE WHEN ma.es_premium THEN 'Premium' ELSE 'Generalista' END AS posicionamiento,
       SUM(v.unidades)      AS motos,
       SUM(v.importe_total) AS facturacion,
       ROUND(SUM(v.unidades)      * 100 / SUM(SUM(v.unidades))      OVER (), 1) AS cuota_unidades_pct,
       ROUND(SUM(v.importe_total) * 100 / SUM(SUM(v.importe_total)) OVER (), 1) AS cuota_facturacion_pct
FROM fact_ventas v
INNER JOIN dim_modelo mo ON mo.id_modelo = v.id_modelo
INNER JOIN dim_marca  ma ON ma.id_marca  = mo.id_marca
WHERE v.estado = 'Completada'
GROUP BY ma.nombre, ma.es_premium
ORDER BY facturacion DESC;
/* INSIGHT 6.2
   · Honda y Yamaha venden el 45,4 % de las unidades.
   · BMW Motorrad es el mejor ejemplo de marca de valor: 7,6 % de las
     unidades pero 15,7 % de la facturación (el doble).
   · Kymco es lo contrario: 9,2 % de unidades y 3,3 % de facturación.
   → Negociar rápeles por volumen con Honda y Yamaha; cuidar a BMW, que
     aporta mucha facturación con pocas unidades. */

-- 6.3 Top 3 modelos de cada segmento. ROW_NUMBER() OVER (PARTITION BY
--     segmento ...) reinicia la numeración en cada segmento; como no se
--     puede filtrar una función ventana en el WHERE, se calcula en una CTE.
WITH ranking_modelos AS (
    SELECT mo.segmento,
           CONCAT(ma.nombre, ' ', mo.nombre) AS modelo,
           SUM(v.unidades)                   AS motos,
           SUM(v.importe_total)              AS facturacion,
           ROW_NUMBER() OVER (PARTITION BY mo.segmento
                              ORDER BY SUM(v.unidades) DESC) AS puesto
    FROM fact_ventas v
    INNER JOIN dim_modelo mo ON mo.id_modelo = v.id_modelo
    INNER JOIN dim_marca  ma ON ma.id_marca  = mo.id_marca
    WHERE v.estado = 'Completada'
    GROUP BY mo.segmento, ma.nombre, mo.nombre
)
SELECT segmento, puesto, modelo, motos, facturacion
FROM ranking_modelos
WHERE puesto <= 3
ORDER BY segmento, puesto;
/* INSIGHT 6.3
   · La Yamaha MT-07 domina las naked (121 uds.), el doble que la segunda.
   · En trail, la Ténéré 700 vende más unidades (115), pero la BMW R 1300 GS
     factura más (1,66 M€ con 74 uds.): volumen frente a valor.
   · La Honda PCX125 lidera scooters (155 uds.).
   → Estos modelos no pueden faltar nunca en stock. */

-- 6.4 Modelos del catálogo con pocas o ninguna venta. LEFT JOIN desde
--     dim_modelo: un INNER JOIN ocultaría justo los modelos sin ventas.
SELECT ma.nombre AS marca,
       mo.nombre AS modelo,
       mo.segmento,
       mo.precio_base,
       CASE WHEN mo.activo THEN 'Activo' ELSE 'Descatalogado' END AS estado_catalogo,
       COUNT(v.id_venta) AS ventas
FROM dim_modelo mo
INNER JOIN dim_marca  ma ON ma.id_marca  = mo.id_marca
LEFT  JOIN fact_ventas v ON v.id_modelo  = mo.id_modelo
                        AND v.estado     = 'Completada'
GROUP BY ma.nombre, mo.nombre, mo.segmento, mo.precio_base, mo.activo
HAVING COUNT(v.id_venta) < 15
ORDER BY ventas;
/* INSIGHT 6.4
   · La Kawasaki Ninja 7 Hybrid tiene 0 ventas en dos años: es una 451 cc
     a 12.495 €, mucho más cara que la alternativa A2 de su propia marca,
     la Ninja 650 (7.995 €).
   · La Harley-Davidson Street Glide (32.900 €) solo vende 12 unidades.
   → Retirar la Ninja 7 Hybrid de la exposición y servir la Street Glide
     solo bajo pedido: liberan espacio y capital inmovilizado. */

-- 6.5 Adopción de una tecnología nueva: CBR650R con embrague electrónico
--     E-Clutch (lanzada a mitad de 2024) frente a la versión convencional.
SELECT c.anio,
       SUM(mo.nombre = 'CBR650R')          AS cbr650r_convencional,
       SUM(mo.nombre = 'CBR650R E-Clutch') AS cbr650r_e_clutch,
       ROUND(SUM(mo.nombre = 'CBR650R E-Clutch') * 100 / COUNT(*), 1) AS pct_e_clutch
FROM fact_ventas v
INNER JOIN dim_modelo     mo ON mo.id_modelo = v.id_modelo
INNER JOIN dim_calendario c  ON c.id_fecha   = v.id_fecha
WHERE v.estado = 'Completada'
  AND mo.nombre LIKE 'CBR650R%'
GROUP BY c.anio;
/* INSIGHT 6.5
   · La versión E-Clutch se queda en torno a 1 de cada 3 CBR650R vendidas
     (34,0 % en 2024 y 31,4 % en 2025) y no gana cuota en su primer año
     completo, pese a costar solo 600 € más.
   → El cliente no está pagando por esta tecnología: priorizar stock de la
     versión convencional y ofrecer la E-Clutch bajo pedido. */


/* =====================================================================
   7. CLIENTES
   ===================================================================== */

-- 7.1 Perfil por edad EN EL MOMENTO DE LA COMPRA (función fn_edad) y
--     segmento preferido. CASE para crear los tramos de edad.
WITH ventas_edad AS (
    SELECT CASE
               WHEN fn_edad(cl.fecha_nacimiento, c.fecha) <= 25 THEN '1) 18-25'
               WHEN fn_edad(cl.fecha_nacimiento, c.fecha) <= 35 THEN '2) 26-35'
               WHEN fn_edad(cl.fecha_nacimiento, c.fecha) <= 50 THEN '3) 36-50'
               ELSE                                                   '4) 51+'
           END AS tramo_edad,
           mo.segmento,
           v.importe_total,
           v.metodo_pago
    FROM fact_ventas v
    INNER JOIN dim_cliente    cl ON cl.id_cliente = v.id_cliente
    INNER JOIN dim_calendario c  ON c.id_fecha    = v.id_fecha
    INNER JOIN dim_modelo     mo ON mo.id_modelo  = v.id_modelo
    WHERE v.estado = 'Completada'
      AND cl.tipo_cliente = 'Particular'
)
SELECT tramo_edad,
       COUNT(*)                                   AS ventas,
       ROUND(AVG(importe_total), 0)               AS ticket_medio,
       ROUND(AVG(segmento = 'Scooter') * 100, 1)  AS pct_scooter,
       ROUND(AVG(segmento = 'Naked')   * 100, 1)  AS pct_naked,
       ROUND(AVG(segmento = 'Trail')   * 100, 1)  AS pct_trail,
       ROUND(AVG(segmento IN ('Touring','Custom')) * 100, 1) AS pct_touring_custom,
       ROUND(AVG(metodo_pago = 'Financiado') * 100, 1)      AS pct_financiado
FROM ventas_edad
GROUP BY tramo_edad
ORDER BY tramo_edad;
/* INSIGHT 7.1
   · El ticket medio crece con la edad: de 7.272 € (18-25) a 12.380 € (51+),
     un 70 % más.
   · Los jóvenes compran scooter (39,7 %) y naked (35,1 %); los mayores de
     50, trail (36,4 %) y touring/custom (24,2 %).
   · Aproximadamente la mitad financia en todos los tramos (48-53 %).
   → Campañas segmentadas: jóvenes → naked A2 con cuota mensual;
     mayores de 50 → trail/touring premium con prueba de moto. */

-- 7.2 Conversión del CRM y recompra. LEFT JOIN cliente → ventas para
--     contar también a quien nunca ha comprado (0 compras).
WITH compras_cliente AS (
    SELECT cl.id_cliente,
           COUNT(v.id_venta) AS n_compras
    FROM dim_cliente cl
    LEFT JOIN fact_ventas v ON v.id_cliente = cl.id_cliente
                           AND v.estado     = 'Completada'
    WHERE cl.tipo_cliente = 'Particular'
    GROUP BY cl.id_cliente
)
SELECT CASE n_compras
           WHEN 0 THEN 'Lead sin compra'
           WHEN 1 THEN 'Comprador único'
           ELSE        'Recurrente (2+)'
       END                                                    AS tipo,
       COUNT(*)                                               AS clientes,
       ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)       AS pct_clientes
FROM compras_cliente
GROUP BY tipo
ORDER BY clientes DESC;
/* INSIGHT 7.2
   · El 72,0 % de los particulares ha comprado una sola vez, el 5,9 % es
     recurrente y el 22,1 % (597 personas) son leads que nunca compraron.
   · La recompra es baja porque una moto se cambia cada varios años.
   → 597 leads son una bolsa de ventas a reactivar con remarketing.
     Para fidelizar: programa de recompra o valor futuro garantizado. */

-- 7.3 Particulares vs empresas (flotas de reparto, alquiler turístico...)
SELECT cl.tipo_cliente,
       COUNT(DISTINCT cl.id_cliente)                AS clientes,
       COUNT(*)                                     AS operaciones,
       SUM(v.unidades)                              AS motos,
       SUM(v.importe_total)                         AS facturacion,
       ROUND(SUM(v.unidades) / COUNT(*), 1)         AS motos_por_operacion,
       ROUND(AVG(v.descuento_pct), 1)               AS descuento_medio_pct,
       ROUND(SUM(v.importe_total) * 100 / SUM(SUM(v.importe_total)) OVER (), 1) AS pct_facturacion
FROM fact_ventas v
INNER JOIN dim_cliente cl ON cl.id_cliente = v.id_cliente
WHERE v.estado = 'Completada'
GROUP BY cl.tipo_cliente;
/* INSIGHT 7.3
   · Solo 8 empresas, pero compran 269 motos (6,3 por operación, el 10,6 %
     de todas las unidades) y aportan el 5,9 % de la facturación.
   · Obtienen más descuento (11,2 % vs 3,6 %), algo razonable por volumen.
   → Canal B2B con potencial (reparto, alquiler turístico, administración):
     crear la figura de gestor de flotas. */


/* =====================================================================
   8. FORMA DE PAGO Y CANCELACIONES
   ===================================================================== */

-- 8.1 Método de pago según la gama de precio (función fn_tramo_precio).
--     Aquí se incluyen TODAS las operaciones (también canceladas).
SELECT fn_tramo_precio(v.precio_unitario)              AS gama,
       COUNT(*)                                        AS operaciones,
       ROUND(AVG(v.metodo_pago = 'Contado')    * 100, 1) AS pct_contado,
       ROUND(AVG(v.metodo_pago = 'Financiado') * 100, 1) AS pct_financiado,
       ROUND(AVG(v.metodo_pago = 'Renting')    * 100, 1) AS pct_renting
FROM fact_ventas v
INNER JOIN dim_cliente cl ON cl.id_cliente = v.id_cliente
WHERE cl.tipo_cliente = 'Particular'
GROUP BY gama
ORDER BY FIELD(gama, 'Entrada', 'Media', 'Alta', 'Premium');
/* INSIGHT 8.1
   · Cuanto más cara la moto, más se financia: del 38,6 % en gama de
     entrada al 63,1 % en premium. El renting apenas existe en entrada
     (1,5 %) y llega al 9,6 % en gama alta.
   → La financiación es clave para vender gama alta: negociar mejores
     condiciones con la financiera es tan importante como el precio. */

-- 8.2 Tasa de cancelación por método de pago y facturación perdida.
SELECT v.metodo_pago,
       COUNT(*)                                                   AS operaciones,
       SUM(v.estado = 'Cancelada')                                AS canceladas,
       ROUND(AVG(v.estado = 'Cancelada') * 100, 1)                AS tasa_cancelacion_pct,
       SUM(CASE WHEN v.estado = 'Cancelada' THEN v.importe_total ELSE 0 END) AS facturacion_perdida
FROM fact_ventas v
GROUP BY v.metodo_pago
ORDER BY tasa_cancelacion_pct DESC;
/* INSIGHT 8.2
   · Las ventas financiadas se cancelan 3,7 veces más que las de contado
     (6,3 % vs 1,7 %), probablemente por financiaciones denegadas.
   · Suponen 0,84 M€ perdidos: el 76 % de toda la facturación cancelada.
   → Pedir preaprobación financiera ANTES de cerrar la reserva y tener
     una segunda financiera para los rechazos. */


/* =====================================================================
   9. COMERCIALES Y DESCUENTOS
   ===================================================================== */

-- 9.1 Ranking de comerciales DENTRO de su concesionario y comparación de
--     su descuento con la media de su concesionario. Funciones ventana:
--       · RANK() OVER (PARTITION BY concesionario ...)
--       · AVG(AVG(descuento)) OVER (PARTITION BY concesionario)
--     Se usa la VISTA vw_ventas_detalle: no hay que repetir los JOIN.
WITH comerciales AS (
    SELECT concesionario,
           vendedor,
           COUNT(*)                   AS ventas,
           SUM(importe_total)         AS facturacion,
           ROUND(AVG(descuento_pct), 2) AS descuento_medio
    FROM vw_ventas_detalle
    WHERE estado = 'Completada'
      AND tipo_cliente = 'Particular'
    GROUP BY concesionario, vendedor
),
comparativa AS (
    SELECT c.*,
           RANK() OVER (PARTITION BY concesionario ORDER BY facturacion DESC) AS ranking_en_conc,
           ROUND(AVG(descuento_medio) OVER (PARTITION BY concesionario), 2)   AS descuento_medio_conc
    FROM comerciales c
)
SELECT concesionario, ranking_en_conc, vendedor, ventas, facturacion,
       descuento_medio, descuento_medio_conc,
       CASE WHEN descuento_medio > descuento_medio_conc + 2
            THEN '⚠ Revisar política de descuento' ELSE 'OK' END AS alerta
FROM comparativa
ORDER BY (alerta = 'OK'), concesionario, ranking_en_conc;
/* INSIGHT 9.1
   · Sara González (Motos Getafe) concede un 7,55 % de descuento medio,
     frente al 3,67 % del resto de comerciales de su concesionario, y no
     vende más: es la 3ª de 4 en facturación.
   · Esos ~3,9 puntos extra sobre ~0,66 M€ de venta bruta suponen unos
     25.000 € dejados de ingresar en dos años.
   → Descuentos por encima de un umbral (p. ej. 6 %) con aprobación del
     jefe de ventas. */

-- 9.2 Coste de los descuentos: cuánto dinero se deja de facturar (precio
--     bruto - importe neto) por mes. Funciones de fecha sobre la columna
--     DATE del calendario.
SELECT DATE_FORMAT(c.fecha, '%Y-%m')                                  AS anio_mes,
       ROUND(SUM(v.unidades * v.precio_unitario - v.importe_total), 0) AS descuento_concedido_eur,
       ROUND(AVG(v.descuento_pct), 2)                                  AS descuento_medio_pct
FROM fact_ventas v
INNER JOIN dim_calendario c ON c.id_fecha = v.id_fecha
WHERE v.estado = 'Completada'
  AND YEAR(c.fecha) = 2025
GROUP BY DATE_FORMAT(c.fecha, '%Y-%m')
ORDER BY anio_mes;
/* INSIGHT 9.2
   · En 2025 se concedieron ≈531.000 € en descuentos. Diciembre (63.747 €)
     y febrero (6,28 % medio) son los meses de mayor descuento.
   → Cada punto de descuento cuenta: es una partida comparable al margen
     de un concesionario pequeño. */

-- 9.3 Plantilla sin actividad reciente. LEFT JOIN + agregación con
--     condición: comerciales sin ventas en el último semestre del periodo.
SELECT co.nombre                                     AS concesionario,
       CONCAT(ve.nombre, ' ', ve.apellidos)          AS vendedor,
       DATE_FORMAT(ve.fecha_contratacion, '%d/%m/%Y') AS contratado,
       CASE WHEN ve.activo THEN 'Activo' ELSE 'Baja' END AS situacion,
       COUNT(v.id_venta)                             AS ventas_totales,
       MAX(c.fecha)                                  AS ultima_venta,
       DATEDIFF('2025-12-31', MAX(c.fecha))          AS dias_sin_vender
FROM dim_vendedor ve
INNER JOIN dim_concesionario co ON co.id_concesionario = ve.id_concesionario
LEFT  JOIN fact_ventas       v  ON v.id_vendedor       = ve.id_vendedor
LEFT  JOIN dim_calendario    c  ON c.id_fecha          = v.id_fecha
GROUP BY co.nombre, ve.id_vendedor, ve.nombre, ve.apellidos, ve.fecha_contratacion, ve.activo
HAVING MAX(c.fecha) IS NULL OR MAX(c.fecha) < '2025-07-01'
ORDER BY ventas_totales;
/* INSIGHT 9.3
   · Irene Castro (Motos Turia) no tiene ventas: es normal, se incorporó
     el 15/12/2025.
   · Óscar Delgado (Motos Nervión) está de baja: correcto y coherente con
     el UPDATE de 02_data.sql.
   · ALERTA: Lucía Vázquez (Motos Ebro) figura como activa pero no vende
     desde el 31/05/2025 (214 días). Es probable que explique parte de la
     caída del −28,6 % de Motos Ebro.
   → Verificar con RRHH (¿baja no registrada?) y con el jefe de tienda. */


/* =====================================================================
   10. RENDIMIENTO: USO DEL ÍNDICE
   ===================================================================== */

-- 10.1 EXPLAIN muestra el plan de ejecución. Resultado obtenido:
--        type = range · key = idx_ventas_conc_fecha · rows = 74
--      MySQL salta directamente al concesionario y lee solo las 74 ventas
--      del rango de fechas, en lugar de recorrer las 2.405 filas de
--      fact_ventas (type = ALL). Con millones de filas, la diferencia sería
--      de segundos a milisegundos.
EXPLAIN
SELECT SUM(importe_total)
FROM fact_ventas
WHERE id_concesionario = 3
  AND id_fecha BETWEEN 20250401 AND 20250630;

-- 10.2 Comprobación cruzada: la función y una consulta manual deben dar
--      exactamente lo mismo (valida que la función está bien escrita).
SELECT fn_facturacion_concesionario(3, 2025) AS segun_funcion,
       (SELECT SUM(v.importe_total)
          FROM fact_ventas v
          JOIN dim_calendario c ON c.id_fecha = v.id_fecha
         WHERE v.id_concesionario = 3 AND c.anio = 2025
           AND v.estado = 'Completada')      AS segun_consulta;


/* =====================================================================
   11. RESULTADO FINAL · VISTA RESUMEN
   ---------------------------------------------------------------------
   vw_resumen_provincia_segmento: una fila por comunidad + provincia del
   concesionario + segmento, con las métricas clave. Es la "tabla" que
   consultaría dirección (o que se conectaría a Power BI en el módulo 4).
   ===================================================================== */
DROP VIEW IF EXISTS vw_resumen_provincia_segmento;
CREATE OR REPLACE VIEW vw_resumen_provincia_segmento AS
SELECT d.comunidad_concesionario                                   AS comunidad,
       d.provincia_concesionario                                   AS provincia,
       d.segmento,
       COUNT(*)                                                    AS operaciones,
       SUM(d.estado = 'Cancelada')                                 AS canceladas,
       SUM(CASE WHEN d.estado = 'Completada' THEN d.unidades END)  AS motos_vendidas,
       SUM(CASE WHEN d.estado = 'Completada' THEN d.importe_total END) AS facturacion,
       ROUND(AVG(CASE WHEN d.estado = 'Completada' THEN d.importe_total END), 2) AS ticket_medio,
       ROUND(AVG(d.descuento_pct), 2)                              AS descuento_medio_pct,
       ROUND(AVG(d.metodo_pago = 'Financiado') * 100, 1)           AS pct_financiado
FROM vw_ventas_detalle d
GROUP BY d.comunidad_concesionario, d.provincia_concesionario, d.segmento;

-- 11.1 Segmento líder en facturación de cada provincia (sobre la vista)
WITH lider AS (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY provincia ORDER BY facturacion DESC) AS puesto,
           ROUND(facturacion * 100 / SUM(facturacion) OVER (PARTITION BY provincia), 1) AS pct_provincia
    FROM vw_resumen_provincia_segmento r
)
SELECT comunidad, provincia, segmento AS segmento_lider, motos_vendidas,
       facturacion, pct_provincia, ticket_medio
FROM lider
WHERE puesto = 1
ORDER BY facturacion DESC;

-- 11.2 Totales por comunidad autónoma (agregando la vista)
SELECT comunidad,
       SUM(motos_vendidas)                        AS motos_vendidas,
       SUM(facturacion)                           AS facturacion,
       ROUND(SUM(facturacion) / SUM(motos_vendidas), 2) AS precio_medio_moto,
       SUM(canceladas)                            AS canceladas
FROM vw_resumen_provincia_segmento
GROUP BY comunidad
ORDER BY facturacion DESC;

/* INSIGHT 11
   · Trail es el segmento líder en facturación en TODAS las provincias
     (entre el 29 % y el 38 % de cada una).
   · Cataluña (5,96 M€) y Andalucía (5,80 M€) están casi empatadas, aunque
     Andalucía reparte su venta en 3 concesionarios.
*/

/* =====================================================================
   CONCLUSIONES Y DECISIONES DE NEGOCIO
   ---------------------------------------------------------------------
   1. EXPANSIÓN: abrir concesionario en Alicante (1,51 M€ de clientes que
      hoy viajan a Murcia/Valencia) y estudiar Baleares. Controlar la
      canibalización de Motos Segura (40 % de sus ventas son alicantinas).
   2. PRODUCTO: apostar por Trail (+43 %, 1/3 de la facturación), reducir
      Sport (−29 %), retirar la Ninja 7 Hybrid y la Street Glide bajo pedido.
      Surtido por tipo de tienda: scooters en centro, trail en periferia.
   3. CALENDARIO: preparar stock y campañas antes de primavera (marzo-julio
      = más de la mitad del año). Reforzar viernes y sábados.
   4. PRECIO: el descuento de invierno no compensa la caída; sustituirlo
      por financiación o preventa. Poner umbral de aprobación a descuentos
      (caso Getafe: ~25.000 € de margen perdido).
   5. FINANCIACIÓN: la mitad de las ventas se financian y generan el 76 %
      de la facturación cancelada → preaprobación antes de reservar.
   6. RED Y EQUIPO: plan de acción en Motos Ebro (−28,6 %, 640 €/m², una
      comercial sin ventas desde mayo).
   7. CLIENTES: reactivar 597 leads, campañas por edad y canal de flotas B2B.

   LIMITACIONES DEL ANÁLISIS
   · Datos ficticios (aunque con patrones realistas): las conclusiones
     ilustran el método, no el mercado real.
   · No hay costes ni márgenes: se analiza facturación, no rentabilidad.
   · Solo 2 años: la estacionalidad se confirma, pero una tendencia
     (p. ej. la caída de Sport) necesitaría más histórico.
   · Los concesionarios pequeños tienen pocas ventas, así que sus
     porcentajes de crecimiento son más volátiles.
   ===================================================================== */
