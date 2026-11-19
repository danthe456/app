-- ============ 05 · GRAFO (emula Neo4j) ============
-- Nodos con restricción de unicidad (PK) y relaciones como tablas de aristas.
create table grafo.usuario(id text primary key);
create table grafo.producto(id text primary key);
create table grafo.vio(                      -- (Usuario)-[:VIO]->(Producto)
  usuario_id text references grafo.usuario(id) on delete cascade,
  producto_id text references grafo.producto(id) on delete cascade,
  veces int not null default 1, ultima timestamptz not null default now(),
  primary key (usuario_id, producto_id));
create table grafo.compro(                   -- (Usuario)-[:COMPRO]->(Producto)
  usuario_id text references grafo.usuario(id) on delete cascade,
  producto_id text references grafo.producto(id) on delete cascade,
  veces int not null default 1, ultima timestamptz not null default now(),
  primary key (usuario_id, producto_id));
create index on grafo.compro(producto_id);

-- Filtrado colaborativo: productos comprados por quienes compraron lo mismo que yo
create or replace function grafo.recomendar(p_usuario text, p_limite int default 4)
returns table(producto_id text, puntaje bigint) language sql stable as $$
  with mios as (select c.producto_id from grafo.compro c where c.usuario_id = p_usuario),
  similares as (
    select distinct c.usuario_id from grafo.compro c
    where c.producto_id in (select producto_id from mios) and c.usuario_id <> p_usuario),
  colab as (
    select c.producto_id, count(*) as puntaje
    from grafo.compro c
    where c.usuario_id in (select usuario_id from similares)
      and c.producto_id not in (select producto_id from mios)
    group by c.producto_id),
  populares as (
    select c.producto_id, 0::bigint as puntaje from grafo.compro c
    where c.producto_id not in (select producto_id from mios)
      and c.producto_id not in (select producto_id from colab)
    group by c.producto_id order by count(*) desc)
  select t.producto_id, t.puntaje
  from (select * from colab union all select * from populares) t
  order by t.puntaje desc, t.producto_id
  limit p_limite
$$;
