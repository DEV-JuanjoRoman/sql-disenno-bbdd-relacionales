

/* =====================================================================
   BLOQUE 5 · LIMPIEZA DEL STAGING  (transacción)
   ===================================================================== */

-- 5.0 Diagnóstico ANTES de limpiar (cuántos problemas hay de cada tipo)
SELECT
    COUNT(*)                                          AS filas_brutas,
    COUNT(DISTINCT codigo_venta)                      AS codigos_distintos,
    COUNT(*) - COUNT(DISTINCT codigo_venta)           AS duplicados,
    SUM(codigo_venta LIKE 'TEST-%')                   AS ventas_prueba,
    SUM(fecha_txt IS NULL OR TRIM(fecha_txt) = '')    AS sin_fecha,
    SUM(precio_txt LIKE '%,%')                        AS precio_con_coma,
    SUM(metodo_pago_txt NOT IN ('Contado','Financiado','Renting')
        OR metodo_pago_txt <> TRIM(metodo_pago_txt))  AS metodo_pago_sucio
FROM stg_ventas_raw;

START TRANSACTION;

-- 5.1 DELETE: ventas de prueba del ERP
DELETE FROM stg_ventas_raw
WHERE codigo_venta LIKE 'TEST-%';

-- 5.2 DELETE: filas sin fecha. Sin fecha no se puede asignar id_fecha
--     (FK obligatoria) y no hay forma fiable de recuperarla.
DELETE FROM stg_ventas_raw
WHERE fecha_txt IS NULL OR TRIM(fecha_txt) = '';

-- 5.3 DELETE: duplicados. ROW_NUMBER() numera las filas de cada
--     codigo_venta; se conserva la primera (rn = 1) y se borra el resto.
DELETE s
FROM stg_ventas_raw s
JOIN (
    SELECT id_raw,
           ROW_NUMBER() OVER (PARTITION BY codigo_venta ORDER BY id_raw) AS rn
    FROM stg_ventas_raw
) d ON d.id_raw = s.id_raw
WHERE d.rn > 1;

-- 5.4 UPDATE: método de pago → sin espacios y con formato 'Financiado'
UPDATE stg_ventas_raw
SET metodo_pago_txt = CONCAT(UPPER(LEFT(TRIM(metodo_pago_txt), 1)),
                             LOWER(SUBSTRING(TRIM(metodo_pago_txt), 2)));

-- 5.5 UPDATE: coma decimal → punto (si no, CAST('9690,00' AS DECIMAL)
--     devolvería 9690 truncando en silencio: error difícil de detectar)
UPDATE stg_ventas_raw
SET precio_txt = REPLACE(precio_txt, ',', '.')
WHERE precio_txt LIKE '%,%';

-- 5.6 Erratas en modelos: un LEFT JOIN contra dim_modelo muestra los
--     textos que NO encuentran pareja (id_modelo IS NULL).
SELECT s.modelo_txt, COUNT(*) AS filas
FROM stg_ventas_raw s
LEFT JOIN dim_modelo m ON m.nombre = s.modelo_txt
WHERE m.id_modelo IS NULL
GROUP BY s.modelo_txt;

--     Se corrigen (mejor que borrarlas: son ventas reales)
UPDATE stg_ventas_raw
SET modelo_txt = CASE modelo_txt
                    WHEN 'MT07'       THEN 'MT-07'
                    WHEN 'PCX 125'    THEN 'PCX125'
                    WHEN 'Tenere-700' THEN 'Ténéré 700'
                 END
WHERE modelo_txt IN ('MT07', 'PCX 125', 'Tenere-700');

-- 5.7 Control final: ningún valor debe fallar al convertirse de tipo.
--     Todas las columnas deben devolver 0.
SELECT
    SUM(precio_txt    NOT REGEXP '^[0-9]+(\\.[0-9]{1,2})?$')  AS precios_no_numericos,
    SUM(descuento_txt NOT REGEXP '^[0-9]+(\\.[0-9])?$')       AS descuentos_no_numericos,
    SUM(STR_TO_DATE(fecha_txt, '%d/%m/%Y') IS NULL)            AS fechas_invalidas,
    SUM(metodo_pago_txt NOT IN ('Contado','Financiado','Renting')) AS metodos_invalidos
FROM stg_ventas_raw;

COMMIT;


/* =====================================================================
   BLOQUE 6 · CARGA DE LA TABLA DE HECHOS  (transacción)
   ---------------------------------------------------------------------
   · CAST de texto a número / fecha → tipos correctos de fact_ventas.
   · Se traducen las claves de negocio del ERP (código de concesionario,
     email, nombre de modelo) a las claves surrogate de las dimensiones
     mediante JOIN.
   · importe_total NO se inserta: es una columna generada.
   ===================================================================== */
START TRANSACTION;

INSERT INTO fact_ventas
    (codigo_venta, id_fecha, id_concesionario, id_vendedor, id_cliente, id_modelo,
     unidades, precio_unitario, descuento_pct, metodo_pago, estado)
SELECT
    s.codigo_venta,
    CAST(DATE_FORMAT(STR_TO_DATE(s.fecha_txt, '%d/%m/%Y'), '%Y%m%d') AS UNSIGNED)  AS id_fecha,
    co.id_concesionario,
    CAST(s.id_vendedor_txt AS UNSIGNED),
    cl.id_cliente,
    mo.id_modelo,
    CAST(s.unidades_txt  AS UNSIGNED),
    CAST(s.precio_txt    AS DECIMAL(9,2)),
    CAST(s.descuento_txt AS DECIMAL(5,2)),
    s.metodo_pago_txt,
    s.estado_txt
