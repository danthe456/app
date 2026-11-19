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
