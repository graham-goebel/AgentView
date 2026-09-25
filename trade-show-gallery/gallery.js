(() => {
  "use strict";

  const CONFIG = window.GALLERY_CONFIG || {};
  const PRODUCTS = (window.MARK_ONE_PRODUCTS || []).map((p) => ({
    ...p,
    haystack: [
      p.name, p.category, p.material, p.process, p.finish, p.description,
      ...(p.industries || []), ...(p.tags || []),
      ...(p.specs || []).flat(),
    ].join(" ").toLowerCase(),
  }));
  const FILTERS = CONFIG.filters || [{ key: "category", label: "Category" }];

  const TILE_BASE = 256;          // px; tiles are scaled down from this so images stay sharp
  const PITCH_LIMIT = 1.45;       // radians; keeps the sphere from flipping upside down
  const REST_PITCH = -0.12;       // slight downward tilt the sphere settles back to
  const $ = (id) => document.getElementById(id);

  const app = $("app");
  const stage = $("stage");
  const sphereEl = $("sphere");
  const canvas = $("dots");
  const ctx = canvas.getContext("2d");
  const hoverLabel = $("hoverLabel");
  const detail = $("detail");
  const fly = $("fly");

  const state = {
    query: "",
    selected: Object.fromEntries(FILTERS.map((f) => [f.key, new Set()])),
    objectScale: 1,
    sphereScale: 1,
    spin: 1,
    zoom: 1,
    yaw: 0,
    pitch: REST_PITCH,
    velYaw: 0,
    velPitch: 0,
    focus: null,             // {yaw, pitch} the sphere is turning towards
    filtered: [],            // unique products currently shown, in display order
    slotCount: 0,
    hovered: null,
    openIndex: -1,
    lastInteraction: performance.now(),
    w: 0, h: 0, dpr: 1,
  };

  const tiles = new Map();   // key -> tile record

  // ---------- Filtering ----------

  const valuesOf = (product, key) => {
    const v = product[key];
    return Array.isArray(v) ? v : v ? [v] : [];
  };

  const matchesQuery = (p) => {
    const terms = state.query.toLowerCase().split(/\s+/).filter(Boolean);
    return terms.every((t) => p.haystack.includes(t));
  };

  const matchesFilters = (p, skipKey) =>
    FILTERS.every(({ key }) => {
      if (key === skipKey) return true;
      const sel = state.selected[key];
      return sel.size === 0 || valuesOf(p, key).some((v) => sel.has(v));
    });

  function buildFilterUI() {
    const container = $("filterGroups");
    container.innerHTML = "";
    for (const { key, label } of FILTERS) {
      const values = [...new Set(PRODUCTS.flatMap((p) => valuesOf(p, key)))].sort((a, b) => a.localeCompare(b));
      if (!values.length) continue;
      const section = document.createElement("section");
      section.className = "group";
      section.innerHTML = `<h3>${escapeHtml(label)}</h3><div class="chips"></div>`;
      const chips = section.querySelector(".chips");
      for (const value of values) {
        const chip = document.createElement("button");
        chip.type = "button";
        chip.className = "chip";
        chip.dataset.key = key;
        chip.dataset.value = value;
        chip.setAttribute("aria-pressed", "false");
        chip.innerHTML = `<span>${escapeHtml(value)}</span><span class="n"></span>`;
        chip.addEventListener("click", () => {
          const sel = state.selected[key];
          sel.has(value) ? sel.delete(value) : sel.add(value);
          applyFilters();
        });
        chips.appendChild(chip);
      }
      container.appendChild(section);
    }
  }

  function updateFilterUI() {
    const base = PRODUCTS.filter(matchesQuery);
    for (const chip of document.querySelectorAll(".chip")) {
      const { key, value } = chip.dataset;
      const count = base.filter((p) => matchesFilters(p, key) && valuesOf(p, key).includes(value)).length;
      const on = state.selected[key].has(value);
      chip.setAttribute("aria-pressed", String(on));
      chip.querySelector(".n").textContent = count;
      chip.classList.toggle("zero", count === 0 && !on);
    }
    const n = state.filtered.length;
    $("resultCount").textContent = `${n} of ${PRODUCTS.length} product${PRODUCTS.length === 1 ? "" : "s"}`;
    $("empty").hidden = n > 0;
  }

  function applyFilters() {
    state.filtered = PRODUCTS
      .filter((p) => matchesQuery(p) && matchesFilters(p))
      .sort((a, b) =>
        (b.featured ? 1 : 0) - (a.featured ? 1 : 0) ||
        (a.category || "").localeCompare(b.category || "") ||
        a.name.localeCompare(b.name));
    layoutSphere();
    updateFilterUI();
  }

  // ---------- Sphere layout ----------

  function fibonacciPoint(i, n) {
    const y = 1 - ((i + 0.5) / n) * 2;
    const r = Math.sqrt(1 - y * y);
    const theta = i * Math.PI * (3 - Math.sqrt(5));
    return { x: Math.cos(theta) * r, y, z: Math.sin(theta) * r };
  }

  function makeTile(key, product) {
    const el = document.createElement("button");
    el.type = "button";
    el.className = product.cutout ? "tile cutout" : "tile";
    el.setAttribute("role", "listitem");
    el.setAttribute("aria-label", product.name);
    el.style.width = el.style.height = `${TILE_BASE}px`;
    el.style.margin = `${-TILE_BASE / 2}px 0 0 ${-TILE_BASE / 2}px`;
    const img = document.createElement("img");
    img.src = product.thumb;
    img.alt = "";
    img.decoding = "async";
    img.draggable = false;
    el.appendChild(img);
    el.dataset.key = key;
    sphereEl.appendChild(el);
    const tile = { key, el, product, cur: null, target: null, presence: 0, show: false };
    tiles.set(key, tile);
    return tile;
  }

  function layoutSphere() {
    const list = state.filtered;
    // A tiny catalog (e.g. while testing with a few photos) is repeated to fill the sphere.
    let copies = 1;
    const minTiles = CONFIG.minTiles || 0;
    if (list.length && PRODUCTS.length < minTiles) {
      copies = Math.max(1, Math.round(minTiles / PRODUCTS.length));
    }
    const slots = [];
    for (let c = 0; c < copies; c++) for (const p of list) slots.push({ key: `${p.id}~${c}`, product: p });
    state.slotCount = slots.length;

    const live = new Set();
    slots.forEach(({ key, product }, i) => {
      const tile = tiles.get(key) || makeTile(key, product);
      tile.target = fibonacciPoint(i, slots.length);
      if (!tile.show) {
        tile.cur = { ...tile.target };
        tile.presence = 0;
        tile.el.style.display = "";
      }
      tile.show = true;
      tile.el.tabIndex = 0;
      live.add(key);
    });
    for (const tile of tiles.values()) {
      if (!live.has(tile.key)) {
        tile.show = false;
        tile.el.tabIndex = -1;
      }
    }
  }

  // ---------- Render loop ----------

  function radius() {
    return Math.min(state.w, state.h) * 0.3 * state.sphereScale * state.zoom;
  }

  function rotate(v, cy, sy, cp, sp) {
    const x1 = v.x * cy + v.z * sy;
    const z1 = -v.x * sy + v.z * cy;
    return { x: x1, y: v.y * cp - z1 * sp, z: v.y * sp + z1 * cp };
  }

  const dotPoints = Array.from({ length: 420 }, (_, i) => fibonacciPoint(i, 420));

  let last = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const k60 = dt * 60;

    // Rotation: focus target > drag > inertia + auto-spin.
    if (state.focus) {
      const e = 1 - Math.pow(0.88, k60);
      state.yaw += (state.focus.yaw - state.yaw) * e;
      state.pitch += (state.focus.pitch - state.pitch) * e;
    } else if (!pointer.dragging) {
      state.yaw += state.velYaw * k60;
      state.pitch += state.velPitch * k60;
      const decay = Math.pow(0.94, k60);
      state.velYaw *= decay;
      state.velPitch *= decay;
      if (state.openIndex < 0) {
        state.yaw += ((CONFIG.spinDegreesPerSecond ?? 6) * Math.PI / 180) * state.spin * dt;
        if (now - state.lastInteraction > 4000) {
          state.pitch += (REST_PITCH - state.pitch) * (1 - Math.pow(0.985, k60));
        }
      }
    }
    state.pitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, state.pitch));

    const R = radius();
    const D = R * 2.6;
    const cx = state.w / 2;
    const cy = state.h / 2;
    const cY = Math.cos(state.yaw), sY = Math.sin(state.yaw);
    const cP = Math.cos(state.pitch), sP = Math.sin(state.pitch);

    // Background dot sphere
    ctx.setTransform(state.dpr, 0, 0, state.dpr, 0, 0);
    ctx.clearRect(0, 0, state.w, state.h);
    const dotR = R * 0.97;
    for (const p of dotPoints) {
      const r = rotate(p, cY, sY, cP, sP);
      const f = D / (D - r.z * dotR);
      const t = (r.z + 1) / 2;
      ctx.globalAlpha = 0.05 + 0.3 * t * t;
      ctx.fillStyle = "#9fb4cc";
      ctx.beginPath();
      ctx.arc(cx + r.x * dotR * f, cy + r.y * dotR * f, 1.1 * f, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    // Tiles
    const spacing = R * Math.sqrt((4 * Math.PI) / Math.max(1, state.slotCount));
    const baseSize = Math.max(32, Math.min(200, spacing * 0.6)) * state.objectScale;
    const move = 1 - Math.pow(0.9, k60);
    for (const tile of tiles.values()) {
      if (!tile.show && tile.presence <= 0.005) continue;
      tile.presence += ((tile.show ? 1 : 0) - tile.presence) * (1 - Math.pow(0.85, k60));
      if (!tile.show && tile.presence <= 0.005) {
        tile.presence = 0;
        tile.el.style.display = "none";
        continue;
      }
      // Glide towards the target slot along the sphere surface.
      const c = tile.cur, g = tile.target;
      c.x += (g.x - c.x) * move; c.y += (g.y - c.y) * move; c.z += (g.z - c.z) * move;
      const len = Math.hypot(c.x, c.y, c.z) || 1;
      const r = rotate({ x: c.x / len, y: c.y / len, z: c.z / len }, cY, sY, cP, sP);
      const f = D / (D - r.z * R);
      const t = (r.z + 1) / 2;
      const size = baseSize * f * tile.presence;
      const x = cx + r.x * R * f;
      const y = cy + r.y * R * f;
      tile.screen = { x, y, size };
      tile.el.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,0) scale(${(size / TILE_BASE).toFixed(4)})`;
      tile.el.style.opacity = ((0.22 + 0.78 * Math.pow(t, 1.4)) * Math.min(1, tile.presence * 1.5)).toFixed(3);
      tile.el.style.zIndex = String(Math.round(t * 1000));
    }

    const h = state.hovered;
    if (h && h.screen && h.show && !pointer.dragging && state.openIndex < 0) {
      hoverLabel.textContent = h.product.name;
      hoverLabel.style.transform = `translate(${h.screen.x.toFixed(0)}px, ${(h.screen.y + h.screen.size / 2 + 10).toFixed(0)}px) translateX(-50%)`;
      hoverLabel.classList.add("show");
    } else {
      hoverLabel.classList.remove("show");
    }

    requestAnimationFrame(frame);
  }

  // ---------- Pointer interaction ----------

  const pointer = { active: new Map(), dragging: false, tile: null, startX: 0, startY: 0, lastX: 0, lastY: 0, lastT: 0, pinch: null };

  function touched() {
    state.lastInteraction = performance.now();
    $("hint").classList.add("gone");
  }

  stage.addEventListener("pointerdown", (e) => {
    if (e.target.closest(".stage-controls")) return;
    touched();
    stage.setPointerCapture(e.pointerId);
    pointer.active.set(e.pointerId, { x: e.clientX, y: e.clientY });
    state.focus = null;
    if (pointer.active.size === 2) {
      const [a, b] = [...pointer.active.values()];
      pointer.pinch = { dist: Math.hypot(a.x - b.x, a.y - b.y), zoom: state.zoom };
      pointer.dragging = true;
      pointer.tile = null;
      return;
    }
    pointer.tile = tileFromEvent(e);
    pointer.dragging = false;
    pointer.startX = pointer.lastX = e.clientX;
    pointer.startY = pointer.lastY = e.clientY;
    pointer.lastT = performance.now();
    state.velYaw = state.velPitch = 0;
  });

  stage.addEventListener("pointermove", (e) => {
    if (!pointer.active.has(e.pointerId)) {
      if (e.pointerType === "mouse") setHover(tileFromEvent(e));
      return;
    }
    pointer.active.set(e.pointerId, { x: e.clientX, y: e.clientY });
    touched();
    if (pointer.pinch && pointer.active.size >= 2) {
      const [a, b] = [...pointer.active.values()];
      setZoom(pointer.pinch.zoom * (Math.hypot(a.x - b.x, a.y - b.y) / pointer.pinch.dist));
      return;
    }
    if (!pointer.dragging && Math.hypot(e.clientX - pointer.startX, e.clientY - pointer.startY) > 6) {
      pointer.dragging = true;
      stage.classList.add("dragging");
      setHover(null);
    }
    if (!pointer.dragging) return;
    const now = performance.now();
    const k = 1 / radius();
    const dx = (e.clientX - pointer.lastX) * k;
    const dy = (e.clientY - pointer.lastY) * k;
    state.yaw += dx;
    state.pitch -= dy;
    const frames = Math.max(1, (now - pointer.lastT) / 16.7);
    state.velYaw = dx / frames;
    state.velPitch = -dy / frames;
    pointer.lastX = e.clientX;
    pointer.lastY = e.clientY;
    pointer.lastT = now;
  });

  function endPointer(e) {
    if (!pointer.active.has(e.pointerId)) return;
    pointer.active.delete(e.pointerId);
    if (pointer.active.size > 0) return;
    if (!pointer.dragging && pointer.tile && e.type === "pointerup") openDetail(pointer.tile);
    if (performance.now() - pointer.lastT > 80) state.velYaw = state.velPitch = 0;
    pointer.dragging = false;
    pointer.pinch = null;
    pointer.tile = null;
    stage.classList.remove("dragging");
  }
  stage.addEventListener("pointerup", endPointer);
  stage.addEventListener("pointercancel", endPointer);
  stage.addEventListener("pointerleave", (e) => { if (e.pointerType === "mouse") setHover(null); });

  stage.addEventListener("wheel", (e) => {
    e.preventDefault();
    touched();
    setZoom(state.zoom * Math.exp(-e.deltaY * 0.0012));
  }, { passive: false });

  // Keyboard users: Enter/Space on a focused tile.
  sphereEl.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" && e.key !== " ") return;
    const tile = tileFromEvent(e);
    if (tile) { e.preventDefault(); openDetail(tile); }
  });

  function tileFromEvent(e) {
    const el = e.target.closest && e.target.closest(".tile");
    return el ? tiles.get(el.dataset.key) : null;
  }

  function setHover(tile) {
    if (state.hovered === tile) return;
    if (state.hovered) state.hovered.el.classList.remove("hover");
    state.hovered = tile;
    if (tile) tile.el.classList.add("hover");
  }

  function setZoom(z) {
    state.zoom = Math.max(0.45, Math.min(2.6, z));
  }

  // ---------- Detail view ----------

  function focusOn(tile) {
    const c = tile.target;
    let yaw = Math.atan2(-c.x, c.z);
    const pitch = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, Math.atan2(c.y, Math.hypot(c.x, c.z))));
    // Turn the short way round.
    yaw += Math.round((state.yaw - yaw) / (2 * Math.PI)) * 2 * Math.PI;
    state.focus = { yaw, pitch };
    state.velYaw = state.velPitch = 0;
    for (const t of tiles.values()) t.el.classList.toggle("active", t === tile);
  }

  function nearestTileFor(product) {
    let best = null, bestZ = -Infinity;
    const cY = Math.cos(state.yaw), sY = Math.sin(state.yaw);
    const cP = Math.cos(state.pitch), sP = Math.sin(state.pitch);
    for (const t of tiles.values()) {
      if (!t.show || t.product !== product) continue;
      const z = rotate(t.target, cY, sY, cP, sP).z;
      if (z > bestZ) { bestZ = z; best = t; }
    }
    return best;
  }

  function fillDetail(product) {
    const idx = state.filtered.indexOf(product);
    state.openIndex = idx;
    $("detailCategory").textContent = product.category || "Product";
    $("detailName").textContent = product.name;
    $("detailDesc").textContent = product.description || "";
    $("detailDesc").hidden = !product.description;

    const facts = [
      ["Material", product.material],
      ["Process", product.process],
      ["Finish", product.finish],
      ["Industries", (product.industries || []).join(", ")],
      ...(product.specs || []).map(([k, v]) => [k || "Note", v.split("|").join(", ")]),
    ].filter(([, v]) => v);
    $("detailFacts").innerHTML = facts
      .map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`)
      .join("");
    $("detailTags").innerHTML = (product.tags || [])
      .map((t) => `<span class="tag">${escapeHtml(t)}</span>`)
      .join("");
    $("detailPos").textContent = `${idx + 1} / ${state.filtered.length}`;
    const multi = state.filtered.length > 1;
    $("prevBtn").disabled = $("nextBtn").disabled = !multi;
    $("prevBtn").style.visibility = $("nextBtn").style.visibility = multi ? "" : "hidden";

    $("detailMedia").classList.toggle("cutout", !!product.cutout);
    const img = $("detailImg");
    img.alt = product.name;
    img.src = product.thumb;
    const full = new Image();
    full.onload = () => { if (state.filtered[state.openIndex] === product) img.src = product.image; };
    full.src = product.image;
  }

  // Rectangle an image of the given aspect ratio occupies when "contain"-fitted in box.
  function containRect(box, aspect) {
    let w = box.width, h = w / aspect;
    if (h > box.height) { h = box.height; w = h * aspect; }
    return { left: box.left + (box.width - w) / 2, top: box.top + (box.height - h) / 2, width: w, height: h };
  }

  function openDetail(tile) {
    touched();
    setHover(null);
    focusOn(tile);
    const product = tile.product;
    const thumb = tile.el.querySelector("img");
    const aspect = thumb.naturalWidth && thumb.naturalHeight ? thumb.naturalWidth / thumb.naturalHeight : 1.5;
    const tileRect = tile.el.getBoundingClientRect();
    const from = product.cutout ? containRect(tileRect, aspect) : tileRect;
    const wasOpen = state.openIndex >= 0;
    fillDetail(product);
    detail.hidden = false;
    if (wasOpen) return;

    const img = $("detailImg");
    img.style.visibility = "hidden";
    requestAnimationFrame(() => {
      detail.classList.add("open");
      const to = containRect(img.getBoundingClientRect(), aspect);
      fly.src = product.thumb;
      fly.style.transition = "none";
      fly.style.objectFit = "cover";
      fly.style.filter = product.cutout ? "drop-shadow(0 24px 30px rgba(0,0,0,0.6))" : "";
      Object.assign(fly.style, px(from), { display: "block", borderRadius: product.cutout ? "0" : "16%" });
      fly.getBoundingClientRect(); // commit start position
      fly.style.transition = "";
      Object.assign(fly.style, px(to), { borderRadius: "0" });
      setTimeout(() => {
        img.style.visibility = "";
        fly.style.display = "none";
      }, 470);
    });
  }

  function closeDetail() {
    if (state.openIndex < 0) return;
    state.openIndex = -1;
    state.focus = null;
    for (const t of tiles.values()) t.el.classList.remove("active");
    detail.classList.remove("open");
    fly.style.display = "none";
    setTimeout(() => { if (state.openIndex < 0) detail.hidden = true; }, 350);
  }

  function step(dir) {
    const n = state.filtered.length;
    if (n < 2 || state.openIndex < 0) return;
    const product = state.filtered[(state.openIndex + dir + n) % n];
    const tile = nearestTileFor(product);
    if (tile) focusOn(tile);
    fillDetail(product);
  }

  detail.addEventListener("click", (e) => { if (e.target.closest("[data-close]")) closeDetail(); });
  $("prevBtn").addEventListener("click", () => { touched(); step(-1); });
  $("nextBtn").addEventListener("click", () => { touched(); step(1); });

  // ---------- Sidebar controls ----------

  const search = $("search");
  search.addEventListener("input", () => {
    touched();
    state.query = search.value.trim();
    applyFilters();
  });

  function bindSlider(id, prop) {
    const input = $(id), out = $(`${id}Out`);
    const sync = () => {
      state[prop] = input.value / 100;
      out.textContent = `${input.value}%`;
    };
    input.addEventListener("input", () => { touched(); sync(); });
    sync();
  }
  bindSlider("objectScale", "objectScale");
  bindSlider("sphereScale", "sphereScale");
  bindSlider("spin", "spin");

  function resetAll() {
    search.value = "";
    state.query = "";
    for (const sel of Object.values(state.selected)) sel.clear();
    state.zoom = 1;
    applyFilters();
  }
  $("resetBtn").addEventListener("click", () => { touched(); resetAll(); });

  $("sidebarToggle").addEventListener("click", () => app.classList.toggle("collapsed"));
  $("fullscreenBtn").addEventListener("click", () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen?.();
  });
  if (window.matchMedia("(max-width: 820px)").matches) app.classList.add("collapsed");

  document.addEventListener("keydown", (e) => {
    touched();
    if (state.openIndex >= 0) {
      if (e.key === "Escape") closeDetail();
      else if (e.key === "ArrowRight") step(1);
      else if (e.key === "ArrowLeft") step(-1);
    } else if (e.key === "/" && document.activeElement !== search) {
      e.preventDefault();
      app.classList.remove("collapsed");
      search.focus();
    }
  });
  document.addEventListener("pointerdown", touched, true);

  // Kiosk idle reset
  if (CONFIG.idleResetSeconds > 0) {
    setInterval(() => {
      if (performance.now() - state.lastInteraction < CONFIG.idleResetSeconds * 1000) return;
      const dirty = state.openIndex >= 0 || state.query || state.zoom !== 1 ||
        Object.values(state.selected).some((s) => s.size);
      if (!dirty) return;
      closeDetail();
      resetAll();
      search.blur();
      $("hint").classList.remove("gone");
    }, 5000);
  }

  // ---------- Sizing ----------

  function resize() {
    const r = stage.getBoundingClientRect();
    state.w = r.width;
    state.h = r.height;
    state.dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(r.width * state.dpr);
    canvas.height = Math.round(r.height * state.dpr);
  }
  new ResizeObserver(resize).observe(stage);

  // ---------- Helpers ----------

  function px(rect) {
    return { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` };
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  // ---------- Start ----------

  resize();
  buildFilterUI();
  applyFilters();
  requestAnimationFrame(frame);
})();