FROM stg_ventas_raw    s
JOIN dim_concesionario co ON co.codigo  = s.cod_concesionario
JOIN dim_cliente       cl ON cl.email   = s.email_cliente
JOIN dim_marca         ma ON ma.nombre  = s.marca_txt
JOIN dim_modelo        mo ON mo.nombre  = s.modelo_txt
                         AND mo.id_marca = ma.id_marca
ORDER BY STR_TO_DATE(s.fecha_txt, '%d/%m/%Y'), s.codigo_venta;

-- Cuadre: las filas del staging limpio y las de fact_ventas deben
-- coincidir. Si no coincidieran, se ejecutaría ROLLBACK en lugar de COMMIT.
SELECT (SELECT COUNT(*) FROM stg_ventas_raw) AS filas_staging,
       (SELECT COUNT(*) FROM fact_ventas)    AS filas_cargadas;

COMMIT;


/* =====================================================================
   BLOQUE 7 · MANTENIMIENTO DE DIMENSIONES  (UPDATE / DELETE)
   ===================================================================== */
START TRANSACTION;

-- 7.1 UPDATE: emails del CRM a minúsculas. La collation de la BBDD no
--     distingue mayúsculas, así que para detectarlos se compara en
--     binario con CAST(... AS BINARY).
UPDATE dim_cliente
SET email = LOWER(TRIM(email))
WHERE CAST(email AS BINARY) <> CAST(LOWER(TRIM(email)) AS BINARY);

-- 7.2 UPDATE: el Suzuki Burgman 400 se descatalogó a final de 2024.
--     No se borra (tiene ventas históricas); se marca como inactivo.
UPDATE dim_modelo
SET activo = FALSE
WHERE nombre = 'Burgman 400';

-- 7.3 UPDATE: RRHH comunica la baja de un comercial (dejó la empresa el
--     30/06/2025). No se borra: sus ventas históricas deben seguir
--     apuntando a él. Se comprueba con una SUBCONSULTA que tiene ventas
--     (es decir, que es el registro correcto y no un homónimo sin actividad).
UPDATE dim_vendedor
SET activo = FALSE
WHERE nombre = 'Óscar'
  AND apellidos = 'Delgado Ruiz'
  AND id_vendedor IN (SELECT id_vendedor FROM fact_ventas);

-- 7.4 DELETE: clientes de prueba del CRM. Por seguridad, solo si no
--     tienen ventas (la FK lo impediría de todos modos: ON DELETE RESTRICT).
DELETE FROM dim_cliente
WHERE email LIKE '%@motos-dw.test'
  AND id_cliente NOT IN (SELECT id_cliente FROM fact_ventas);

COMMIT;


/* =====================================================================
   BLOQUE 8 · ROLLBACK: deshacer un error humano
   ---------------------------------------------------------------------
   Simulación: se quería subir un 10 % el precio de enero de 2025, pero
   por error se multiplica por 10. Como estamos dentro de una transacción,
   se comprueba el resultado ANTES de confirmar y se deshace con ROLLBACK.
   ===================================================================== */
SELECT 'Antes del error' AS momento, SUM(importe_total) AS facturacion_ene_2025
FROM fact_ventas WHERE id_fecha BETWEEN 20250101 AND 20250131;

START TRANSACTION;

UPDATE fact_ventas
SET precio_unitario = precio_unitario * 10          -- ¡debía ser * 1.10!
WHERE id_fecha BETWEEN 20250101 AND 20250131;

SELECT 'Tras el UPDATE erróneo' AS momento, SUM(importe_total) AS facturacion_ene_2025
FROM fact_ventas WHERE id_fecha BETWEEN 20250101 AND 20250131;

ROLLBACK;   -- se descarta el cambio: nada llegó a guardarse

SELECT 'Tras el ROLLBACK' AS momento, SUM(importe_total) AS facturacion_ene_2025
FROM fact_ventas WHERE id_fecha BETWEEN 20250101 AND 20250131;


/* =====================================================================
   BLOQUE 9 · CIERRE
   ===================================================================== */
-- El staging ya no es necesario: los datos limpios están en fact_ventas
DROP TABLE IF EXISTS stg_ventas_raw;

-- Actualiza las estadísticas que usa el optimizador para elegir índices.
-- Tras una carga masiva conviene hacerlo: con estadísticas antiguas MySQL
-- puede creer que la tabla está casi vacía y no usar los índices.
ANALYZE TABLE fact_ventas, dim_cliente;

-- Resumen de la carga: filas por tabla
SELECT 'dim_calendario'    AS tabla, COUNT(*) AS filas FROM dim_calendario    UNION ALL
SELECT 'dim_provincia',              COUNT(*)          FROM dim_provincia     UNION ALL
SELECT 'dim_marca',                  COUNT(*)          FROM dim_marca         UNION ALL
SELECT 'dim_modelo',                 COUNT(*)          FROM dim_modelo        UNION ALL
SELECT 'dim_concesionario',          COUNT(*)          FROM dim_concesionario UNION ALL
SELECT 'dim_vendedor',               COUNT(*)          FROM dim_vendedor      UNION ALL
SELECT 'dim_cliente',                COUNT(*)          FROM dim_cliente       UNION ALL
SELECT 'fact_ventas',                COUNT(*)          FROM fact_ventas;

SET SQL_SAFE_UPDATES = @old_safe_updates;
