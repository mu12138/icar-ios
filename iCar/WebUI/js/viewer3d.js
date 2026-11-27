// 转速展示：超出合理范围（16383/65535 之类占位值）就显示 --
function rpmText(v) {
  const n = +v || 0;
  return (n > 12000 || n <= 0) ? '--' : Math.round(n) + ' rpm';
}

// 3D 车辆查看器 - 按照模型渲染差异说明配置
        class Vehicle3DViewer {
            constructor(canvas) {
                this.canvas = canvas;
                this.scene = new THREE.Scene();
                this.mixer = null;
                this.animations = {};
                this.model = null;
                this._wheelLabelsDirty = true;
                this._lastWheelUpdateTime = 0;
                this.raycaster = new THREE.Raycaster();
                this.mouse = new THREE.Vector2();
                
                // 渲染器配置
                this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
                this.renderer.setSize(canvas.clientWidth, canvas.clientHeight);
                this.renderer.setPixelRatio(window.devicePixelRatio);
                this.renderer.setClearColor(0xffffff, 0);
                this.renderer.outputColorSpace = THREE.SRGBColorSpace;
                this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
                this.renderer.toneMappingExposure = 1.0;
                // 阴影常开（只有车内聚光会投射，车外没光源投射，几乎不额外花钱）
                this.renderer.shadowMap.enabled = true;
                this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
                
                // 相机配置 - 根据容器尺寸自适应
                const aspect = canvas.clientWidth / canvas.clientHeight;
                this.camera = new THREE.PerspectiveCamera(10, aspect, 0.3, 100);
                // 根据容器尺寸计算相机距离
                const baseDistance = 28;
                this.cameraDistance = baseDistance / Math.min(aspect, 1);
                this.camera.position.set(this.cameraDistance * 0.68, this.cameraDistance * 0.08, this.cameraDistance * 0.71);
                this.camera.lookAt(0, 0, 0);
                
                // 灯光系统 - 适度亮度
                this.ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
                this.scene.add(this.ambientLight);
                
                const directionalLight = new THREE.DirectionalLight(0xffffff, 0.6);
                directionalLight.position.set(0, 10, 0);
                this.scene.add(directionalLight);
                
                const directionalLight2 = new THREE.DirectionalLight(0xffffff, 0.3);
                directionalLight2.position.set(5, 5, 5);
                this.scene.add(directionalLight2);
                
                const pointLight = new THREE.PointLight(0xffffff, 1.2);
                pointLight.position.set(0, 8, 0);
                this.scene.add(pointLight);
                
                // 半球光增强可见性
                this.hemiLight = new THREE.HemisphereLight(0xffffff, 0x444444, 0.4);
                this.scene.add(this.hemiLight);
                
                // 轨道控制器
                this.controls = new THREE.OrbitControls(this.camera, canvas);
                this.controls.enableDamping = true;
                this.controls.enableZoom = false;
                this.controls.enablePan = false;
                this.controls.enableRotate = true;
                this.controls.maxPolarAngle = 1.56;
                this.controls.minPolarAngle = 1.3;
                this.controls.rotateSpeed = 0.5;
                this.controls.addEventListener('change', () => {
                    this._wheelLabelsDirty = true;
                });
                
                // 点击事件 - 进入顶视图（区分点击和拖动）
                this.isTopView = false;
                this.isDragging = false;
                // 车内视角：双指撑开进车内，双指捏合回车外
                this.isInterior = false;
                this._ptrs = new Map();
                this._pinchStart = 0;
                this.canvas.addEventListener('pointerdown', (e) => {
                    this.isDragging = false;
                    this._ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
                    if (this._ptrs.size === 2) {
                        this.isDragging = true;   // 双指不算点击
                        this._pinchStart = this._pinchDist();
                        // 记下撑开前的视角，回来时原样还原
                        this._prePinchCam = {
                            pos: this.camera.position.clone(),
                            look: this.controls.target.clone(),
                            fov: this.camera.fov,
                            near: this.camera.near
                        };
                        this.controls.enabled = false;
                    }
                });
                this.canvas.addEventListener('pointermove', (e) => {
                    if (!this._ptrs.has(e.pointerId)) return;
                    this.isDragging = true;
                    this._ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
                    if (this._ptrs.size < 2 || !this._pinchStart) return;
                    const d = this._pinchDist();
                    if (!this.isInterior && d > this._pinchStart * 1.35) this.enterInterior();
                    else if (this.isInterior && d < this._pinchStart * 0.70) this.exitInterior();
                });
                const endPtr = (e) => {
                    this._ptrs.delete(e.pointerId);
                    if (this._ptrs.size < 2) this._pinchStart = 0;
                    if (this._ptrs.size === 0 && !this.isInterior && !this.isTopView) {
                        this.controls.enabled = true;
                    }
                };
                this.canvas.addEventListener('pointerup', (e) => {
                    endPtr(e);
                    if (!this.isDragging) {
                        e.stopPropagation();
                        this.toggleTopView();
                    }
                });
                this.canvas.addEventListener('pointercancel', endPtr);
                
                // 过场虚化层：切镜头时画面糊一下，掩盖跳变
                this.camBlur = document.getElementById('cam-blur');
                try {
                    this._hasBackdrop = !!(window.CSS && CSS.supports &&
                        (CSS.supports('backdrop-filter', 'blur(4px)') || CSS.supports('-webkit-backdrop-filter', 'blur(4px)')));
                } catch (e) { this._hasBackdrop = false; }
                // 兜底用的黑场遮罩
                try {
                    const mask = document.createElement('div');
                    mask.style.cssText = 'position:absolute;inset:0;background:#0B0C10;opacity:0;' +
                        'pointer-events:none;transition:opacity .14s linear;z-index:5;';
                    this.canvas.parentElement.appendChild(mask);
                    this.camMask = mask;
                } catch (e) { this.camMask = null; }

                this.loadEnvironment();
                this.animate();
            }
            
            toggleTopView() {
                this.setTopView(!this.isTopView);
            }

            /** 幂等：已经是这个状态就直接返回，避免和 setMore 互相触发 */
            setTopView(on) {
                if (this.isInterior) return;   // 车内视角下不切俯视
                on = !!on;
                if (this.isTopView === on) return;
                this.isTopView = on;

                const d = this.cameraDistance || 28;
                const hint = document.getElementById('stage-hint');
                const stage = this.canvas.parentElement;

                if (on) {
                    // 禁用控制器，相机由俯视独占
                    this.controls.enabled = false;
                    this.controls.maxPolarAngle = Math.PI;
                    this.controls.minPolarAngle = 0;
                    // 正上方俯视：车头朝屏幕上方
                    this.animateCamera(0, d * 1.25, 0.001, 0, 0, 1);
                    if (hint) hint.textContent = '俯视中 · 点击返回';
                    if (stage) stage.classList.add('top');
                    // 俯视时顺手把车况详情展开（setMore 里也会调 setTopView，幂等不会打转）
                    if (typeof window.setMore === 'function') window.setMore(true);
                    setTimeout(() => {
                        if (this.isTopView && typeof window.setMore === 'function') window.setMore(true);
                    }, 260);
                    setTimeout(() => {
                        if (this.isTopView) this.showWheelLabels();
                    }, 620);
                } else {
                    this.animateCamera(d * 0.68, d * 0.08, d * 0.71, 0, 1, 0);
                    this.controls.target.set(0, 0, 0);
                    if (hint) hint.textContent = '拖动旋转 · 点击俯视看胎压';
                    if (stage) stage.classList.remove('top');
                    if (typeof window.setMore === 'function') window.setMore(false);
                    this.hideWheelLabels();
                }
            }

            // 相机补间：交给主循环逐帧推进，帧率低也能走到终点
            animateCamera(x, y, z, upX, upY, upZ) {
                this._cam = {
                    from: this.camera.position.clone(),
                    to: new THREE.Vector3(x, y, z),
                    fromUp: this.camera.up.clone(),
                    toUp: new THREE.Vector3(upX || 0, upY === undefined ? 1 : upY, upZ || 0),
                    fromLook: new THREE.Vector3(0, 0, 0),
                    toLook: new THREE.Vector3(0, 0, 0),
                    fromFov: this.camera.fov,
                    toFov: this.camera.fov,
                    t0: performance.now(),
                    dur: 700
                };
            }

            /** 曲线补间：从当前机位经 ctrl 点飞到 toPos，起收都平滑 */
            animateCamPath(toPos, ctrl, look, fov, dur, opts) {
                const fwd = new THREE.Vector3(0, 0, -1).applyQuaternion(this.camera.quaternion).multiplyScalar(3);
                this._cam = {
                    from: this.camera.position.clone(),
                    to: new THREE.Vector3(toPos[0], toPos[1], toPos[2]),
                    ctrl: new THREE.Vector3(ctrl[0], ctrl[1], ctrl[2]),
                    fromUp: this.camera.up.clone(),
                    toUp: new THREE.Vector3(0, 1, 0),
                    fromLook: this.camera.position.clone().add(fwd),
                    toLook: new THREE.Vector3(look[0], look[1], look[2]),
                    fromFov: this.camera.fov,
                    toFov: fov === undefined ? this.camera.fov : fov,
                    t0: performance.now(),
                    dur: dur || 900,
                    onRestore: opts && opts.onRestore,
                    restoreAt: opts && opts.restoreAt,
                    fovDelay: opts && opts.fovDelay
                };
            }

            /** 通用补间：位置 + 朝向 + 视角大小 */
            animateCamLook(pos, look, fov, dur, up, opts) {
                const toLookV = new THREE.Vector3(look[0], look[1], look[2]);
                // 起始视线就朝目标方向：飞行过程中画面不转，感觉是直接冲进去而不是绕车
                const dir = toLookV.clone().sub(this.camera.position).normalize().multiplyScalar(3);
                this._cam = {
                    from: this.camera.position.clone(),
                    to: new THREE.Vector3(pos[0], pos[1], pos[2]),
                    fromUp: this.camera.up.clone(),
                    toUp: new THREE.Vector3(...(up || [0, 1, 0])),
                    fromLook: this.camera.position.clone().add(dir),
                    toLook: toLookV,
                    fromFov: this.camera.fov,
                    toFov: fov === undefined ? this.camera.fov : fov,
                    t0: performance.now(),
                    dur: dur || 700,
                    onRestore: opts && opts.onRestore,
                    restoreAt: opts && opts.restoreAt,
                    ease: opts && opts.ease,
                    onArrive: opts && opts.onArrive,
                    blur: opts && opts.blur,
                    onProgress: opts && opts.onProgress
                };
            }

            stepCamera(now) {
                const c = this._cam;
                if (!c) return false;
                const p = Math.min(1, (now - c.t0) / c.dur);
                // 曲线路径用 easeInOut，起步和收尾都不顿
                const e = (c.ctrl || c.ease === 'inout')
                    ? (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2)
                    : 1 - Math.pow(1 - p, 3); // easeOutCubic
                if (c.ctrl) {
                    const t = e, it = 1 - t;
                    this.camera.position.set(
                        it * it * c.from.x + 2 * it * t * c.ctrl.x + t * t * c.to.x,
                        it * it * c.from.y + 2 * it * t * c.ctrl.y + t * t * c.to.y,
                        it * it * c.from.z + 2 * it * t * c.ctrl.z + t * t * c.to.z
                    );
                } else {
                    this.camera.position.lerpVectors(c.from, c.to, e);
                }
                if (c.blur && this.camBlur) {
                    const b = c.blur;
                    let k;
                    if (b.mode === 'bell') {
                        // 峰值后置：最糊的一下正好压在穿车壳的时候
                        const peak = b.peak || 0.86;
                        k = p < peak
                            ? Math.sin(Math.PI * 0.5 * (p / peak))
                            : Math.cos(Math.PI * 0.5 * ((p - peak) / (1 - peak)));
                    }
                    else if (b.mode === 'in') k = Math.pow(p, 2.2);
                    else k = Math.pow(1 - p, 1.6);
                    this._setBlur(b.max * k);
                }
                if (c.onProgress) c.onProgress(p);
                if (c.onRestore && !c._restored && p >= (c.restoreAt || 0.5)) {
                    c._restored = true;
                    c.onRestore();
                }
                this.camera.up.lerpVectors(c.fromUp, c.toUp, e);
                this.camera.lookAt(c.fromLook.clone().lerp(c.toLook, e));
                if (c.toFov !== c.fromFov) {
                    // 视角和位置用同一条缓动，推进和展开同步，不会先缩小再进入
                    this.camera.fov = c.fromFov + (c.toFov - c.fromFov) * e;
                    this.camera.updateProjectionMatrix();
                }
                this._wheelLabelsDirty = true;
                if (p >= 1) {
                    this._cam = null;
                    if (c.onArrive) c.onArrive();
                    if (this._camQueue && this._camQueue.length) {
                        const n = this._camQueue.shift();
                        if (typeof n.before === 'function') n.before();
                        this.animateCamLook(n.pos, n.look, n.fov, n.dur, n.up);
                        return true;
                    }
                    if (!this.isTopView && !this.isInterior) {
                        this.controls.maxPolarAngle = 1.56;
                        this.controls.minPolarAngle = 1.3;
                        this.controls.enabled = true;
                    }
                }
                return true;
            }

            /** 双指撑开：镜头坐进驾驶位，藏掉车身外壳 */
            _pinchDist() {
                const a = [...this._ptrs.values()];
                if (a.length < 2) return 0;
                return Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y);
            }

            enterInterior() {
                if (this.isInterior || !this.model) return;
                if (this.isTopView) return;   // 俯视角度下不进车内
                this.isInterior = true;
                this._pinchStart = 0;
                this._outCam = this._prePinchCam || {
                    pos: this.camera.position.clone(),
                    look: this.controls.target.clone(),
                    fov: this.camera.fov,
                    near: this.camera.near
                };
                this.controls.enabled = false;
                this.camera.near = 0.03;
                this.camera.updateProjectionMatrix();
                // 灯光先准备好，亮度在飞行途中按进度渐入
                this._lightBackup = {
                    amb: this.ambientLight ? this.ambientLight.intensity : 0.4,
                    hemi: this.hemiLight ? this.hemiLight.intensity : 0.4
                };
                if (!this.interiorLight) {
                    this.interiorLight = new THREE.PointLight(0xffffff, 1.7, 3.4, 2);
                    this.scene.add(this.interiorLight);
                }
                this.interiorLight.position.set(0, 0.66, 0.42);
                this.interiorLight.visible = true;
                // 一盏左上方的聚光：让中控台有明暗过渡，别像平涂
                if (!this.cabinSpot) {
                    this.cabinSpot = new THREE.SpotLight(0xfff1e0, 9, 4.5, Math.PI * 0.30, 0.65, 1.1);
                    this.cabinSpot.castShadow = true;
                    this.cabinSpot.shadow.mapSize.set(2048, 2048);
                    this.cabinSpot.shadow.bias = -0.0004;
                    this.cabinSpot.shadow.radius = 3;
                    this.cabinSpot.shadow.camera.near = 0.1;
                    this.cabinSpot.shadow.camera.far = 4.0;
                    this.cabinSpot.position.set(-0.75, 1.05, 0.55);
                    this.scene.add(this.cabinSpot);
                    this.scene.add(this.cabinSpot.target);
                }
                this.cabinSpot.target.position.set(0.05, 0.30, 0.30);
                this.cabinSpot.visible = true;
                // 补一盏侧面柔光，别让内饰只被一个点光源硬打
                if (!this.interiorLight2) {
                    this.interiorLight2 = new THREE.PointLight(0xffffff, 0.85, 3.0, 2);
                    this.scene.add(this.interiorLight2);
                }
                this.interiorLight2.position.set(-0.55, 0.72, 0.15);
                this.interiorLight2.visible = true;
                // 内饰材质：环境反射给足，纯黑塑料提亮一点，不然近看是死块
                if (this.model) this.model.traverse(o => {
                    if (!o.isMesh || !/_Int$/.test(o.name)) return;
                    const mats = Array.isArray(o.material) ? o.material : [o.material];
                    mats.forEach(m => {
                        if (!m) return;
                        if (!m.userData.__origColor && m.color) m.userData.__origColor = m.color.clone();
                        if (m.color) {
                            const c = m.userData.__origColor.clone();
                            const lum = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;
                            if (lum < 0.10) c.lerp(new THREE.Color(0.09, 0.09, 0.10), 0.20);
                            m.color.copy(c);
                        }
                        if (m.envMapIntensity !== undefined) m.envMapIntensity = 1.15;
                        m.needsUpdate = true;
                    });
                });
                this._headMats = [];
                this.model.traverse(o => {
                    if (!o.isMesh || !/WhiteMattePlastic/.test(o.name)) return;
                    const m = o.material;
                    if (!m || !m.color) return;
                    if (!m.userData.__origColor) m.userData.__origColor = m.color.clone();
                    this._headMats.push(m);
                });
                // 一条直线一口气飞进驾驶位：位置和视角都连续，中段最糊
                this._cabinBase = new THREE.Vector3(0.00, 0.53, -0.05);
                this._cabinLook = new THREE.Vector3(0.00, 0.25, 1.95);
                const FLY_MS = 900;   // 飞进驾驶位的时长，读数冲顶要和它同一刻到顶
                this.animateCamLook([0.00, 0.53, -0.05], [0.00, 0.25, 1.95], 70, FLY_MS, undefined, {
                    ease: 'inout',
                    onProgress: (p) => this._lightStep(p, true)
                });
                const stage = this.canvas.parentElement;
                if (stage) stage.classList.add('is-interior');
                if (typeof window.setMore === 'function') {
                    window.setMore(true);
                    setTimeout(() => window.setMore(true), 260);
                }
                const cd = document.getElementById('cabin-data');
                if (cd) {
                    cd.classList.remove('hide');
                    cd.classList.remove('in');
                    void cd.offsetWidth;          // 强制重排，让过渡从头播
                    cd.classList.add('in');
                }
                if (window.playCabinIntro) window.playCabinIntro(FLY_MS);
                const hint = document.getElementById('stage-hint');
                if (hint) hint.textContent = '车内视角 · 双指捏合回到车外';
            }

            exitInterior() {
                if (!this.isInterior) return;
                this.isInterior = false;
                this._cabinBase = null;
                this._pinchStart = 0;
                const c = this._outCam || {
                    pos: new THREE.Vector3(19, 2.2, 19.8), look: new THREE.Vector3(0, 0, 0), fov: 10, near: 0.3
                };
                // 反着飞回去，灯光和顶棚在途中渐出
                this.animateCamLook(c.pos.toArray(), c.look.toArray(), c.fov, 900, undefined, {
                    ease: 'inout',
                    onProgress: (p) => this._lightStep(p, false),
                    onArrive: () => {
                        // 精确回到进入前的机位，避免退出后车漆高光角度变了
                        this.camera.position.copy(c.pos);
                        this.camera.up.set(0, 1, 0);
                        this.camera.lookAt(c.look);
                        this.controls.target.copy(c.look);
                        this.camera.near = c.near;
                        this.camera.updateProjectionMatrix();
                        if (this.interiorLight) this.interiorLight.visible = false;
                if (this.cabinSpot) this.cabinSpot.visible = false;
                        if (this.interiorLight2) this.interiorLight2.visible = false;
                        if (this.model) this.model.traverse(o => {
                            if (!o.isMesh) return;
                            const mats = Array.isArray(o.material) ? o.material : [o.material];
                            mats.forEach(m => {
                                if (m && m.color && m.userData.__origColor) {
                                    m.color.copy(m.userData.__origColor);
                                    m.needsUpdate = true;
                                }
                            });
                        });
                        const st = this.canvas.parentElement;
                        if (st) st.classList.remove('is-interior');
                        if (typeof window.setMore === 'function') window.setMore(false);
                        const cd = document.getElementById('cabin-data');
                        if (cd) cd.classList.remove('in');
                        if (!this.isTopView) this.controls.enabled = true;
                    }
                });
                const hint = document.getElementById('stage-hint');
                if (hint) hint.textContent = '拖动旋转 · 点击俯视看胎压';
            }

            /** 设置过场虚化强度 */
            _setBlur(px) {
                const v = Math.max(0, px);
                if (this._hasBackdrop && this.camBlur) {
                    const t = v.toFixed(1) + 'px';
                    this.camBlur.style.backdropFilter = 'blur(' + t + ')';
                    this.camBlur.style.webkitBackdropFilter = 'blur(' + t + ')';
                    return;
                }
                // 老内核没有 backdrop-filter，就直接糊画布
                if (this.canvas) this.canvas.style.filter = v > 0.15 ? 'blur(' + v.toFixed(1) + 'px)' : '';
            }

            /** 车内灯光按进度渐入/渐出 */
            _lightStep(p, entering) {
                const base = this._lightBackup || { amb: 0.4, hemi: 0.4 };
                const k = Math.min(1, Math.max(0, (p - 0.12) / 0.72));
                const w = entering ? k : (1 - k);
                if (this.ambientLight) this.ambientLight.intensity = base.amb + (0.68 - base.amb) * w;
                if (this.hemiLight) this.hemiLight.intensity = base.hemi + (0.42 - base.hemi) * w;
                // 车内补光和聚光也按进度渐入渐出，别在动画结束时一刀切
                if (this.interiorLight) {
                    this.interiorLight.intensity = 2.8 * w;
                    this.interiorLight.visible = w > 0.01;
                }
                if (this.cabinSpot) {
                    this.cabinSpot.intensity = 17 * w;
                    this.cabinSpot.visible = w > 0.01;
                }
                // 顶棚内衬跟着一起渐变，别在结束时一下子变白
                if (this._headMats) {
                    const f = 1 - 0.58 * w;
                    for (let i = 0; i < this._headMats.length; i++) {
                        const m = this._headMats[i];
                        if (m.userData.__origColor) {
                            m.color.copy(m.userData.__origColor).multiplyScalar(f);
                        }
                    }
                }
            }

            /** 顶棚内衬是纯白，进车内压暗一档，出来还原 */
            _dimHeadliner(on) {
                if (!this.model) return;
                this.model.traverse(o => {
                    if (!o.isMesh || !/WhiteMattePlastic/.test(o.name)) return;
                    const m = o.material;
                    if (!m || !m.color) return;
                    if (!m.userData.__origColor) m.userData.__origColor = m.color.clone();
                    m.color.copy(m.userData.__origColor);
                    if (on) m.color.multiplyScalar(0.42);
                    m.needsUpdate = true;
                });
            }

            updateDetailData() {
                const data = window.app?.apiData;
                if (!data) return;
                if (!document.getElementById('detail-lock')) return;
                
                // 车锁状态
                const locks = [data.driverDoorLock, data.passengerDoorLock, data.leftRearDoorLock, data.rightRearDoorLock];
                const lockOpen = locks.some(v => v === 1);
                document.getElementById('detail-lock').textContent = lockOpen ? '已解锁' : '已上锁';
                document.getElementById('detail-lock').className = `detail-value ${lockOpen ? 'open' : 'closed'}`;
                
                // 车门状态
                const doors = [data.leftFrontDoor, data.rightFrontDoor, data.leftRearDoor, data.rightRearDoor];
                const doorOpen = doors.some(v => v === 1);
                document.getElementById('detail-door').textContent = doorOpen ? '未关' : '已关';
                document.getElementById('detail-door').className = `detail-value ${doorOpen ? 'open' : 'closed'}`;
                
                // 车窗状态
                const windows = [data.diverWindow, data.passengerWindow, data.leftRearWindow, data.rightRearWindow];
                const windowOpen = windows.some(v => v === 1);
                document.getElementById('detail-window').textContent = windowOpen ? '未关' : '已关';
                document.getElementById('detail-window').className = `detail-value ${windowOpen ? 'open' : 'closed'}`;
                
                // 天窗状态
                const sunroofOpen = data.sunroof === 1;
                document.getElementById('detail-sunroof').textContent = sunroofOpen ? '已开' : '已关';
                document.getElementById('detail-sunroof').className = `detail-value ${sunroofOpen ? 'open' : 'closed'}`;
                
                // 后备箱状态
                const trunkOpen = data.trunk === 1;
                document.getElementById('detail-trunk').textContent = trunkOpen ? '已开' : '已关';
                document.getElementById('detail-trunk').className = `detail-value ${trunkOpen ? 'open' : 'closed'}`;
                
                // 车灯状态
                const lights = [data.lowBeam, data.highBeam, data.frontFogLight, data.rearFogLight, data.positionLight];
                const lightOn = lights.some(v => v === 1);
                document.getElementById('detail-light').textContent = lightOn ? '已开' : '已关';
                document.getElementById('detail-light').className = `detail-value ${lightOn ? 'on' : 'off'}`;
                
                // 第二页：系统状态
                const airStatus = data.airStatus === 1;
                document.getElementById('detail-air').textContent = airStatus ? '已开' : '已关';
                document.getElementById('detail-air').className = `detail-value ${airStatus ? 'on' : 'off'}`;
                
                const engineOn = data.engineStatus === 2;   // 1 是上电，2 才是运转中
                document.getElementById('detail-engine').textContent = engineOn ? '运行中' : '已熄火';
                document.getElementById('detail-engine').className = `detail-value ${engineOn ? 'on' : 'off'}`;
                
                const batteryStatus = data.powerBatteryStatus === 0 ? '正常' : '异常';
                document.getElementById('detail-battery').textContent = batteryStatus;
                document.getElementById('detail-battery').className = `detail-value ${data.powerBatteryStatus === 0 ? 'closed' : 'open'}`;
                
                document.getElementById('detail-voltage').textContent = (data.batteryVoltage || 0) + ' V';
                
                const systems = [data.absStatus, data.engineSystemStatus, data.transmissionSystemStatus, data.airbagSystemStatus];
                const systemOk = systems.every(v => v === 0);
                document.getElementById('detail-system').textContent = systemOk ? '正常' : '异常';
                document.getElementById('detail-system').className = `detail-value ${systemOk ? 'closed' : 'open'}`;
                
                const tire = document.getElementById('detail-tire');
                if (tire) {
                    const fl = data.lfTyrePressure || 0;
                    const fr = data.rfTyrePressure || 0;
                    const rl = data.lrTyrePressure || 0;
                    const rr = data.rrTyrePressure || 0;
                    tire.textContent = `${fl}/${fr}/${rl}/${rr}`;
                }
                
                document.getElementById('detail-env-temp').textContent = (data.environmentalTemp || 0) + ' ℃';
                
                // 第三页：油量油耗里程
                document.getElementById('detail-fuel').textContent = (data.fuelLeftover || data.remainingFuel || 0) + ' L';
                document.getElementById('detail-range').textContent = (data.remainedOilMile || 0) + ' km';
                document.getElementById('detail-consumption').textContent = (data.fuelConsumption100km || 0) + ' L';
                document.getElementById('detail-total-oil').textContent = (data.igniteCumulativeOil || 0) + ' L';
                document.getElementById('detail-odometer').textContent = (data.totalOdometer || 0) + ' km';
                document.getElementById('detail-trip').textContent = (data.igniteCumulativeMileage || 0) + ' km';
                
                // 第四页：其他信息
                document.getElementById('detail-speed').textContent = (data.vehicleSpeed || data.speed || 0) + ' km/h';
                document.getElementById('detail-rpm').textContent = rpmText(data.engineSpeed);
                document.getElementById('detail-water-temp').textContent = (data.engineWaterTemp || 0) + ' ℃';
                document.getElementById('detail-voltage').textContent = (data.batteryVoltage || 0) + ' V';
                document.getElementById('detail-altitude').textContent = (data.alti || 0) + ' m';
                document.getElementById('detail-signal').textContent = (data.signaIntensity || data.networkType || 0) + '%';
                
                // 初始化分页切换
                this.initDetailSlider();
            }

            initDetailSlider() {
                const pages = document.querySelectorAll('.detail-page');
                const dots = document.querySelectorAll('.detail-dot');
                if (!pages.length || !dots.length) return;
                if (pages[0]._init) return;
                pages[0]._init = true;
                
                let currentPage = 0;
                
                const goToPage = (page) => {
                    currentPage = page;
                    pages.forEach((p, i) => {
                        p.classList.toggle('active', i === page);
                    });
                    dots.forEach((dot, i) => {
                        dot.classList.toggle('active', i === page);
                    });
                };
                
                // 初始化第一页
                goToPage(0);
                
                // 点击指示器切换
                dots.forEach(dot => {
                    dot.addEventListener('click', (e) => {
                        e.stopPropagation();
                        goToPage(parseInt(dot.dataset.page));
                    });
                });
                
                // 触摸滑动切换
                const slider = document.getElementById('detail-slider');
                let startX = 0;
                let startY = 0;
                let isDragging = false;
                
                slider.addEventListener('touchstart', (e) => {
                    startX = e.touches[0].clientX;
                    startY = e.touches[0].clientY;
                    isDragging = true;
                });
                
                slider.addEventListener('touchend', (e) => {
                    if (!isDragging) return;
                    isDragging = false;
                    const endX = e.changedTouches[0].clientX;
                    const endY = e.changedTouches[0].clientY;
                    const diffX = startX - endX;
                    const diffY = startY - endY;
                    
                    // 只处理水平滑动，忽略垂直滑动
                    if (Math.abs(diffX) > Math.abs(diffY) && Math.abs(diffX) > 50) {
                        if (diffX > 0 && currentPage < 3) {
                            goToPage(currentPage + 1);
                        } else if (diffX < 0 && currentPage > 0) {
                            goToPage(currentPage - 1);
                        }
                    }
                });
            }

            showDetailModal(type) {
                const data = window.app?.apiData;
                if (!data) return;
                
                const modal = document.getElementById('detail-modal');
                const title = document.getElementById('detail-modal-title');
                const body = document.getElementById('detail-modal-body');
                
                let items = [];
                
                switch(type) {
                    case 'lock':
                        title.textContent = '车锁详情';
                        items = [
                            { label: '主驾车锁', value: data.driverDoorLock, isLock: true },
                            { label: '副驾车锁', value: data.passengerDoorLock, isLock: true },
                            { label: '左后车锁', value: data.leftRearDoorLock, isLock: true },
                            { label: '右后车锁', value: data.rightRearDoorLock, isLock: true }
                        ];
                        break;
                    case 'door':
                        title.textContent = '车门详情';
                        items = [
                            { label: '主驾车门', value: data.leftFrontDoor, isOpen: true },
                            { label: '副驾车门', value: data.rightFrontDoor, isOpen: true },
                            { label: '左后车门', value: data.leftRearDoor, isOpen: true },
                            { label: '右后车门', value: data.rightRearDoor, isOpen: true }
                        ];
                        break;
                    case 'window':
                        title.textContent = '车窗详情';
                        items = [
                            { label: '主驾车窗', value: data.diverWindow, isOpen: true },
                            { label: '副驾车窗', value: data.passengerWindow, isOpen: true },
                            { label: '左后车窗', value: data.leftRearWindow, isOpen: true },
                            { label: '右后车窗', value: data.rightRearWindow, isOpen: true }
                        ];
                        break;
                    case 'sunroof':
                        title.textContent = '天窗详情';
                        items = [
                            { label: '天窗', value: data.sunroof, isOpen: true }
                        ];
                        break;
                    case 'trunk':
                        title.textContent = '后备箱详情';
                        items = [
                            { label: '后备箱', value: data.trunk, isOpen: true },
                            { label: '引擎盖', value: data.hood, isOpen: true }
                        ];
                        break;
                    case 'light':
                        title.textContent = '车灯详情';
                        items = [
                            { label: '近光灯', value: data.lowBeam, isLight: true },
                            { label: '远光灯', value: data.highBeam, isLight: true },
                            { label: '前雾灯', value: data.frontFogLight, isLight: true },
                            { label: '后雾灯', value: data.rearFogLight, isLight: true },
                            { label: '位置灯', value: data.positionLight, isLight: true },
                            { label: '左转向灯', value: data.leftTurnSignal, isLight: true },
                            { label: '右转向灯', value: data.rightTurnSignal, isLight: true }
                        ];
                        break;
                    case 'air':
                        title.textContent = '空调详情';
                        const airData = data.air || {};
                        items = [
                            { label: '空调状态', value: data.airStatus, isLight: true },
                            { label: '设定温度', value: data.airConditioningSetTemperature + '℃', isText: true },
                            { label: '车内温度', value: (data.vehicleTemperature || 0) + '℃', isText: true },
                            { label: '风量', value: airData.wind || '--', isText: true },
                            { label: '循环模式', value: data.airRecycleStatus === 1 ? '内循环' : '外循环', isText: true },
                            { label: '空气质量', value: (data.airQualityInCarLevel || 0) + '级', isText: true }
                        ];
                        break;
                    case 'engine':
                        title.textContent = '发动机详情';
                        items = [
                            { label: '发动机状态', value: data.engineStatus, isLight: true },
                            { label: '转速', value: rpmText(data.engineSpeed), isText: true },
                            { label: '水温', value: (data.engineWaterTemp || 0) + '℃', isText: true },
                            { label: '冷却液状态', value: data.engineCoolantStatus, isLight: true },
                            { label: '启动时间', value: data.ignitionTime || '--', isText: true }
                        ];
                        break;
                    case 'system':
                        title.textContent = '系统状态详情';
                        items = [
                            { label: 'ABS', value: data.absStatus, isLight: true },
                            { label: '发动机系统', value: data.engineSystemStatus, isLight: true },
                            { label: '变速箱系统', value: data.transmissionSystemStatus, isLight: true },
                            { label: '安全气囊', value: data.airbagSystemStatus, isLight: true },
                            { label: '稳定控制', value: data.vehicleStabilityControlSystemStatus, isLight: true },
                            { label: '助力转向', value: data.assistantSteeringStatus, isLight: true },
                            { label: '无钥匙启动', value: data.keylessEntryStartSystemStatus, isLight: true }
                        ];
                        break;
                }
                
                body.innerHTML = items.map(item => {
                    let statusText, statusClass;
                    if (item.isText) {
                        statusText = item.value;
                        statusClass = '';
                    } else if (item.isLock) {
                        statusText = item.value === 1 ? '已解锁' : '已上锁';
                        statusClass = item.value === 1 ? 'open' : 'closed';
                    } else if (item.isLight) {
                        statusText = item.value === 1 ? '已开启' : '已关闭';
                        statusClass = item.value === 1 ? 'on' : 'off';
                    } else if (item.isOpen) {
                        statusText = item.value === 1 ? '已开启' : '已关闭';
                        statusClass = item.value === 1 ? 'open' : 'closed';
                    } else {
                        statusText = item.value === 1 ? '正常' : '异常';
                        statusClass = item.value === 0 ? 'closed' : 'open';
                    }
                    return `<div class="detail-modal-item">
                        <span class="detail-modal-item-label">${item.label}</span>
                        <span class="detail-modal-item-value ${statusClass}">${statusText}</span>
                    </div>`;
                }).join('');
                
                modal.style.display = 'flex';
            }

            hideDetailModal() {
                document.getElementById('detail-modal').style.display = 'none';
            }
            
            // 俯视标注（四轮胎压 + 机盖电压）由 overlay.js 负责

            showWheelLabels() {
                if (window.CarOverlay) window.CarOverlay.show(this);
            }

            hideWheelLabels() {
                if (window.CarOverlay) window.CarOverlay.hide();
            }

            loadEnvironment() {
                const cubePromise = new Promise((resolve) => {
                    const cubeLoader = new THREE.CubeTextureLoader();
                    cubeLoader.load([
                        'textures/cube/px.png', 'textures/cube/nx.png',
                        'textures/cube/py.png', 'textures/cube/ny.png',
                        'textures/cube/pz.png', 'textures/cube/nz.png'
                    ], resolve, undefined, () => {
                        const rgbeLoader = new THREE.RGBELoader();
                        rgbeLoader.load('textures/HDR_250.hdr', (hdrTexture) => {
                            hdrTexture.mapping = THREE.EquirectangularReflectionMapping;
                            resolve(hdrTexture);
                        }, undefined, () => resolve(null));
                    });
                });

                const modelPromise = new Promise((resolve, reject) => {
                    const loader = new THREE.GLTFLoader();
                    loader.setMeshoptDecoder(MeshoptDecoder);
                    loader.load(window.CAR_MODEL_FILE || '3D/C211.glb', resolve, undefined, reject);
                });

                Promise.all([cubePromise, modelPromise]).then(([envTexture, gltf]) => {
                    if (envTexture) {
                        this.scene.environment = envTexture;
                    }
                    this.onModelLoaded(gltf);
                }).catch((error) => {
                    console.error('资源加载失败:', error);
                });
            }

            onModelLoaded(gltf) {
                    this.model = gltf.scene;
                    this.model.scale.set(1, 1, 1);
                    
                    // 移除模型自带灯光
                    const lightsToRemove = [];
                    this.model.traverse((child) => {
                        if (child.isLight) lightsToRemove.push(child);
                    });
                    lightsToRemove.forEach(light => light.parent.remove(light));
                    
                    // 灯光部件精确配置
                    const lightVisibility = {
                        'Light_L_LOn_Ext': false,
                        'Light_R_LOn_Ext': false,
                        'Light_L_LOn_Door_FL': false,
                        'Light_R_LOn_Door_FR': false,
                        'Light_L_LOn_LuggageDoor': false,
                        'Light_R_LOn_LuggageDoor': false,
                        'Light_BL_LOn_Ext': false,
                        'Light_TL_LOn_Ext': false,
                        'Light_DRL_LOn_Ext': false,
                        'Light_HL_LOn_Ext': false,
                        'Light_TL_LOn_LuggageDoor': false,
                        'Light_BL_LOn_LuggageDoor': false,
                        'LightGlass_Ext': true,  // 唯一默认可见的灯光部件
                        'HightLight_Handle_FL': false
                    };
                    
                    // 应用材质覆盖和特殊处理
                    this.model.traverse((child) => {
                        if (!child.isMesh) return;
                        const name = child.name;
                        
                        // 处理车窗玻璃
                        if (name === 'WindowGlass_Ext') {
                            child.material.opacity = 0.6;
                            child.material.transparent = true;
                        }
                        
                        // 处理灯光部件 - 精确匹配
                        if (lightVisibility.hasOwnProperty(name)) {
                            if (child.material) {
                                child.material.blending = THREE.AdditiveBlending;
                            }
                            child.visible = lightVisibility[name];
                        }
                        
                        // 优化车漆材质（记下来，换色时统一改）
                        // 轮毂叫 GreyCarPaint_Wheel_*，别跟着车身一起变色
                        const isPaint = (name.includes('CarPaint') || name.includes('Body'))
                                        && !/wheel/i.test(name);
                        if (isPaint) {
                            const paintMat = new THREE.MeshPhysicalMaterial({
                                color: 0xffffff,
                                metalness: 0.1,
                                roughness: 0.4,
                                clearcoat: 1,
                                clearcoatRoughness: 0.2,
                                reflectivity: 0.5,
                                sheen: 0.1,
                                envMap: this.scene.environment,
                                envMapIntensity: 0.5
                            });
                            child.material = paintMat;
                            if (!this.paintMats) this.paintMats = [];
                            this.paintMats.push(paintMat);
                        }
                        
                        // 设置贴图翻转
                        if (child.material.map) {
                            child.material.map.flipY = false;
                        }
                        if (child.material.normalMap) {
                            child.material.normalMap.flipY = false;
                        }
                    });
                    
                    // 模型位置调整
                    this.model.position.set(0, -0.6, 0);
                    
                    this.model.traverse(o => {
                        if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
                    });
                    this.scene.add(this.model);
                    
                    // 存储动画
                    this.mixer = new THREE.AnimationMixer(this.model);
                    gltf.animations.forEach(clip => {
                        this.animations[clip.name] = clip;
                    });
                    
                    console.log('3D模型加载完成，动画:', Object.keys(this.animations));
                    
                    // 套用选好的车漆
                    this.applyPaint(window.CAR_PAINT || '#FFFFFF');

                    // 初始化车身状态
                    this.updateBodyStatus();
            }
            
            /** 换车漆：清漆层保留，只改底色 */

            applyPaint(hex) {
                const c = new THREE.Color(hex || '#FFFFFF');
                (this.paintMats || []).forEach(m => {
                    m.color.copy(c);
                    m.needsUpdate = true;
                });
            }

            updateBodyStatus() {
                const data = window.app?.apiData;
                if (!data || !this.animations) return;
                
                if (!this._playedAnims) this._playedAnims = new Set();
                
                // 车门动画
                const doorMap = {
                    'DoorOpen_FL': data.leftFrontDoor,
                    'DoorOpen_FR': data.rightFrontDoor,
                    'DoorOpen_BL': data.leftRearDoor,
                    'DoorOpen_BR': data.rightRearDoor
                };
                
                // 车窗动画
                const windowMap = {
                    'WindowOpen_FL': data.diverWindow,
                    'WindowOpen_FR': data.passengerWindow,
                    'WindowOpen_BL': data.leftRearWindow,
                    'WindowOpen_BR': data.rightRearWindow,
                    'WindowOpen_T': data.sunroof
                };
                
                // 后备箱动画
                const trunkMap = {
                    'LuggageDoorOpen': data.trunk
                };
                
                // 播放所有开启的动画（只播放一次，关闭时倒放）
                const allMaps = [doorMap, windowMap, trunkMap];
                allMaps.forEach(map => {
                    Object.entries(map).forEach(([animName, status]) => {
                        if (status === 1 && !this._playedAnims.has(animName)) {
                            this.playAnimation(animName, false);
                            this._playedAnims.add(animName);
                        } else if (status !== 1 && this._playedAnims.has(animName)) {
                            this.playAnimation(animName, true);
                            this._playedAnims.delete(animName);
                        }
                    });
                });
            }
            
            playAnimation(name, reverse = false) {
                if (!this.mixer || !this.animations[name]) return;
                const clip = this.animations[name];
                const action = this.mixer.clipAction(clip);
                action.reset();
                action.setLoop(THREE.LoopOnce);
                action.clampWhenFinished = true;
                if (reverse) {
                    action.timeScale = -1;
                    action.time = clip.duration;
                } else {
                    action.timeScale = 1;
                }
                action.play();
            }
            

            
            onResize() {
                const container = this.canvas.parentElement;
                const width = container.offsetWidth;
                const height = container.offsetHeight;
                this.camera.aspect = width / height;
                this.camera.updateProjectionMatrix();
                this.renderer.setSize(width, height);
            }
            
            animate() {
                requestAnimationFrame(() => this.animate());
                if (this.mixer) {
                    this.mixer.update(0.016);
                    if (this.mixer._actions?.some(a => a.isRunning())) {
                        this._wheelLabelsDirty = true;
                    }
                }
                // 补间进行中或俯视状态下，相机由补间独占，不能让 OrbitControls 抢回去
                const tweening = this.stepCamera(performance.now());
                if (!tweening && this.controls.enabled) this.controls.update();
                // 车内视角：镜头极轻微地呼吸，画面不再是死图
                if (this.isInterior && !tweening && this._cabinBase) {
                    const t = performance.now() / 1000;
                    this.camera.position.set(
                        this._cabinBase.x + Math.sin(t * 0.70) * 0.005,
                        this._cabinBase.y + Math.sin(t * 0.53 + 1.1) * 0.006,
                        this._cabinBase.z + Math.cos(t * 0.61) * 0.004
                    );
                    this.camera.lookAt(
                        this._cabinLook.x + Math.sin(t * 0.41) * 0.012,
                        this._cabinLook.y + Math.sin(t * 0.33 + 0.7) * 0.006,
                        this._cabinLook.z
                    );
                }
                this.renderer.render(this.scene, this.camera);
            }
        }
        
        // 初始化3D查看器
        function init3DViewer() {
            const canvas = document.getElementById('vehicle-3d');
            if (!canvas) return;
            
            // 确保容器有尺寸
            const container = canvas.parentElement;
            if (container.offsetWidth === 0 || container.offsetHeight === 0) {
                setTimeout(init3DViewer, 100);
                return;
            }
            
            // 设置 canvas 实际尺寸
            canvas.width = container.offsetWidth;
            canvas.height = container.offsetHeight;
            
            window.vehicle3D = new Vehicle3DViewer(canvas);
            window.carViewer = window.vehicle3D;
            
            // 监听窗口大小变化
            window.addEventListener('resize', () => {
                if (window.vehicle3D) window.vehicle3D.onResize();
            });
        }
        
        // 延迟初始化，确保容器已渲染
        setTimeout(init3DViewer, 500);
