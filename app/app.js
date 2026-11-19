(() => {
  const $ = s => document.querySelector(s);
  const money = n => '$' + n.toLocaleString('es-CO');
  const cat = id => CATEGORIAS.find(c => c.id === id);
  const load = (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d; } catch { return d; } };
  const save = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };

  // Estado (visual: luego sesión y carrito vivirán en Redis)
  let user = load('ps_user', null);
  let cart = load('ps_cart', {});          // { P001: cantidad }
  let orders = load('ps_orders', []);
  let filtro = 'todos';

  // Hero icons
  ['portatil','celular','ropa','accesorio'].forEach((c, i) => $('#heroIcon' + (i + 1)).innerHTML = ICONS[c]);

  // Toast
  let tt;
  const toast = msg => { const t = $('#toast'); t.textContent = msg; t.classList.add('show'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('show'), 2400); };

  // Tarjeta de producto
  const card = p => `
    <article class="card" data-id="${p.id}" tabindex="0" aria-label="${p.nombre}">
      <div class="thumb" style="background:${cat(p.categoria).bg}">
        ${ICONS[p.categoria]}
        ${p.stock <= 4 ? `<span class="tag low">Quedan ${p.stock}</span>` : `<span class="tag">${cat(p.categoria).nombre}</span>`}
      </div>
      <div class="info">
        <h3>${p.nombre}</h3>
        <span class="meta">${Object.values(p.atributos).slice(0, 2).join(' · ')}</span>
        <div class="row"><span class="price">${money(p.precio)}</span>
          <button class="add" data-add="${p.id}" aria-label="Agregar ${p.nombre} al carrito" ${p.stock ? '' : 'disabled'}>+</button></div>
      </div>
    </article>`;

  // Catálogo
  function renderChips() {
    $('#chips').innerHTML = [{id:'todos',nombre:'Todos'}, ...CATEGORIAS]
      .map(c => `<button class="chip" data-cat="${c.id}" aria-pressed="${c.id === filtro}">${c.nombre}</button>`).join('');
  }
  function renderGrid() {
    const q = $('#q').value.trim().toLowerCase(), o = $('#orden').value;
    let list = PRODUCTOS.filter(p => (filtro === 'todos' || p.categoria === filtro) && p.nombre.toLowerCase().includes(q));
    if (o === 'asc') list.sort((a, b) => a.precio - b.precio);
    if (o === 'desc') list.sort((a, b) => b.precio - a.precio);
    $('#grid').innerHTML = list.map(card).join('');
    $('#empty').hidden = list.length > 0;
  }
  function renderReco() {
    if (!user) { $('#reco').innerHTML = ''; $('#recoHint').textContent = 'Inicia sesión para ver recomendaciones según lo que has comprado.'; return; }
    $('#recoHint').textContent = `Basadas en las compras de clientes parecidos a ti, ${user.nombre}.`;
    $('#reco').innerHTML = RECOMENDACIONES.map(id => card(PRODUCTOS.find(p => p.id === id))).join('');
  }

  // Detalle
  function openProduct(id) {
    const p = PRODUCTOS.find(x => x.id === id);
    $('#prodBody').innerHTML = `
      <div class="thumb" style="background:${cat(p.categoria).bg}">${ICONS[p.categoria]}</div>
      <div class="prod-info">
        <span class="meta">${cat(p.categoria).nombre} · ${p.id}</span>
        <h2>${p.nombre}</h2>
        <span class="price">${money(p.precio)}</span>
        <dl class="specs">${Object.entries(p.atributos).map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('')}
          <dt>Disponibles</dt><dd>${p.stock} unidades</dd></dl>
        <button class="btn primary block-btn" data-add="${p.id}" ${p.stock ? '' : 'disabled'}>Agregar al carrito</button>
      </div>`;
    $('#dlgProducto').showModal();
  }

  // Carrito
  const count = () => Object.values(cart).reduce((a, b) => a + b, 0);
  function renderCart() {
    const ids = Object.keys(cart);
    $('#cartCount').textContent = count();
    $('#cartBody').innerHTML = ids.length ? ids.map(id => {
      const p = PRODUCTOS.find(x => x.id === id);
      return `<div class="line">
        <div class="mini" style="background:${cat(p.categoria).bg}">${ICONS[p.categoria]}</div>
        <div><strong>${p.nombre}</strong><div class="qty">
          <button data-dec="${id}" aria-label="Quitar una unidad">−</button><span>${cart[id]}</span>
          <button data-inc="${id}" aria-label="Agregar una unidad">+</button></div></div>
        <div style="text-align:right"><div class="price">${money(p.precio * cart[id])}</div><button class="rm" data-rm="${id}">Quitar</button></div>
      </div>`;
    }).join('') : '<p class="empty">Tu carrito está vacío. Agrega productos desde el catálogo.</p>';
    $('#cartTotal').textContent = money(ids.reduce((s, id) => s + PRODUCTOS.find(x => x.id === id).precio * cart[id], 0));
    $('#btnBuy').disabled = !ids.length;
    save('ps_cart', cart);
  }
  function addToCart(id) {
    const p = PRODUCTOS.find(x => x.id === id);
    if ((cart[id] || 0) >= p.stock) return toast('No hay más unidades disponibles');
    cart[id] = (cart[id] || 0) + 1; renderCart(); toast(`${p.nombre} agregado al carrito`);
  }
  const setDrawer = open => {
    $('#drawer').classList.toggle('open', open); $('#drawer').setAttribute('aria-hidden', !open); $('#scrim').hidden = !open;
  };

  // Pedidos
  function renderOrders() {
    $('#pedidos').innerHTML = !user ? '<p class="empty">Inicia sesión para ver tus pedidos.</p>'
      : !orders.length ? '<p class="empty">Aún no tienes pedidos. Cuando compres, aparecerán aquí.</p>'
      : orders.map(o => `<div class="order"><div class="order-top"><strong>Pedido ${o.id}</strong><span class="badge">${o.estado}</span></div>
          <ul>${o.items.map(i => `<li>${i.cant} × ${i.nombre}</li>`).join('')}</ul>
          <div class="row"><span class="meta">${o.fecha}</span><span class="price">${money(o.total)}</span></div></div>`).join('');
  }
  function buy() {
    if (!user) { setDrawer(false); toast('Inicia sesión para comprar'); return $('#dlgLogin').showModal(); }
    const items = Object.keys(cart).map(id => { const p = PRODUCTOS.find(x => x.id === id); return { cant: cart[id], nombre: p.nombre, sub: p.precio * cart[id] }; });
    orders.unshift({ id: 'PED-' + String(orders.length + 1).padStart(4, '0'), estado: 'Pagado', fecha: new Date().toLocaleDateString('es-CO'), items, total: items.reduce((s, i) => s + i.sub, 0) });
    save('ps_orders', orders); cart = {}; renderCart(); renderOrders(); setDrawer(false);
    toast('Compra realizada'); location.hash = '#pedidos';
  }

  // Sesión (simulada)
  function renderUser() {
    $('#btnLogin').textContent = user ? `Cerrar sesión (${user.nombre})` : 'Iniciar sesión';
    renderReco(); renderOrders();
  }

  // Vistas por hash
  function route() {
    const v = location.hash === '#pedidos' ? 'pedidos' : 'inicio';
    $('#vista-inicio').hidden = v !== 'inicio'; $('#vista-pedidos').hidden = v !== 'pedidos';
    document.querySelectorAll('.nav a').forEach(a => a.classList.toggle('on', a.dataset.view === v && (v === 'pedidos' || a.getAttribute('href') === '#inicio')));
    if (v === 'pedidos') scrollTo(0, 0);
  }

  // Eventos
  document.addEventListener('click', e => {
    const t = e.target;
    const add = t.closest('[data-add]');
    if (add) { e.stopPropagation(); return addToCart(add.dataset.add); }
    const ch = t.closest('[data-cat]'); if (ch) { filtro = ch.dataset.cat; renderChips(); return renderGrid(); }
    if (t.closest('[data-inc]')) { addToCart(t.closest('[data-inc]').dataset.inc); return; }
    if (t.closest('[data-dec]')) { const id = t.closest('[data-dec]').dataset.dec; if (--cart[id] <= 0) delete cart[id]; return renderCart(); }
    if (t.closest('[data-rm]')) { delete cart[t.closest('[data-rm]').dataset.rm]; return renderCart(); }
    if (t.closest('[data-close]')) return t.closest('dialog').close();
    const c = t.closest('.card'); if (c) return openProduct(c.dataset.id);
    if (t.id === 'scrim' || t.id === 'closeCart') return setDrawer(false);
    if (t.id === 'btnCart') return setDrawer(true);
    if (t.id === 'btnBuy') return buy();
    if (t.id === 'btnLogin') {
      if (user) { user = null; save('ps_user', null); renderUser(); return toast('Sesión cerrada'); }
      $('#loginErr').hidden = true; $('#dlgLogin').showModal();
    }
    if (t.tagName === 'DIALOG') t.close();
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') setDrawer(false);
    if (e.key === 'Enter' && e.target.classList?.contains('card')) openProduct(e.target.dataset.id);
  });
  $('#q').addEventListener('input', renderGrid);
  $('#orden').addEventListener('change', renderGrid);
  $('#formLogin').addEventListener('submit', e => {
    e.preventDefault();
    const mail = $('#email').value.trim(), pass = $('#pass').value;
    if (!/^\S+@\S+\.\S+$/.test(mail) || pass.length < 4) return $('#loginErr').hidden = false;
    user = { id: 'U001', nombre: mail.split('@')[0] }; save('ps_user', user);
    $('#dlgLogin').close(); $('#formLogin').reset(); renderUser(); toast(`Hola, ${user.nombre}`);
  });
  window.addEventListener('hashchange', route);

  renderChips(); renderGrid(); renderCart(); renderUser(); route();
})();
