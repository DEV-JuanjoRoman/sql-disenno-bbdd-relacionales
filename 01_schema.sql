/* =====================================================================
   PROYECTO MÓDULO 2 · SQL
   Diseño de Base de Datos Relacional y EDA en SQL
   Dominio: red de concesionarios de motos en España (2024-2025)
   ---------------------------------------------------------------------
   01_schema.sql  →  modelo, constraints, índices, vistas y funciones
   Motor: MySQL 8.0+  (necesario para CHECK, CTE y funciones ventana)
   Ejecutar desde MySQL Workbench o CLI:  mysql -u root -p < 01_schema.sql
   =====================================================================

   MODELO EN ESTRELLA (star schema)
   --------------------------------
   · 1 tabla de HECHOS  → fact_ventas: cada fila es un evento de negocio
     medible (una venta). Contiene claves a las dimensiones y MÉTRICAS
     numéricas que se agregan (unidades, precio, descuento, importe).
   · 7 tablas de DIMENSIONES → describen el "quién, qué, dónde y cuándo"
     de cada venta. Contienen atributos descriptivos por los que se
     filtra y agrupa (provincia, segmento, marca, mes...).

                       dim_calendario (cuándo)
                              │
     dim_cliente (quién) ── fact_ventas ── dim_modelo (qué) ── dim_marca
                              │    │
            dim_vendedor ─────┘    └── dim_concesionario (dónde) ── dim_provincia

   dim_marca y dim_provincia cuelgan de otra dimensión (modelo y
   concesionario/cliente): es un "copo de nieve" parcial. Se hace así
   para no repetir el país de la marca en cada modelo ni la comunidad
   autónoma en cada concesionario y cliente (3FN), y porque dim_provincia
   la comparten dos dimensiones distintas (concesionario y cliente).

   ALCANCE
   · Dentro: ventas de motos nuevas (particulares y empresas) de 12
     concesionarios propios en 10 provincias, ene-2024 a dic-2025.
   · Fuera: taller/postventa, recambios, motos de ocasión, stock e
     inventario, costes y márgenes (no hay coste de compra al fabricante).
   ===================================================================== */

-- Cliente y servidor hablan en UTF-8 (si no, los literales con tildes
-- o ñ de los CHECK, como 'Otoño', se guardarían corruptos)
SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS motos_dw
    CHARACTER SET utf8mb4          -- admite tildes, ñ y cualquier carácter
    COLLATE utf8mb4_0900_ai_ci;    -- comparaciones sin distinguir mayúsculas/tildes

USE motos_dw;

/* ---------------------------------------------------------------------
   LIMPIEZA PREVIA (script re-ejecutable desde cero)
   Se borra en orden INVERSO a las dependencias: primero lo que depende
   de otros objetos (vistas, funciones, hechos) y al final las dimensiones
   "raíz". Si se borrase antes dim_provincia, las FK lo impedirían.
   --------------------------------------------------------------------- */
DROP VIEW     IF EXISTS vw_resumen_provincia_segmento;
DROP VIEW     IF EXISTS vw_ventas_detalle;
DROP FUNCTION IF EXISTS fn_facturacion_concesionario;
DROP FUNCTION IF EXISTS fn_tramo_precio;
DROP FUNCTION IF EXISTS fn_edad;
DROP TABLE    IF EXISTS stg_ventas_raw;
DROP TABLE    IF EXISTS fact_ventas;
DROP TABLE    IF EXISTS dim_cliente;
DROP TABLE    IF EXISTS dim_vendedor;
DROP TABLE    IF EXISTS dim_concesionario;
DROP TABLE    IF EXISTS dim_modelo;
DROP TABLE    IF EXISTS dim_marca;
DROP TABLE    IF EXISTS dim_provincia;
DROP TABLE    IF EXISTS dim_calendario;

/* Todas las tablas usan ENGINE=InnoDB: es el único motor de MySQL que
   aplica FOREIGN KEY y soporta transacciones (BEGIN/COMMIT/ROLLBACK). */


