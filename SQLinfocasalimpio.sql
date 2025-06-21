CREATE DATABASE infocasasbol; -- Crea la base de datos principal
USE infocasasbol;             -- Selecciona la base de datos para trabajar
ALTER TABLE infocasas                 --Agregar columna ID autoincremental como clave primaria
ADD id INT IDENTITY(1,1) PRIMARY KEY; 

----------- A. LIMPIEZA DATOS CRUDOS -------------------
-- 1. Limpieza de precios

ALTER TABLE infocasas ADD precio_usd INT; -- Crea nueva columna para precios limpios

-- Elimina registros con precios nulos o no definidos 
DELETE FROM infocasas
WHERE precio IS NULL
   OR precio LIKE '%Consultar%';

-- Limpia texto y convierte los precios a enteros
UPDATE infocasas
SET precio_usd = CAST(REPLACE(REPLACE(precio, 'U$S ', ''), '.', '') AS INT);

-- 2. Limpieza de gastos comunes

ALTER TABLE infocasas ADD gastoscom_usd INT; -- Nueva columna

-- Limpieza y conversión a entero
UPDATE infocasas
SET gastoscom_usd = CAST(REPLACE(REPLACE(gastos_comunes, 'U$S ', ''), '.', '') AS INT);

-- 3. Limpieza del área
ALTER TABLE infocasas ADD area_m2 INT; -- Nueva columna para el área limpia

-- Limpieza del carácter “²” y conversión a número entero
UPDATE infocasas
SET area_m2 = CAST(CAST(REPLACE(area, '²', '') AS FLOAT) AS INT);

-- 4. Corrección del año de construcción
-- Corrige errores de importación donde el año tiene un 0 extra 
UPDATE infocasas
SET anio_construccion = anio_construccion / 10
WHERE anio_construccion > 2100;

-- Convierte año a tipo fecha 
ALTER TABLE infocasas ADD anio_construccion_fecha DATE;

UPDATE infocasas
SET anio_construccion_fecha = 
    TRY_CONVERT(DATE, CONCAT(CAST(CAST(anio_construccion AS INT) AS VARCHAR), '-01-01'))
WHERE anio_construccion IS NOT NULL;

-- 5. Limpieza de número de dormitorios
-- Corrige valores erróneos que tiene un O extra
UPDATE infocasas
SET dormitorios = dormitorios / 10
WHERE dormitorios >= 10;

-- 6. Eliminación de columnas originales sucias

ALTER TABLE infocasas DROP COLUMN anio_construccion;
EXEC sp_rename 'infocasas.anio_construccion_fecha', 'anio_construccion', 'COLUMN';
ALTER TABLE infocasas DROP COLUMN precio;
ALTER TABLE infocasas DROP COLUMN area;
ALTER TABLE infocasas DROP COLUMN gastos_comunes;

-------- B. LIMPIEZA DE LA DATA ------------------------
-- 1. Eliminar registros con coordenadas vacías o inválidas
DELETE
FROM infocasas
WHERE 
    (latitud IS NULL OR latitud = '' OR latitud = '0' OR latitud = '0.0')
    AND 
    (longitud IS NULL OR longitud = '' OR longitud = '0' OR longitud = '0.0');

-- 2. Eliminar registros fuera de los límites geográficos de cada ciudad

SELECT *
FROM infocasas
WHERE
    (ciudad = 'Santa Cruz' AND (latitud NOT BETWEEN -18.1 AND -17.0 OR longitud NOT BETWEEN -64.5 AND -62.5))
    OR
    (ciudad = 'Cochabamba' AND (latitud NOT BETWEEN -17.5 AND -16.9 OR longitud NOT BETWEEN -66.3 AND -65.8))
    OR
    (ciudad = 'La Paz' AND (latitud NOT BETWEEN -16.6 AND -16.3 OR longitud NOT BETWEEN -68.3 AND -68.0));

