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
