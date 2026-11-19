-- ============ 01 · NÚCLEO RELACIONAL (esquema relacional) ============
-- Todo vive en PostgreSQL; cada "motor" lógico tiene su propio esquema.
create schema if not exists relacional;
create schema if not exists catalogo;   -- emula MongoDB
create schema if not exists cache;      -- emula Redis
create schema if not exists telemetria; -- emula Cassandra
create schema if not exists grafo;      -- emula Neo4j

create sequence if not exists relacional.seq_usuario;

create table relacional.usuarios(
  id        text primary key default 'U' || lpad(nextval('relacional.seq_usuario')::text, 3, '0'),
  auth_uid  uuid unique references auth.users(id) on delete cascade,
  nombre    text not null,
  email     text not null unique,
  rol       text not null default 'cliente' check (rol in ('cliente','admin')),
  creado    timestamptz not null default now()
);

-- Stock del producto. producto_id_externo = mismo ID que el catálogo (P001...)
create table relacional.inventario(
  producto_id_externo text primary key,
  stock int not null check (stock >= 0)
);

create table relacional.pedidos(
  id         bigserial primary key,
  usuario_id text not null references relacional.usuarios(id),
  estado     text not null check (estado in ('PAGADO','CANCELADO')),
  total      numeric(14,0) not null check (total >= 0),
  creado     timestamptz not null default now()
);

create table relacional.detalle(
  pedido_id   bigint not null references relacional.pedidos(id) on delete cascade,
  producto_id text   not null references relacional.inventario(producto_id_externo),
  cantidad    int    not null check (cantidad > 0),
  precio_unit numeric(14,0) not null check (precio_unit >= 0),
  primary key (pedido_id, producto_id)
);

create table relacional.pagos(
  id        bigserial primary key,
  pedido_id bigint not null unique references relacional.pedidos(id) on delete cascade,
  metodo    text not null,
  monto     numeric(14,0) not null check (monto >= 0),
  estado    text not null check (estado in ('APROBADO','RECHAZADO')),
  creado    timestamptz not null default now()
);

create table relacional.auditoria(
  id          bigserial primary key,
  tabla       text not null,
  operacion   text not null,
  usuario_app text not null,   -- usuario de la aplicación (no solo el de la base)
  usuario_db  text not null,
  antes       jsonb,
  despues     jsonb,
  ts          timestamptz not null default now()
);

-- Patrón Outbox: la compra se confirma aquí y un worker propaga a telemetría y grafo
create table relacional.outbox(
  id        bigserial primary key,
  tipo      text not null,
  payload   jsonb not null,
  estado    text not null default 'PENDIENTE' check (estado in ('PENDIENTE','PROCESADO','ERROR')),
  intentos  int  not null default 0,
  error     text,
  creado    timestamptz not null default now(),
  procesado timestamptz
);
create index on relacional.outbox(estado, id);

create table relacional.config(clave text primary key, valor text not null);
insert into relacional.config values ('grafo_activo','true');  -- 'false' simula Neo4j detenido
-- ============ 02 · CATÁLOGO DOCUMENTAL (emula MongoDB) ============
-- El "validador $jsonSchema" se implementa como CHECK sobre jsonb.
create or replace function catalogo.validar_producto(d jsonb) returns boolean
language sql immutable as $$
  select coalesce(
    case
      when jsonb_typeof(d) <> 'object' then false
      when not (d ? 'nombre' and d ? 'categoria' and d ? 'precio' and d ? 'atributos') then false
      when jsonb_typeof(d->'precio') <> 'number' or (d->>'precio')::numeric < 0 then false
      when jsonb_typeof(d->'atributos') <> 'object' then false
      when d->>'categoria' = 'portatil' then (d->'atributos') ?& array['procesador','ram','almacenamiento']
      when d->>'categoria' = 'celular'  then (d->'atributos') ?& array['pantalla','camara','bateria']
      when d->>'categoria' = 'ropa'     then (d->'atributos') ?& array['talla','color','material']
      when d->>'categoria' = 'accesorio' then true
      else false
    end, false)
$$;

