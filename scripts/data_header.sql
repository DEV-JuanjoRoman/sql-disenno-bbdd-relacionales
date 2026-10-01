/* =====================================================================
   PROYECTO MÓDULO 2 · SQL
   02_data.sql  →  carga de datos, limpieza y transacciones
   Motor: MySQL 8.0+   ·   Requiere haber ejecutado antes 01_schema.sql
   ---------------------------------------------------------------------
   Origen de los datos: base de datos FICTICIA generada con un script de
   Python (semilla fija, reproducible) que simula las exportaciones del
   CRM (clientes) y del ERP (ventas) de una red de concesionarios.
   Los datos incluyen patrones de negocio realistas (estacionalidad,
   preferencias por edad, financiación según precio...) y también
   ERRORES INTENCIONADOS para practicar la limpieza en SQL.

   Orden de carga = orden de dependencias de las FK:
     provincia → marca → modelo → concesionario → vendedor
     → calendario → cliente → (staging) → fact_ventas
   ===================================================================== */

USE motos_dw;
SET NAMES utf8mb4;

-- MySQL Workbench trae activado "safe updates", que bloquea UPDATE/DELETE
-- sin una clave en el WHERE. Lo desactivamos solo durante este script
-- y al final se restaura el valor que tuviera.
SET @old_safe_updates = @@SQL_SAFE_UPDATES;
SET SQL_SAFE_UPDATES = 0;