/* =====================================================================
   DIMENSIÓN 1 · dim_calendario
   Granularidad: 1 fila = 1 día natural (2024-01-01 a 2025-12-31).
   ---------------------------------------------------------------------
   · PK id_fecha INT en formato AAAAMMDD (20250101). Es la convención
     habitual en data warehouses: es legible, ordena igual que la fecha
     y es más ligera en los JOIN que un DATE o un VARCHAR.
   · Tener el calendario como tabla (y no sacar el mes de la fecha en
     cada consulta) permite agrupar por trimestre, temporada o fin de
     semana con un simple JOIN, e incluir días SIN ventas en un LEFT JOIN.
   · Formato pedido en el enunciado: fecha_texto '01/01/2025', dia '1',
     mes '1', anio '2025'.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_calendario (
    id_fecha       INT          NOT NULL,
    fecha          DATE         NOT NULL,
    fecha_texto    CHAR(10)     NOT NULL,              -- 'dd/mm/aaaa'
    dia            TINYINT      NOT NULL,
    mes            TINYINT      NOT NULL,
    anio           SMALLINT     NOT NULL,
    trimestre      TINYINT      NOT NULL,
    nombre_mes     VARCHAR(12)  NOT NULL,
    dia_semana     TINYINT      NOT NULL,              -- 1 = lunes ... 7 = domingo
    nombre_dia     VARCHAR(10)  NOT NULL,
    es_fin_semana  BOOLEAN      NOT NULL DEFAULT FALSE,
    temporada      VARCHAR(10)  NOT NULL,
    CONSTRAINT pk_calendario        PRIMARY KEY (id_fecha),
    CONSTRAINT uq_calendario_fecha  UNIQUE (fecha),    -- un único registro por día
    CONSTRAINT ck_cal_id_fecha      CHECK (id_fecha BETWEEN 20000101 AND 20991231),
    CONSTRAINT ck_cal_dia           CHECK (dia BETWEEN 1 AND 31),
    CONSTRAINT ck_cal_mes           CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT ck_cal_trimestre     CHECK (trimestre BETWEEN 1 AND 4),
    CONSTRAINT ck_cal_dia_semana    CHECK (dia_semana BETWEEN 1 AND 7),
    CONSTRAINT ck_cal_temporada     CHECK (temporada IN ('Invierno','Primavera','Verano','Otoño'))
) ENGINE=InnoDB COMMENT='Dimensión tiempo. 1 fila = 1 día.';


/* =====================================================================
   DIMENSIÓN 2 · dim_provincia
   Granularidad: 1 fila = 1 provincia española.
   ---------------------------------------------------------------------
   · PK = código INE de la provincia (14 = Córdoba, 28 = Madrid...).
     Es una clave NATURAL oficial y estable, así que no hace falta
     inventar un AUTO_INCREMENT: se puede cruzar con datos del INE.
   · La comunidad autónoma vive aquí y no en cliente/concesionario
     (evita la dependencia transitiva cliente → provincia → comunidad).
   · poblacion (aprox. INE 2024) permite calcular ventas por 100.000
     habitantes, que compara provincias de distinto tamaño.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_provincia (
    id_provincia        TINYINT UNSIGNED NOT NULL,
    nombre              VARCHAR(40)      NOT NULL,
    comunidad_autonoma  VARCHAR(40)      NOT NULL,
    poblacion           INT UNSIGNED     NOT NULL,
    CONSTRAINT pk_provincia         PRIMARY KEY (id_provincia),
    CONSTRAINT uq_provincia_nombre  UNIQUE (nombre),
    CONSTRAINT ck_prov_codigo_ine   CHECK (id_provincia BETWEEN 1 AND 52),  -- rango de códigos INE
    CONSTRAINT ck_prov_poblacion    CHECK (poblacion > 0)
) ENGINE=InnoDB COMMENT='Provincias (código INE). Compartida por concesionario y cliente.';


/* =====================================================================
   DIMENSIÓN 3 · dim_marca
   Granularidad: 1 fila = 1 fabricante.
   · PK surrogate AUTO_INCREMENT: el nombre podría cambiar (rebranding)
     y no queremos propagar ese cambio a miles de filas.
   · UNIQUE en nombre para impedir marcas duplicadas.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_marca (
    id_marca     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(40)       NOT NULL,
    pais_origen  VARCHAR(30)       NOT NULL,
    es_premium   BOOLEAN           NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_marca         PRIMARY KEY (id_marca),
    CONSTRAINT uq_marca_nombre  UNIQUE (nombre)
) ENGINE=InnoDB COMMENT='Fabricantes de motos.';


/* =====================================================================
   DIMENSIÓN 4 · dim_modelo  (producto)
   Granularidad: 1 fila = 1 modelo comercial de una marca.
   ---------------------------------------------------------------------
   · FK id_marca → dim_marca. ON DELETE RESTRICT: no se puede borrar
     una marca que tenga modelos (perderíamos el historial).
     ON UPDATE CASCADE: si cambiara el id de la marca, se propaga.
   · UNIQUE (id_marca, nombre): el mismo nombre podría existir en dos
     marcas, pero no repetirse dentro de una.
   · CHECK en segmento y carnet: dominio cerrado de valores válidos
     (hace el papel de una lista desplegable a nivel de base de datos).
   · precio_base = PVP de tarifa 2024. El precio REAL de cada venta se
     guarda en fact_ventas, porque cambia con el tiempo (ver más abajo).
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_modelo (
    id_modelo          SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_marca           SMALLINT UNSIGNED NOT NULL,
    nombre             VARCHAR(50)       NOT NULL,
    segmento           VARCHAR(10)       NOT NULL,
    cilindrada_cc      SMALLINT UNSIGNED NOT NULL,
    potencia_cv        DECIMAL(5,1)      NOT NULL,
    carnet_minimo      VARCHAR(2)        NOT NULL,
    precio_base        DECIMAL(9,2)      NOT NULL,
    anio_lanzamiento   SMALLINT          NOT NULL,
    activo             BOOLEAN           NOT NULL DEFAULT TRUE,   -- FALSE = descatalogado
    CONSTRAINT pk_modelo              PRIMARY KEY (id_modelo),
    CONSTRAINT uq_modelo_marca_nombre UNIQUE (id_marca, nombre),
    CONSTRAINT fk_modelo_marca        FOREIGN KEY (id_marca)
        REFERENCES dim_marca (id_marca) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_modelo_segmento     CHECK (segmento IN ('Naked','Sport','Trail','Touring','Custom','Scooter')),
    CONSTRAINT ck_modelo_carnet       CHECK (carnet_minimo IN ('A1','A2','A')),
    CONSTRAINT ck_modelo_cilindrada   CHECK (cilindrada_cc BETWEEN 50 AND 2500),
    CONSTRAINT ck_modelo_potencia     CHECK (potencia_cv > 0),
    CONSTRAINT ck_modelo_precio       CHECK (precio_base > 0),
    CONSTRAINT ck_modelo_lanzamiento  CHECK (anio_lanzamiento BETWEEN 1990 AND 2030)
) ENGINE=InnoDB COMMENT='Catálogo de modelos (producto).';


/* =====================================================================
   DIMENSIÓN 5 · dim_concesionario  (punto de venta)
   Granularidad: 1 fila = 1 concesionario propio.
   · codigo 'CO-001' es la clave del ERP de origen (UNIQUE); la PK es un
     surrogate numérico, más eficiente para los JOIN.
   · tipo_zona permite estudiar si los locales en centro urbano venden
     un mix distinto (más scooters) que los de periferia.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_concesionario (
    id_concesionario  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    codigo            CHAR(6)           NOT NULL,
    nombre            VARCHAR(60)       NOT NULL,
    ciudad            VARCHAR(40)       NOT NULL,
    id_provincia      TINYINT UNSIGNED  NOT NULL,
    tipo_zona         VARCHAR(15)       NOT NULL DEFAULT 'Periferia',
    superficie_m2     SMALLINT UNSIGNED NOT NULL,
    fecha_apertura    DATE              NOT NULL,
    CONSTRAINT pk_concesionario         PRIMARY KEY (id_concesionario),
    CONSTRAINT uq_concesionario_codigo  UNIQUE (codigo),
    CONSTRAINT fk_concesionario_prov    FOREIGN KEY (id_provincia)
        REFERENCES dim_provincia (id_provincia) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_conc_zona             CHECK (tipo_zona IN ('Centro urbano','Periferia')),
    CONSTRAINT ck_conc_superficie       CHECK (superficie_m2 BETWEEN 100 AND 5000),
    CONSTRAINT ck_conc_codigo           CHECK (codigo LIKE 'CO-___')
) ENGINE=InnoDB COMMENT='Concesionarios propios de la red.';


/* =====================================================================
   DIMENSIÓN 6 · dim_vendedor
   Granularidad: 1 fila = 1 comercial.
   · FK id_concesionario: cada comercial pertenece a un concesionario.
   · activo con DEFAULT TRUE: al dar de baja a alguien NO se borra
     (sus ventas históricas deben seguir apuntando a él); se marca FALSE.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_vendedor (
    id_vendedor         SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_concesionario    SMALLINT UNSIGNED NOT NULL,
    nombre              VARCHAR(40)       NOT NULL,
    apellidos           VARCHAR(60)       NOT NULL,
    fecha_contratacion  DATE              NOT NULL,
    comision_pct        DECIMAL(4,2)      NOT NULL DEFAULT 2.00,
    activo              BOOLEAN           NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_vendedor       PRIMARY KEY (id_vendedor),
    CONSTRAINT fk_vendedor_conc  FOREIGN KEY (id_concesionario)
        REFERENCES dim_concesionario (id_concesionario) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_vend_comision  CHECK (comision_pct BETWEEN 0 AND 10)
) ENGINE=InnoDB COMMENT='Comerciales de cada concesionario.';


/* =====================================================================
   DIMENSIÓN 7 · dim_cliente
   Granularidad: 1 fila = 1 cliente (particular o empresa).
   ---------------------------------------------------------------------
   · email UNIQUE: es el identificador real del cliente en el CRM y se
     usa para enlazar la exportación de ventas con esta tabla.
   · CHECK condicional: a un particular se le exige fecha de nacimiento
     (para segmentar por edad); a una empresa no tiene sentido.
     No se puede validar "mayor de 18" con un CHECK, porque MySQL no
     admite funciones no deterministas como CURDATE() en un CHECK
     (limitación documentada en el README).
   · fecha_alta con DEFAULT (CURRENT_DATE): si el CRM no la envía,
     se registra el día de la carga.
   · Hay clientes SIN compras (leads del CRM): se detectan con LEFT JOIN.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS dim_cliente (
    id_cliente        INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    tipo_cliente      VARCHAR(10)      NOT NULL DEFAULT 'Particular',
    nombre            VARCHAR(60)      NOT NULL,              -- nombre o razón social
    apellidos         VARCHAR(60)      NULL,                  -- NULL en empresas
    email             VARCHAR(100)     NOT NULL,
    fecha_nacimiento  DATE             NULL,
    id_provincia      TINYINT UNSIGNED NOT NULL,              -- provincia de residencia
    fecha_alta        DATE             NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT pk_cliente          PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_email    UNIQUE (email),
    CONSTRAINT fk_cliente_prov     FOREIGN KEY (id_provincia)
        REFERENCES dim_provincia (id_provincia) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_cli_tipo         CHECK (tipo_cliente IN ('Particular','Empresa')),
    CONSTRAINT ck_cli_nacimiento   CHECK (tipo_cliente = 'Empresa'
                                          OR fecha_nacimiento >= '1930-01-01'),
    CONSTRAINT ck_cli_email        CHECK (email LIKE '%_@_%._%'),
    -- Índice de apoyo para búsquedas del equipo comercial por apellido
    INDEX idx_cliente_apellidos (apellidos)
) ENGINE=InnoDB COMMENT='Clientes y leads del CRM.';


/* =====================================================================
   TABLA DE HECHOS · fact_ventas
   Granularidad: 1 fila = 1 línea de venta (un modelo vendido a un
   cliente en un concesionario un día). Normalmente unidades = 1; en
   ventas a flotas de empresa puede ser > 1.
   ---------------------------------------------------------------------
   · PK surrogate id_venta. codigo_venta es la clave del ERP (UNIQUE):
     garantiza que una misma venta no se carga dos veces (idempotencia).
   · Una FK por dimensión, todas NOT NULL: no hay ventas "huérfanas".
     ON DELETE RESTRICT en todas: una dimensión con ventas no se borra.
   · precio_unitario se guarda en la venta aunque exista precio_base en
     dim_modelo. NO es redundancia: es el precio histórico real (en 2025
     subió la tarifa). Si solo usáramos dim_modelo, al cambiar la tarifa
     se "reescribiría" la facturación pasada.
   · importe_total es una COLUMNA GENERADA (STORED): se calcula sola a
     partir de unidades, precio y descuento, así nunca puede quedar
     incoherente con ellas.
   · Desnormalización consciente: id_concesionario se podría deducir de
     id_vendedor. Se mantiene en la tabla de hechos (práctica estándar
     en modelos estrella) porque (1) el vendedor puede cambiar de
     concesionario en el futuro y la venta debe quedarse donde ocurrió,
     y (2) evita un JOIN extra en la consulta más frecuente.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS fact_ventas (
    id_venta          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    codigo_venta      VARCHAR(12)       NOT NULL,
    id_fecha          INT               NOT NULL,
    id_concesionario  SMALLINT UNSIGNED NOT NULL,
    id_vendedor       SMALLINT UNSIGNED NOT NULL,
    id_cliente        INT UNSIGNED      NOT NULL,
    id_modelo         SMALLINT UNSIGNED NOT NULL,
    unidades          SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    precio_unitario   DECIMAL(9,2)      NOT NULL,
    descuento_pct     DECIMAL(5,2)      NOT NULL DEFAULT 0.00,
    importe_total     DECIMAL(11,2)     GENERATED ALWAYS AS
                      (ROUND(unidades * precio_unitario * (1 - descuento_pct / 100), 2)) STORED,
    metodo_pago       VARCHAR(10)       NOT NULL DEFAULT 'Contado',
    estado            VARCHAR(10)       NOT NULL DEFAULT 'Completada',
    fecha_carga       TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- auditoría ETL
    CONSTRAINT pk_ventas              PRIMARY KEY (id_venta),
    CONSTRAINT uq_ventas_codigo       UNIQUE (codigo_venta),
    CONSTRAINT fk_ventas_fecha        FOREIGN KEY (id_fecha)
        REFERENCES dim_calendario (id_fecha)             ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ventas_concesionario FOREIGN KEY (id_concesionario)
        REFERENCES dim_concesionario (id_concesionario)  ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ventas_vendedor     FOREIGN KEY (id_vendedor)
        REFERENCES dim_vendedor (id_vendedor)            ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ventas_cliente      FOREIGN KEY (id_cliente)
        REFERENCES dim_cliente (id_cliente)              ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ventas_modelo       FOREIGN KEY (id_modelo)
        REFERENCES dim_modelo (id_modelo)                ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_ventas_unidades     CHECK (unidades BETWEEN 1 AND 50),
    CONSTRAINT ck_ventas_precio       CHECK (precio_unitario > 0),
    CONSTRAINT ck_ventas_descuento    CHECK (descuento_pct BETWEEN 0 AND 25),  -- política comercial: máx. 25 %
    CONSTRAINT ck_ventas_metodo_pago  CHECK (metodo_pago IN ('Contado','Financiado','Renting')),
    CONSTRAINT ck_ventas_estado       CHECK (estado IN ('Completada','Cancelada')),

    /* ÍNDICE COMPUESTO (concesionario, fecha)
       InnoDB ya crea automáticamente un índice por cada FK, así que un
       índice simple sobre id_concesionario no aportaría nada. Este índice
       compuesto sirve para la consulta más habitual de negocio:
       "ventas del concesionario X entre la fecha A y la B". MySQL localiza
       primero el concesionario y dentro de él recorre solo el rango de
       fechas, en lugar de leer toda la tabla. Además cubre la FK de
       id_concesionario (es la columna inicial), así que no se duplica índice.
       En 03_eda.sql se comprueba su uso con EXPLAIN.
       No se indexa 'estado' ni 'metodo_pago': con 2-3 valores posibles su
       selectividad es muy baja y el índice apenas filtraría. */
    INDEX idx_ventas_conc_fecha (id_concesionario, id_fecha)
) ENGINE=InnoDB COMMENT='Hechos: 1 fila = 1 línea de venta.';


