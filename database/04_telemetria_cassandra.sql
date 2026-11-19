-- ============ 04 · TELEMETRÍA (emula Cassandra, query-first) ============
-- Consulta de la app: "eventos de un usuario en un día"
-- Clave de partición: (usuario_id, dia)  ·  Clustering: ts, evento_id (dos eventos en el mismo instante no se pisan)
create table telemetria.eventos_por_usuario_dia(
  usuario_id  text not null,
  dia         date not null,
  ts          timestamptz not null default clock_timestamp(),
  evento_id   uuid not null default gen_random_uuid(),
  tipo        text not null check (tipo in ('LOGIN','VISTA','AGREGAR_CARRITO','COMPRA')),
  producto_id text,
  detalle     jsonb not null default '{}',
  primary key (usuario_id, dia, ts, evento_id)
);
-- Sin índice por producto_id a propósito: filtrar por producto es la consulta que en Cassandra
-- exigiría ALLOW FILTERING (aquí se ve como Seq Scan en EXPLAIN).
