# PolyStore 360 · Frontend (etapa visual)

Sitio estático (HTML, CSS, JS). Sin backend por ahora: los datos están en `js/data.js`.

## Estructura
- `index.html` · estructura de la página
- `css/styles.css` · estilos
- `js/data.js` · catálogo de ejemplo (IDs `P001…`, usuario `U001`, iguales en los 5 motores)
- `js/app.js` · interfaz (filtros, carrito, login, pedidos simulados)

## Despliegue
1. Sube la carpeta a un repositorio de GitHub.
2. En Netlify: *Add new site → Import from Git*, sin comando de build y con directorio de publicación `.`
