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