/* =====================================================================
   FUNCIONES
   Nota: con el binlog activado (por defecto en MySQL 8) es obligatorio
   declarar DETERMINISTIC / NO SQL / READS SQL DATA al crear funciones.
   ===================================================================== */
DELIMITER $$

/* fn_edad: edad en años cumplidos a una fecha dada.
   Recibe la fecha de referencia como parámetro (y no usa CURDATE()) para
   poder calcular la edad que tenía el cliente EL DÍA DE LA COMPRA,
   que es la que importa para el análisis. Por eso es DETERMINISTIC. */
CREATE FUNCTION IF NOT EXISTS fn_edad(p_nacimiento DATE, p_fecha_ref DATE)
RETURNS TINYINT UNSIGNED
DETERMINISTIC NO SQL
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, p_nacimiento, p_fecha_ref);
END$$

/* fn_tramo_precio: clasifica un precio en gama de producto.
   Centraliza la regla de negocio: si mañana cambian los umbrales,
   se cambian aquí y todas las consultas que la usan quedan al día. */
CREATE FUNCTION IF NOT EXISTS fn_tramo_precio(p_precio DECIMAL(9,2))
RETURNS VARCHAR(12)
DETERMINISTIC NO SQL
BEGIN
    RETURN CASE
        WHEN p_precio <  6000 THEN 'Entrada'
        WHEN p_precio < 12000 THEN 'Media'
        WHEN p_precio < 20000 THEN 'Alta'
        ELSE 'Premium'
    END;
