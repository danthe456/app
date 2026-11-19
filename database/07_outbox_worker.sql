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