DELETE
FROM infocasas
WHERE
    (ciudad = 'Santa Cruz' AND (latitud NOT BETWEEN -18.1 AND -17.0 OR longitud NOT BETWEEN -64.5 AND -62.5))
    OR
    (ciudad = 'Cochabamba' AND (latitud NOT BETWEEN -17.5 AND -16.9 OR longitud NOT BETWEEN -66.3 AND -65.8))
    OR
    (ciudad = 'La Paz' AND (latitud NOT BETWEEN -16.6 AND -16.3 OR longitud NOT BETWEEN -68.3 AND -68.0));

-- 3. Revisar y corregir duplicados y registros incompletos 

-- Verifica si hay registros duplicados por URL y título
SELECT url, titulo, COUNT(*) AS cantidad
FROM infocasas
GROUP BY url, titulo
HAVING COUNT(*) > 1;

-- Elimina registros sin precio limpio o precio inválido
DELETE FROM infocasas WHERE precio_usd IS NULL OR precio_usd <= 0;

-- Elimina registros sin área
DELETE FROM infocasas WHERE area_m2 IS NULL;
-- Elimina registros con precios irrealmente bajos
SELECT * FROM infocasas WHERE precio_usd < 100;
DELETE FROM infocasas WHERE precio_usd < 100;

-- 4. Ajuste de Moneda
--  Revisar y corregir  precios que parecen estar en bolivianos y no dólares
SELECT *
FROM infocasas
WHERE precio_usd > 1400
  AND id_zona IN (49, 48, 39, 35, 34)
	AND area_m2 < 300;

UPDATE infocasas
SET precio_usd = precio_usd / 6.96
WHERE precio_usd > 1400
  AND id_zona IN (49, 48, 39, 35, 34)
  AND area_m2 < 300;

-- Revisar y corregir  precios excesivos posiblemente en bolivianos
SELECT *
FROM infocasas
WHERE precio_usd > 3000;

UPDATE infocasas
SET precio_usd = precio_usd / 6.96
WHERE precio_usd > 3000;

-------- C. NORMALIZACIÓN DE ZONAS Y CIUDADES ----------------------

CREATE TABLE ciudades (
    id_ciudad INT IDENTITY(1,1) PRIMARY KEY,
    nombre_ciudad NVARCHAR(100) UNIQUE
);

CREATE TABLE zonas (
    id_zona INT IDENTITY(1,1) PRIMARY KEY,
    nombre_zona NVARCHAR(100),
    id_ciudad INT NOT NULL,
    FOREIGN KEY (id_ciudad) REFERENCES ciudades(id_ciudad)
);

-- Garantiza que no se repitan zonas dentro de la misma ciudad
CREATE UNIQUE INDEX ux_zona_ciudad
ON zonas (nombre_zona, id_ciudad);

-- Agregar claves foráneas a tabla principal
ALTER TABLE infocasas ADD id_zona INT;

ALTER TABLE infocasas
ADD CONSTRAINT fk_infocasas_zona FOREIGN KEY (id_zona) REFERENCES zonas(id_zona);

-- Poblar tablas de ciudades y zonas
INSERT INTO ciudades (nombre_ciudad)
SELECT DISTINCT ciudad
FROM infocasas
WHERE ciudad IS NOT NULL;

INSERT INTO zonas (nombre_zona, id_ciudad)
SELECT DISTINCT i.zona, c.id_ciudad
FROM infocasas i
JOIN ciudades c ON i.ciudad = c.nombre_ciudad
WHERE i.zona IS NOT NULL;

-- Actualizar la tabla principal con las nuevas claves foráneas
UPDATE i
SET i.id_zona = z.id_zona
FROM infocasas i
JOIN zonas z ON i.zona = z.nombre_zona
             AND i.ciudad = (SELECT nombre_ciudad FROM ciudades WHERE id_ciudad = z.id_ciudad);

-- Verificación final y limpieza
SELECT * FROM infocasas WHERE id_zona IS NULL; -- Verifica registros sin zona asignada
SELECT * FROM infocasas;
SELECT * FROM ciudades;
SELECT * FROM zonas;

-- Elimina columnas originales de zona y ciudad
ALTER TABLE infocasas DROP COLUMN zona, ciudad;
