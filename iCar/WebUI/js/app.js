/* 长安汽车 · 车控页（小米风格 UI） */

// ---------------- 原生桥 ----------------
const hasNative = typeof Native !== 'undefined';
let seq = 0;
const pending = {};

// ---------------- 本地偏好存储 ----------------
// 页面跑在 127.0.0.1 的本地服务上，localStorage 按「IP:端口」隔离，
// 端口一变（甚至随机）存储就全没了。所以优先写进原生 SharedPreferences，
// localStorage 只当备份。
const store = {
  get(k, def) {
    let v = '';
    if (hasNative) { try { v = Native.kvGet(k) || ''; } catch (e) {} }
    if (!v) { try { v = localStorage.getItem(k) || ''; } catch (e) {} }
    return v || def || '';
  },
  set(k, v) {
    v = v == null ? '' : String(v);
    if (hasNative) { try { Native.kvSet(k, v); } catch (e) {} }
    try { localStorage.setItem(k, v); } catch (e) {}
  },
  del(k) {
    if (hasNative) { try { Native.kvSet(k, ''); } catch (e) {} }
    try { localStorage.removeItem(k); } catch (e) {}
  }
};

window.__cb = function (id, ok, msg) {
  const p = pending[id];
  if (!p) return;
  delete pending[id];
  ok ? p.res(msg) : p.rej(new Error(msg || '执行失败'));
};

function invoke(fn) {
  return new Promise((res, rej) => {
    const id = 'c' + (++seq);
    pending[id] = { res, rej };
    try { fn(id); } catch (e) { delete pending[id]; rej(e); }
    setTimeout(() => {
      if (pending[id]) { delete pending[id]; rej(new Error('超时')); }
    }, 120000);
  });
}

const api = {
  state: () => { try { return JSON.parse(Native.state()); } catch (e) { return { loggedIn: false }; } },
  carMeta: () => invoke(id => Native.carMeta(id)).then(s => JSON.parse(s)),
  status: () => invoke(id => Native.status(id)).then(s => JSON.parse(s)),
  exec: cmd => invoke(id => Native.exec(cmd, id)),
  sendCode: phone => invoke(id => Native.sendCode(phone, id)),
  login: (p, c) => invoke(id => Native.login(p, c, id)),
  logout: () => { try { Native.logout(); } catch (e) {} },
  photos: () => invoke(id => Native.photos(id)).then(s => JSON.parse(s)),
  capture: () => invoke(id => Native.capture(id)),
  air: () => invoke(id => Native.air(0, 0, 0, id)),
  airOff: () => invoke(id => Native.airOff(id)),
  acDiag: () => { try { return Native.acDiag(); } catch (e) { return ''; } },
  raw: () => invoke(id => Native.rawStatus(id)),
  trips: (a, b) => invoke(id => Native.trips(a, b, id)).then(s => JSON.parse(s)),
  actions: (p, n) => invoke(id => Native.actions(p, n, id)).then(s => JSON.parse(s)),
  location: () => invoke(id => Native.location(id)).then(s => JSON.parse(s)),
  openMap: (lat, lng) => { try { Native.openMap(lat, lng); } catch (e) {} },
  updateInfo: () => invoke(id => Native.updateInfo(id)),
  pinCode: () => { try { return Native.pinCode() || ''; } catch (e) { return ''; } },
  setPinCode: v => { try { Native.setPinCode(v); } catch (e) {} },
  deletePhoto: (id, name, taskId) => invoke(i => Native.deletePhoto(id, name, taskId, i))
};

// ---------------- 3D 车模 ----------------
// 模型来自官方 App 的车模包，按车架号里的 seriesCode 自动匹配
const CAR_MODELS = [
  { key: 'c211',    file: 'C211.glb',    code: 'C211',    type: '轿车' },
  { key: 'c236',    file: 'C236.glb',    code: 'C236',    type: '轿车' },
  { key: 'c281',    file: 'C281.glb',    code: 'C281',    type: '轿车' },
  { key: 'c281_p',  file: 'C281_P.glb',  code: 'C281 P',  type: '轿车 · 插混' },
  { key: 'c589',    file: 'C589.glb',    code: 'C589',    type: '轿车' },
  { key: 'c589_p',  file: 'C589_P.glb',  code: 'C589 P',  type: '轿车 · 插混' },
  { key: 'cd569',   file: 'CD569.glb',   code: 'CD569',   type: 'SUV' },
  { key: 's202',    file: 'S202.glb',    code: 'S202',    type: 'SUV' },
  { key: 's203',    file: 'S203.glb',    code: 'S203',    type: 'SUV' },
  { key: 's203_p',  file: 'S203_P.glb',  code: 'S203 P',  type: 'SUV · 插混' },
  { key: 's311',    file: 'S311.glb',    code: 'S311',    type: 'SUV' },
  { key: 's311_p',  file: 'S311_P.glb',  code: 'S311 P',  type: 'SUV · 插混' },
  { key: 's311mca', file: 'S311MCA.glb', code: 'S311MCA', type: 'SUV' }
];
const MODEL_KEY = 'icar.carModel';

function byKey(k) { return CAR_MODELS.find(m => m.key === k) || null; }

// C211-1 / S311MCA-1 / C281-P 这类编码统一折算成模型 key
function detectModelKey(seriesCode) {
  if (!seriesCode) return null;
  const raw = String(seriesCode).toLowerCase().trim();
  const cands = [
    raw.replace(/[-_]/g, '_'),
    raw.split('-')[0],
    raw.replace(/[^a-z0-9]/g, '')
  ];
  for (const c of cands) {
    if (byKey(c)) return c;
  }
  let best = null;
  for (const m of CAR_MODELS) {
    for (const c of cands) {
      if (c.startsWith(m.key) && (!best || m.key.length > best.length)) best = m.key;
    }
  }
  return best;
}

function savedModelKey() {
  try {
    const v = store.get(MODEL_KEY, 'auto');
    return v === 'auto' || byKey(v) ? v : 'auto';
  } catch (e) { return 'auto'; }
}

function currentModelKey() {
  const saved = savedModelKey();
  if (saved !== 'auto') return saved;
  let st = {};
  try { st = api.state(); } catch (e) {}
  return detectModelKey(st.seriesCode) || 'c211';
}

function currentModelFile() {
  const m = byKey(currentModelKey());
  return '3D/' + (m ? m.file : 'C211.glb');
}

// ---------------- 车漆 ----------------
// 模型的主车漆材质本来没设颜色，运行时改 material.color 就能换，
// 清漆层（clearcoat）还在，质感不变。
const PAINTS = [
  { k: 'white',  name: '白', hex: '#F4F5F7' },
  { k: 'silver', name: '银', hex: '#BFC4CC' },
  { k: 'grey',   name: '灰', hex: '#5A5F68' },
  { k: 'black',  name: '黑', hex: '#111318' },
  { k: 'red',    name: '红', hex: '#B3121C' },
  { k: 'blue',   name: '蓝', hex: '#1D4E8F' },
];
const PAINT_KEY = 'icar.paint';

function paintKey() {
  const k = store.get(PAINT_KEY, 'white');
  return PAINTS.some(p => p.k === k) ? k : 'white';
}

function paintOf(k) { return PAINTS.find(p => p.k === k) || PAINTS[0]; }

// viewer3d.js 在 500ms 后才初始化，这里先把它要加载的文件名和车漆放好
window.CAR_MODEL_FILE = currentModelFile();
window.CAR_PAINT = paintOf(paintKey()).hex;

function chooseModel(key) {
  if (key === 'auto') store.del(MODEL_KEY);
  else store.set(MODEL_KEY, key);
  location.reload();
}

function renderModelSheet() {
  paintSwitches();
  paintNtf();
  let st = {};
  try { st = api.state(); } catch (e) {}
  const auto = detectModelKey(st.seriesCode);
  const saved = savedModelKey();
  const cur = currentModelKey();

  const autoTxt = auto ? byKey(auto).code : '未识别';
  $('model-note').innerHTML = st.seriesCode
    ? `车架号识别：<b>${st.seriesCode}</b>${st.seriesName ? ' · ' + st.seriesName : ''} → <b>${autoTxt}</b>`
    : '还没读到车型编码，请手动选择';

  const cells = [];
  cells.push(`
    <div class="model-cell auto${saved === 'auto' ? ' on' : ''}" data-k="auto">
      <div class="thumb"><span>自动</span></div>
      <div class="mc">自动识别</div>
      <div class="mt">${autoTxt}</div>
    </div>`);
  CAR_MODELS.forEach(m => {
    cells.push(`
      <div class="model-cell${cur === m.key && saved !== 'auto' ? ' on' : ''}" data-k="${m.key}">
        <div class="thumb"><img src="3D/thumbs/${m.key}.jpg" loading="lazy" alt=""></div>
        <div class="mc">${m.code}</div>
        <div class="mt">${m.type}</div>
      </div>`);
  });
  $('model-grid').innerHTML = cells.join('');
  $('model-grid').querySelectorAll('.model-cell').forEach(el => {
    el.onclick = () => chooseModel(el.dataset.k);
  });

  renderPaintRow();

  let v = '?';
  try { v = Native.version(); } catch (e) {}
  $('model-foot').textContent = `当前：${byKey(cur).code} · v${v} · 换车模后页面会自动刷新`;
}

function renderPaintRow() {
  const cur = paintKey();
  $('paint-row').innerHTML = PAINTS.map(p => `
    <div class="paint${p.k === cur ? ' on' : ''}" data-k="${p.k}">
      <i style="background:${p.hex}"></i><span>${p.name}</span>
    </div>`).join('');
  $('paint-row').querySelectorAll('.paint').forEach(el => {
    el.onclick = () => choosePaint(el.dataset.k);
  });
}

function choosePaint(k) {
  const p = paintOf(k);
  store.set(PAINT_KEY, p.k);
  window.CAR_PAINT = p.hex;
  if (window.vehicle3D && window.vehicle3D.applyPaint) window.vehicle3D.applyPaint(p.hex);
  renderPaintRow();
}

