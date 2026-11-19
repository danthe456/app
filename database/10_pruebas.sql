-- ============ 10 · PRUEBAS PARA LA SUSTENTACIÓN (ejecutar una por una) ============
-- 1) app_user no puede leer la auditoría
set role app_user;  select * from relacional.auditoria;  reset role;   -- ERROR: permission denied

-- 2) Validador rechaza un producto sin precio
insert into catalogo.productos values ('PX','{"nombre":"Sin precio","categoria":"ropa","atributos":{"talla":"M","color":"rojo","material":"lana"}}');  -- ERROR check

-- 3) Índices en uso (buscar Index Scan / Bitmap Index Scan)
set enable_seqscan = off;
explain select * from catalogo.productos where doc->>'categoria' = 'celular';
explain select * from catalogo.productos where (doc->>'precio')::numeric < 500000;
reset enable_seqscan;

-- 4) Telemetría: por partición completa vs. filtrando por producto (el "ALLOW FILTERING")
explain select * from telemetria.eventos_por_usuario_dia where usuario_id = 'U001' and dia = current_date;
explain select * from telemetria.eventos_por_usuario_dia where producto_id = 'P001';   -- Seq Scan

-- 5) Inventario nunca negativo
update relacional.inventario set stock = -1 where producto_id_externo = 'P001';        -- ERROR check

-- 6) Outbox: simular grafo caído, comprar, ver ERROR, recuperar
update relacional.config set valor = 'false' where clave = 'grafo_activo';
select relacional.procesar_outbox();  select id, tipo, estado, intentos, error from relacional.outbox order by id;
update relacional.config set valor = 'true' where clave = 'grafo_activo';
select relacional.procesar_outbox();  select id, tipo, estado, intentos from relacional.outbox order by id;

-- 7) Auditoría con el usuario de la aplicación
select tabla, operacion, usuario_app, usuario_db, ts from relacional.auditoria order by id desc limit 10;
