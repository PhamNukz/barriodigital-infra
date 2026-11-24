-- Oracle Free en ec2-db: 4 usuarios/esquemas, uno por microservicio
-- (Database per Service con esquemas separados). Flyway crea las tablas al
-- arrancar cada MS (V1__init.sql de cada repo); aqui solo van usuarios y grants.
--
-- Uso (ver barriodigital-docs/AWS-Infraestructura.md §6):
--   1. Copiarlo FUERA del repo como ~/oracle/init/01-schemas.sql en ec2-db y
--      reemplazar los 4 CAMBIAR_* por las contrasenas de apps/.env
--      (*_DB_PASSWORD). Nunca commitear este archivo con las contrasenas reales.
--   2. docker run ... -v ~/oracle/init:/container-entrypoint-initdb.d gvenzl/oracle-free:23-slim
-- gvenzl lo ejecuta solo con el volumen oracle-data vacio (primer arranque).

ALTER SESSION SET CONTAINER = FREEPDB1;

CREATE USER barriodigital_requests IDENTIFIED BY "CAMBIAR_REQUESTS_DB_PASSWORD";
CREATE USER barriodigital_catalog  IDENTIFIED BY "CAMBIAR_CATALOG_DB_PASSWORD";
CREATE USER barriodigital_audit    IDENTIFIED BY "CAMBIAR_AUDIT_DB_PASSWORD";
CREATE USER barriodigital_report   IDENTIFIED BY "CAMBIAR_REPORT_DB_PASSWORD";

BEGIN
  FOR u IN (SELECT column_value AS name FROM TABLE(sys.odcivarchar2list(
      'BARRIODIGITAL_REQUESTS','BARRIODIGITAL_CATALOG','BARRIODIGITAL_AUDIT','BARRIODIGITAL_REPORT'))) LOOP
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE VIEW TO ' || u.name;
    EXECUTE IMMEDIATE 'ALTER USER ' || u.name || ' QUOTA UNLIMITED ON USERS';
  END LOOP;
END;
/
