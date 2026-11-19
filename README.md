# PolyStore 360 · Persistencia políglota sobre PostgreSQL (Supabase)

Frontend estático (HTML, CSS, JS) en Netlify + base de datos en Supabase.
Los cinco "motores" se emulan en PostgreSQL, uno por esquema (autorizado por el docente).

| Motor original | Esquema | Cómo se emula |
|---|---|---|
| PostgreSQL | `relacional` | tablas, FK, CHECK, procedimiento, función, vistas, triggers de auditoría, outbox |
| MongoDB | `catalogo` | `jsonb` + validador `CHECK` por categoría + índices (GIN y de expresión) |
| Redis | `cache` | sesiones con `expira`, carrito como hash (usuario, producto), caché cache-aside con TTL |
| Cassandra | `telemetria` | PK `(usuario_id, dia, ts, evento_id)`: partición por usuario+día, sin consultas por otro campo |
| Neo4j | `grafo` | nodos con PK, aristas `vio` / `compro`, recomendación por filtrado colaborativo |

## Puesta en marcha
1. Crea un proyecto en Supabase. En *Authentication → Providers → Email* desactiva "Confirm email" (más cómodo en clase).
2. En el *SQL Editor* ejecuta `database/00_instalar_todo.sql` (equivale a los scripts 01 a 09, en orden).
3. Edita `js/config.js` con la URL y la clave *anon* (Project Settings → API).
4. Sube el proyecto a GitHub **conservando las carpetas** `css/`, `js/` y `database/`. En Netlify, publish directory vacío.
5. Para la sustentación usa `database/10_pruebas.sql`.

## Seguridad
- El navegador solo ve `api_catalogo`, `v_mis_pedidos` y 9 funciones `rpc`. Los esquemas internos no son accesibles.
- La compra es una sola transacción (`comprar()` → `sp_crear_pedido`); el precio sale del catálogo, nunca del cliente.
- Stock: `UPDATE ... WHERE stock >= n` más `CHECK (stock >= 0)`, así dos compras simultáneas no pueden dejarlo negativo.
- Las contraseñas las guarda Supabase Auth con bcrypt.
- Outbox: `relacional.procesar_outbox()` propaga a telemetría y grafo (idempotente). Prográmalo con `pg_cron` cada minuto.
- Para simular Neo4j caído: `update relacional.config set valor='false' where clave='grafo_activo';`
