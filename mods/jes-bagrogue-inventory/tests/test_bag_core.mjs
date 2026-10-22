// 背包核心逻辑测试（Node headless，先于实现编写 —— TDD 红→绿）
// 运行：node tests/test_bag_core.mjs
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const assert = require("node:assert");

let BagCore;
try { BagCore = require("../sandbox/bag_core.js"); }
catch (e) { console.error("RED: bag_core.js 尚不存在 ——", e.message); process.exit(1); }

const CFG = {
  A: { cols: 7, rows: 5 }, B: { cols: 6, rows: 5 },
  BASE: { atk: 10, spd: 1.0, crit: 5, move: 100, hp: 100 },
};
const IT = (id, w, h, stats) => ({ id, w, h, stats: stats || {} });

let passed = 0, failed = 0;
function t(name, fn) {
  try { fn(); passed++; console.log("  ✔ " + name); }
  catch (e) { failed++; console.error("  ✘ " + name + " —— " + e.message); }
}

console.log("== bag_core 逻辑测试 ==");

t("初始化：道具占格登记（含多格）", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("sword", 1, 2, { atk: 8 }), bag: "A", x: 0, y: 0 },
  ]);
  assert.equal(m.bags.A["0,0"], "sword");
  assert.equal(m.bags.A["0,1"], "sword");
});

t("属性汇总：只有 A 背包生效，B 背包不计入", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("a1", 1, 1, { atk: 8 }), bag: "A", x: 0, y: 0 },
    { def: IT("b1", 1, 1, { atk: 100 }), bag: "B", x: 0, y: 0 },
  ]);
  const s = BagCore.stats(m, CFG.BASE);
  assert.equal(s.atk, 18, "B 包 +100 不得计入");
});

t("移动到空位：成功，占格更新", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("x", 1, 1), bag: "A", x: 3, y: 1 },
  ]);
  const r = BagCore.drop(m, "x", "A", 6, 4);
  assert.ok(r.placed && !r.bounced);
  assert.equal(m.bags.A["6,4"], "x");
  assert.equal(m.bags.A["3,1"], undefined);
});

t("移动出界：弹回原位，占格不变", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("x", 1, 1), bag: "A", x: 3, y: 1 },
  ]);
  const r = BagCore.drop(m, "x", "A", 6, 5); // 行 5 越界（rows=5）
  assert.ok(r.bounced && !r.placed);
  assert.equal(m.bags.A["3,1"], "x");
  assert.equal(m.bags.A["6,5"], undefined);
});

t("互换：1x1 换 1x1，双方锚点交换", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("p", 1, 1), bag: "A", x: 5, y: 3 },
    { def: IT("q", 1, 1), bag: "A", x: 3, y: 1 },
  ]);
  const r = BagCore.drop(m, "p", "A", 3, 1);
  assert.ok(r.placed && r.swapped);
  assert.equal(m.bags.A["3,1"], "p");
  assert.equal(m.bags.A["5,3"], "q");
});

t("互换失败（对方在新锚放不下）：双方弹回，占格不变", () => {
  // q 是 1x3 竖条在 (0,0)-(0,2)；p 1x1 在 (6,4) 角落
  const m = BagCore.createModel(CFG, [
    { def: IT("q", 1, 3), bag: "A", x: 0, y: 0 },
    { def: IT("p", 1, 1), bag: "A", x: 6, y: 4 },
  ]);
  const r = BagCore.drop(m, "p", "A", 0, 1); // 拖 p 盖住 q 中段
  // q 要搬去 p 的旧锚 (6,4)：需 (6,4)(6,5)(6,6) → 行 5/6 越界，换不动
  assert.ok(r.bounced && !r.placed && !r.swapped, "应整体弹回");
  assert.equal(m.bags.A["6,4"], "p");
  assert.equal(m.bags.A["0,1"], "q");
});

t("落点压住两个道具：不互换，弹回", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("x", 1, 1), bag: "A", x: 0, y: 0 },
    { def: IT("y", 1, 1), bag: "A", x: 1, y: 0 },
    { def: IT("z", 2, 1), bag: "A", x: 4, y: 0 },
  ]);
  const r = BagCore.drop(m, "z", "A", 0, 0); // 压住 x、y 两个
  assert.ok(r.bounced && !r.placed);
  assert.equal(m.bags.A["4,0"], "z");
});

t("跨包拖动：生效状态随包切换（A→B 属性降，B→A 属性升）", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("x", 1, 1, { atk: 3 }), bag: "A", x: 3, y: 1 },
  ]);
  assert.equal(BagCore.stats(m, CFG.BASE).atk, 13);
  BagCore.drop(m, "x", "B", 0, 0);
  assert.equal(BagCore.stats(m, CFG.BASE).atk, 10, "进 B 包应失效");
  assert.equal(m.bags.B["0,0"], "x");
  BagCore.drop(m, "x", "A", 6, 4);
  assert.equal(BagCore.stats(m, CFG.BASE).atk, 13, "回 A 包应重新生效");
});

t("互换可跨包进行", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("p", 1, 1), bag: "A", x: 3, y: 1 },
    { def: IT("q", 1, 1), bag: "B", x: 2, y: 2 },
  ]);
  const r = BagCore.drop(m, "p", "B", 2, 2);
  assert.ok(r.placed && r.swapped);
  assert.equal(m.bags.B["2,2"], "p");
  assert.equal(m.bags.A["3,1"], "q");
});

t("负属性道具：生效时扣减，失效时还原", () => {
  const m = BagCore.createModel(CFG, [
    { def: IT("curse", 1, 1, { hp: -15 }), bag: "A", x: 0, y: 4 },
  ]);
  assert.equal(BagCore.stats(m, CFG.BASE).hp, 85);
  BagCore.drop(m, "curse", "B", 0, 0);
  assert.equal(BagCore.stats(m, CFG.BASE).hp, 100);
});

console.log(`\n结果：${passed} 通过 / ${failed} 失败`);
process.exit(failed ? 1 : 0);
