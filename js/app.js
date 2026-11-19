(() => {
  const $ = s => document.querySelector(s);
  const money = n => '$' + Number(n).toLocaleString('es-CO');
  const cat = id => CATEGORIAS.find(c => c.id === id) || CATEGORIAS[3];
  const nombreAttr = k => k.charAt(0).toUpperCase() + k.slice(1);
  const configurado = !SUPABASE_URL.includes('TU-PROYECTO');
  const sb = configurado ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

  let user = null, productos = [], cart = {}, cartTotal = 0, orders = [], reco = [];
  let filtro = 'todos', registro = false;
  const P = id => productos.find(p => p.id === id);

  ['portatil','celular','ropa','accesorio'].forEach((c, i) => $('#heroIcon' + (i + 1)).innerHTML = ICONS[c]);

  let tt;
  const toast = msg => { const t = $('#toast'); t.textContent = msg; t.classList.add('show'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('show'), 2800); };
  const fail = (e, d = 'Ocurrió un error') => toast(e?.message || d);

  // ---------- Datos (Supabase) ----------
  async function loadCatalog() {
    const { data, error } = await sb.from('api_catalogo').select('*').order('id');
    if (error) return fail(error, 'No se pudo cargar el catálogo');
    productos = data; renderGrid(); renderReco(); renderCart();
  }
  async function loadCart() {
    cart = {}; cartTotal = 0;
    if (user) {
      const [c, t] = await Promise.all([sb.rpc('carrito_ver'), sb.rpc('carrito_total')]);
      (c.data || []).forEach(r => cart[r.producto_id] = r.cantidad); cartTotal = t.data || 0;
    }
    renderCart();
  }
  async function loadOrders() {
    orders = []; if (user) { const { data } = await sb.from('v_mis_pedidos').select('*').order('creado', { ascending: false }); orders = data || []; }
    renderOrders();
  }
  async function loadReco() {
    reco = []; if (user) { const { data } = await sb.rpc('recomendaciones'); reco = data || []; }
    renderReco();
  }

  // ---------- Vistas ----------
  const card = p => `
    <article class="card" data-id="${p.id}" tabindex="0" aria-label="${p.nombre}">
      <div class="thumb" style="background:${cat(p.categoria).bg}">
        ${ICONS[p.categoria]}
        ${p.stock <= 0 ? '<span class="tag low">Agotado</span>' : p.stock <= 4 ? `<span class="tag low">Quedan ${p.stock}</span>` : `<span class="tag">${cat(p.categoria).nombre}</span>`}
      </div>
      <div class="info">
        <h3>${p.nombre}</h3>
        <span class="meta">${Object.values(p.atributos).slice(0, 2).join(' · ')}</span>
        <div class="row"><span class="price">${money(p.precio)}</span>
          <button class="add" data-add="${p.id}" aria-label="Agregar ${p.nombre} al carrito" ${p.stock > 0 ? '' : 'disabled'}>+</button></div>
      </div>
    </article>`;

  function renderChips() {
    $('#chips').innerHTML = [{ id: 'todos', nombre: 'Todos' }, ...CATEGORIAS]
      .map(c => `<button class="chip" data-cat="${c.id}" aria-pressed="${c.id === filtro}">${c.nombre}</button>`).join('');
  }
  function renderGrid() {
    const q = $('#q').value.trim().toLowerCase(), o = $('#orden').value;
    const list = productos.filter(p => (filtro === 'todos' || p.categoria === filtro) && p.nombre.toLowerCase().includes(q));
    if (o === 'asc') list.sort((a, b) => a.precio - b.precio);
    if (o === 'desc') list.sort((a, b) => b.precio - a.precio);
    $('#grid').innerHTML = list.map(card).join('');
    $('#empty').hidden = list.length > 0 || !productos.length;
  }
  function renderReco() {
    const items = reco.map(P).filter(Boolean);
    $('#recoHint').textContent = !user ? 'Inicia sesión para ver recomendaciones según lo que has comprado.'
      : items.length ? `Basadas en las compras de clientes parecidos a ti, ${user.nombre}.` : 'Aún no hay recomendaciones para ti.';
    $('#reco').innerHTML = items.map(card).join('');
  }
  function renderCart() {
    const ids = Object.keys(cart).filter(id => P(id));
    $('#cartCount').textContent = ids.reduce((s, id) => s + cart[id], 0);
    $('#cartBody').innerHTML = ids.length ? ids.map(id => {
      const p = P(id);
      return `<div class="line">
        <div class="mini" style="background:${cat(p.categoria).bg}">${ICONS[p.categoria]}</div>
        <div><strong>${p.nombre}</strong><div class="qty">
          <button data-dec="${id}" aria-label="Quitar una unidad">−</button><span>${cart[id]}</span>
          <button data-inc="${id}" aria-label="Agregar una unidad">+</button></div></div>
        <div style="text-align:right"><div class="price">${money(p.precio * cart[id])}</div><button class="rm" data-rm="${id}">Quitar</button></div>
      </div>`;
    }).join('') : `<p class="empty">${user ? 'Tu carrito está vacío. Agrega productos desde el catálogo.' : 'Inicia sesión para usar el carrito.'}</p>`;
    $('#cartTotal').textContent = money(cartTotal);
    $('#btnBuy').disabled = !ids.length;
  }
  function renderOrders() {
    $('#pedidos').innerHTML = !user ? '<p class="empty">Inicia sesión para ver tus pedidos.</p>'
      : !orders.length ? '<p class="empty">Aún no tienes pedidos. Cuando compres, aparecerán aquí.</p>'
      : orders.map(o => `<div class="order"><div class="order-top"><strong>Pedido #${String(o.id).padStart(4, '0')}</strong><span class="badge">${o.estado}</span></div>
          <ul>${(o.items || []).map(i => `<li>${i.cantidad} × ${i.nombre}</li>`).join('')}</ul>
          <div class="row"><span class="meta">${new Date(o.creado).toLocaleDateString('es-CO')}</span><span class="price">${money(o.total)}</span></div></div>`).join('');
  }
  function renderUser() { $('#btnLogin').textContent = user ? `Cerrar sesión (${user.nombre})` : 'Iniciar sesión'; }

  function openProduct(id) {
    const p = P(id); if (!p) return;
    $('#prodBody').innerHTML = `
      <div class="thumb" style="background:${cat(p.categoria).bg}">${ICONS[p.categoria]}</div>
      <div class="prod-info">
        <span class="meta">${cat(p.categoria).nombre} · ${p.id}</span>
        <h2>${p.nombre}</h2><span class="price">${money(p.precio)}</span>
        <dl class="specs">${Object.entries(p.atributos).map(([k, v]) => `<dt>${nombreAttr(k)}</dt><dd>${v}</dd>`).join('')}
          <dt>Disponibles</dt><dd>${p.stock} unidades</dd></dl>
        <button class="btn primary block-btn" data-add="${p.id}" ${p.stock > 0 ? '' : 'disabled'}>Agregar al carrito</button>
      </div>`;
    $('#dlgProducto').showModal();
    if (user) sb.rpc('registrar_evento', { p_tipo: 'VISTA', p_producto: id });
  }

  // ---------- Acciones ----------
  const needLogin = () => { toast('Inicia sesión para continuar'); $('#dlgProducto').close(); setDrawer(false); abrirLogin(); };
  async function setQty(id, n) {
    if (!user) return needLogin();
    const { error } = await sb.rpc('carrito_set', { p_producto: id, p_cantidad: n });
    if (error) return fail(error);
    await loadCart();
  }
  async function addToCart(id) { await setQty(id, (cart[id] || 0) + 1); if (cart[id]) toast(`${P(id).nombre} agregado al carrito`); }
  async function buy() {
    if (!user) return needLogin();
    $('#btnBuy').disabled = true;
    const { error } = await sb.rpc('comprar');
    if (error) { fail(error); return loadCart(); }
    await Promise.all([loadCart(), loadOrders(), loadCatalog()]);
    setDrawer(false); toast('Compra realizada'); location.hash = '#pedidos';
    setTimeout(loadReco, 1500);
  }
  const setDrawer = open => { $('#drawer').classList.toggle('open', open); $('#drawer').setAttribute('aria-hidden', !open); $('#scrim').hidden = !open; };

  // ---------- Sesión ----------
  function abrirLogin() { $('#loginErr').hidden = true; setModo(false); $('#dlgLogin').showModal(); }
  function setModo(r) {
    registro = r; $('#lblNombre').hidden = !r;
    $('#loginTitulo').textContent = r ? 'Crear cuenta' : 'Iniciar sesión';
    $('#loginSubmit').textContent = r ? 'Registrarme' : 'Entrar';
    $('#toggleModo').textContent = r ? 'Ya tengo cuenta' : '¿No tienes cuenta? Regístrate';
  }
  async function aplicarSesion(session, nuevoLogin = false) {
    user = session ? { nombre: session.user.user_metadata?.nombre || session.user.email.split('@')[0] } : null;
    renderUser();
    if (user && nuevoLogin) await sb.rpc('abrir_sesion');
    await Promise.all([loadCart(), loadOrders(), loadReco()]);
  }
  async function logout() { await sb.rpc('cerrar_sesion'); await sb.auth.signOut(); await aplicarSesion(null); toast('Sesión cerrada'); }

  function route() {
    const v = location.hash === '#pedidos' ? 'pedidos' : 'inicio';
    $('#vista-inicio').hidden = v !== 'inicio'; $('#vista-pedidos').hidden = v !== 'pedidos';
    document.querySelectorAll('.nav a').forEach(a => a.classList.toggle('on', a.dataset.view === v && (v === 'pedidos' || a.getAttribute('href') === '#inicio')));
    if (v === 'pedidos') scrollTo(0, 0);
  }

  // ---------- Eventos ----------
  document.addEventListener('click', e => {
    const t = e.target;
    const add = t.closest('[data-add]'); if (add) { e.stopPropagation(); return addToCart(add.dataset.add); }
    const ch = t.closest('[data-cat]'); if (ch) { filtro = ch.dataset.cat; renderChips(); return renderGrid(); }
    const inc = t.closest('[data-inc]'); if (inc) return setQty(inc.dataset.inc, (cart[inc.dataset.inc] || 0) + 1);
    const dec = t.closest('[data-dec]'); if (dec) return setQty(dec.dataset.dec, (cart[dec.dataset.dec] || 0) - 1);
    const rm = t.closest('[data-rm]'); if (rm) return setQty(rm.dataset.rm, 0);
    if (t.closest('[data-close]')) return t.closest('dialog').close();
    const c = t.closest('.card'); if (c) return openProduct(c.dataset.id);
    if (t.id === 'scrim' || t.id === 'closeCart') return setDrawer(false);
    if (t.id === 'btnCart') return setDrawer(true);
    if (t.id === 'btnBuy') return buy();
    if (t.id === 'toggleModo') return setModo(!registro);
    if (t.id === 'btnLogin') return user ? logout() : abrirLogin();
    if (t.tagName === 'DIALOG') t.close();
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') setDrawer(false);
    if (e.key === 'Enter' && e.target.classList?.contains('card')) openProduct(e.target.dataset.id);
  });
  $('#q').addEventListener('input', renderGrid);
  $('#orden').addEventListener('change', renderGrid);
  $('#formLogin').addEventListener('submit', async e => {
    e.preventDefault();
    const email = $('#email').value.trim(), password = $('#pass').value, nombre = $('#nombre').value.trim();
    const err = $('#loginErr'); err.hidden = true;
    if (!/^\S+@\S+\.\S+$/.test(email) || password.length < 6) { err.textContent = 'Correo válido y contraseña de 6 o más caracteres.'; return err.hidden = false; }
    const { data, error } = registro
      ? await sb.auth.signUp({ email, password, options: { data: { nombre: nombre || email.split('@')[0] } } })
      : await sb.auth.signInWithPassword({ email, password });
    if (error) { err.textContent = registro ? error.message : 'Correo o contraseña incorrectos.'; return err.hidden = false; }
    if (!data.session) { $('#dlgLogin').close(); return toast('Cuenta creada. Confirma tu correo e inicia sesión.'); }
    $('#dlgLogin').close(); $('#formLogin').reset(); await aplicarSesion(data.session, true); toast(`Hola, ${user.nombre}`);
  });
  window.addEventListener('hashchange', route);

  // ---------- Inicio ----------
  renderChips(); renderUser(); route(); renderCart(); renderOrders(); renderReco();
  if (!configurado) {
    $('#grid').innerHTML = '<p class="empty">Falta configurar Supabase: edita <code>js/config.js</code> con tu URL y tu clave anon.</p>';
  } else {
    loadCatalog();
    sb.auth.getSession().then(({ data }) => aplicarSesion(data.session));
  }
})();