END$$

/* fn_facturacion_concesionario: facturación neta (ventas completadas)
   de un concesionario en un año. Función CON CONSULTA (READS SQL DATA).
   Devuelve 0 en lugar de NULL si no hubo ventas (COALESCE), para que se
   pueda sumar o comparar sin sorpresas. */
CREATE FUNCTION IF NOT EXISTS fn_facturacion_concesionario(
    p_id_concesionario SMALLINT UNSIGNED,
    p_anio             SMALLINT)
RETURNS DECIMAL(14,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(14,2);
    SELECT COALESCE(SUM(v.importe_total), 0)
      INTO v_total
      FROM fact_ventas    v
      JOIN dim_calendario c ON c.id_fecha = v.id_fecha
     WHERE v.id_concesionario = p_id_concesionario
       AND c.anio   = p_anio
       AND v.estado = 'Completada';
    RETURN v_total;
END$$

DELIMITER ;


/* =====================================================================
   VISTA · vw_ventas_detalle
   "Tabla plana" que une los hechos con todas sus dimensiones. Sirve de
   capa semántica: el analista (o Power BI en el módulo 4) consulta
   nombres legibles sin reescribir 7 JOIN cada vez.
   Usa INNER JOIN porque todas las FK de fact_ventas son NOT NULL:
   toda venta tiene siempre su dimensión, no se pierde ninguna fila.
   ===================================================================== */
CREATE OR REPLACE VIEW vw_ventas_detalle AS
SELECT
    v.id_venta,
    v.codigo_venta,
    c.fecha,
    c.anio,
    c.trimestre,
    c.mes,
    c.nombre_mes,
    c.nombre_dia,
    c.temporada,
    co.nombre               AS concesionario,
    co.tipo_zona,
    pc.nombre               AS provincia_concesionario,
    pc.comunidad_autonoma   AS comunidad_concesionario,
    CONCAT(ve.nombre, ' ', ve.apellidos) AS vendedor,
    cl.tipo_cliente,
    pcl.nombre              AS provincia_cliente,
    CASE WHEN cl.tipo_cliente = 'Particular'
         THEN fn_edad(cl.fecha_nacimiento, c.fecha) END AS edad_cliente,
    ma.nombre               AS marca,
    mo.nombre               AS modelo,
    mo.segmento,
    mo.carnet_minimo,
    mo.cilindrada_cc,
    fn_tramo_precio(v.precio_unitario) AS tramo_precio,
    v.unidades,
    v.precio_unitario,
    v.descuento_pct,
    v.importe_total,
    v.metodo_pago,
    v.estado
FROM fact_ventas        v
JOIN dim_calendario     c   ON c.id_fecha          = v.id_fecha
JOIN dim_concesionario  co  ON co.id_concesionario = v.id_concesionario
JOIN dim_provincia      pc  ON pc.id_provincia     = co.id_provincia
JOIN dim_vendedor       ve  ON ve.id_vendedor      = v.id_vendedor
JOIN dim_cliente        cl  ON cl.id_cliente       = v.id_cliente
JOIN dim_provincia      pcl ON pcl.id_provincia    = cl.id_provincia
JOIN dim_modelo         mo  ON mo.id_modelo        = v.id_modelo
JOIN dim_marca          ma  ON ma.id_marca         = mo.id_marca;

-- La vista resumen final (vw_resumen_provincia_segmento) se crea al
-- final de 03_eda.sql, porque es el resultado del análisis.
