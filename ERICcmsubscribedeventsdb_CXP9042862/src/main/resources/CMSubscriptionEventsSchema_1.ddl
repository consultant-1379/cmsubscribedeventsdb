-- ##########################################################################
-- # COPYRIGHT Ericsson 2022
-- #
-- # The copyright to the computer program(s) herein is the property of
-- # Ericsson Inc. The programs may be used and/or copied only with written
-- # permission from Ericsson Inc. or in accordance with the terms and
-- # conditions stipulated in the agreement/contract under which the
-- # program(s) have been supplied.
-- ##########################################################################
CREATE OR REPLACE function create_sequence_if_not_exists (
    s_name text, sequence_sql text
)
RETURNS void AS
$BODY$
BEGIN
    IF NOT EXISTS (SELECT 0
                   FROM pg_class WHERE relname = s_name) THEN
         EXECUTE sequence_sql;
    END IF;
END;
$BODY$
LANGUAGE plpgsql
;


SELECT create_sequence_if_not_exists('version_id','CREATE SEQUENCE DB_VERSION_ID START 1');
ALTER SEQUENCE IF EXISTS DB_VERSION_ID OWNER TO cmsubscribedevents;

CREATE TABLE IF NOT EXISTS version
(
  id integer NOT NULL DEFAULT NEXTVAL('DB_VERSION_ID'),
  version character varying(255) NOT NULL,
  comments character varying(255) NOT NULL,
  updated_date date NOT NULL,
  status character varying(255) NOT NULL,
  CONSTRAINT pk_version_id PRIMARY KEY (id),
  CONSTRAINT uk_version_id UNIQUE (version)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE IF EXISTS version
  OWNER TO cmsubscribedevents;

INSERT INTO version(id,version,comments,updated_date,status) SELECT 1,'1','updated to new database model',CURRENT_DATE,'current' WHERE NOT EXISTS (SELECT * FROM version WHERE id = 1);

CREATE TABLE IF NOT EXISTS scope (
    id integer NOT NULL PRIMARY KEY,
    scopeType varchar(42),
    scopeLevel integer
  );

CREATE TABLE IF NOT EXISTS cmsubscribedeventssubs (
    id integer NOT NULL PRIMARY KEY,
    notificationRecipientAddress varchar(300) NOT NULL,
    scopeId integer,
    notificationTypes varchar(300),
    notificationFilter varchar(5000),
    objectInstance varchar(600)NOT NULL,
    objectClass varchar(300)NOT NULL,
    CONSTRAINT "scope_fk" FOREIGN KEY (scopeId) REFERENCES scope (id)
  );

ALTER TABLE IF EXISTS cmsubscribedeventssubs SET (autovacuum_enabled=true);
ALTER TABLE IF EXISTS cmsubscribedeventssubs SET (autovacuum_vacuum_scale_factor = 0.15);
ALTER TABLE IF EXISTS cmsubscribedeventssubs SET (autovacuum_vacuum_threshold = 100);
ALTER TABLE IF EXISTS cmsubscribedeventssubs SET (autovacuum_analyze_scale_factor = 0.12);
ALTER TABLE IF EXISTS cmsubscribedeventssubs SET (autovacuum_analyze_threshold = 50);
ALTER TABLE IF EXISTS cmsubscribedeventssubs
  OWNER TO cmsubscribedevents;

ALTER TABLE IF EXISTS scope SET (autovacuum_enabled=true);
ALTER TABLE IF EXISTS scope SET (autovacuum_vacuum_scale_factor = 0.15);
ALTER TABLE IF EXISTS scope SET (autovacuum_vacuum_threshold = 100);
ALTER TABLE IF EXISTS scope SET (autovacuum_analyze_scale_factor = 0.12);
ALTER TABLE IF EXISTS scope SET (autovacuum_analyze_threshold = 50);
ALTER TABLE IF EXISTS scope
  OWNER TO cmsubscribedevents;

CREATE SEQUENCE hibernate_sequence START 1;