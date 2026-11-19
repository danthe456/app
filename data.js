// Datos de ejemplo (etapa visual). Después vendrán de MongoDB (catálogo) y PostgreSQL (precio/stock).
// IDs compartidos: P001… productos, U001 usuario.
const ICONS = {
  portatil:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/></svg>',
  celular:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/></svg>',
  ropa:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3 3 6l2 4 3-1v12h8V9l3 1 2-4-5-3a4 4 0 0 1-8 0z"/></svg>',
  accesorio:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 14v-2a8 8 0 0 1 16 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/></svg>'
};
const CATEGORIAS = [
  {id:'portatil',nombre:'Portátiles',bg:'#FFB52E'},
  {id:'celular',nombre:'Celulares',bg:'#12A87B'},
  {id:'ropa',nombre:'Ropa',bg:'#FF5C7A'},
  {id:'accesorio',nombre:'Accesorios',bg:'#8E7CFF'}
];
const PRODUCTOS = [
  {id:'P001',nombre:'Aero 14 Pro',categoria:'portatil',precio:3899000,stock:8,atributos:{Procesador:'Core Ultra 7',RAM:'16 GB',Almacenamiento:'512 GB SSD',Pantalla:'14" OLED'}},
  {id:'P002',nombre:'Forge 16 Gamer',categoria:'portatil',precio:6299000,stock:3,atributos:{Procesador:'Ryzen 9',RAM:'32 GB',Almacenamiento:'1 TB SSD',Pantalla:'16" 165 Hz'}},
  {id:'P003',nombre:'Slim 13 Air',categoria:'portatil',precio:2499000,stock:15,atributos:{Procesador:'Core i5',RAM:'8 GB',Almacenamiento:'256 GB SSD',Pantalla:'13" IPS'}},
  {id:'P004',nombre:'Nova X5',categoria:'celular',precio:1899000,stock:20,atributos:{Pantalla:'6.5" AMOLED',Cámara:'64 MP',Batería:'5000 mAh',Almacenamiento:'128 GB'}},
  {id:'P005',nombre:'Nova X5 Max',categoria:'celular',precio:2699000,stock:2,atributos:{Pantalla:'6.8" AMOLED',Cámara:'108 MP',Batería:'5500 mAh',Almacenamiento:'256 GB'}},
  {id:'P006',nombre:'Pulse Lite',categoria:'celular',precio:799000,stock:40,atributos:{Pantalla:'6.1" LCD',Cámara:'13 MP',Batería:'4500 mAh',Almacenamiento:'64 GB'}},
  {id:'P007',nombre:'Camiseta algodón orgánico',categoria:'ropa',precio:69000,stock:60,atributos:{Talla:'S, M, L, XL',Color:'Blanco',Material:'Algodón 100 %'}},
  {id:'P008',nombre:'Chaqueta cortaviento',categoria:'ropa',precio:219000,stock:12,atributos:{Talla:'M, L',Color:'Azul noche',Material:'Poliéster reciclado'}},
  {id:'P009',nombre:'Jean recto clásico',categoria:'ropa',precio:159000,stock:25,atributos:{Talla:'28 a 38',Color:'Índigo',Material:'Denim'}},
  {id:'P010',nombre:'Audífonos Wave ANC',categoria:'accesorio',precio:329000,stock:18,atributos:{Tipo:'Diadema',Conexión:'Bluetooth 5.3',Autonomía:'40 h'}},
  {id:'P011',nombre:'Mouse inalámbrico Glide',categoria:'accesorio',precio:89000,stock:50,atributos:{Conexión:'2.4 GHz y Bluetooth',DPI:'4000',Autonomía:'90 días'}},
  {id:'P012',nombre:'Cargador GaN 65 W',categoria:'accesorio',precio:119000,stock:4,atributos:{Potencia:'65 W',Puertos:'2 USB-C + 1 USB-A',Compatibilidad:'Portátiles y celulares'}}
];
// Recomendaciones simuladas (luego vendrán de Neo4j)
const RECOMENDACIONES = ['P010','P012','P005','P011'];
