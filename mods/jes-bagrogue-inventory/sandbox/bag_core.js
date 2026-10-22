/* ============================================================
 * bag_core.js —— 背包肉鸽核心逻辑（纯数据，零 DOM 依赖）
 * 同一份代码喂两边：Node 测试（module.exports）+ HTML 原型（window.BagCore）
 * 模型：
 *   model = { cfg, bags: {A:{},B:{}}, itemMap: {id: {def, bag, x, y}} }
 *   bags[bag]["列,行"] = id（每个被占格都登记；锚点 = 道具左上角）
 * 规则：
 *   - 只有 A 背包（武器背包）内的道具计入 stats
 *   - drop：空位直落；落点被单个其他道具占住 → 互换锚点；
 *     对方换不动 或 压住 ≥2 个道具 → 整体弹回（bounced）
 * ============================================================ */
(function (root) {
"use strict";

function createModel(cfg, layout) {
  const m = { cfg, bags: { A: {}, B: {} }, itemMap: {} };
  for (const L of layout) {
    m.itemMap[L.def.id] = { def: L.def, bag: L.bag, x: L.x, y: L.y };
    occupy(m, L.def.id);
  }
  return m;
}

function occupy(m, id) {
  const it = m.itemMap[id];
  for (let dy = 0; dy < it.def.h; dy++)
    for (let dx = 0; dx < it.def.w; dx++)
      m.bags[it.bag][(it.x + dx) + "," + (it.y + dy)] = id;
}
function clear(m, id) {
  const it = m.itemMap[id];
  for (let dy = 0; dy < it.def.h; dy++)
    for (let dx = 0; dx < it.def.w; dx++)
      delete m.bags[it.bag][(it.x + dx) + "," + (it.y + dy)];
}

function fits(m, bag, x, y, w, h) {
  const g = m.cfg[bag];
  if (x < 0 || y < 0 || x + w > g.cols || y + h > g.rows) return false;
  for (let iy = y; iy < y + h; iy++)
    for (let ix = x; ix < x + w; ix++)
      if (m.bags[bag][ix + "," + iy]) return false;
  return true;
}

/* 落子。返回 { placed, swapped, bounced }（三者互斥关系：bounced 时后两者为 false） */
function drop(m, id, target, gx, gy) {
  const cur = m.itemMap[id];
  // 越界快速失败 → 弹回
  const g = m.cfg[target];
  if (gx < 0 || gy < 0 || gx + cur.def.w > g.cols || gy + cur.def.h > g.rows)
    return { placed: false, swapped: false, bounced: true };

  clear(m, id);
  // 落点被哪些道具占住
  const occIds = new Set();
  for (let dy = 0; dy < cur.def.h; dy++)
    for (let dx = 0; dx < cur.def.w; dx++) {
      const o = m.bags[target][(gx + dx) + "," + (gy + dy)];
      if (o && o !== id) occIds.add(o);
    }

  let swapped = false;
  if (occIds.size === 1) {
    // 互换：对方搬到我的旧锚点；放不下则双方弹回
    const otherId = occIds.values().next().value;
    const other = m.itemMap[otherId];
    const oldAx = other.x, oldAy = other.y, oldBag = other.bag;
    clear(m, otherId);
    if (fits(m, cur.bag, cur.x, cur.y, other.def.w, other.def.h)) {
      other.bag = cur.bag; other.x = cur.x; other.y = cur.y;
      occupy(m, otherId);
      swapped = true;
    } else {
      other.bag = oldBag; other.x = oldAx; other.y = oldAy;
      occupy(m, otherId);
      occupy(m, id);           // 我也弹回旧锚
      return { placed: false, swapped: false, bounced: true };
    }
  } else if (occIds.size > 1) {
    occupy(m, id);             // 压住多个 → 弹回
    return { placed: false, swapped: false, bounced: true };
  }

  cur.bag = target; cur.x = gx; cur.y = gy;
  occupy(m, id);
  return { placed: true, swapped, bounced: false };
}

/* 属性汇总：只统计 A 背包内的道具 */
function stats(m, base) {
  const s = { ...base };
  for (const id in m.itemMap) {
    const it = m.itemMap[id];
    if (it.bag !== "A") continue;
    for (const k in it.def.stats) s[k] += it.def.stats[k];
  }
  return s;
}

const api = { createModel, fits, drop, stats, occupy, clear };
root.BagCore = api;
if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof self !== "undefined" ? self : this);
