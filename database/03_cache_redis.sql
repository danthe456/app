-- ============ 03 · SESIONES, CARRITO Y CACHÉ (emula Redis) ============
create table cache.sesiones(               -- SET sesion:<token> con TTL
  token      uuid primary key default gen_random_uuid(),
  usuario_id text not null references relacional.usuarios(id) on delete cascade,
  datos      jsonb not null default '{}',
  expira     timestamptz not null default now() + interval '30 minutes'
);
create index on cache.sesiones(expira);

create table cache.carrito(                -- HASH carrito:<usuario>  (campo = producto, valor = cantidad)
  usuario_id  text not null references relacional.usuarios(id) on delete cascade,
  producto_id text not null,
  cantidad    int  not null check (cantidad > 0),
  actualizado timestamptz not null default now(),
  primary key (usuario_id, producto_id)
);

create table cache.kv(                     -- caché cache-aside con expiración
  clave  text primary key,
  valor  jsonb not null,
  expira timestamptz not null
);

-- Expiración activa (Redis expira solo; aquí se purga y además se filtra al leer)
create or replace function cache.purgar_expirados() returns int language plpgsql as $$
declare n int;
begin
  delete from cache.sesiones where expira < now();
  delete from cache.kv where expira < now();
  delete from cache.carrito where actualizado < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end $$;
-- Opcional (Database → Extensions → pg_cron):
-- select cron.schedule('purga-cache','*/5 * * * *','select cache.purgar_expirados()');
