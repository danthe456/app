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
