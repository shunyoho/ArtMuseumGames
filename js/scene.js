// 背景場景：從樹下往上看的楓樹，葉叢和枝條隨風擺動、楓葉飄落、雲朵飄過
// 每叢樹葉只在載入時畫一次，之後動畫只移動畫好的圖，手機不用一直重畫葉子
(function () {
  const LEAF = 'M12 1 14 6 17 4.5 16 9.5 20 8 19 11 23 12 19.5 15 20.5 17 14.5 16.5 13 17 12.7 23 11.3 23 11 17 9.5 16.5 3.5 17 4.5 15 1 12 5 11 4 8 8 9.5 7 4.5 10 6Z';
  const CLOUD = '<svg viewBox="0 -8 90 48" aria-hidden="true"><g fill="#fff"><ellipse cx="42" cy="26" rx="42" ry="13"/><circle cx="27" cy="17" r="14"/><circle cx="50" cy="12" r="18"/><circle cx="68" cy="19" r="11"/></g></svg>';
  const LEAF_COLORS = ['#e3242b', '#f0483e', '#ff7a2a', '#f7a23b', '#c8141c'];

  // 場景以 375×640 為基準，貼齊畫面右上角
  const BASE_W = 375, BASE_H = 640, MAX_SCALE = 1.5;

  // 葉叢：[中心 x, 中心 y, 半徑, 亂數種子]；種子固定，每次畫出來的樹都一樣
  const BACK = [[300, 30, 88, 20261031], [352, 128, 88, 1131303467], [262, 128, 84, 939452520], [170, 120, 58, 1077402738], [332, 246, 76, 1985462939], [250, 232, 62, 540888485], [368, 322, 52, 531894947]];
  const FRONT = [[338, 62, 60, 93306768], [256, 62, 60, 1872099295], [302, 160, 60, 2011093652], [214, 166, 52, 1557027042], [136, 150, 36, 1057266438], [358, 214, 50, 1045260711], [282, 262, 52, 57207852], [204, 248, 40, 1086108675], [336, 322, 44, 1321185903], [256, 330, 32, 469249057]];
  const TOP = [[326, 120, 26, 1226323984], [236, 70, 22, 2092706286], [272, 214, 24, 825454677], [186, 196, 18, 1513645649], [318, 276, 24, 1439727126], [150, 120, 16, 115606525]];
  const BRANCH_SEED = 1568607951;

  let seed = 1;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;

  const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const mix = (a, b, t) => {
    const k = Math.max(0, Math.min(1, t));
    return a.map((v, i) => Math.round(v + (b[i] - v) * k));
  };
  const rgb = (c) => `rgb(${c.join(',')})`;

  const DARK = hex('#6e0d14'), DEEP = hex('#a8141c'), RED = hex('#d9231f'), ORANGE = hex('#f4661c'), AMBER = hex('#ffa52e');

  // 樹冠上方偏紅、下方偏橘，顏色跟著葉叢的高度走
  const baseAt = (y) => {
    const t = y / 380;
    return t < .5 ? mix(DEEP, RED, t * 2) : mix(RED, ORANGE, (t - .5) * 2);
  };

  // 一叢樹葉：先鋪暗色底，再由暗到亮疊上很多片小楓葉；左上受光、右下背光，每叢才看得出體積
  function drawClump([cx, cy, R, clumpSeed], depth, pixelRatio) {
    seed = clumpSeed;
    const size = Math.ceil(R * 2.6);
    const cv = document.createElement('canvas');
    cv.width = cv.height = size * pixelRatio;
    cv.className = 'clump';
    cv.style.cssText = `left:${cx - size / 2}px;top:${cy - size / 2}px;width:${size}px;height:${size}px;--d:${(4 + rnd() * 3.5).toFixed(1)}s;--dl:${(-rnd() * 6).toFixed(1)}s;--a:${(.9 + rnd() * 1.4).toFixed(1)}deg`;
    const g = cv.getContext('2d');
    g.scale(pixelRatio, pixelRatio);
    g.translate(size / 2, size / 2);

    const base = mix(baseAt(cy), DARK, depth);
    g.fillStyle = rgb(mix(base, DARK, .55));
    for (let i = 0; i < 12; i++) {
      const a = rnd() * 6.283, d = R * .5 * rnd();
      g.beginPath();
      g.arc(Math.cos(a) * d, Math.sin(a) * d, R * (.28 + rnd() * .16), 0, 6.283);
      g.fill();
    }

    const leaves = Array.from({ length: Math.round(R * R * .07) }, () => {
      const a = rnd() * 6.283, d = R * Math.pow(rnd(), .62), x = Math.cos(a) * d, y = Math.sin(a) * d * .9;
      const lit = .5 - (y * .75 + x * .4) / R * .55 + (rnd() - .5) * .42;
      return { x, y, lit, s: (7 + rnd() * 8) * (.8 + R / 170) };
    }).sort((p, q) => p.lit - q.lit);

    const path = new Path2D(LEAF);
    for (const { x, y, lit, s } of leaves) {
      const c = lit < .5
        ? mix(mix(base, DARK, .6), base, lit * 2)
        : mix(base, mix(ORANGE, AMBER, cy / 380), (lit - .5) * 2 * (1 - depth));
      g.save();
      g.translate(x, y);
      g.rotate(rnd() * 6.283);
      g.scale(s / 24, s / 24);
      g.translate(-12, -12);
      g.fillStyle = rgb(c);
      g.fill(path);
      g.restore();
    }
    return cv;
  }

  // 左上的樹枝不能伸出葉叢外；超出的段落不畫，但照常跑亂數，其他枝條的形狀才不會變
  const outsideCanopy = (x, y) => y < 140 && x < 245 - y * .4;
  let twigCount = 0;

  // 枝幹一段一段往外長，每個分岔都是一組，繞著分岔點轉，而且包在上一層裡面：
  // 越末端累積的擺幅越大，風吹過去也會一層層晚一點才到
  function growBranch(x, y, ang, len, w, depth, level = 0, hidden = false) {
    const x0 = x, y0 = y;
    let body = '';
    const wrap = () => {
      if (!body) return '';
      const n = twigCount++;
      return `<g class="twig" style="transform-origin:${x0.toFixed(1)}px ${y0.toFixed(1)}px;--d:${(4.2 + (n % 5) * .5).toFixed(1)}s;--dl:${(-level * .4 - (n % 3) * .5).toFixed(1)}s;--a:${(.5 + level * .45).toFixed(2)}deg">${body}</g>`;
    };
    for (let i = 0; i < 3; i++) {
      ang += (rnd() - .5) * .42;
      const nx = x + Math.cos(ang) * len, ny = y + Math.sin(ang) * len;
      if (nx < 100 || ny < 4 || ny > 318) return wrap();
      hidden = hidden || outsideCanopy(nx, ny);
      if (!hidden) body += `<line x1="${x.toFixed(1)}" y1="${y.toFixed(1)}" x2="${nx.toFixed(1)}" y2="${ny.toFixed(1)}" stroke-width="${Math.max(w, 2).toFixed(1)}"/>`;
      x = nx; y = ny; w *= .86;
    }
    if (depth > 0) {
      const spread = .32 + rnd() * .32;
      body += growBranch(x, y, ang + spread, len * .78, w * .78, depth - 1, level + 1, hidden);
      body += growBranch(x, y, ang - spread, len * .78, w * .68, depth - 1, level + 1, hidden);
    }
    return wrap();
  }

  function branchesHtml() {
    seed = BRANCH_SEED;
    twigCount = 0;
    const limbs = growBranch(395, 34, Math.PI - .55, 22, 20, 4) + growBranch(395, 170, Math.PI - .35, 18, 14, 3);
    return `<svg class="branches" viewBox="0 0 ${BASE_W} ${BASE_H}" aria-hidden="true"><g stroke="#4a2415" stroke-linecap="round">${limbs}</g></svg>`;
  }

  function cloudHtml(y, s, d, dl) {
    return `<span class="cloud" style="top:${y}px;width:${Math.round(90 * s)}px;--d:${d}s;--dl:${dl}s">${CLOUD}</span>`;
  }

  function fallingLeavesHtml(viewH) {
    return Array.from({ length: 16 }, (_, i) => {
      const l = 60 + (i * 47) % 300, t = 90 + (i * 53) % 270, s = 12 + (i * 5) % 13;
      const d = 9 + (i * 3) % 8, dl = -(i * 1.9), x = -(70 + (i * 37) % 190), y = viewH + 20 - t - (i * 7) % 40;
      return `<span class="lf" style="left:${l}px;top:${t}px;width:${s}px;height:${s}px;--d:${d}s;--dl:${dl}s;--x:${x}px;--y:${y}px;--f:${1.4 + (i % 4) * .5}s"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="${LEAF_COLORS[i % 5]}" d="${LEAF}"/></svg></span>`;
    }).join('');
  }

  function build() {
    const vw = window.innerWidth, vh = window.innerHeight;
    const scale = Math.min(Math.max(vw / BASE_W, 1), MAX_SCALE);
    const pixelRatio = Math.min((window.devicePixelRatio || 1) * scale, 3);

    const scene = document.createElement('div');
    scene.className = 'scene';
    scene.setAttribute('aria-hidden', 'true');
    scene.style.setProperty('--w', `${vw + 160}px`);
    const ky = vh / BASE_H;
    scene.innerHTML = cloudHtml(250 * ky, 1.3, 70, -30) + cloudHtml(345 * ky, .9, 95, -70)
      + cloudHtml(150 * ky, .7, 120, -20) + cloudHtml(440 * ky, 1.1, 85, -5);

    const canopy = document.createElement('div');
    canopy.className = 'canopy';
    canopy.style.transform = `scale(${scale})`;
    BACK.forEach((c) => canopy.append(drawClump(c, .3, pixelRatio)));
    [[282, 205, 84, 3.8, 0], [325, 108, 64, 3.2, -1]].forEach(([x, y, s, d, dl]) =>
      canopy.insertAdjacentHTML('beforeend', `<span class="glow" style="left:${x - s / 2}px;top:${y - s / 2}px;width:${s}px;height:${s}px;--d:${d}s;--dl:${dl}s"></span>`));
    FRONT.forEach((c) => canopy.append(drawClump(c, 0, pixelRatio)));
    // 枝幹放在大部分葉叢前面才看得清楚，再用幾小叢葉子蓋住局部，像枝條穿過樹葉
    canopy.insertAdjacentHTML('beforeend', branchesHtml());
    TOP.forEach((c) => canopy.append(drawClump(c, 0, pixelRatio)));
    canopy.insertAdjacentHTML('beforeend', fallingLeavesHtml(vh / scale));
    scene.append(canopy);

    document.querySelector('.scene')?.remove();
    document.body.prepend(scene);
  }

  build();

  // 手機捲動時網址列伸縮也會觸發 resize，所以只有寬度變了（例如轉向）才重畫
  let lastWidth = window.innerWidth, timer;
  window.addEventListener('resize', () => {
    if (window.innerWidth === lastWidth) return;
    lastWidth = window.innerWidth;
    clearTimeout(timer);
    timer = setTimeout(build, 200);
  });
})();
