/* 俯视标注层：四个轮胎的胎压 + 机盖电压
   只在俯视角度显示，位置由 3D 坐标实时投影，随旋转/缩放自动跟随。 */
(function () {
  'use strict';

  const MESH = {
    fl: 'GlossyMetal_Wheel_FL',
    fr: 'GlossyMetal_Wheel_FR',
    rear: 'GlossyMetal_Wheel_B',
    hood: 'CarPaint_EngineDoor_Ext'
  };

  // 胎压正常区间（kPa），超出高亮提醒
  const TIRE_MIN = 200;
  const TIRE_MAX = 300;
  const VOLT_LOW = 11.8;

  const data = { voltage: 0, tireFL: 0, tireFR: 0, tireRL: 0, tireRR: 0 };

  let root = null;
  let nodes = null;
  let anchors = null;
  let raf = 0;
  let viewer = null;

  // ---------- 锚点 ----------
  function boxOf(model, name) {
    const b = new THREE.Box3();
    let hit = false;
    model.traverse(c => {
      if (c.isMesh && c.name === name) { b.expandByObject(c); hit = true; }
    });
    return hit ? b : null;
  }

  function buildAnchors(v) {
    const model = v && v.model;
    if (!model) return false;
    const fl = boxOf(model, MESH.fl);
    const fr = boxOf(model, MESH.fr);
    const re = boxOf(model, MESH.rear);
    if (!fl || !fr || !re) return false;

    const center = b => b.getCenter(new THREE.Vector3());
    const flc = center(fl), frc = center(fr), rec = center(re);
    const hd = boxOf(model, MESH.hood);

    anchors = {
      fl: flc.clone(),
      fr: frc.clone(),
      rl: new THREE.Vector3(flc.x, rec.y, rec.z),
      rr: new THREE.Vector3(frc.x, rec.y, rec.z),
      // 机盖取中心略靠前一点，指向发动机舱
      hood: hd ? center(hd) : new THREE.Vector3(0, rec.y + 0.7, flc.z + 0.3)
    };
    return true;
  }

  // ---------- DOM ----------
  function build() {
    root = document.getElementById('overlay');
    if (!root) return false;
    root.innerHTML = '';
    nodes = {};

    const mk = (key, cls, html) => {
      const el = document.createElement('div');
      el.className = 'tp ' + cls;
      el.dataset.k = key;
      el.innerHTML = `<span class="ln"></span><span class="box">${html}</span>`;
      root.appendChild(el);
      nodes[key] = el;
      return el;
    };

    mk('fl', 'left', '--<small>kPa</small>');
    mk('fr', 'right', '--<small>kPa</small>');
    mk('rl', 'left', '--<small>kPa</small>');
    mk('rr', 'right', '--<small>kPa</small>');
    mk('hood', 'up volt', '--<small>V</small>');
    paint();
    return true;
  }

  // ---------- 数值 ----------
  function paint() {
    if (!nodes) return;
    const tire = (key, raw) => {
      const el = nodes[key];
      const p = Number(raw) || 0;
      const box = el.querySelector('.box');
      if (p <= 0) {
        box.innerHTML = '--<small>kPa</small>';
        box.classList.remove('warn');
        return;
      }
      box.innerHTML = `${Math.round(p)}<small>kPa</small>`;
      box.classList.toggle('warn', p < TIRE_MIN || p > TIRE_MAX);
    };
    tire('fl', data.tireFL);
    tire('fr', data.tireFR);
    tire('rl', data.tireRL);
    tire('rr', data.tireRR);

    const v = Number(data.voltage) || 0;
    const vbox = nodes.hood.querySelector('.box');
    if (v <= 0) {
      vbox.innerHTML = '--<small>V</small>';
      vbox.classList.remove('warn');
    } else {
      vbox.innerHTML = `${v.toFixed(1)}<small>V</small>`;
      vbox.classList.toggle('warn', v < VOLT_LOW);
    }
  }

  // ---------- 逐帧投影 ----------
  const tmp = new THREE.Vector3();

  function layout() {
    const v = viewer || window.vehicle3D;
    if (!v || !v.model || !v.camera || !nodes) return;
    if (!anchors && !buildAnchors(v)) return;

    const canvas = v.canvas;
    const W = canvas.clientWidth || canvas.width;
    const H = canvas.clientHeight || canvas.height;
    if (!W || !H) return;

    Object.keys(anchors).forEach(key => {
      const el = nodes[key];
      if (!el) return;
      tmp.copy(anchors[key]).project(v.camera);
      el.style.left = ((tmp.x * 0.5 + 0.5) * W).toFixed(1) + 'px';
      el.style.top = ((-tmp.y * 0.5 + 0.5) * H).toFixed(1) + 'px';
    });
  }

  function tick() {
    raf = requestAnimationFrame(tick);
    layout();
  }

  // ---------- 对外 ----------
  window.CarOverlay = {
    set(d) {
      if (!d) return;
      data.voltage = d.voltage || 0;
      data.tireFL = d.tireFL || 0;
      data.tireFR = d.tireFR || 0;
      data.tireRL = d.tireRL || 0;
      data.tireRR = d.tireRR || 0;
      paint();
    },
    show(v) {
      viewer = v || window.vehicle3D;
      if (!viewer) return;
      if (!nodes && !build()) return;
      anchors = null;
      buildAnchors(viewer);
      layout();
      root.classList.add('show');
      if (!raf) raf = requestAnimationFrame(tick);
    },
    hide() {
      if (root) root.classList.remove('show');
      if (raf) { cancelAnimationFrame(raf); raf = 0; }
    }
  };
})();
