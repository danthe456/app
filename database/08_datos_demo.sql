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