// ---------------- 图标 ----------------
const svg = inner => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${inner}</svg>`;
const ICON = {
  window_close: svg('<rect x="4" y="6.5" width="16" height="13" rx="2.6"/><path d="M12 16.6v-7.4"/><path d="M8.9 12.1 12 9l3.1 3.1"/>'),
  sunroof_open: svg('<rect x="3.5" y="5.5" width="17" height="13" rx="3"/><path d="M7.6 5.5v13M16.4 5.5v13"/><path d="M12 15v-4.4"/><path d="M9.9 12.7 12 10.6l2.1 2.1"/>'),
  sunroof_full: svg('<rect x="3.5" y="5.5" width="17" height="13" rx="3"/><rect x="7.6" y="5.5" width="8.8" height="3.2" rx="1.2"/><rect x="7.6" y="10.2" width="8.8" height="4.8" rx="1.4"/>'),
  sunroof_close: svg('<rect x="3.5" y="5.5" width="17" height="13" rx="3"/><rect x="7.6" y="9" width="8.8" height="6" rx="1.6"/>'),
  engine_off: svg('<circle cx="12" cy="12" r="7.8"/><path d="M12 7.8v4.2"/><path d="M6.4 6.4 17.6 17.6"/>'),
};

/** 图标：PNG 用蒙版上色（跟 --icon 走），内联 SVG 用 currentColor */
function iconHTML(a, cls) {
  if (!a.img) return ICON[a.icon] || '';
  const u = `url(${a.img})`;
  return `<i class="mi${cls ? ' ' + cls : ''}" style="-webkit-mask-image:${u};mask-image:${u}"></i>`;
}

// ---------------- 功能表 ----------------
const ACTIONS = [
  { cmd: 'UnLockDoor',      label: '解锁',   img: 'xm/unlock.png' },
  { cmd: 'LockDoor',        label: '锁车',   img: 'xm/lock.png' },
  { cmd: 'OpenWindow',      label: '开窗',   img: 'xm/window_open.png' },
  { cmd: 'CloseWindow',     label: '关窗',   icon: 'window_close' },
  { cmd: 'WindowSlit',      label: '留缝',   img: 'xm/window_ventilate.png' },
  { cmd: 'SkyWindowLiftUp', label: '天窗翘起', icon: 'sunroof_open' },
  { cmd: 'OpenDormer',      label: '天窗全开', icon: 'sunroof_full' },
  { cmd: 'CloseDormer',     label: '关天窗', icon: 'sunroof_close' },
  { cmd: 'RemoteSearchCar', label: '寻车',   img: 'xm/find.png' },
  { cmd: 'OpenEngine',      label: '启动',   img: 'xm/engine_start.png' },
  { cmd: 'CloseEngine',     label: '熄火',   icon: 'engine_off' },
  { cmd: 'FlashLight',      label: '闪灯',   img: 'xm/light.png' },
];

// ---------------- DOM ----------------
const $ = id => document.getElementById(id);

let toastTimer;
function toast(msg, type) {
  const t = $('toast');
  t.textContent = msg;
  t.className = 'toast show' + (type ? ' ' + type : '');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.className = 'toast'; }, 2200);
}

// ---------------- 设置：二次确认 / 首页功能开关 ----------------
// 都存在原生偏好里，键名统一 icar.xxx；默认全开
const CF_KEY = 'icar.confirm';
const SHOW_KEYS = { pano: 'icar.show.pano', trip: 'icar.show.trip', log: 'icar.show.log', loc: 'icar.show.loc' };

function on2(k) { return store.get(k, '1') !== '0'; }      // 默认开
function showSec(k) { return on2(SHOW_KEYS[k]); }
function needConfirm() { return on2(CF_KEY); }

/** 按开关把首页的几块藏起来 */
function applyVisibility() {
  const set = (id, on) => { const n = $(id); if (n) n.classList.toggle('hide', !on); };
  set('sec-pano', showSec('pano'));
  set('card-trip', showSec('trip'));
  set('card-log', showSec('log'));
  set('card-loc', showSec('loc'));
}

/** 行开关的当前状态；data-def="0" 的行默认关 */
function rowOn(row) {
  const def = row.dataset.def || '1';
  return store.get('icar.' + row.dataset.k, def) === '1';
}

function paintSwitches() {
  document.querySelectorAll('.set-row').forEach(row => {
    const sw = row.querySelector('.switch');
    if (!sw || !row.dataset.k) return;
    sw.classList.toggle('on', rowOn(row));
  });
}

function toggleSetting(row) {
  const k = row.dataset.k;
  const next = !rowOn(row);
  store.set('icar.' + k, next ? '1' : '0');
  if (k === 'keep' && hasNative) { try { Native.keepAlive(next); } catch (e) {} }
  paintSwitches();
  applyVisibility();
  // 刚打开的功能，顺手把数据拉一次
  if (next && k === 'show.pano') loadPhotos();
  if (next && k === 'show.trip') refreshTripSummary();
  if (next && k === 'show.loc') loadLocation();
}

/** 通知记录：最近收到过的通知，排查某个 App 到底有没有被监听到 */
function openNtfLog() {
  const pre = $('ntf-pre');
  let t = '';
  if (hasNative) { try { t = Native.ntfLog() || ''; } catch (e) {} }
  pre.textContent = t || '还没有记录。';
  $('ntf-sheet').classList.add('show');
}

/** 点了「通知使用权」之后盯一会儿：开成功就提示，没开成功就给受限设置的引导 */
let authPoll = null, authHinted = false;

function ntfOn() {
  let on = '0';
  try { on = Native.ntfState(); } catch (e) {}
  return on === '1';
}

function watchAuth() {
  if (!hasNative) return;
  authHinted = false;
  if (authPoll) clearInterval(authPoll);
  let n = 0;
  authPoll = setInterval(() => {
    if (++n > 100) { clearInterval(authPoll); authPoll = null; return; }
    if (ntfOn()) {
      clearInterval(authPoll); authPoll = null;
      paintNtf();
      toast('通知使用权已开启');
    }
  }, 1000);
}

// 从系统设置页切回来还没开成功：多半是被「受限设置」挡了
window.addEventListener('focus', () => {
  if (!authPoll) return;
  setTimeout(() => {
    if (!authPoll || authHinted || ntfOn()) return;
    authHinted = true;
    askConfirm('开关是灰的？',
      '澎湃 OS 对侧载安装的 APP 做了「受限设置」，通知使用权的开关会被禁用。\n' +
      '到 应用信息 → 右上角 ⋮ → 允许受限设置，再回来开启即可。',
      '去应用信息页').then(ok => {
        if (ok && hasNative) { try { Native.openAppSettings(); } catch (e) {} }
      });
  }, 800);
});

/** 通知使用权状态 + 指令写法列表（一条一条，点哪条复制哪条） */
function paintNtf() {
  const a = $('ntf-auth'), box = $('cmd-list'), go = $('ntf-go');
  if (go) go.textContent = ntfOn() ? '已开启' : '去授权';
  if (a) {
    if (!hasNative) {
      a.textContent = '仅手机端可用';
    } else {
      a.textContent = ntfOn() ? '已授权' : '未授权，点这里开启';
    }
  }
  if (!box) return;
  let list = '';
  if (hasNative) { try { list = Native.ntfCmds(); } catch (e) {} }
  if (!list) { box.innerHTML = ''; return; }
  box.innerHTML = list.split(' ').map(x => {
    const p = x.split('|');
    return `<div class="cmd-row" data-cmd="${p[0]}"><b>${p[1] || ''}</b><span>${p[0]}</span></div>`;
  }).join('');
}

function bindSettings() {
  document.querySelectorAll('.set-row').forEach(row => {
    row.addEventListener('click', () => {
      const act = row.dataset.act;
      if (act === 'ntflog') { openNtfLog(); return; }
      if (act === 'theme') {
        syncThemeUI();
        $('theme-sheet').classList.add('show');
        return;
      }
      if (act === 'perm') {
        if (!hasNative) return;
        try { Native.openAppSettings(); } catch (e) {}
        return;
      }
      if (act === 'auth') {
        if (!hasNative) return toast('仅手机端可用');
        if (ntfOn()) { toast('通知使用权已开启'); paintNtf(); return; }
        try { Native.ntfOpen(); } catch (e) {}
        setTimeout(paintNtf, 900);
        watchAuth();
        return;
      }
      if (row.dataset.k) toggleSetting(row);
    });
  });

  const box = $('cmd-list');
  if (box) box.addEventListener('click', e => {
    const r = e.target.closest('.cmd-row');
    if (!r || !hasNative) return;
    try { Native.ntfCopyCmd(r.dataset.cmd); } catch (err) {}
  });
}

// ---- 二次确认 ----
let cfResolve = null;
let cfOpenedAt = 0;
function askConfirm(title, desc, yesText) {
  cfOpenedAt = Date.now();
  if (cfResolve) cfResolve(false);      // 连点两下：上一句先按取消处理
  return new Promise(res => {
    const box = $('confirm');
    $('cf-title').textContent = title;
    $('cf-desc').textContent = desc || '指令会立刻下发到车端，执行后无法撤回。';
    $('cf-yes').textContent = yesText || '执 行';
    box.classList.add('show');
    cfResolve = v => { box.classList.remove('show'); cfResolve = null; res(v); };
  });
}

function bindConfirm() {
  $('cf-yes').addEventListener('click', () => { if (cfResolve) cfResolve(true); });
  $('cf-no').addEventListener('click', () => { if (cfResolve) cfResolve(false); });
  $('confirm').addEventListener('click', e => {
    // 长按刚松手那一下会点到遮罩上，开头的 500ms 内不认，否则等于自动取消
    if (Date.now() - cfOpenedAt < 500) return;
    if (e.target.id === 'confirm' && cfResolve) cfResolve(false);
  });
}

// ---------------- 渲染 ----------------
// 快捷控制排序：顺序存进原生偏好（按指令名），重启、换端口都不会丢
const ORDER_KEY = 'icar.actOrder';
let actOrder = loadOrder();
let sortMode = false;
let drag = null;

function loadOrder() {
  const raw = store.get(ORDER_KEY, '');
  // 从没存过：默认把 12 个全放上去
  if (!raw) return ACTIONS.slice();
  let saved = [];
  try { saved = JSON.parse(raw); } catch (e) { saved = []; }
  if (!Array.isArray(saved)) saved = [];
  const byCmd = new Map(ACTIONS.map(a => [a.cmd, a]));
  const list = [], seen = new Set();
  saved.forEach(c => {
    const a = byCmd.get(c);
    if (a && !seen.has(c)) { list.push(a); seen.add(c); }
  });
  return list;   // 可能是子集，也可能被删光
}

function saveOrder() {
  store.set(ORDER_KEY, JSON.stringify(actOrder.map(a => a.cmd)));
}

function renderGrid() {
  const grid = $('grid');
  // animation-delay 错开，进排序模式后各卡片抖动不同步，像桌面图标
  grid.innerHTML = actOrder.map((a, i) => `
    <div class="act" data-i="${i}" style="animation-delay:${-((i % 8) * 0.07).toFixed(2)}s">
      ${iconHTML(a)}
      <span>${a.label}</span>
      <i class="act-x" data-del="${i}">✕</i>
    </div>`).join('')
    + `<div class="act act-add" id="act-add"><b>＋</b><span>添加</span></div>`;

  grid.classList.toggle('empty', actOrder.length === 0);

  grid.querySelectorAll('.act[data-i]').forEach(el => {
    el.addEventListener('click', () => onCardClick(el));
    el.addEventListener('pointerdown', e => beginDrag(e, el));
    const x = el.querySelector('.act-x');
    if (x) {
      // 叉号自己吃掉事件，否则会顺带触发选卡/拖动
      x.addEventListener('pointerdown', e => e.stopPropagation());
      x.addEventListener('click', e => { e.stopPropagation(); removeCard(+x.dataset.del); });
    }
  });

  const add = grid.querySelector('#act-add');
  if (add) add.addEventListener('click', () => { if (sortMode || actOrder.length === 0) openPicker(); });
}

/** 删掉第 i 张卡片 */
function removeCard(i) {
  if (i < 0 || i >= actOrder.length) return;
  actOrder.splice(i, 1);
  if (selEl) { selEl = null; }
  saveOrder();
  renderGrid();
}

// ---------- 添加快捷指令 ----------
function openPicker() {
  const have = new Set(actOrder.map(a => a.cmd));
  const rest = ACTIONS.filter(a => !have.has(a.cmd));
  if (!rest.length) { toast('12 个指令都已经在面板上了'); return; }
  $('picker-bd').innerHTML = rest.map(a => `
    <div class="pk-row" data-cmd="${a.cmd}">
      <span class="pk-ic">${iconHTML(a)}</span>
      <span class="pk-lb">${a.label}</span>
      <span class="pk-add">添加</span>
    </div>`).join('');
  $('act-picker').classList.add('show');
}

function closePicker() { $('act-picker').classList.remove('show'); }

function addAction(cmd) {
  if (actOrder.some(a => a.cmd === cmd)) return;
  const a = ACTIONS.find(x => x.cmd === cmd);
  if (!a) return;
  actOrder.push(a);
  saveOrder();
  renderGrid();
  openPicker();     // 列表重算，加完还能接着加
}

// ---------- 排序模式：拖动换位，或者点两张卡片互换 ----------
let selEl = null;
let suppressClick = false;

function setSortMode(on) {
  sortMode = on;
  if (!on) { endDrag(); }
  $('grid').classList.toggle('sorting', on);
  $('grid').classList.remove('shifting');
  const b = $('grid-sort');
  b.textContent = on ? '完成' : '排序';
  b.classList.toggle('on', on);
  $('grid-tip').textContent = on ? '拖动排序 · 点 ✕ 删除 · 点 ＋ 添加' : '点击即执行';
  if (selEl) { selEl.classList.remove('sel'); selEl = null; }
  if (!on) { saveOrder(); renderGrid(); }
}

function onCardClick(el) {
  if (!sortMode) { runAction(el, actOrder[+el.dataset.i]); return; }
  if (suppressClick) { suppressClick = false; return; }

  if (!selEl) {
    selEl = el;
    el.classList.add('sel');
    return;
  }
  if (selEl === el) {
    el.classList.remove('sel');
    selEl = null;
    return;
  }
  const a = selEl;
  selEl.classList.remove('sel');
  selEl = null;
  // 用 FLIP 让周围卡片滑过去，而不是瞬间跳
  const grid = $('grid');
  const kids = Array.from(grid.children);
  const ia = kids.indexOf(a), ib = kids.indexOf(el);
  flip(grid, [], () => {
    if (ia < ib) { grid.insertBefore(el, a); grid.insertBefore(a, kids[ib].nextSibling); }
    else { grid.insertBefore(a, el); grid.insertBefore(el, kids[ia].nextSibling); }
  });
  reindex();
  saveOrder();
}

// 记录改动前的视觉位置，改完 DOM 后用 transform 反向补回去再动画归零
function flip(grid, exclude, mutate) {
  // 抖动动画用的是 transform，会盖掉补间；先停掉，动画结束再恢复
  grid.classList.add('shifting');
  clearTimeout(flip._t);
  flip._t = setTimeout(() => { if (!drag) grid.classList.remove('shifting'); }, 360);

  const kids = Array.from(grid.children).filter(k => !exclude.includes(k));
  const before = kids.map(k => k.getBoundingClientRect());
  mutate();
  kids.forEach((k, i) => {
    const a = before[i], b = k.getBoundingClientRect();
    const dx = a.left - b.left, dy = a.top - b.top;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) return;
    k.style.transition = 'none';
    k.style.transform = `translate(${dx}px, ${dy}px)`;
    void k.offsetWidth;
    k.style.transition = 'transform .26s cubic-bezier(.22,.9,.28,1)';
    k.style.transform = '';
    clearTimeout(k._ft);
    k._ft = setTimeout(() => { k.style.transition = ''; k.style.transform = ''; }, 320);
  });
}

// DOM 顺序即新顺序，回写到数组并重新编号
function reindex() {
  const kids = Array.from($('grid').children)
    .filter(k => k.classList.contains('act') && !k.classList.contains('act-add'));
  actOrder = kids.map(k => actOrder[+k.dataset.i]);
  kids.forEach((k, i) => { k.dataset.i = i; });
}

// ---------- 拖动：卡片抬起来跟手，其它卡片让位 ----------
function beginDrag(e, el) {
  if (!sortMode || drag) return;
  if (e.pointerType === 'mouse' && e.button !== 0) return;
  e.preventDefault();

  const r = el.getBoundingClientRect();
  const ph = document.createElement('div');
  ph.className = 'act-ph';
  ph.style.width = r.width + 'px';
  ph.style.height = r.height + 'px';

  // 先占位，再让卡片脱离文档流，这样其它卡片不会塌下去
  el.parentNode.insertBefore(ph, el);
  el.classList.add('dragging');
  el.style.transition = 'none';
  el.style.position = 'fixed';
  el.style.left = r.left + 'px';
  el.style.top = r.top + 'px';
  el.style.width = r.width + 'px';
  el.style.height = r.height + 'px';
  el.style.margin = '0';
  el.style.transform = 'translate(0px, 0px) scale(1.06)';

  drag = { el, ph, sx: e.clientX, sy: e.clientY, moved: false };
  $('grid').classList.add('shifting');

  window.addEventListener('pointermove', onDragMove);
  window.addEventListener('pointerup', onDragEnd);
  window.addEventListener('pointercancel', onDragEnd);
}

// 手指所在位置对应的插入槽位
function slotFor(x, y) {
  const grid = drag.ph.parentNode;
  const items = Array.from(grid.children)
    .filter(k => k !== drag.el && k !== drag.ph && !k.classList.contains('act-add'));
  for (let i = 0; i < items.length; i++) {
    const r = items[i].getBoundingClientRect();
    if (y < r.top + 1) return i;
    if (y <= r.bottom && x < r.left + r.width / 2) return i;
  }
  return items.length;
}

function onDragMove(e) {
  if (!drag) return;

  if (!drag.moved) {
    if (Math.abs(e.clientX - drag.sx) < 6 && Math.abs(e.clientY - drag.sy) < 6) return;
    drag.moved = true;
    if (selEl) { selEl.classList.remove('sel'); selEl = null; }
  }

  // 卡片跟手
  const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
  drag.el.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;

  // 占位块移到新槽位，其它卡片做让位动画
  const grid = drag.ph.parentNode;
  const cur = Array.from(grid.children).filter(k => k !== drag.el);
  const idx = slotFor(e.clientX, e.clientY);
  if (cur.indexOf(drag.ph) === idx) return;

  const items = Array.from(grid.children)
    .filter(k => k !== drag.el && k !== drag.ph && !k.classList.contains('act-add'));
  flip(grid, [drag.el, drag.ph], () => {
    if (idx >= items.length) grid.appendChild(drag.ph);
    else grid.insertBefore(drag.ph, items[idx]);
  });
}

function endDrag() {
  if (!drag) return;
  const el = drag.el, ph = drag.ph, moved = drag.moved;
  drag = null;
  window.removeEventListener('pointermove', onDragMove);
  window.removeEventListener('pointerup', onDragEnd);
  window.removeEventListener('pointercancel', onDragEnd);

  const from = el.getBoundingClientRect();
  el.classList.remove('dragging');
  el.style.position = '';
  el.style.left = '';
  el.style.top = '';
  el.style.width = '';
  el.style.height = '';
  el.style.margin = '';
  el.style.transition = '';
  el.style.transform = '';
  if (ph.parentNode) ph.parentNode.replaceChild(el, ph);

  // 落位：从手指松开的位置滑进槽位
  if (moved) {
    const to = el.getBoundingClientRect();
    const dx = from.left - to.left, dy = from.top - to.top;
    if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
      el.style.transition = 'none';
      el.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
      void el.offsetWidth;
      el.style.transition = 'transform .24s cubic-bezier(.22,.9,.28,1)';
      el.style.transform = 'translate(0px, 0px) scale(1)';
      setTimeout(() => { el.style.transition = ''; el.style.transform = ''; }, 280);
    }
  }

  const grid = $('grid');
  setTimeout(() => grid.classList.remove('shifting'), 300);

  if (moved) {
    suppressClick = true;
    setTimeout(() => { suppressClick = false; }, 400);
    reindex();
    saveOrder();
  }
}

function onDragEnd() { endDrag(); }
async function runAction(el, a) {
  if (el.classList.contains('busy')) return;
  if (needConfirm()) {
    const ok = await askConfirm(`执行「${a.label}」？`);
    if (!ok) return;
  }
  el.classList.remove('done', 'fail');
  el.classList.add('busy');
  try {
    const r = await api.exec(a.cmd);
    el.classList.remove('busy');
    el.classList.add('done');
    toast(a.label + '：' + (r || '已下发'), 'ok');
    setTimeout(() => el.classList.remove('done'), 2600);
    setTimeout(loadStatus, 1500);
  } catch (e) {
    el.classList.remove('busy');
    el.classList.add('fail');
    toast(a.label + '失败：' + e.message, 'err');
    setTimeout(() => el.classList.remove('fail'), 3200);
  }
}

function setText(id, v) { const n = $(id); if (n) n.innerHTML = v; }

// ---------------- 电瓶电压 / 胎压 ----------------
// 不再单独占卡片，全部交给 3D 俯视标注层（overlay.js）
function paintVitals(d) {
  if (window.CarOverlay) window.CarOverlay.set(d);
}

// ---------------- 油量：百分比 ⇄ 剩余升数 ----------------
// 车端只上报百分比，升数按油箱容量换算。逸动PLUS 是 50L，
// 换车只改这一行（桌面小组件里 WidgetProvider.TANK_L 要同步改）。
// 油箱容量：每个车型不一样，从偏好读（设置里可改），默认 50
function tankL() {
  const v = parseFloat(hasNative ? Native.kvGet('icar.tankL') : store.get('icar.tankL', ''));
  return (v >= 20 && v <= 150) ? v : 50;
}
const TANK_L = 50;   // 兜底常量，实际用 tankL()
const FUEL_UNIT_KEY = 'icar.fuelUnit';
let lastFuel = 0;
let lastData = null;

function fuelUnit() { return store.get(FUEL_UNIT_KEY, '%') === 'L' ? 'L' : '%'; }

// ---------------- 数据来源：服务器 / 本地计算 / 车端升数 ----------------
// server = 车端 remainingFuel（百分比，官方 App 用的就是它）
// local  = fuelLeftover ÷ 油箱容量 × 100（按你填的油箱换算）
// liter  = 车端 fuelLeftover 直接当油量（不经过油箱换算，显示升）
const DS_KEY = 'icar.dataSource';
const DS_LIST = ['server', 'local', 'liter'];

function dataSource() {
  const v = store.get(DS_KEY, 'server');
  return DS_LIST.indexOf(v) >= 0 ? v : 'server';
}
function setDataSource(v) {
  store.set(DS_KEY, v);
  // 选车端升数时先按升数显示（再点一下油量卡就切百分比，百分比按填的油箱算）
  if (v === 'liter') store.set(FUEL_UNIT_KEY, 'L');
  if (lastData) renderStatus(lastData);
  const msg = v === 'local' ? '已改为本地计算' : (v === 'liter' ? '已改为车端升数' : '已改为服务器数据');
  toast(msg, 'ok');
}

/** 车端升数：fuelLeftover，没给就是 null */
function carLiter(d) {
  const v = d ? (+d.fuelLiter || 0) : 0;
  return v > 0 ? v : null;
}

/** 油量（百分比口径）：三个来源都归一到 0-100，界面和组件都按这个走 */
function pickFuel(d) {
  const ds = dataSource();
  if (ds === 'liter') {
    const lit = carLiter(d);
    if (lit != null) return Math.round(Math.min(100, lit / tankL() * 100));
  }
  if (ds === 'local') return (d.fuelLocal != null ? d.fuelLocal : d.fuel);
  return (d.fuelServer != null ? d.fuelServer : d.fuel);
}

/** 续航：服务器给 remainedOilMile，本地/升数按油量和百公里油耗估算 */
function pickRange(d) {
  const ds = dataSource();
  const server = +d.range || 0;
  if (ds === 'server') return server;
  const liters = ds === 'liter' ? (carLiter(d) || pickFuel(d) / 100 * tankL()) : pickFuel(d) / 100 * tankL();
  const per = +d.fuel100 || 0;
  // 25.5 是车端除零兜底的假值，算不出可信续航
  if (liters > 0 && per > 0 && Math.abs(per - 25.5) > 0.05) {
    return Math.round(liters / per * 100);
  }
  return server;
}

/** 来源标记，显示在详情页数字后面 */
function dsTag() {
  const ds = dataSource();
  return ds === 'liter' ? '车端升数' : (ds === 'local' ? '本地' : '');
}

function renderFuel(p) {
  lastFuel = p || 0;
  const u = fuelUnit();
  // 车端升数模式：升数用车上报的原值（不换算），百分比按你自己填的油箱算
  const lit = dataSource() === 'liter' ? carLiter(lastData) : null;
  const txt = u === 'L'
    ? (lit != null ? lit : lastFuel / 100 * tankL()).toFixed(1)
    : String(lastFuel);
  setText('s-fuel', `${txt}<small class="u" id="s-fuel-u">${u}</small>`);
  const bar = $('s-fuel-bar');
  if (bar) bar.style.width = Math.max(0, Math.min(100, lastFuel)) + '%';
}

function toggleFuel() {
  store.set(FUEL_UNIT_KEY, fuelUnit() === 'L' ? '%' : 'L');
  renderFuel(lastFuel);
  if (lastData) renderMore(lastData);
  flipVal('s-fuel');
}

// ---------------- 总里程 ⇄ 小计里程 / 车外 ⇄ 车内温度 ----------------
// 车端不给「小计里程」，就用总里程读数自己算：小计 = 当前总里程 - 起点。
// 起点存在本地，第一次切到小计就是 0.0，长按卡片清零。
const ODO_BASE_KEY = 'icar.tripBase';
const ODO_MODE_KEY = 'icar.odoMode';
const TEMP_MODE_KEY = 'icar.tempMode';

function odoMode() { return store.get(ODO_MODE_KEY, 'total') === 'trip' ? 'trip' : 'total'; }
function tempMode() { return store.get(TEMP_MODE_KEY, 'out') === 'in' ? 'in' : 'out'; }

/** 小计里程（km）：起点丢了、或者总里程比起点还小，就重新起算 */
function tripKm(d) {
  const odo = d.odo || 0;
  if (!(odo > 0)) return 0;
  let b = parseFloat(store.get(ODO_BASE_KEY, ''));
  if (!isFinite(b) || b <= 0 || b > odo) { b = odo; store.set(ODO_BASE_KEY, String(odo)); }
  return Math.max(0, odo - b);
}

function renderOdo(d) {
  const chip = $('chip-odo');
  if (!chip) return;
  const trip = odoMode() === 'trip';
  chip.textContent = trip
    ? `小计 ${tripKm(d).toFixed(1)} km`
    : `${Math.round(d.odo || 0)} km`;
}

// 续航卡：点一下在 续航里程 / 本次里程 之间切
const RANGE_MODE_KEY = 'icar.rangeMode';
function rangeMode() { return store.get(RANGE_MODE_KEY, 'range') === 'trip' ? 'trip' : 'range'; }

function renderRange(d) {
  if (rangeMode() === 'trip') {
    const km = tripRec ? (+tripRec.mileage || 0) : null;
    setText('s-range', `${km == null ? '--' : km.toFixed(1)}<small>km</small>`);
    setText('s-range-k', '本次里程');
  } else {
    setText('s-range', `${pickRange(d)}<small>km</small>`);
    setText('s-range-k', '续航里程');
  }
}

function toggleRange() {
  store.set(RANGE_MODE_KEY, rangeMode() === 'trip' ? 'range' : 'trip');
  if (lastData) renderRange(lastData);
  flipVal('s-range');
  if (rangeMode() === 'trip') loadTripOil(true);   // 切到本次里程就立刻重取一次
}

// 油耗卡：点一下在 平均油耗 / 本次油耗 之间切，只显示一个
const OIL_MODE_KEY = 'icar.oilMode';
function oilMode() { return store.get(OIL_MODE_KEY, 'avg') === 'trip' ? 'trip' : 'avg'; }

function renderOil(d) {
  const avgMode = oilMode() === 'avg';
  if (avgMode) {
    // 车端除零兜底固定返回 25.5，是假值，显示成 --（本次油耗不受影响）
    const v = +d.fuel100 || 0;
    const BOGUS_OIL = 25.5;
    const bogus = v > 0 && Math.abs(v - BOGUS_OIL) < 0.05;
    setText('s-oil', `${v > 0 && !bogus ? v.toFixed(1) : '--'}<small>L</small>`);
    setText('s-oil-k', '平均油耗');
    return;
  }
  // 本次油耗优先用最近一条轨迹；轨迹取不到就退回车端的累计字段，保证有数可显示
  const fromTrip = (tripOil != null && tripOil > 0) ? tripOil : (tripRec ? (+tripRec.oil || 0) : null);
  const fallback = +d.oilTrip || 0;
  const v = (fromTrip != null && fromTrip > 0) ? fromTrip : (fallback > 0 ? fallback : null);
  // 车端给 25.5 同样是除零兜底的假值，这里也显示 --
  const bogus = v != null && Math.abs(v - 25.5) < 0.05;
  setText('s-oil', `${v == null || bogus ? '--' : v.toFixed(1)}<small>L</small>`);
  setText('s-oil-k', '本次油耗');
}


// ---------------- 本次行程：从最近一次轨迹记录取 ----------------
// 注意：行程接口（/app2/api/driving）官方 App 一直是「同一天传两次」的单日查法，
// 传一个月/一年的区间它不一定给数据，所以以前「历史行程有记录、本次却不显示」。
// 现在先用区间试一次，没结果就逐日往前找（和行程页同一个查法），命中即停。
let tripOil = null;        // 最近一次行程的油耗（L），null = 没读到
let tripRec = null;        // 最近一条轨迹记录（本次里程、行程时间都从它取）
let tripOilAt = 0;         // 缓存时间
let tripOilBusy = false;
let tripNote = '';         // 取数过程，取不到时显示在「更多」里，方便反馈
const TRIP_TTL = 45 * 1000;
const TRIP_LOOKBACK = 15;  // 最多往前找 15 天

function sortTrips(list) {
  return (list || []).slice().sort((a, b) => String(a.endTime || '').localeCompare(String(b.endTime || '')));
}
function dayBack(n) { const d = new Date(); d.setDate(d.getDate() - n); return ymd(d); }

/** 收下一天的记录：里程用最新那条；油耗优先取有值的那条（刚结束的行程油耗可能还没结算） */
function applyTrip(list) {
  const sorted = sortTrips(list);
  const last = sorted[sorted.length - 1] || null;
  if (!last) return false;
  const withOil = sorted.slice().reverse().find(r => +r.oil > 0);
  tripRec = last;
  tripOil = +last.oil > 0 ? +last.oil : (withOil ? +withOil.oil : null);
  tripOilAt = Date.now();
  return true;
}

/** force=true 跳过缓存（手动点油耗卡时用） */
async function loadTripOil(force) {
  if (tripOilBusy) return;
  if (!force && tripRec && Date.now() - tripOilAt < TRIP_TTL) return;
  tripOilBusy = true;
  tripNote = '';
  try {
    const today = ymd(new Date());
    // 1) 区间查询：服务端支持就一次拿全，最快
    try {
      const list = await api.trips(dayBack(30), today);
      if (applyTrip(list)) { tripNote = '区间30天'; return; }
      tripNote = '区间30天无记录';
    } catch (e) { tripNote = '区间失败:' + (e.message || e); }

    // 2) 逐日往前找，命中即停
    for (let i = 0; i <= TRIP_LOOKBACK; i++) {
      const day = dayBack(i);
      try {
        const list = await api.trips(day, day);
        if (applyTrip(list)) { tripNote = '逐日命中 ' + day; return; }
      } catch (e) { tripNote = '逐日失败 ' + day + ':' + (e.message || e); }
    }
    if (!tripNote) tripNote = TRIP_LOOKBACK + '天内没有行程';
    tripRec = null;
    tripOil = null;
    tripOilAt = Date.now();
  } catch (e) {
    tripNote = '异常:' + (e.message || e);
    tripOil = null;
  } finally {
    tripOilBusy = false;
    console.log('[行程] 本次行程:', tripRec ? (tripRec.endTime + ' 里程' + tripRec.mileage + 'km 油耗' + tripRec.oil + 'L') : '无', '|', tripNote);
    if (lastData) { renderOil(lastData); renderRange(lastData); renderMore(lastData); }
  }
}

function toggleOil() {
  store.set(OIL_MODE_KEY, oilMode() === 'avg' ? 'trip' : 'avg');
  if (lastData) renderOil(lastData);
  flipVal('s-oil');
  if (oilMode() === 'trip') loadTripOil(true);
}

function renderTemp(d) {
  const inside = tempMode() === 'in';
  setText('s-temp', `${inside ? d.tempIn : d.tempOut}<small>℃</small>`);
  setText('s-temp-k', inside ? '车内温度' : '车外温度');
}

function flipVal(id) {
  const v = $(id);
  if (!v) return;
  v.classList.remove('flip');
  void v.offsetWidth;
  v.classList.add('flip');
  setTimeout(() => v.classList.remove('flip'), 420);
}

function toggleOdo() {
  const toTrip = odoMode() !== 'trip';
  store.set(ODO_MODE_KEY, toTrip ? 'trip' : 'total');
  if (lastData) { renderOdo(lastData); renderOil(lastData); renderMore(lastData); }
  flipVal('chip-odo');
  if (toTrip) toast('长按这里可以把小计里程清零');
}

function resetTrip() {
  if (odoMode() !== 'trip' || !lastData) return;
  store.set(ODO_BASE_KEY, String(lastData.odo || 0));
  renderOdo(lastData); renderOil(lastData); renderMore(lastData);
  flipVal('chip-odo');
  toast('小计里程已清零', 'ok');
}

function toggleTemp() {
  store.set(TEMP_MODE_KEY, tempMode() === 'in' ? 'out' : 'in');
  if (lastData) renderTemp(lastData);
  flipVal('s-temp');
}

/** 点整张卡 = 切换；卡片里的小胶囊（如「清零」）自己处理，不再冒泡切换 */
function bindTap(el, onTap) {
  if (!el) return;
  el.addEventListener('contextmenu', e => e.preventDefault());
  el.addEventListener('click', e => {
    if (e.target && e.target.closest && e.target.closest('.clr')) return;
    if (onTap) onTap();
  });
}

/** 长按底部「数据时间」看车况原始数据：车端字段对不上时靠它排查 */
/** 控车码：设置一次，下发指令时自动带上 */
/** 数据来源选择：服务器 / 本地计算 */
/** 油箱容量设置：每个车型不一样 */
function bindTank() {
  const row = $('row-tank');
  if (!row) return;
  const sync = () => {
    const v = tankL();
    const sub = $('tank-sub');
    if (sub) sub.textContent = v + ' L · 换车型请按实际改';
  };
  sync();
  row.addEventListener('click', () => {
    const inp = $('tank-input');
    if (inp) inp.value = String(tankL());
    $('tank-sheet').classList.add('show');
  });
  $('tank-x').addEventListener('click', () => $('tank-sheet').classList.remove('show'));
  $('tank-sheet').querySelectorAll('.chip[data-tank]').forEach(c => {
    c.addEventListener('click', () => { $('tank-input').value = c.dataset.tank; });
  });
  $('tank-save').addEventListener('click', () => {
    const v = parseFloat($('tank-input').value);
    if (!(v >= 20 && v <= 150)) { toast('请填 20~150 之间的数', 'err'); return; }
    if (hasNative) Native.kvSet('icar.tankL', String(v));
    store.set('icar.tankL', String(v));
    sync();
    $('tank-sheet').classList.remove('show');
    if (lastData) renderStatus(lastData);
    toast('油箱容量已设为 ' + v + ' L', 'ok');
  });
  $('tank-reset').addEventListener('click', () => {
    if (hasNative) Native.kvSet('icar.tankL', '50');
    store.set('icar.tankL', '50');
    sync();
    $('tank-sheet').classList.remove('show');
    if (lastData) renderStatus(lastData);
    toast('已恢复 50 L', 'ok');
  });
}

// ---------------- 数据校验：拿车上读数反推该用哪个来源 ----------------
// 用户填他自己确认过的油量 / 续航（仪表盘或官方 App 显示的），
// 跟各来源的值比差值，最接近的那个就是「在他这台车上算得对」的来源，一键切过去。
let checkUnit = 'pct';

/** 本地估算续航：升数 ÷ 百公里油耗 × 100，算不出来返回 null */
function localRangeFrom(liters, d) {
  const per = +d.fuel100 || 0;
  // 25.5 是车端除零兜底的假值，算不出可信续航
  if (!(liters > 0) || !(per > 0) || Math.abs(per - 25.5) < 0.05) return null;
  return Math.round(liters / per * 100);
}

/** 油量：三个来源各自的值（pct / liter） */
function fuelRows(d) {
  const t = tankL();
  const serverPct = (d.fuelServer != null ? +d.fuelServer : null);
  const localPct = (d.fuelLocal != null ? +d.fuelLocal : null);
  const lit = carLiter(d);
  return [
    { key: 'server', name: '服务器', note: '车端 remainingFuel 百分比', pct: serverPct,
      liter: serverPct != null ? serverPct / 100 * t : null },
    { key: 'local', name: '本地计算', note: '升数 ÷ 油箱 ' + t + ' L', pct: localPct,
      liter: localPct != null ? localPct / 100 * t : null },
    { key: 'liter', name: '车端升数', note: '车端 fuelLeftover 原值', pct: lit != null ? Math.round(lit / t * 100) : null,
      liter: lit },
  ];
}

/** 续航：服务器给多少就是多少，本地两个来源都按升数估 */
function rangeRows(d) {
  const t = tankL();
  const server = +d.range || 0;
  const litCar = carLiter(d);
  const litLocal = (d.fuelLocal != null ? +d.fuelLocal : null);
  return [
    { key: 'server', name: '服务器', note: '车端 remainedOilMile', km: server > 0 ? server : null },
    { key: 'local', name: '本地计算', note: '升数 ÷ 百公里油耗', km: litLocal != null ? localRangeFrom(litLocal / 100 * t, d) : null },
    { key: 'liter', name: '车端升数', note: '升数 ÷ 百公里油耗', km: litCar != null ? localRangeFrom(litCar, d) : null },
  ];
}

function checkRowHtml(r, unit, userVal, isBest) {
  const v = unit === 'km' ? r.km : (unit === 'pct' ? r.pct : r.liter);
  const suf = unit === 'km' ? ' km' : (unit === 'pct' ? ' %' : ' L');
  const alt = unit === 'pct'
    ? (r.liter == null ? '' : ' · ' + r.liter.toFixed(1) + ' L')
    : (unit === 'km' ? '' : (r.pct == null ? '' : ' · ' + Math.round(r.pct) + ' %'));
  const val = v == null ? '无数据'
    : (unit === 'pct' ? Math.round(v) + suf : v.toFixed(1) + suf);
  const diff = v == null ? null : Math.abs(v - userVal);
  const diffTxt = diff == null ? '—'
    : '差 ' + (unit === 'km' ? diff.toFixed(0) + ' km' : (unit === 'pct' ? diff.toFixed(0) + ' %' : diff.toFixed(1) + ' L'));
  return `<div class="check-item${isBest ? ' best' : ''}">
    <div class="ci-name"><b>${r.name}${isBest ? ' · 最接近' : ''}</b><span>${r.note}</span></div>
    <div class="ci-val">${val}<br><small style="color:var(--txt-3)">${diffTxt}${alt}</small></div>
    <button class="ci-use" data-use="${r.key}">用这个</button>
  </div>`;
}

/** 并列时优先车端升数（原值，不经过油箱换算） */
function pickBest(scored) {
  if (!scored.length) return null;
  const sorted = scored.slice().sort((a, b) => a.diff - b.diff);
  const first = sorted[0];
  const tie = sorted.filter(x => Math.abs(x.diff - first.diff) < 0.0001).map(x => x.key);
  if (tie.indexOf('liter') >= 0) return 'liter';
  return first.key;
}

function runCheck() {
  const d = lastData;
  const box = $('check-out');
  if (!d) { if (box) box.innerHTML = '<div class="check-empty">还没读到车况，等首页刷新完再来。</div>'; return; }

  const fuelVal = parseFloat($('check-input').value);
  const rangeVal = parseFloat($('check-range').value);
  const hasFuel = isFinite(fuelVal);
  const hasRange = isFinite(rangeVal);
  if (!hasFuel && !hasRange) { toast('油量或续航，填一项就行', 'err'); return; }

  const fuelLim = checkUnit === 'pct' ? 100 : tankL();
  if (hasFuel && (fuelVal < 0 || fuelVal > fuelLim)) {
    toast(checkUnit === 'pct' ? '油量请填 0~100 的百分比' : '油量请填 0~' + tankL() + ' 的升数', 'err');
    return;
  }
  if (hasRange && (rangeVal <= 0 || rangeVal > 2000)) { toast('续航请填 1~2000 的公里数', 'err'); return; }

  // 每个来源的总差值：两个指标各自归一后相加，只有填了的指标才参与
  const score = {};
  const fRows = hasFuel ? fuelRows(d) : [];
  const rRows = hasRange ? rangeRows(d) : [];
  fRows.forEach(r => {
    const v = checkUnit === 'pct' ? r.pct : r.liter;
    if (v == null) return;
    score[r.key] = (score[r.key] || 0) + Math.abs(v - fuelVal) / (checkUnit === 'pct' ? 100 : tankL());
  });
  rRows.forEach(r => {
    if (r.km == null) return;
    score[r.key] = (score[r.key] || 0) + Math.abs(r.km - rangeVal) / Math.max(1, rangeVal);
  });
  const bestKey = pickBest(Object.keys(score).map(k => ({ key: k, diff: score[k] })));

  let html = '';
  if (hasFuel) {
    html += '<div class="ck-sec">油量对比</div>';
    html += fRows.map(r => checkRowHtml(r, checkUnit, fuelVal, r.key === bestKey)).join('');
  }
  if (hasRange) {
    html += '<div class="ck-sec">续航对比</div>';
    html += rRows.map(r => checkRowHtml(r, 'km', rangeVal, r.key === bestKey)).join('');
  }
  if (bestKey) {
    const names = { server: '服务器', local: '本地计算', liter: '车端升数' };
    html += `<div class="check-empty" style="margin-top:6px">综合最接近的是「${names[bestKey]}」，点它那行的「用这个」就切过去。</div>`;
  }
  box.innerHTML = html;
  box.querySelectorAll('.ci-use').forEach(b => {
    b.addEventListener('click', () => useSource(b.dataset.use));
  });
}

function useSource(key) {
  setDataSource(key);
  const names = { server: '服务器', local: '本地计算', liter: '车端升数' };
  toast('已切到「' + (names[key] || key) + '」', 'ok');
  $('check-sheet').classList.remove('show');
  if (lastData) renderStatus(lastData);
}

function bindCheck() {
  const row = $('row-check');
  if (!row) return;
  row.addEventListener('click', () => {
    const out = $('check-out');
    if (out) out.innerHTML = '';
    $('check-sheet').classList.add('show');
    // 默认把当前显示的值填进去，用户改成实测值即可
    if (lastData) {
      const cur = dataSource();
      const fr = fuelRows(lastData).find(x => x.key === cur);
      const inp = $('check-input');
      if (inp && fr) {
        const v = checkUnit === 'pct' ? fr.pct : fr.liter;
        if (v != null) inp.value = checkUnit === 'pct' ? String(Math.round(v)) : v.toFixed(1);
      }
      const rr = rangeRows(lastData).find(x => x.key === cur);
      const rInp = $('check-range');
      if (rInp && rr && rr.km != null) rInp.value = String(Math.round(rr.km));
    }
  });
  $('check-x').addEventListener('click', () => $('check-sheet').classList.remove('show'));
  $('check-run').addEventListener('click', runCheck);
  $('check-unit').querySelectorAll('.chip[data-unit]').forEach(c => {
    c.addEventListener('click', () => {
      checkUnit = c.dataset.unit;
      $('check-unit').querySelectorAll('.chip[data-unit]').forEach(x => x.classList.toggle('on', x === c));
      const inp = $('check-input');
      if (inp) inp.placeholder = checkUnit === 'pct' ? '例如 62' : '例如 31.5';
      const out = $('check-out');
      if (out) out.innerHTML = '';
    });
  });
}

function bindDataSource() {
  const row = $('row-ds');
  if (!row) return;
  const sync = () => {
    const cur = dataSource();
    row.querySelectorAll('.chip[data-ds]').forEach(c => {
      c.classList.toggle('on', c.dataset.ds === cur);
    });
    const sub = $('ds-sub');
    if (sub) sub.textContent = cur === 'local'
      ? '油量按升数换算，续航按油耗估算'
      : (cur === 'liter'
        ? '油量显示车端升数，点油量卡可切百分比（按油箱算）'
        : '油量、续航用服务器返回的值');
  };
  row.querySelectorAll('.chip[data-ds]').forEach(c => {
    c.addEventListener('click', () => { setDataSource(c.dataset.ds); sync(); });
  });
  sync();
}

function bindPin() {
  const row = $('row-pin');
  if (!row) return;
  const refresh = () => {
    const v = api.pinCode();
    const el = $('pin-state');
    if (el) el.textContent = v ? '已设置（' + v.replace(/./g, '•') + '）' : '未设置，部分车型下发指令需要';
  };
  refresh();
  row.addEventListener('click', () => {
    const inp = $('pin-input');
    if (inp) inp.value = api.pinCode();
    $('pin-sheet').classList.add('show');
  });
  $('pin-x').addEventListener('click', () => $('pin-sheet').classList.remove('show'));
  $('pin-save').addEventListener('click', () => {
    const v = ($('pin-input').value || '').replace(/[^0-9]/g, '');
    if (v.length < 4) { toast('控车码至少 4 位数字', 'err'); return; }
    api.setPinCode(v);
    refresh();
    $('pin-sheet').classList.remove('show');
    toast('控车码已保存', 'ok');
  });
  $('pin-clear').addEventListener('click', () => {
    api.setPinCode('');
    refresh();
    $('pin-sheet').classList.remove('show');
    toast('已清除控车码', 'ok');
  });
}

function bindRaw() {
  const foot = $('foot-sync');
  if (!foot) return;
  let lp = 0, fired = false;
  const open = async () => {
    $('raw-pre').textContent = '读取中…';
    $('raw-sheet').classList.add('show');
    try {
      const t = await api.raw();
      $('raw-pre').textContent = t || '（空）';
    } catch (e) {
      $('raw-pre').textContent = '读取失败：' + e.message;
    }
  };
  foot.addEventListener('contextmenu', e => e.preventDefault());
  foot.addEventListener('pointerdown', () => {
    fired = false;
    lp = setTimeout(() => { fired = true; open(); }, 700);
  });
  // 只认 pointerup：headless / 触摸里 pointercancel、pointerleave 会莫名其妙地来一发，
  // 挂上去长按就废了
  foot.addEventListener('pointerup', () => clearTimeout(lp));
  foot.addEventListener('click', e => { if (fired) { e.preventDefault(); e.stopPropagation(); } });
  const x = $('raw-x');
  if (x) x.addEventListener('click', () => $('raw-sheet').classList.remove('show'));
  const nx = $('ntf-x');
  if (nx) nx.addEventListener('click', () => $('ntf-sheet').classList.remove('show'));
  const nc = $('ntf-clear');
  if (nc) nc.addEventListener('click', () => {
    if (hasNative) { try { Native.ntfClearLog(); } catch (e) {} }
    $('ntf-pre').textContent = '还没有记录。';
    toast('已清空通知记录', 'ok');
  });

}

function bindCards() {
  bindTap($('stat-fuel'), toggleFuel);
  bindTap($('stat-oil'), toggleOil);
  bindTap($('stat-temp'), toggleTemp);
  bindTap($('stat-range'), toggleRange);

  // 总里程挪到顶部胶囊：点一下切 总里程 / 小计里程，长按 0.7s 清零小计
  const chip = $('chip-odo');
  if (!chip) return;
  let lp = 0, longPressed = false;
  chip.addEventListener('contextmenu', e => e.preventDefault());
  chip.addEventListener('pointerdown', () => {
    longPressed = false;
    lp = setTimeout(() => {
      longPressed = true;
      if (odoMode() === 'trip') resetTrip();
      else toast('点一下切到小计里程，再长按清零');
    }, 700);
  });
  chip.addEventListener('pointerup', () => clearTimeout(lp));
  chip.addEventListener('click', () => { if (!longPressed) toggleOdo(); });
}

// ---------------- 车门 / 车窗 / 天窗 / 后备箱 状态条 ----------------
const FLAGS = [
  ['doorFL', '左前门'], ['doorFR', '右前门'], ['doorBL', '左后门'], ['doorBR', '右后门'],
  ['winFL', '左前窗'], ['winFR', '右前窗'], ['winBL', '左后窗'], ['winBR', '右后窗'],
  ['sunroof', '天窗'], ['trunk', '后备箱'],
];

function paintFlags(d) {
  const box = $('car-flags');
  if (!box) return;
  const opened = FLAGS.filter(([k]) => +d[k] === 1).map(([, n]) => `<span class="flag">${n}已开</span>`);
  // 发动机着着的时候也标一下（远程启动后能一眼确认）
  // 车机数据不新鲜时别挂发动机标签，熄火后不会一直留着
  // 发动机是否真在转：只看转速。
  // engineStatus 在部分车型上「上电」就给 2，电压也会被充到 13V 以上，两者都不可靠。
  const raw = +d.engineSpeed || 0;
  const rpm = raw >= 60000 ? 0 : raw;   // 65535 = 车端无数据
  if (d.online && rpm > 0) opened.push('<span class="flag">发动机已启动</span>');
  box.classList.toggle('hide', opened.length === 0);
  box.innerHTML = opened.join('');
}

function renderStatus(d) {
  lastData = d;
  paintVitals(d);
  renderFuel(pickFuel(d));
  renderRange(d);
  renderOdo(d);
  renderOil(d);
  loadTripOil();   // 本次里程/本次油耗都要用，跟当前显示模式无关（内部有缓存和防重入）
  renderTemp(d);

  const lock = $('chip-lock');
  lock.textContent = d.locked ? '已锁车' : '未锁车';
  lock.className = 'chip ' + (d.locked ? 'ok' : 'on');

  $('chip-online').textContent = d.online ? '在线' : '离线';
  $('chip-time').textContent = d.time || '--';
  paintFlags(d);

  acState.on = !!d.acOn;
  acState.inTemp = d.tempIn;
  acState.setTemp = parseInt(d.acTemp, 10) || null;
  paintAc();
  $('ac-sub').textContent = `设定 ${acState.setTemp || '--'}℃ · 车外 ${d.tempOut}℃`;

  // 油量低时先提醒，免得点了以为成功
  const fuelPct = pickFuel(d);
  const lowFuel = fuelPct > 0 && fuelPct <= 15;
  const note = $('ac-note');
  if (note) {
    note.classList.toggle('show', lowFuel);
    if (lowFuel) note.textContent = `剩余油量 ${fuelPct}%，油量过低时车端会拒绝启动空调`;
  }

  $('loc-title').textContent = d.gps ? '车辆位置' : '定位不可用';
  $('loc-sub').textContent = d.gps ? `${d.lat.toFixed(5)}, ${d.lng.toFixed(5)} · 车速 ${d.speed} km/h` : '车辆未上报定位';
  $('foot-sync').textContent = `数据时间 ${d.time || '--'} · 来自长安车联网`;
  renderMore(d);
  if (!cabinIntroBusy) renderCabinData(d);   // 出场动画在播时别抢

  // 3D 车身联动
  window.app = {
    apiData: {
      driverDoorLock: d.locked ? 1 : 0,
      passengerDoorLock: d.locked ? 1 : 0,
      leftRearDoorLock: d.locked ? 1 : 0,
      rightRearDoorLock: d.locked ? 1 : 0,
      leftFrontDoor: d.doorFL, rightFrontDoor: d.doorFR,
      leftRearDoor: d.doorBL, rightRearDoor: d.doorBR,
      diverWindow: d.winFL, passengerWindow: d.winFR,
      leftRearWindow: d.winBL, rightRearWindow: d.winBR,
      sunroof: d.sunroof, trunk: d.trunk, hood: d.hood, winSlit: d.winSlit,
      lowBeam: d.lowBeam, highBeam: d.highBeam, positionLight: d.positionLight,
      leftTurnSignal: d.leftTurnSignal, rightTurnSignal: d.rightTurnSignal,
      engineStatus: d.engineStatus,
      airStatus: d.acOn ? 1 : 0,
      speed: d.speed, waterTemp: d.waterTemp,
    },
    fetchFreshData: () => loadStatus()
  };
  if (window.vehicle3D) { try { window.vehicle3D.updateBodyStatus(); } catch (e) {} }
}

let lastLoad = 0;

async function loadStatus(silent) {
  lastLoad = Date.now();
  if (!silent) $('btn-refresh').classList.add('spin');
  let result = { ok: true };
  try {
    const d = await api.status();
    renderStatus(d);
  } catch (e) {
    result = { ok: false, error: e.message || '车况读取失败' };
    if (!silent) {
      toast('车况读取失败：' + result.error, 'err');
      $('chip-online').textContent = '离线';
    }
  } finally {
    setTimeout(() => $('btn-refresh').classList.remove('spin'), 500);
  }
  return result;
}

/** 右上角 ↻：把车辆数据整套重新拉一遍（车况 + 开着的位置/轨迹/全景） */
async function refreshVehicle() {
  const btn = $('btn-refresh');
  if (btn.dataset.busy === '1') return;
  btn.dataset.busy = '1';
  btn.classList.add('spin');
  const wrap = p => Promise.resolve().then(p).then(() => ({ ok: true }), e => ({ ok: false, error: (e && e.message) || '读取失败' }));
  const jobs = [loadStatus(true)];
  if (showSec('loc')) jobs.push(wrap(() => loadLocation()));
  if (showSec('trip')) jobs.push(wrap(() => refreshTripSummary()));
  if (showSec('pano')) jobs.push(wrap(() => loadPhotos()));
  const settled = await Promise.allSettled(jobs);
  btn.dataset.busy = '';
  btn.classList.remove('spin');
  const bad = settled
    .map(r => (r.status === 'fulfilled' ? r.value : { ok: false, error: (r.reason && r.reason.message) || '读取失败' }))
    .filter(v => v && v.ok === false);
  if (bad.length) toast('部分数据没拉到：' + bad[0].error, 'err');
  else toast('车辆数据已更新', 'ok');
}

/** 回到前台就刷一次，页面开着也每 60 秒刷一次——不然熄火后车门/发动机那几个标会一直挂着 */
// 刷新间隔（秒）：60 / 300 / 600，0 = 不自动刷新。
// 查车况会让车机上报数据，车机被唤醒时部分车型大灯会亮一下，所以默认放宽到 5 分钟。
const REFRESH_KEY = 'icar.refreshSec';
const REFRESH_OPTS = [60, 300, 600, 0];

function refreshSec() {
  const v = parseInt(store.get(REFRESH_KEY, '300'), 10);
  return REFRESH_OPTS.indexOf(v) >= 0 ? v : 300;
}

function startAutoRefresh() {
  if (startAutoRefresh.done) return;
  startAutoRefresh.done = true;
  const kick = () => { if (Date.now() - lastLoad > 15000) loadStatus(true); };
  document.addEventListener('visibilitychange', () => { if (!document.hidden) kick(); });
  window.addEventListener('focus', kick);
  const tick = () => {
    const s = refreshSec();
    if (s > 0 && !document.hidden && Date.now() - lastLoad > s * 1000) loadStatus(true);
    setTimeout(tick, 20000);   // 每 20 秒看一眼该不该刷新，间隔本身按设置走
  };
  setTimeout(tick, 20000);
}

function bindRefresh() {
  const row = $('row-refresh');
  if (!row) return;
  const sync = () => {
    const cur = refreshSec();
    row.querySelectorAll('.chip[data-rs]').forEach(c => {
      c.classList.toggle('on', parseInt(c.dataset.rs, 10) === cur);
    });
    const sub = $('refresh-sub');
    if (sub) {
      const txt = cur === 0 ? '不自动刷新 · 下拉或点刷新按钮才查'
        : (cur === 60 ? '1 分钟' : (cur === 300 ? '5 分钟' : '10 分钟'));
      sub.textContent = txt + ' · 刷新会唤醒车机，越勤越费电瓶';
    }
  };
  row.querySelectorAll('.chip[data-rs]').forEach(c => {
    c.addEventListener('click', () => {
      store.set(REFRESH_KEY, c.dataset.rs);
      sync();
      toast(parseInt(c.dataset.rs, 10) === 0 ? '已改为不自动刷新' : '刷新间隔已改', 'ok');
    });
  });
  sync();
}


// ---------------- 车内视角底部：车速 / 水温 ----------------
// 5x7 点阵字模
const DOT_GLYPH = {
  '0': ['01110','10001','10011','10101','11001','10001','01110'],
  '1': ['00100','01100','00100','00100','00100','00100','01110'],
  '2': ['01110','10001','00001','00010','00100','01000','11111'],
  '3': ['11111','00010','00100','00010','00001','10001','01110'],
  '4': ['00010','00110','01010','10010','11111','00010','00010'],
  '5': ['11111','10000','11110','00001','00001','10001','01110'],
  '6': ['00110','01000','10000','11110','10001','10001','01110'],
  '7': ['11111','00001','00010','00100','01000','01000','01000'],
  '8': ['01110','10001','10001','01110','10001','10001','01110'],
  '9': ['01110','10001','10001','01111','00001','00010','01100'],
  '-': ['00000','00000','00000','11111','00000','00000','00000']
};

function renderDots(el, text) {
  if (!el) return;
  const chars = String(text);
  el.innerHTML = chars.split('').map(ch => {
    const g = DOT_GLYPH[ch] || DOT_GLYPH['-'];
    return '<div class="dg">' + g.map(row => row.split('').map(c =>
      '<i' + (c === '1' ? ' class="on"' : '') + '></i>').join('')).join('') + '</div>';
  }).join('');
}

function renderCabinData(d, factor, over) {
  const k = factor === undefined ? 1 : factor;
  const sp = document.getElementById('cd-speed');
  const wt = document.getElementById('cd-water');
  if (!sp || !wt) return;
  const data = d || (window.app && window.app.apiData) || {};
  const speed = Number(data.speed) || 0;
  const water = Number(data.waterTemp) || 0;
  let spd = speed * k, wat = water * k;
  // 出场动画用绝对值驱动，不走倍数
  if (over) {
    if (typeof over.speed === 'number') spd = over.speed;
    if (typeof over.water === 'number') wat = over.water;
  }
  renderDots(sp, spd >= 1 ? Math.round(spd) : '--');
  renderDots(wt, wat >= 1 ? Math.round(wat) : '--');

  // 水温小矩阵：12 列 × 3 行，从右往左涨
  const wbar = document.getElementById('cd-wbar');
  if (wbar) {
    const WCOLS = 12, WROWS = 1, WN = WCOLS * WROWS;
    if (wbar.children.length !== WN) {
      wbar.innerHTML = Array.from({ length: WN }, () => '<i></i>').join('');
    }
    const wp = Math.max(0, Math.min(1, wat / 120));
    const wlit = Math.round(wp * WCOLS);
    const whue = 195 - 195 * wp;   // 蓝青 → 红
    const wcol = `hsl(${whue}, 85%, 58%)`;
    for (let i = 0; i < WN; i++) {
      const el = wbar.children[i];
      const col = i % WCOLS;
      const on = col >= WCOLS - wlit;   // 从右侧开始点亮
      if (on) {
        el.style.background = wcol;
        el.style.boxShadow = `0 0 6px ${wcol}`;
      } else {
        el.style.background = '';
        el.style.boxShadow = '';
      }
    }
  }

  // 车速点阵条：越高越红
  const bar = document.getElementById('cd-bar');
  if (bar) {
    const COLS = 48, ROWS = 6, N = COLS * ROWS;
    if (bar.children.length !== N) {
      bar.innerHTML = Array.from({ length: N }, () => '<i></i>').join('');
    }
    const p = Math.max(0, Math.min(1, spd / 180));
    const lit = Math.round(p * COLS);
    const hue = 168 - 168 * p;      // 青绿 → 黄 → 红
    const col = `hsl(${hue}, 88%, 56%)`;
    for (let i = 0; i < N; i++) {
      const el = bar.children[i];
      const c = i % COLS;
      if (c < lit) {
        el.style.background = col;
        el.style.boxShadow = `0 0 6px ${col}`;
        el.classList.add('on');
      } else {
        el.style.background = '';
        el.style.boxShadow = '';
        el.classList.remove('on');
      }
    }
  }
}
window.renderCabinData = renderCabinData;

/** 进车内时：镜头飞入的过程中读数冲到满格，镜头到位那一刻正好到顶，随后回落再归位 */
let cabinIntroBusy = false;
let cabinIntroToken = 0;

function playCabinIntro(camDur) {
  const d = (window.app && window.app.apiData) || {};
  const targetSpeed = Number(d.speed) || 0;
  const targetWater = Number(d.waterTemp) || 0;

  const MAX_SPD = 180;  // 车速点阵条满格
  const MAX_WAT = 120;  // 水温条满格
  const T1 = camDur || 900;   // 冲顶：正好用掉内饰动画那么久，结束时到顶
  const HOLD = 150;           // 到顶后停一下，让人看清
  const T2 = 400;             // 落回 0
  const T3 = 600;             // 归位到真实值
  const total = T1 + HOLD + T2 + T3;

  const t0 = performance.now();
  const eo = p => 1 - Math.pow(1 - p, 3);
  const ei = p => p * p;
  const my = ++cabinIntroToken;

  cabinIntroBusy = true;

  const step = () => {
    if (my !== cabinIntroToken) return;   // 被新的一次进场接管了

    const el = performance.now() - t0;
    let spd, wat;
    if (el < T1) {                        // 冲上去：0 → 满格
      const e = eo(el / T1);
      spd = MAX_SPD * e;
      wat = MAX_WAT * e;
    } else if (el < T1 + HOLD) {          // 停在满格
      spd = MAX_SPD;
      wat = MAX_WAT;
    } else if (el < T1 + HOLD + T2) {     // 落回 0：满格 → 0
      const e = 1 - ei((el - T1 - HOLD) / T2);
      spd = MAX_SPD * e;
      wat = MAX_WAT * e;
    } else if (el < total) {              // 归位：0 → 真实值
      const e = eo((el - T1 - HOLD - T2) / T3);
      spd = targetSpeed * e;
      wat = targetWater * e;
    } else {
      spd = targetSpeed;
      wat = targetWater;
    }
    renderCabinData(null, 1, { speed: spd, water: wat });

    if (el < total) {
      requestAnimationFrame(step);
    } else {
      cabinIntroBusy = false;
      renderCabinData(null, 1);            // 交回真实数据
    }
  };
  requestAnimationFrame(step);
}
window.playCabinIntro = playCabinIntro;

// ---------------- 车况详情：小白条 + 展开面板 ----------------
// 小白条在「油量四宫格」和「快捷控制」中间，往下拖或者点一下展开，
// 展开后列出车端能读到的全部字段。
let moreOpen = false;

function onOff(v) { return v ? '打开' : '关闭'; }

function renderMore(d) {
  const t = (k, v) => `<div class="mtile"><span>${k}</span><b>${v}</b></div>`;
  const sec = k => `<div class="msec">${k}</div>`;
  const tire = v => (v > 0 ? v + ' kPa' : '--');
  const vol = d.voltage > 0 ? d.voltage.toFixed(1) : '--';

  $('more').innerHTML = `<div class="mcard">
    ${sec('基本')}
    ${t('剩余油量', (carLiter(d) != null && dataSource() === 'liter'
        ? carLiter(d).toFixed(1) + ' L / ' + pickFuel(d) + ' %'
        : (pickFuel(d) / 100 * tankL()).toFixed(1) + ' L / ' + pickFuel(d) + ' %') + (dsTag() ? ' · ' + dsTag() : ''))}
    ${t('续航里程', pickRange(d) + ' km' + (dsTag() ? ' · ' + dsTag() : ''))}
    ${t('总里程', Math.round(d.odo) + ' km')}
    ${t('小计里程', tripKm(d).toFixed(1) + ' km')}
    ${t('本次里程', tripRec ? (+tripRec.mileage || 0).toFixed(1) + ' km' : '--')}
    ${t('本次行程', tripRec ? String(tripRec.endTime || '').slice(5, 16) : (tripNote || '读取中…'))}
    ${t('车外温度', d.tempOut + ' ℃')}
    ${t('车内温度', d.tempIn + ' ℃')}
    ${t('水温', d.waterTemp > 0 ? Math.round(d.waterTemp) + ' ℃' : '--')}
    ${t('车速', Math.round(d.speed || 0) + ' km/h')}
    ${t('转速', (+d.engineSpeed || 0) > 0 ? Math.round(d.engineSpeed) + ' rpm' : '--')}
    ${t('发动机状态位', 'engineStatus=' + (d.engineStatus ?? '--'))}
    ${t('电瓶电压', vol + ' V')}

    ${sec('状态')}
    ${t('车锁', d.locked ? '已锁车' : '未锁车')}
    ${t('空调', d.acOn ? '已开启 · ' + (d.acTemp || '--') + '℃' : '已关闭')}
    ${t('天窗', onOff(d.sunroof))}
    ${t('后备箱', onOff(d.trunk))}
    ${t('网络', d.online ? '在线' : '离线')}
    ${t('主驾门', onOff(d.doorFL))}
    ${t('副驾门', onOff(d.doorFR))}
    ${t('左后门', onOff(d.doorBL))}
    ${t('右后门', onOff(d.doorBR))}
    ${t('左前窗', onOff(d.winFL))}
    ${t('右前窗', onOff(d.winFR))}
    ${t('左后窗', onOff(d.winBL))}
    ${t('右后窗', onOff(d.winBR))}

    ${sec('胎压')}
    ${t('左前轮', tire(d.tireFL))}
    ${t('右前轮', tire(d.tireFR))}
    ${t('左后轮', tire(d.tireRL))}
    ${t('右后轮', tire(d.tireRR))}

    ${sec('位置')}
    ${t('GPS', d.gps ? '已定位' : '未定位')}
    ${t('车速', Math.round(d.speed) + ' km/h')}
    <div class="mtile wide"><span>坐标</span><b>${d.gps ? d.lat.toFixed(5) + ', ' + d.lng.toFixed(5) : '--'}</b></div>
  </div>`;

  if (moreOpen) {
    const m = $('more');
    m.style.maxHeight = m.scrollHeight + 'px';
  }
}

function setMore(open) {
  moreOpen = open;
  const m = $('more'), g = $('grab');
  m.style.maxHeight = open ? (m.scrollHeight || 2200) + 'px' : '0px';
  g.classList.toggle('open', open);
  // 展开详情时车模切俯视，收起时一起还原（setTopView 是幂等的，不会和它互相触发）
  if (window.vehicle3D && typeof window.vehicle3D.setTopView === 'function') {
    try { window.vehicle3D.setTopView(open); } catch (e) {}
  }
}

function bindGrab() {
  const g = $('grab');
  let sy = 0, down = false, moved = false;

  g.addEventListener('pointerdown', e => {
    down = true; moved = false; sy = e.clientY;
    try { g.setPointerCapture(e.pointerId); } catch (err) {}
  });

  g.addEventListener('pointermove', e => {
    if (!down) return;
    const dy = e.clientY - sy;
    if (Math.abs(dy) > 10) moved = true;
    if (dy > 26 && !moreOpen) setMore(true);
    if (dy < -26 && moreOpen) setMore(false);
  });

  const end = () => {
    if (down && !moved) setMore(!moreOpen);
    down = false;
  };
  g.addEventListener('pointerup', end);
  g.addEventListener('pointercancel', () => { down = false; });
}

// ---------------- 360 全景 ----------------
const DIR = { F: '前', D: '左', R: '后', P: '右' };
let panoGroups = [];

// ---------- 本地隐藏照片（只影响 App 里显示，不动服务端） ----------
function panoHidden() {
  try { return JSON.parse(store.get('icar.panoHidden', '[]')) || []; } catch (e) { return []; }
}
function panoHide(id) {
  if (!id) return;
  const arr = panoHidden();
  if (arr.indexOf(id) < 0) arr.push(id);
  store.set('icar.panoHidden', JSON.stringify(arr));
}
function cellHtml(it) {
  return `<div class="pano-cell" data-url="${it.url}" data-id="${it.id || ''}"
      data-name="${it.name || ''}" data-task="${it.taskId || ''}">
    <img src="${it.thumb}" loading="lazy" alt="">
    <span>${DIR[it.dir] || ''}</span>
  </div>`;
}

async function doDeletePhoto(el) {
  const ok = await askConfirm('删除这张照片',
    '会从服务端真正删除，所有设备上都看不到，无法恢复。', '删 除');
  if (!ok) return;
  toast('删除中…');
  try {
    const r = await api.deletePhoto(el.dataset.id, el.dataset.name, el.dataset.task);
    if (String(r) === 'ok' || String(r).indexOf('ok:') === 0) {
      toast('已删除', 'ok');
      // 服务端列表有延迟，先刷新一次，1.5 秒后再刷一次，不用重启 App
      loadPhotos();
      if ($('sheet').classList.contains('show')) setTimeout(openSheet, 600);
      setTimeout(() => {
        loadPhotos();
        if ($('sheet').classList.contains('show')) openSheet();
      }, 1500);
    } else {
      toast('删除失败：' + String(r).replace('fail:', ''), 'err');
    }
  } catch (e) {
    toast('删除失败：' + e.message, 'err');
  }
}

let panoActTarget = null;

/** 长按后弹出：删除（服务端）/ 隐藏（仅本机），点空白处退出 */
function showPanoAct(el) {
  panoActTarget = el;
  $('pano-act').classList.add('show');
}

function bindPanoAct() {
  const box = $('pano-act');
  if (!box) return;
  box.addEventListener('click', e => {
    if (e.target === box) box.classList.remove('show');   // 点空白退出
  });
  $('pa-del').addEventListener('click', async () => {
    box.classList.remove('show');
    if (panoActTarget) await doDeletePhoto(panoActTarget);
  });
  $('pa-hide').addEventListener('click', () => {
    box.classList.remove('show');
    if (!panoActTarget) return;
    panoHide(panoActTarget.dataset.id);
    if (lastPanoGroups) renderPano(lastPanoGroups);
    if ($('sheet').classList.contains('show')) openSheet();
    toast('已隐藏这张照片', 'ok');
  });
}

function bindLightbox(root, allowHide) {
  root.querySelectorAll('[data-url]').forEach(el => {
    let lp = 0, armed = false, swallow = false;
    // 系统默认的长按会开始拖图片，直接掐掉
    el.addEventListener('dragstart', e => e.preventDefault());
    el.addEventListener('contextmenu', e => e.preventDefault());
    let sx = 0, sy = 0;
    el.addEventListener('pointerdown', e => {
      armed = false;
      sx = e.clientX; sy = e.clientY;
      clearTimeout(lp);
      if (!allowHide) return;          // 首页卡片上不挂长按，只有「全部照片」里能隐藏
      // 按住够久就直接弹确认框，不用等松手
      lp = setTimeout(() => {
        armed = true;
        swallow = true;                     // 吃掉松手后的 click，别打开大图
        setTimeout(() => { swallow = false; }, 800);
        showPanoAct(el);
      }, 750);
    });
    // 手指一移动就取消：滑动、轻扫都不该触发隐藏
    el.addEventListener('pointermove', e => {
      if (Math.abs(e.clientX - sx) > 10 || Math.abs(e.clientY - sy) > 10) clearTimeout(lp);
    });
    el.addEventListener('pointerup', () => { clearTimeout(lp); });
    el.addEventListener('pointercancel', () => { clearTimeout(lp); });
    el.onclick = e => {
      if (swallow) { e.preventDefault(); e.stopPropagation(); return; }
      $('lightbox-img').src = el.dataset.url;
      $('lightbox').classList.add('show');
    };
  });
}

function renderPano(groups) {
  panoGroups = groups || [];
  lastPanoGroups = panoGroups;
  const grid = $('pano-grid');
  if (!panoGroups.length) {
    grid.innerHTML = '<div class="pano-empty">暂无照片，点下面拍一张</div>';
    $('pano-time').textContent = '暂无';
    return;
  }
  const hid = panoHidden();
  // 整组都隐藏了就跳过，直接顶上下一组
  let g = null, items = [];
  for (const grp of panoGroups) {
    const vis = (grp.items || []).filter(it => hid.indexOf(it.id) < 0);
    if (vis.length) { g = grp; items = vis; break; }
  }
  if (!g) {
    $('pano-time').textContent = '暂无';
    grid.innerHTML = '<div class="pano-empty">暂无照片，点下面拍一张</div>';
    return;
  }
  $('pano-time').textContent = (g.time || '').slice(5, 16).replace('-', '/');
  grid.innerHTML = items.map(cellHtml).join('');
  bindLightbox(grid, false);
}

async function loadPhotos() {
  try { renderPano(await api.photos()); }
  catch (e) { $('pano-time').textContent = '读取失败'; }
}

async function doCapture() {
  const b = $('btn-capture');
  if (b.disabled) return;
  b.disabled = true; b.textContent = '拍摄中…';
  try {
    const r = await api.capture();
    const i = r.lastIndexOf('|');
    const json = i > 0 ? r.slice(0, i) : r;
    const msg = i > 0 ? r.slice(i + 1) : '';
    renderPano(JSON.parse(json));
    toast('车外拍照：' + (msg || '已上传'), 'ok');
  } catch (e) {
    toast('拍照失败：' + e.message, 'err');
  } finally {
    b.disabled = false; b.textContent = '车外拍照';
  }
}

function openSheet() {
  const bd = $('sheet-bd');
  const hid = panoHidden();
  const groups = (panoGroups || [])
    .map(g => ({ time: g.time, items: (g.items || []).filter(it => hid.indexOf(it.id) < 0) }))
    .filter(g => g.items.length);
  if (!groups.length) {
    bd.innerHTML = '<div class="pano-empty">暂无照片</div>';
  } else {
    bd.innerHTML = groups.map(g => `
      <div class="sheet-g">
        <div class="t">${(g.time || '').slice(0, 16)}</div>
        <div class="g">${g.items.map(cellHtml).join('')}</div>
      </div>`).join('');
    bindLightbox(bd, true);
  }
  $('sheet').classList.add('show');
}

/** 恢复隐藏的照片：长按「360 全景」标题触发，平时不占位置 */
function panoRestoreAll() {
  store.set('icar.panoHidden', '[]');
  loadPhotos();
  if ($('sheet').classList.contains('show')) openSheet();
  toast('已恢复全部照片', 'ok');
}

function bindPanoRestore() {
  const el = $('pano-title');
  if (!el) return;
  let lp = 0, armed = false;
  let tx = 0, ty = 0;
  el.addEventListener('pointerdown', e => {
    armed = false;
    tx = e.clientX; ty = e.clientY;
    clearTimeout(lp);
    lp = setTimeout(async () => {
      armed = true;
      const n = panoHidden().length;
      if (!n) { toast('没有隐藏的照片'); return; }
      const ok = await askConfirm('恢复隐藏的照片', '共隐藏 ' + n + ' 张，恢复后重新显示。', '恢 复');
      if (ok) panoRestoreAll();
    }, 900);
  });
  el.addEventListener('pointermove', e => {
    if (Math.abs(e.clientX - tx) > 10 || Math.abs(e.clientY - ty) > 10) clearTimeout(lp);
  });
  el.addEventListener('pointerup', () => { clearTimeout(lp); });
  el.addEventListener('pointercancel', () => { clearTimeout(lp); });
  el.addEventListener('pointercancel', () => clearTimeout(lp));
}

function bindPano() {
  $('btn-capture').addEventListener('click', doCapture);
  $('btn-all').addEventListener('click', openSheet);
  bindPanoRestore();
  bindPanoAct();
  $('sheet-x').addEventListener('click', () => $('sheet').classList.remove('show'));
  $('lightbox').addEventListener('click', () => $('lightbox').classList.remove('show'));
}


// ---------------- 空调 ----------------
// 开放平台通道只能开关，不支持调温/风量，所以这里只显示车内温度
// 成败一律以「操作记录」里车端回执为准，和操作记录页面显示完全一致
const acState = { on: false, inTemp: null, setTemp: null, pending: null };

const sleep = ms => new Promise(r => setTimeout(r, ms));

function paintAc() {
  const v = acState.inTemp;
  $('ac-temp').textContent = (v === null || v === undefined || v === '' || isNaN(v)) ? '--' : v;

  const st = $('ac-state');
  const p = $('ac-power');

  if (acState.pending !== null) {
    st.textContent = '等待回执…';
    st.className = 'wait';
    p.textContent = acState.pending ? '启动中…' : '关闭中…';
    p.className = 'ac-power wait';
    return;
  }

  st.textContent = acState.on ? '运行中' : '已关闭';
  st.className = acState.on ? 'on' : '';
  p.textContent = acState.on ? '关闭' : '开启';
  p.className = 'ac-power' + (acState.on ? '' : ' off');
}

// auth=true 表示是授权/登录态的问题，直接给「重新登录」的指引
function setAcHint(msg, auth) {
  const h = $('ac-hint');
  if (!msg && !auth) {
    h.className = 'ac-hint';
    h.innerHTML = '';
    return;
  }
  h.innerHTML = auth
    ? '开放平台授权已失效，请到页面底部点「退出登录」，再重新登录一次即可恢复。<br><span class="dim">点这里查看详细原因</span>'
    : msg + '<br><span class="dim">点这里查看详细原因</span>';
  h.className = 'ac-hint show';
}

function showAcDiag() {
  const log = api.acDiag();
  if (!log) return;
  $('diag-pre').textContent = log;
  $('diag-sheet').classList.add('show');
}

// 从操作记录里取指定指令的最新一条（tboxCmd 是 openAir / closeAir 这种驼峰）
async function findAcRecord(kind) {
  const list = await api.actions(0, 6);
  const arr = Array.isArray(list) ? list : [];
  return arr.find(r => String(r.tboxCmd || '').toLowerCase() === kind) || null;
}

function recTime(r) {
  const t = String(r.cmdSendTime || '').replace(' ', 'T').replace(/\.\d+$/, '');
  const d = new Date(t);
  return isNaN(d.getTime()) ? 0 : d.getTime();
}

// 车端回执状态：Completed 成功；RunFailure 之类算失败；Sending 等还在路上
// 车端的中间态：Initialized（建单）→ Runing（注意官方拼写少个 n）→ Completed / RunFailure
const REC_PENDING = /^(initialized|runing|running|sending|executing|pending|init|processing|waiting)$/i;

// 车端没给原因时兜底用的中文
const REC_CN = {
  RunFailure: '车端执行失败',
  Timeout: '车端超时未响应',
  Offline: '车辆离线',
  Failed: '车端执行失败'
};

async function waitAcRecord(kind, t0, timeout) {
  const end = Date.now() + timeout;
  for (;;) {
    try {
      const rec = await findAcRecord(kind);
      if (rec && recTime(rec) >= t0 - 5000) {
        const st = String(rec.handleStatus || '');
        const desc = String(rec.resultDesc || '').trim();
        // Completed 直接算成功；其它状态必须带上原因才算最终结果，
        // 否则就是 Initialized / Runing 这种还在跑的中间态
        const done = st === 'Completed' || (st.length > 0 && !REC_PENDING.test(st) && desc.length > 0);
        if (done) return rec;
      }
    } catch (e) {
      // 单次读失败继续等
    }
    if (Date.now() > end) return null;
    await sleep(700);
  }
}

async function toggleAc() {
  if (acState.pending !== null) return;

  const expectOn = !acState.on;
  const kind = expectOn ? 'openair' : 'closeair';
  if (needConfirm()) {
    const ok = await askConfirm(expectOn ? '开启空调？' : '关闭空调？');
    if (!ok) return;
  }
  const p = $('ac-power');
  p.disabled = true;
  acState.pending = expectOn;
  paintAc();
  setAcHint('');

  const t0 = Date.now();

  try {
    if (expectOn) await api.air(); else await api.airOff();
    toast('指令已下发，等待车端回执…');

    const rec = await waitAcRecord(kind, t0, 15000);
    acState.pending = null;

    if (!rec) {
      acState.on = !expectOn;
      paintAc();
      setAcHint('车端还在处理，没等到最终结果。过一会儿到「操作记录」里看一下。', false);
      toast('车端还没返回结果', 'err');
      return;
    }

    const ok = rec.handleStatus === 'Completed';
    const raw = String(rec.resultDesc || '').trim();
    const desc = raw || (ok ? '指令执行成功' : (REC_CN[rec.handleStatus] || '车端没有给出原因'));

    if (ok) {
      acState.on = expectOn;
      paintAc();
      setAcHint('');
      toast((expectOn ? '空调已开启：' : '空调已关闭：') + desc, 'ok');
      setTimeout(loadStatus, 800);
    } else {
      acState.on = !expectOn;
      paintAc();
      setAcHint((expectOn ? '空调没有开启：' : '空调没有关闭：') + desc, false);
      toast((expectOn ? '空调没有开启：' : '空调没有关闭：') + desc, 'err');
    }
  } catch (e) {
    acState.pending = null;
    paintAc();
    const msg = e.message || '空调操作失败';
    const auth = /登录|授权|token|过期|失效|expired/i.test(msg);
    setAcHint(auth ? '' : '空调操作失败：' + msg, auth);
    toast(auth ? '开放平台授权失效，请重新登录' : '空调操作失败', 'err');
  } finally {
    p.disabled = false;
  }
}

function bindAc() {
  $('ac-power').addEventListener('click', toggleAc);
  $('ac-hint').addEventListener('click', showAcDiag);
  $('diag-x').addEventListener('click', () => $('diag-sheet').classList.remove('show'));
  paintAc();
}


// ---------------- 我的轨迹 ----------------
function ymd(d) {
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
let tripDay = new Date();

function hm(t) { return t ? t.split(' ')[1].slice(0, 5) : '--'; }

function renderTrips(list, dayStr) {
  const bd = $('trip-bd');
  $('trip-date').textContent = dayStr;
  $('trip-next').disabled = dayStr >= ymd(new Date());

  if (!list.length) {
    bd.innerHTML = '<div class="trip-empty">这一天没有行驶记录</div>';
    return;
  }
  const km = list.reduce((a, r) => a + (r.mileage || 0), 0);
  const min = list.reduce((a, r) => a + (r.spendTime || 0), 0);
  const oil = list.reduce((a, r) => a + (r.oil || 0), 0);
  const hh = Math.floor(min / 60), mm = Math.round(min % 60);
  const dur = hh > 0 ? `${hh}<small>h</small>${String(mm).padStart(2, '0')}` : `${mm}<small>min</small>`;

  bd.innerHTML = `
    <div class="trip-sum">
      <div><b>${km.toFixed(1)}<small>km</small></b><span>行驶里程</span></div>
      <div><b>${dur}</b><span>驾驶时长</span></div>
      <div><b>${list.length}<small>次</small></b><span>行程</span></div>
    </div>
    ${list.map(r => `
      <div class="trip-item">
        <div class="tt"><b>${hm(r.startTime)} - ${hm(r.endTime)}</b><span>${(r.oil || 0).toFixed(1)} L</span></div>
        <div class="route">${r.startAddressName || '未知'} <i>→</i> ${r.endAddressName || '未知'}</div>
        <div class="meta">
          <span>里程 <b>${r.mileage}</b> km</span>
          <span>均速 <b>${Math.round(r.avrgSpeed || 0)}</b> km/h</span>
          <span>评分 <b>${r.score || 0}</b></span>
        </div>
      </div>`).join('')}`;
}

async function loadTrips() {
  const dayStr = ymd(tripDay);
  $('trip-bd').innerHTML = '<div class="trip-empty">加载中…</div>';
  $('trip-date').textContent = dayStr;
  try {
    const list = await api.trips(dayStr, dayStr);
    renderTrips(list, dayStr);
    return list;
  } catch (e) {
    $('trip-bd').innerHTML = '<div class="trip-empty">读取失败：' + e.message + '</div>';
    return null;
  }
}

async function refreshTripSummary() {
  try {
    const list = await api.trips(ymd(new Date()), ymd(new Date()));
    if (!list.length) { $('trip-sub').textContent = '今天还没有行驶记录'; return; }
    const km = list.reduce((a, r) => a + (r.mileage || 0), 0);
    $('trip-sub').textContent = `今天 ${list.length} 次 · ${km.toFixed(1)} km`;
  } catch (e) {
    $('trip-sub').textContent = '点击查看';
  }
}

function bindTrips() {
  $('card-trip').addEventListener('click', () => {
    $('trip-sheet').classList.add('show');
    loadTrips();
  });
  $('trip-x').addEventListener('click', () => $('trip-sheet').classList.remove('show'));
  $('trip-prev').addEventListener('click', () => {
    tripDay.setDate(tripDay.getDate() - 1); loadTrips();
  });
  $('trip-next').addEventListener('click', () => {
    const n = new Date(tripDay); n.setDate(n.getDate() + 1);
    if (n > new Date()) return;
    tripDay = n; loadTrips();
  });
}


// ---------------- 操作记录 ----------------
const CMD_CN = {
  UnLockDoor: '车辆解锁', LockDoor: '锁车', OpenWindow: '打开车窗', CloseWindow: '关闭车窗',
  WindowSlit: '车窗留缝', SkyWindowLiftUp: '天窗翘起', OpenDormer: '天窗全开', CloseDormer: '关天窗',
  OpenEngine: '启动发动机', CloseEngine: '关闭发动机',
  openair: '开空调', closeair: '关空调', openAir: '开空调', closeAir: '关空调',
  FlashLight: '闪灯', RemoteSearchCar: '寻车',
  photograph: '车外拍照', OpenTrunk: '开后备箱',
};

function renderLog(list) {
  const bd = $('log-bd');
  if (!list.length) { bd.innerHTML = '<div class="trip-empty">还没有操作记录</div>'; return; }
  bd.innerHTML = list.map(r => {
    const ok = r.handleStatus === 'Completed';
    const t = (r.cmdSendTime || '').replace('.0', '').slice(5, 16).replace('-', '/');
    const cmd = CMD_CN[r.tboxCmd] || r.tboxCmd || '未知指令';
    const desc = r.resultDesc || (ok ? '指令执行成功' : r.handleStatus || '');
    return `<div class="log-item">
      <div class="log-dot${ok ? '' : ' bad'}"></div>
      <div class="log-main">
        <div class="log-top"><span class="log-cmd">${cmd}</span><span class="log-time">${t}</span></div>
        <div class="log-desc">${desc}</div>
      </div>
    </div>`;
  }).join('');
}

async function loadLog() {
  $('log-bd').innerHTML = '<div class="trip-empty">加载中…</div>';
  try {
    const list = await api.actions(0, 30);
    renderLog(list);
    if (list.length) {
      const bad = list.filter(r => r.handleStatus !== 'Completed').length;
      $('log-sub').textContent = `最近 ${list.length} 条 · ${bad ? bad + ' 条失败' : '全部成功'}`;
    }
  } catch (e) {
    $('log-bd').innerHTML = '<div class="trip-empty">读取失败：' + e.message + '</div>';
  }
}

function bindLog() {
  $('card-log').addEventListener('click', () => {
    $('log-sheet').classList.add('show');
    loadLog();
  });
  $('log-x').addEventListener('click', () => $('log-sheet').classList.remove('show'));
}


// ---------------- 车辆位置 ----------------
const DIRS = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
let locCache = null;

function dirName(deg) {
  const d = ((deg % 360) + 360) % 360;
  return DIRS[Math.round(d / 45) % 8];
}

function paintLoc(d) {
  locCache = d;
  $('loc-addr').textContent = d.addrDesc || '未知位置';
  $('loc-lng').textContent = Number(d.lng).toFixed(5);
  $('loc-lat').textContent = Number(d.lat).toFixed(5);
  $('loc-speed').textContent = Math.round(d.speed || 0) + ' km/h';
  $('loc-head').textContent = dirName(d.heading || 0);
  $('loc-time').textContent = '定位时间 ' + (d.gpsTime || '--');
  if (d.addrDesc) $('loc-sub').textContent = d.addrDesc;
}

async function loadLocation() {
  try {
    const d = await api.location();
    paintLoc(d);
  } catch (e) {
    $('loc-addr').textContent = '定位失败：' + e.message;
  }
}

function bindLoc() {
  $('card-loc').addEventListener('click', () => {
    $('loc-sheet').classList.add('show');
    if (!locCache) loadLocation();
  });
  $('loc-x').addEventListener('click', () => $('loc-sheet').classList.remove('show'));
  $('loc-open').addEventListener('click', () => {
    if (locCache) api.openMap(locCache.lat, locCache.lng);
    else toast('还没拿到定位', 'err');
  });
}

// ---------------- 启动 ----------------
// ---------------- 更新提示 ----------------
// 版本信息来自 Gitee / jsDelivr 上的 version.json，拉不到就静默跳过
async function checkUpdate(curCode) {
  if (checkUpdate.done) return;
  checkUpdate.done = true;
  let info;
  try {
    const raw = await api.updateInfo();
    if (!raw) return;
    info = JSON.parse(raw);
  } catch (e) {
    return;
  }
  if (!info || !info.code || !info.url) return;
  if (Number(info.code) <= Number(curCode || 0)) return;
  showUpdateBar(info);
}

function showUpdateBar(info) {
  if (document.getElementById('upd-bar')) return;
  const bar = document.createElement('div');
  bar.id = 'upd-bar';
  bar.style.cssText = 'position:fixed;left:12px;right:12px;top:12px;z-index:9999;' +
    'background:linear-gradient(135deg,#2E7DFF,#1B5FD9);color:#fff;border-radius:14px;' +
    'padding:12px 14px;box-shadow:0 8px 24px rgba(0,0,0,.45);font-size:14px;' +
    'display:flex;align-items:center;gap:10px;';
  const extra = info.code_text ? ' · ' + info.code_text : '';
  bar.innerHTML =
    '<div style="flex:1;line-height:1.35;min-width:0">' +
      '<b>有新版本 ' + (info.version || '') + '</b>' +
      '<div style="opacity:.85;font-size:12px;margin-top:2px;overflow:hidden;text-overflow:ellipsis">' +
        (info.note || '点击前往网盘下载') + extra + '</div>' +
    '</div>' +
    '<button id="upd-go" style="flex:none;background:#fff;color:#1B5FD9;border:0;border-radius:9px;' +
      'padding:8px 14px;font-size:13px;font-weight:600">去下载</button>' +
    '<span id="upd-x" style="flex:none;opacity:.75;padding:4px 6px;font-size:16px">✕</span>';
  document.body.appendChild(bar);
  bar.querySelector('#upd-go').onclick = () => {
    try { Native.openUrl(info.url); } catch (e) { toast('打不开链接', 'err'); }
  };
  bar.querySelector('#upd-x').onclick = () => bar.remove();
}

function showApp(st) {
  $('login').classList.add('hidden');
  $('app').classList.remove('hidden');
  document.body.classList.remove('booting');
  $('car-name').textContent = (st && st.seriesName) ? st.seriesName : '逸动 PLUS';
  renderGrid();
  applyVisibility();
  paintSwitches();
  loadStatus();
  startAutoRefresh();
  if (showSec('pano')) loadPhotos();
  if (showSec('trip')) refreshTripSummary();
  if (showSec('loc')) loadLocation();
}

function showLogin() {
  $('app').classList.add('hidden');
  $('login').classList.remove('hidden');
  document.body.classList.remove('booting');
}

function bindLogin() {
  $('btn-code').addEventListener('click', async () => {
    const phone = $('phone').value.trim();
    if (phone.length !== 11) return toast('请输入 11 位手机号', 'err');
    $('btn-code').textContent = '发送中…';
    try {
      await api.sendCode(phone);
      toast('验证码已发送', 'ok');
      $('btn-code').textContent = '已发送';
    } catch (e) {
      toast('发送失败：' + e.message, 'err');
      $('btn-code').textContent = '获取验证码';
    }
  });

  $('btn-login').addEventListener('click', async () => {
    const phone = $('phone').value.trim();
    const code = $('code').value.trim();
    if (phone.length !== 11 || code.length < 4) return toast('请填写手机号和验证码', 'err');
    const b = $('btn-login');
    b.disabled = true; b.textContent = '登录中…';
    try {
      const name = await api.login(phone, code);
      b.disabled = false; b.textContent = '登录并绑定车辆';
      toast('登录成功：' + name, 'ok');
      showApp(api.state());
    } catch (e) {
      b.disabled = false; b.textContent = '登录并绑定车辆';
      toast('登录失败：' + e.message, 'err');
    }
  });
}

function bindApp() {
  $('btn-refresh').addEventListener('click', refreshVehicle);
  $('grid-sort').addEventListener('click', () => setSortMode(!sortMode));
  $('picker-x').addEventListener('click', closePicker);
  $('act-picker').addEventListener('click', e => { if (e.target.id === 'act-picker') closePicker(); });
  $('picker-bd').addEventListener('click', e => {
    const row = e.target.closest('.pk-row');
    if (row) addAction(row.dataset.cmd);
  });
  $('btn-logout').addEventListener('click', e => {
    e.preventDefault();
    api.logout();
    showLogin();
    toast('已退出登录');
  });
  $('btn-more').addEventListener('click', () => {
    renderModelSheet();
    $('model-sheet').classList.add('show');
  });
  $('model-x').addEventListener('click', () => $('model-sheet').classList.remove('show'));
  $('card-loc').addEventListener('click', () => {
    const t = $('loc-sub').textContent.split(' · ')[0].split(', ');
    if (t.length === 2) api.openMap(parseFloat(t[0]), parseFloat(t[1]));
  });
}

// 老版本登录过的用户本地没有车型编码，补拉一次；车型变了就重载页面
async function syncCarMeta() {
  const st = hasNative ? api.state() : {};
  if (!st.loggedIn || st.seriesCode) return;
  let done = false;
  try { done = sessionStorage.getItem('icar.metaSynced') === '1'; } catch (e) {}
  if (done) return;
  try { sessionStorage.setItem('icar.metaSynced', '1'); } catch (e) {}
  try {
    const fresh = await api.carMeta();
    const key = detectModelKey(fresh.seriesCode);
    const m = key && byKey(key);
    if (m && window.CAR_MODEL_FILE !== '3D/' + m.file) location.reload();
  } catch (e) {}
}

function start() {
  const st = hasNative ? api.state() : { loggedIn: false };
  if (st.loggedIn) { showApp(st); syncCarMeta(); checkUpdate(st.versionCode); } else showLogin();
}

function bindGate() {
  const inp = $('gate-input'), btn = $('gate-btn');

  // 设置里「我的抖音主页」跳转
  const dyHome = $('dy-home');
  if (dyHome) dyHome.addEventListener('click', () => {
    try { Native.openUrl('https://v.douyin.com/V-ceQdCsRA4/'); }
    catch (e) { toast('没有可以打开抖音的应用', 'err'); }
  });

  // 抖音主页：只放一个按钮，链接不外露
  const dy = $('gate-douyin');
  if (dy) dy.addEventListener('click', () => {
    try { Native.openUrl('https://v.douyin.com/V-ceQdCsRA4/'); }
    catch (e) { toast('没有可以打开抖音的应用', 'err'); }
  });

  inp.addEventListener('input', () => {
    btn.disabled = inp.value.trim() !== '我同意';
  });
  btn.addEventListener('click', () => {
    if (inp.value.trim() !== '我同意') return;
    try { if (hasNative) Native.accept(); } catch (e) {}
    $('gate').classList.remove('show');
    start();
  });
}


// ---------------- 外观 / 主题 ----------------
const TH = {
  bgBlur:    ['icar.bgBlur', '0'],
  bgDim:     ['icar.bgDim', '0'],
  cardStyle: ['icar.cardStyle', 'glass'],
  cardAlpha: ['icar.cardAlpha', '6'],
  cardRadius:['icar.cardRadius', '22'],
  cardShadow:['icar.cardShadow', '25'],
  cardColor: ['icar.cardColor', '#FFFFFF'],
  txtColor:  ['icar.txtColor', '#FFFFFF'],
  iconColor: ['icar.iconColor', '#FFFFFF'],
  accent:    ['icar.accent', '#2456E6'],
  bgImg:     ['icar.bgImg', ''],
  bgPreset:  ['icar.bgPreset', ''],
  bgImgV:    ['icar.bgImgV', ''],
};

// 内置主题：背景图 + 配色（按图片风格配的）
const THEMES = [
  { id: 'sakura',   name: '樱粉',  accent: '#E75480', icon: '#FFD6E7', dim: 38, blur: 3 },
  { id: 'sand',     name: '暖砂',  accent: '#C9A063', icon: '#F0E2CE', dim: 42, blur: 4 },
  { id: 'ink',      name: '墨灰',  accent: '#9AA0AC', icon: '#D8DCE3', dim: 18, blur: 2 },
  { id: 'sky',      name: '晴空',  accent: '#4A90D9', icon: '#CFE2F7', dim: 36, blur: 3 },
  { id: 'sapphire', name: '宝石',  accent: '#3D6BE0', icon: '#C9D8FF', dim: 22, blur: 2 },
  { id: 'blush',    name: '藕粉',  accent: '#D97F94', icon: '#F5D9DF', dim: 32, blur: 3 },
  { id: 'snow',     name: '冬夜',  accent: '#F0B429', icon: '#FFE6AE', dim: 16, blur: 2 },
  { id: 'azure',    name: '青空',  accent: '#35A8E0', icon: '#CDEBFA', dim: 34, blur: 3 },
  { id: 'deep',     name: '深海',  accent: '#10A5B8', icon: '#C2EDF3', dim: 18, blur: 2 },
];

/** 套用一个内置主题 */
function applyPreset(id) {
  const t = THEMES.find(x => x.id === id);
  if (!t) return;
  thSet('bgPreset', t.id);
  thSet('bgImg', '');          // 预设和自选图二选一
  thSet('accent', t.accent);
  thSet('iconColor', t.icon);
  thSet('txtColor', '#FFFFFF');
  thSet('bgDim', t.dim);
  thSet('bgBlur', t.blur);
  applyTheme();
  syncThemeUI();
  renderThemeGrid();
  toast('已切换主题：' + t.name, 'ok');
}

/** 渲染主题选择格子 */
function renderThemeGrid() {
  const box = $('theme-grid');
  if (!box) return;
  const cur = thGet('bgPreset');
  box.innerHTML = '';
  THEMES.forEach(t => {
    const d = document.createElement('div');
    d.className = 'th-item' + (cur === t.id ? ' on' : '');
    d.innerHTML = '<div class="th-thumb" style="background-image:url(\'bg/' + t.id + '.jpg\')">' +
                  '<i style="background:' + t.accent + '"></i></div>' +
                  '<span>' + t.name + '</span>';
    d.onclick = () => applyPreset(t.id);
    box.appendChild(d);
  });
}

const thGet = k => store.get(TH[k][0], TH[k][1]);
const thSet = (k, v) => store.set(TH[k][0], String(v));

function hx2rgb(hex) {
  let h = String(hex || '#FFFFFF').replace('#', '');
  if (h.length === 3) h = h.split('').map(c => c + c).join('');
  const n = parseInt(h, 16);
  if (isNaN(n)) return [255, 255, 255];
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
const hx2str = hex => hx2rgb(hex).join(',');
const hx2rgba = (hex, a) => `rgba(${hx2str(hex)},${a})`;
function hxLight(hex, t) {
  const [r, g, b] = hx2rgb(hex);
  const f = v => Math.round(v + (255 - v) * t);
  return '#' + [f(r), f(g), f(b)].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
}

/** 把当前主题写进 CSS 变量 */
function applyTheme() {
  const root = document.documentElement;
  const cc = thGet('cardColor'), tc = thGet('txtColor'), ac = thGet('accent');
  const ca = Math.max(0, Math.min(100, +thGet('cardAlpha') || 0)) / 100;
  const radius = Math.max(0, Math.min(34, +thGet('cardRadius') || 0));

  root.style.setProperty('--card-rgb', hx2str(cc));
  root.style.setProperty('--card', hx2rgba(cc, ca));
  root.style.setProperty('--card-b', hx2rgba(cc, Math.min(1, ca + 0.03)));
  root.style.setProperty('--accent-rgb', hx2str(ac));
  root.style.setProperty('--accent', ac);
  root.style.setProperty('--accent-2', hxLight(ac, 0.34));
  root.style.setProperty('--txt', tc);
  root.style.setProperty('--txt-2', hx2rgba(tc, 0.62));
  root.style.setProperty('--txt-3', hx2rgba(tc, 0.38));
  root.style.setProperty('--icon', thGet('iconColor'));
  const sh = Math.max(0, Math.min(100, +thGet('cardShadow') || 0)) / 100;
  root.style.setProperty('--sh', String(sh));
  root.style.setProperty('--r', radius + 'px');

  const style = thGet('cardStyle');
  document.body.classList.toggle('glass', style !== 'clear');
  document.body.classList.toggle('clear', style === 'clear');

  const preset = thGet('bgPreset');
  const hasBg = !!thGet('bgImg') || !!preset;
  const blur = Math.max(0, Math.min(24, +thGet('bgBlur') || 0));
  const dim = Math.max(0, Math.min(85, +thGet('bgDim') || 0));
  document.body.classList.toggle('custombg', hasBg);
  const layer = $('bg-img');
  if (layer) {
    if (hasBg) {
      layer.style.backgroundImage = preset
        ? `url("bg/${preset}.jpg")`
        : `url("__bg.jpg?v=${thGet('bgImgV') || 0}")`;
      layer.style.filter = blur > 0 ? `blur(${blur}px)` : '';
    } else {
      layer.style.backgroundImage = '';
      layer.style.filter = '';
    }
  }
  const dimEl = $('bg-shade');
  if (dimEl) dimEl.style.opacity = String(dim / 100);
}

/** 把偏好里的值同步回面板控件 */
function syncThemeUI() {
  const blur = $('bg-blur'), dim = $('bg-dim'), ca = $('card-alpha'), cr = $('card-radius'), cs = $('card-shadow');
  if (!blur) return;
  blur.value = thGet('bgBlur');  $('bg-blur-v').textContent = thGet('bgBlur');
  dim.value = thGet('bgDim');    $('bg-dim-v').textContent = thGet('bgDim') + '%';
  ca.value = thGet('cardAlpha'); $('card-alpha-v').textContent = thGet('cardAlpha') + '%';
  cr.value = thGet('cardRadius');$('card-radius-v').textContent = thGet('cardRadius') + 'px';
  cs.value = thGet('cardShadow'); $('card-shadow-v').textContent = thGet('cardShadow') + '%';
  const st = thGet('cardStyle');
  document.querySelectorAll('.chip[data-style]').forEach(c => c.classList.toggle('on', c.dataset.style === st));
  $('sw-card').style.background = thGet('cardColor');
  $('sw-text').style.background = thGet('txtColor');
  $('sw-icon').style.background = thGet('iconColor');
  $('sw-accent').style.background = thGet('accent');
}

// ---------- 色盘 ----------
let cpState = null;

function hsv2rgb(h, s, v) {
  h = ((h % 360) + 360) % 360;
  const c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c;
  let r = 0, g = 0, b = 0;
  if (h < 60) { r = c; g = x; }
  else if (h < 120) { r = x; g = c; }
  else if (h < 180) { g = c; b = x; }
  else if (h < 240) { g = x; b = c; }
  else if (h < 300) { r = x; b = c; }
  else { r = c; b = x; }
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

function rgb2hex(r, g, b) {
  return '#' + [r, g, b].map(v => Math.max(0, Math.min(255, v | 0)).toString(16).padStart(2, '0'))
    .join('').toUpperCase();
}

function hex2hsv(hex) {
  const [r0, g0, b0] = hx2rgb(hex);
  const r = r0 / 255, g = g0 / 255, b = b0 / 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) {
    if (mx === r) h = 60 * (((g - b) / d) % 6);
    else if (mx === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  return { h, s: mx ? d / mx : 0, v: mx };
}

const cpHex = () => rgb2hex(...hsv2rgb(cpState.h, cpState.s, cpState.v));

function cpDrawSV() {
  const c = $('cp-sv'); if (!c) return;
  const ctx = c.getContext('2d'), w = c.width, h = c.height;
  const base = hsv2rgb(cpState.h, 1, 1);
  ctx.fillStyle = `rgb(${base.join(',')})`;
  ctx.fillRect(0, 0, w, h);
  let g = ctx.createLinearGradient(0, 0, w, 0);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,1)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  const x = cpState.s * w, y = (1 - cpState.v) * h;
  ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2);
  ctx.strokeStyle = 'rgba(0,0,0,.55)'; ctx.lineWidth = 3; ctx.stroke();
  ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2);
  ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke();
}

function cpDrawHue() {
  const c = $('cp-hue'); if (!c) return;
  const ctx = c.getContext('2d'), w = c.width, h = c.height;
  const g = ctx.createLinearGradient(0, 0, w, 0);
  for (let i = 0; i <= 6; i++) g.addColorStop(i / 6, `rgb(${hsv2rgb(i * 60, 1, 1).join(',')})`);
  ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  const x = Math.max(4, Math.min(w - 4, (cpState.h / 360) * w));
  ctx.beginPath(); ctx.arc(x, h / 2, h / 2 - 1, 0, Math.PI * 2);
  ctx.fillStyle = '#fff'; ctx.fill();
  ctx.beginPath(); ctx.arc(x, h / 2, h / 2 - 3.5, 0, Math.PI * 2);
  ctx.fillStyle = `rgb(${hsv2rgb(cpState.h, 1, 1).join(',')})`; ctx.fill();
}

function cpRefresh() {
  const hex = cpHex();
  $('cp-prev').style.background = hex;
  $('cp-hex').value = hex;
  cpDrawSV(); cpDrawHue();
}

function cpBind(el, fn) {
  let down = false;
  const at = e => {
    const r = el.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)),
      y: Math.max(0, Math.min(1, (e.clientY - r.top) / r.height))
    };
  };
  el.addEventListener('pointerdown', e => { down = true; try { el.setPointerCapture(e.pointerId); } catch (x) {} fn(at(e)); e.preventDefault(); });
  el.addEventListener('pointermove', e => { if (down) { fn(at(e)); e.preventDefault(); } });
  el.addEventListener('pointerup', () => { down = false; });
  el.addEventListener('pointercancel', () => { down = false; });
}

function openColorPicker(title, hex, cb) {
  const hsv = hex2hsv(hex);
  cpState = { h: hsv.h, s: hsv.s, v: hsv.v, cb };
  $('cp-title').textContent = title;
  $('cp').classList.add('show');
  cpRefresh();
}

function closeColorPicker() { $('cp').classList.remove('show'); cpState = null; }

// ---------- 背景图片 ----------
function pickBg() {
  if (!hasNative) return toast('仅手机端可用');
  invoke(id => Native.pickBg(id)).then(() => {
    thSet('bgImg', '1');
    thSet('bgImgV', String(Date.now()));
    thSet('bgPreset', '');        // 自选图和预设二选一
    renderThemeGrid();
    applyTheme();
    toast('背景已更换', 'ok');
  }).catch(e => toast('换背景失败：' + e.message, 'err'));
}

function clearBg() {
  thSet('bgImg', '');
  thSet('bgImgV', '');
  thSet('bgPreset', '');
  if (hasNative) { try { Native.clearBg(); } catch (e) {} }
  applyTheme();
}

function resetTheme() {
  Object.keys(TH).forEach(k => store.del(TH[k][0]));
  clearBg();
  applyTheme();
  syncThemeUI();
  renderThemeGrid();
  toast('已恢复默认外观', 'ok');
}

function bindTheme() {
  renderThemeGrid();
  $('bg-pick').addEventListener('click', pickBg);
  $('bg-clear').addEventListener('click', () => { clearBg(); toast('已恢复默认背景'); });
  $('theme-reset').addEventListener('click', resetTheme);
  $('theme-x').addEventListener('click', () => $('theme-sheet').classList.remove('show'));

  $('bg-blur').addEventListener('input', e => {
    thSet('bgBlur', e.target.value); $('bg-blur-v').textContent = e.target.value; applyTheme();
  });
  $('bg-dim').addEventListener('input', e => {
    thSet('bgDim', e.target.value); $('bg-dim-v').textContent = e.target.value + '%'; applyTheme();
  });
  $('card-alpha').addEventListener('input', e => {
    thSet('cardAlpha', e.target.value); $('card-alpha-v').textContent = e.target.value + '%'; applyTheme();
  });
  $('card-radius').addEventListener('input', e => {
    thSet('cardRadius', e.target.value); $('card-radius-v').textContent = e.target.value + 'px'; applyTheme();
  });
  $('card-shadow').addEventListener('input', e => {
    thSet('cardShadow', e.target.value); $('card-shadow-v').textContent = e.target.value + '%'; applyTheme();
  });
  document.querySelectorAll('.chip[data-style]').forEach(c => {
    c.addEventListener('click', () => {
      thSet('cardStyle', c.dataset.style);
      document.querySelectorAll('.chip[data-style]').forEach(x => x.classList.toggle('on', x === c));
      applyTheme();
    });
  });

  const sw = { card: ['卡片颜色', 'cardColor', 'sw-card'], text: ['字体颜色', 'txtColor', 'sw-text'], icon: ['图标颜色', 'iconColor', 'sw-icon'], accent: ['强调色', 'accent', 'sw-accent'] };
  document.querySelectorAll('.th-row[data-color]').forEach(row => {
    row.addEventListener('click', () => {
      const conf = sw[row.dataset.color];
      if (!conf) return;
      openColorPicker(conf[0], thGet(conf[1]), hex => {
        thSet(conf[1], hex);
        $(conf[2]).style.background = hex;
        applyTheme();
      });
    });
  });

  // 色盘交互
  cpBind($('cp-sv'), p => { cpState.s = p.x; cpState.v = 1 - p.y; cpRefresh(); });
  cpBind($('cp-hue'), p => { cpState.h = p.x * 360; cpRefresh(); });
  $('cp-hex').addEventListener('input', e => {
    const v = e.target.value.trim();
    if (/^#?[0-9a-fA-F]{6}$/.test(v)) {
      const hsv = hex2hsv(v.startsWith('#') ? v : '#' + v);
      cpState.h = hsv.h; cpState.s = hsv.s; cpState.v = hsv.v;
      cpDrawSV(); cpDrawHue();
      $('cp-prev').style.background = cpHex();
    }
  });
  $('cp-cancel').addEventListener('click', closeColorPicker);
  $('cp-ok').addEventListener('click', () => {
    const cb = cpState && cpState.cb, hex = cpState ? cpHex() : '';
    closeColorPicker();
    if (cb) cb(hex);
  });
  $('cp').addEventListener('click', e => { if (e.target.id === 'cp') closeColorPicker(); });
}

applyTheme();

// ---------------- 返回键：先关最上层的二级面板 ----------------
// 原生 MainActivity 会先问这里：返回 true 表示已经关掉一层，false 才退回桌面
window.__back = function () {
  const shown = id => { const n = $(id); return !!(n && n.classList.contains('show')); };
  if (shown('confirm')) { if (cfResolve) cfResolve(false); return true; }
  if (shown('act-picker')) { closePicker(); return true; }
  if (shown('cp')) { closeColorPicker(); return true; }
  if (shown('theme-sheet')) { $('theme-sheet').classList.remove('show'); return true; }
  if (shown('lightbox')) { $('lightbox').classList.remove('show'); return true; }
  // 所有二级弹层都关一遍；漏一个就会按返回键直接退出 App
  const sheets = ['sheet', 'trip-sheet', 'log-sheet', 'loc-sheet', 'diag-sheet',
                  'model-sheet', 'ntf-sheet', 'pin-sheet', 'raw-sheet', 'tank-sheet', 'check-sheet'];
  for (let i = sheets.length - 1; i >= 0; i--) {
    if (shown(sheets[i])) { $(sheets[i]).classList.remove('show'); return true; }
  }
  // 兜底：还有没列到的 .sheet 开着，关掉最上面那个
  const open = document.querySelectorAll('.sheet.show');
  if (open.length) { open[open.length - 1].classList.remove('show'); return true; }
  if (moreOpen) { setMore(false); return true; }
  if (sortMode) { setSortMode(false); return true; }
  return false;
};

(function boot() {
  renderGrid();
  bindLogin();
  bindApp();
  bindGrab();
  bindCards();
  bindRaw();
  bindPin();
  bindDataSource();
  bindTank();
  bindCheck();
  bindRefresh();
  bindSettings();
  bindTheme();
  bindConfirm();
  paintSwitches();
  applyVisibility();
  bindPano();
  bindAc();
  bindTrips();
  bindLog();
  bindLoc();
  bindGate();
  let ok = false;
  try { ok = hasNative && Native.accepted(); } catch (e) { ok = false; }
  if (!ok) $('gate').classList.add('show');
  else start();
})();