create table catalogo.productos(
  id  text primary key,                       -- _id de Mongo (P001...)
  doc jsonb not null check (catalogo.validar_producto(doc))
);
-- Índices en campos de filtro (se demuestran con EXPLAIN)
create index idx_prod_categoria on catalogo.productos ((doc->>'categoria'));
create index idx_prod_precio    on catalogo.productos (((doc->>'precio')::numeric));
create index idx_prod_doc_gin   on catalogo.productos using gin (doc jsonb_path_ops);
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
-- ============ 06 · LÓGICA RELACIONAL Y API PARA EL FRONTEND ============
-- Usuario de la aplicación a partir del JWT de Supabase Auth
create or replace function relacional.usuario_actual() returns text
language sql stable security definer set search_path = '' as $$
  select id from relacional.usuarios where auth_uid = auth.uid()
$$;

-- Alta automática del perfil al registrarse (contraseña: bcrypt en Supabase Auth)
create or replace function relacional.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into relacional.usuarios(auth_uid, nombre, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)), new.email);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function relacional.handle_new_user();

-- Trigger de auditoría: registra el usuario de la APLICACIÓN
create or replace function relacional.fn_auditar() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into relacional.auditoria(tabla, operacion, usuario_app, usuario_db, antes, despues)
  values (tg_table_name, tg_op, coalesce(relacional.usuario_actual(), 'sistema'), current_user,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;
create trigger aud_inventario after insert or update or delete on relacional.inventario for each row execute function relacional.fn_auditar();
create trigger aud_pedidos    after insert or update or delete on relacional.pedidos    for each row execute function relacional.fn_auditar();
create trigger aud_pagos      after insert or update or delete on relacional.pagos      for each row execute function relacional.fn_auditar();

-- FUNCIÓN: total del carrito (precio tomado del catálogo, nunca del cliente)
create or replace function relacional.fn_total_carrito(p_usuario text) returns numeric
language sql stable as $$
  select coalesce(sum(c.cantidad * (k.doc->>'precio')::numeric), 0)
  from cache.carrito c join catalogo.productos k on k.id = c.producto_id
  where c.usuario_id = p_usuario
$$;

-- PROCEDIMIENTO ALMACENADO: crea el pedido en UNA transacción.
-- El UPDATE condicional bloquea la fila: dos compras de la última unidad no pueden ambas pasar.
create or replace procedure relacional.sp_crear_pedido(p_usuario text, p_items jsonb, inout p_pedido bigint)
language plpgsql as $$
declare it record; v_precio numeric; v_total numeric := 0;
begin
  insert into relacional.pedidos(usuario_id, estado, total) values (p_usuario, 'PAGADO', 0)
  returning id into p_pedido;
  for it in select e->>'producto_id' as pid, (e->>'cantidad')::int as cant
            from jsonb_array_elements(p_items) e order by 1 loop      -- orden fijo evita deadlocks
    update relacional.inventario set stock = stock - it.cant
    where producto_id_externo = it.pid and stock >= it.cant;
    if not found then raise exception 'Stock insuficiente para %', it.pid; end if;
    select (doc->>'precio')::numeric into v_precio from catalogo.productos where id = it.pid;
    insert into relacional.detalle values (p_pedido, it.pid, it.cant, v_precio);
    v_total := v_total + v_precio * it.cant;
  end loop;
  update relacional.pedidos set total = v_total where id = p_pedido;
  insert into relacional.pagos(pedido_id, metodo, monto, estado) values (p_pedido, 'SIMULADO', v_total, 'APROBADO');
  insert into relacional.outbox(tipo, payload) values ('COMPRA_CONFIRMADA',
    jsonb_build_object('pedido_id', p_pedido, 'usuario_id', p_usuario, 'items', p_items, 'ts', now()));
end $$;

-- ---------- API pública (lo único que ve el navegador) ----------
create or replace view public.api_catalogo as
  select c.id, c.doc->>'nombre' as nombre, c.doc->>'categoria' as categoria,
         (c.doc->>'precio')::numeric as precio, i.stock, c.doc->'atributos' as atributos
  from catalogo.productos c join relacional.inventario i on i.producto_id_externo = c.id;

-- VISTA: mis pedidos (filtrada por el usuario de la sesión)
create or replace view public.v_mis_pedidos as
  select p.id, p.estado, p.total, p.creado,
    (select jsonb_agg(jsonb_build_object('producto_id', d.producto_id, 'cantidad', d.cantidad, 'nombre', k.doc->>'nombre'))
       from relacional.detalle d join catalogo.productos k on k.id = d.producto_id where d.pedido_id = p.id) as items
  from relacional.pedidos p where p.usuario_id = relacional.usuario_actual();

create or replace function public.abrir_sesion() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare u text := relacional.usuario_actual(); e timestamptz;
begin
  if u is null then raise exception 'No autenticado'; end if;
  insert into cache.sesiones(usuario_id) values (u) returning expira into e;
  perform public.registrar_evento('LOGIN', null);
  return e;
end $$;

create or replace function public.cerrar_sesion() returns void
language sql security definer set search_path = '' as $$
  delete from cache.sesiones where usuario_id = relacional.usuario_actual()
$$;

create or replace function public.carrito_ver() returns table(producto_id text, cantidad int)
language sql stable security definer set search_path = '' as $$
  select producto_id, cantidad from cache.carrito where usuario_id = relacional.usuario_actual() order by actualizado
$$;

create or replace function public.carrito_total() returns numeric
language sql stable security definer set search_path = '' as $$
  select relacional.fn_total_carrito(relacional.usuario_actual())
$$;

create or replace function public.carrito_set(p_producto text, p_cantidad int) returns void
language plpgsql security definer set search_path = '' as $$
declare u text := relacional.usuario_actual(); v_stock int;
begin
  if u is null then raise exception 'Inicia sesión para usar el carrito'; end if;
  if p_cantidad <= 0 then
    delete from cache.carrito where usuario_id = u and producto_id = p_producto; return;
  end if;
  select stock into v_stock from relacional.inventario where producto_id_externo = p_producto;
  if v_stock is null then raise exception 'Producto inexistente'; end if;
  if p_cantidad > v_stock then raise exception 'No hay más unidades disponibles'; end if;
  insert into cache.carrito(usuario_id, producto_id, cantidad) values (u, p_producto, p_cantidad)
  on conflict (usuario_id, producto_id) do update set cantidad = excluded.cantidad, actualizado = now();
  perform public.registrar_evento('AGREGAR_CARRITO', p_producto);
end $$;

create or replace function public.registrar_evento(p_tipo text, p_producto text) returns void
language plpgsql security definer set search_path = '' as $$
declare u text := relacional.usuario_actual();
begin
  if u is null then return; end if;
  insert into telemetria.eventos_por_usuario_dia(usuario_id, dia, tipo, producto_id)
  values (u, (now() at time zone 'UTC')::date, p_tipo, p_producto);
  if p_tipo = 'VISTA' then   -- la vista llega al grafo de forma eventual (outbox)
    insert into relacional.outbox(tipo, payload)
    values ('VISTA', jsonb_build_object('usuario_id', u, 'producto_id', p_producto));
  end if;
end $$;

-- Consulta por partición completa (usuario + día)
create or replace function public.mis_eventos(p_dia date default (now() at time zone 'UTC')::date)
returns setof telemetria.eventos_por_usuario_dia
language sql stable security definer set search_path = '' as $$
  select * from telemetria.eventos_por_usuario_dia
  where usuario_id = relacional.usuario_actual() and dia = p_dia order by ts
$$;

create or replace function public.comprar() returns bigint
language plpgsql security definer set search_path = '' as $$
declare u text := relacional.usuario_actual(); items jsonb; v_pedido bigint;
begin
  if u is null then raise exception 'Inicia sesión para comprar'; end if;
  select jsonb_agg(jsonb_build_object('producto_id', producto_id, 'cantidad', cantidad))
    into items from cache.carrito where usuario_id = u;
  if items is null then raise exception 'El carrito está vacío'; end if;
  call relacional.sp_crear_pedido(u, items, v_pedido);
  delete from cache.carrito where usuario_id = u;
  return v_pedido;
end $$;

-- Recomendaciones con caché cache-aside (TTL 5 min)
create or replace function public.recomendaciones() returns setof text
language plpgsql security definer set search_path = '' as $$
declare u text := relacional.usuario_actual(); k text; v jsonb;
begin
  if u is null then return; end if;
  k := 'reco:' || u;
  select valor into v from cache.kv where clave = k and expira > now();
  if v is null then
    select coalesce(jsonb_agg(producto_id), '[]'::jsonb) into v from grafo.recomendar(u, 4);
    insert into cache.kv values (k, v, now() + interval '5 minutes')
    on conflict (clave) do update set valor = excluded.valor, expira = excluded.expira;
  end if;
  return query select jsonb_array_elements_text(v);
end $$;
-- ============ 07 · WORKER DEL OUTBOX (consistencia eventual) ============
-- Propaga compras y vistas a telemetría y grafo. Si el grafo está "caído" el evento queda en ERROR
-- y se reintenta en la siguiente ejecución. Es idempotente.
create or replace function relacional.procesar_outbox(p_limite int default 50) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; it jsonb; n int := 0; v_u text; v_p text; v_ts timestamptz;
begin
  for r in select * from relacional.outbox
           where estado in ('PENDIENTE','ERROR') and intentos < 10
           order by id limit p_limite for update skip locked loop
    begin
      if (select valor from relacional.config where clave = 'grafo_activo') <> 'true' then
        raise exception 'Grafo no disponible';
      end if;
      v_u := r.payload->>'usuario_id';
      insert into grafo.usuario(id) values (v_u) on conflict do nothing;
      if r.tipo = 'VISTA' then
        v_p := r.payload->>'producto_id';
        insert into grafo.producto(id) values (v_p) on conflict do nothing;
        insert into grafo.vio(usuario_id, producto_id) values (v_u, v_p)
        on conflict (usuario_id, producto_id) do update set veces = grafo.vio.veces + 1, ultima = now();
      else
        v_ts := (r.payload->>'ts')::timestamptz;
        for it in select * from jsonb_array_elements(r.payload->'items') loop
          v_p := it->>'producto_id';
          insert into telemetria.eventos_por_usuario_dia(usuario_id, dia, ts, evento_id, tipo, producto_id, detalle)
          values (v_u, (v_ts at time zone 'UTC')::date, v_ts, md5(r.id::text || '-' || v_p)::uuid, 'COMPRA', v_p,
                  jsonb_build_object('pedido_id', r.payload->'pedido_id', 'cantidad', it->'cantidad'))
          on conflict do nothing;
          insert into grafo.producto(id) values (v_p) on conflict do nothing;
          insert into grafo.compro(usuario_id, producto_id, veces) values (v_u, v_p, (it->>'cantidad')::int)
          on conflict (usuario_id, producto_id) do update set veces = grafo.compro.veces + excluded.veces, ultima = now();
        end loop;
        delete from cache.kv where clave = 'reco:' || v_u;   -- invalida la caché
      end if;
      update relacional.outbox set estado = 'PROCESADO', procesado = now(), error = null where id = r.id;
      n := n + 1;
    exception when others then
      update relacional.outbox set estado = 'ERROR', intentos = intentos + 1, error = sqlerrm where id = r.id;
    end;
  end loop;
  return n;
end $$;

-- Ejecutar cada minuto (Database → Extensions → habilitar pg_cron):
-- select cron.schedule('outbox-worker','* * * * *','select relacional.procesar_outbox()');
-- ============ 08 · DATOS DE EJEMPLO ============
insert into catalogo.productos(id, doc) values
('P001','{"nombre":"Aero 14 Pro","categoria":"portatil","precio":3899000,"atributos":{"procesador":"Core Ultra 7","ram":"16 GB","almacenamiento":"512 GB SSD","pantalla":"14\" OLED"}}'),
('P002','{"nombre":"Forge 16 Gamer","categoria":"portatil","precio":6299000,"atributos":{"procesador":"Ryzen 9","ram":"32 GB","almacenamiento":"1 TB SSD","pantalla":"16\" 165 Hz"}}'),
('P003','{"nombre":"Slim 13 Air","categoria":"portatil","precio":2499000,"atributos":{"procesador":"Core i5","ram":"8 GB","almacenamiento":"256 GB SSD","pantalla":"13\" IPS"}}'),
('P004','{"nombre":"Nova X5","categoria":"celular","precio":1899000,"atributos":{"pantalla":"6.5\" AMOLED","camara":"64 MP","bateria":"5000 mAh","almacenamiento":"128 GB"}}'),
('P005','{"nombre":"Nova X5 Max","categoria":"celular","precio":2699000,"atributos":{"pantalla":"6.8\" AMOLED","camara":"108 MP","bateria":"5500 mAh","almacenamiento":"256 GB"}}'),
('P006','{"nombre":"Pulse Lite","categoria":"celular","precio":799000,"atributos":{"pantalla":"6.1\" LCD","camara":"13 MP","bateria":"4500 mAh","almacenamiento":"64 GB"}}'),
('P007','{"nombre":"Camiseta algodón orgánico","categoria":"ropa","precio":69000,"atributos":{"talla":"S, M, L, XL","color":"Blanco","material":"Algodón 100 %"}}'),
('P008','{"nombre":"Chaqueta cortaviento","categoria":"ropa","precio":219000,"atributos":{"talla":"M, L","color":"Azul noche","material":"Poliéster reciclado"}}'),
('P009','{"nombre":"Jean recto clásico","categoria":"ropa","precio":159000,"atributos":{"talla":"28 a 38","color":"Índigo","material":"Denim"}}'),
('P010','{"nombre":"Audífonos Wave ANC","categoria":"accesorio","precio":329000,"atributos":{"tipo":"Diadema","conexión":"Bluetooth 5.3","autonomía":"40 h"}}'),
('P011','{"nombre":"Mouse inalámbrico Glide","categoria":"accesorio","precio":89000,"atributos":{"conexión":"2.4 GHz y Bluetooth","dpi":"4000","autonomía":"90 días"}}'),
('P012','{"nombre":"Cargador GaN 65 W","categoria":"accesorio","precio":119000,"atributos":{"potencia":"65 W","puertos":"2 USB-C + 1 USB-A","compatibilidad":"Portátiles y celulares"}}');

insert into relacional.inventario values
('P001',8),('P002',3),('P003',15),('P004',20),('P005',2),('P006',40),
('P007',60),('P008',12),('P009',25),('P010',18),('P011',50),('P012',4);

-- Clientes ficticios con historial, para que haya recomendaciones desde el inicio
insert into relacional.usuarios(id, nombre, email) values
('U901','Cliente demo 1','demo1@polystore.co'),('U902','Cliente demo 2','demo2@polystore.co'),('U903','Cliente demo 3','demo3@polystore.co');
insert into grafo.usuario select id from relacional.usuarios where id like 'U9%';
insert into grafo.producto select id from catalogo.productos;
insert into grafo.compro(usuario_id, producto_id) values
('U901','P001'),('U901','P010'),('U901','P012'),
('U902','P001'),('U902','P010'),('U902','P011'),
('U903','P004'),('U903','P005'),('U903','P010');
-- ============ 09 · SEGURIDAD (mínimo privilegio) ============
-- Los esquemas internos no son accesibles para el navegador (anon / authenticated).
revoke all on schema relacional, catalogo, cache, telemetria, grafo from public, anon, authenticated;
revoke all on all tables in schema relacional, catalogo, cache, telemetria, grafo from public, anon, authenticated;
revoke all on all functions in schema relacional, catalogo, cache, telemetria, grafo from public, anon, authenticated;

-- RLS activado en todas las tablas internas (sin políticas = nadie accede salvo el dueño)
do $$ declare t record; begin
  for t in select schemaname, tablename from pg_tables
           where schemaname in ('relacional','catalogo','cache','telemetria','grafo') loop
    execute format('alter table %I.%I enable row level security', t.schemaname, t.tablename);
  end loop;
end $$;

-- Cuenta de aplicación con privilegios mínimos (equivale a app_user del enunciado)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'app_user') then create role app_user nologin; end if;
end $$;
grant app_user to postgres;
grant usage on schema public to app_user;
grant select on public.api_catalogo, public.v_mis_pedidos to app_user;
grant select on public.api_catalogo to anon;
grant select on public.api_catalogo, public.v_mis_pedidos to authenticated;

-- Solo estas funciones son invocables desde el navegador, y solo con sesión iniciada
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in
           ('abrir_sesion','cerrar_sesion','carrito_ver','carrito_total','carrito_set','registrar_evento','mis_eventos','comprar','recomendaciones') loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, app_user', f.sig);
  end loop;
end $$;
