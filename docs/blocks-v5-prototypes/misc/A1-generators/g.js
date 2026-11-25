// 推式：生成器 = 收一个 emit 回调的函数；emit 返回 false 表示“别再给了”
const nat = (emit) => { let i = 1; while (true) { if (!emit(i)) return; i++; } };
const iterMap = (src, f) => (emit) => src((v) => emit(f(v)));
const iterFilter = (src, f) => (emit) => src((v) => f(v) ? emit(v) : true);
const iterTake = (src, n) => (emit) => { let k = 0; if (n <= 0) return; src((v) => { k++; if (!emit(v)) return false; return k < n; }); };
function firstOver(src, limit) { // “对每一项”里提前返回：标志 + 存返回值
  let has = false, ret = null;
  src((v) => { if (v > limit) { has = true; ret = v; return false; } return true; });
  return has ? ret : null;
}
const out = []; iterTake(iterFilter(iterMap(nat, x => x * x), x => x % 2 === 1), 4)((v) => { out.push(v); return true; });
console.log(out.join(","), firstOver(iterMap(nat, x => x * 3), 10));
