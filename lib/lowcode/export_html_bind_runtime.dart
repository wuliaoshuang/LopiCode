/// 普通网页导出里“状态与绑定”的那一小段运行代码（第 5 期）。不依赖任何库。只有用了绑定的页面才带。
///
/// 三条规矩（和 D 分册一致）：改状态立刻生效（下一句就读得到新值）；派生值读的时候才算，算过记着，
/// 有状态改了就作废；界面攒到这一段代码跑完再统一更新一次（排在微任务里）。
library;

/// 用了绑定的页面里，挂事件改成“托给整页”：重复出来的每一份、条件满足后才出现的控件，事件一样管用。
const String lcJsDelegatedOn = r'''
// 给控件挂事件。挂在整页上、看点的是不是这个控件（或它里面）：重复出来的每一份、后来才出现的控件也管用。
function lcOn(id, type, handler) {
  document.addEventListener(type, (event) => {
    const t = event.target;
    if (t && t.closest && t.closest(".n-" + id)) handler(event);
  });
}
''';

const String lcJsBindRuntime = r'''
// —— 状态与绑定 ——
// state.名字 读写状态；写了以后，绑了它的地方会在这一段代码跑完后统一更新（不用自己去改控件）。
// 注意：往列表里直接 push、直接改记录里的一格，界面不知道；要换成一个新的列表 / 记录再写回去，或者改完调一下 lcChanged()。
let lcCache = Object.create(null);
let lcQueued = false;

// 项目级状态放在 sessionStorage 里，换到别的页还在（关掉这个标签页就没了）。
function lcLoadShared() {
  try {
    const saved = JSON.parse(sessionStorage.getItem("lc-state") || "{}");
    for (const k of lcSharedNames) {
      if (Object.prototype.hasOwnProperty.call(saved, k)) lcData[k] = saved[k];
    }
  } catch (e) {
    // 读不了（隐私模式、内容坏了）：就用初值。
  }
}

function lcSaveShared() {
  try {
    const saved = JSON.parse(sessionStorage.getItem("lc-state") || "{}");
    for (const k of lcSharedNames) saved[k] = lcData[k];
    sessionStorage.setItem("lc-state", JSON.stringify(saved));
  } catch (e) {
    // 存不了：这一页照常用，只是换页以后带不过去。
  }
}

function lcMakeState() {
  const s = {};
  for (const k of Object.keys(lcData)) {
    Object.defineProperty(s, k, {
      enumerable: true,
      get() {
        return lcData[k];
      },
      set(v) {
        lcData[k] = v;
        lcChanged(k);
      },
    });
  }
  for (const k of Object.keys(lcDerived)) {
    Object.defineProperty(s, k, {
      enumerable: true,
      get() {
        if (!(k in lcCache)) {
          lcCache[k] = undefined; // 绕回来用到自己时读到空的，不会死循环
          lcCache[k] = lcDerived[k]();
        }
        return lcCache[k];
      },
      set() {
        // 派生值是算出来的，写它不起作用。
      },
    });
  }
  return s;
}

// 有状态变了：派生值作废，排一次界面更新。
function lcChanged(k) {
  lcCache = Object.create(null);
  if (k === undefined || lcSharedNames.indexOf(k) >= 0) lcSaveShared();
  if (lcQueued) return;
  lcQueued = true;
  Promise.resolve().then(lcRender);
}

function lcRender() {
  lcQueued = false;
  lcApply(document, undefined, Object.create(null));
}

function lcFind(root, id) {
  if (root.classList && root.classList.contains("n-" + id)) return root;
  return root.querySelector(".n-" + id);
}

// “重复”和“存在条件”：原来那个元素从页面上拿下来当样板，原地留一个记号。
function lcSlot(root, b) {
  const all = root.lcSlots || (root.lcSlots = Object.create(null));
  if (all[b.id]) return all[b.id];
  const el = lcFind(root, b.id);
  if (!el || el === root) return null;
  const mark = document.createComment("lc " + b.id);
  el.parentNode.insertBefore(mark, el);
  el.parentNode.removeChild(el);
  el.style.display = "";
  if (!el.getAttribute("style")) el.removeAttribute("style");
  return (all[b.id] = { mark: mark, tpl: el, live: new Map(), on: false, empty: null });
}

// 把归 owner 管的绑定在 root 里过一遍。s 是“重复”带出来的这一项 / 序号。
function lcApply(root, owner, s) {
  for (const b of lcBinds) {
    if (b.in !== owner) continue;
    if (b.each) {
      lcEach(root, b, s);
      continue;
    }
    let el;
    if (b.when) {
      const slot = lcSlot(root, b);
      if (!slot) continue;
      const on = !!b.when(s);
      if (on && !slot.on) slot.mark.parentNode.insertBefore(slot.tpl, slot.mark.nextSibling);
      if (!on && slot.on) slot.tpl.parentNode.removeChild(slot.tpl);
      slot.on = on;
      if (!on) continue;
      el = slot.tpl;
    } else {
      el = lcFind(root, b.id);
    }
    if (el) lcPaint(el, b, s);
  }
}

// 重复：按标识认项——还在的留着（只挪位置），新来的照样板做一份，没了的拿掉。
function lcEach(root, b, s) {
  const slot = lcSlot(root, b);
  if (!slot) return;
  const list = lcList(b.each(s));
  const live = new Map();
  let prev = slot.mark;
  for (let i = 0; i < list.length; i++) {
    const sc = Object.assign(Object.create(null), s);
    sc[b.item] = list[i];
    sc[b.index] = i;
    if (b.only && !b.only(sc)) continue;
    let k = b.key ? b.key(sc) : i;
    k = typeof k + ":" + String(k);
    while (live.has(k)) k += "#";
    const el = slot.live.get(k) || slot.tpl.cloneNode(true);
    if (prev.nextSibling !== el) prev.parentNode.insertBefore(el, prev.nextSibling);
    live.set(k, el);
    prev = el;
    lcApply(el, b.id, sc);
  }
  slot.live.forEach((el, k) => {
    if (live.get(k) !== el && el.parentNode) el.parentNode.removeChild(el);
  });
  slot.live = live;
  if (!b.empty) return;
  if (live.size === 0 && !slot.empty) {
    slot.empty = document.createElement("p");
    slot.empty.className = "lc-text lc-empty";
    slot.empty.textContent = b.empty;
    slot.mark.parentNode.insertBefore(slot.empty, slot.mark.nextSibling);
  } else if (live.size > 0 && slot.empty) {
    slot.empty.parentNode.removeChild(slot.empty);
    slot.empty = null;
  }
}

// 只换文字，不动里面的图标之类。
function lcSetText(el, t) {
  let node = null;
  for (const c of el.childNodes) {
    if (c.nodeType === 3) node = c;
  }
  if (!node) el.appendChild(document.createTextNode(t));
  else if (node.nodeValue !== t) node.nodeValue = t;
}

// 这个控件里真正能填能点的那一个（或几个：单选组）。
function lcControls(el) {
  if (el.matches("input, textarea, select")) return [el];
  return Array.from(el.querySelectorAll("[data-lc-c]"));
}

function lcSetAttr(el, name, v) {
  if (name === "disabled") {
    el.disabled = !!v;
  } else if (name === "src" && el.tagName !== "IMG") {
    el.style.backgroundImage = "url(" + JSON.stringify(lcText(v)) + ")";
    el.style.backgroundSize = "cover";
    el.style.backgroundPosition = "center";
  } else if (name === "alt" && el.tagName !== "IMG") {
    el.setAttribute("aria-label", lcText(v));
  } else if (el.getAttribute(name) !== lcText(v)) {
    el.setAttribute(name, lcText(v));
  }
}

// 把一个控件上的各种绑定按现在的状态画一遍。
function lcPaint(el, b, s) {
  if (b.show) el.style.display = b.show(s) ? "" : "none";
  if (b.text) lcSetText(el, lcText(b.text(s)));
  if (b.parts) {
    for (const p of Object.keys(b.parts)) {
      const t = el.querySelector('[data-lc-t="' + b.id + ":" + p + '"]');
      if (t) lcSetText(t, lcText(b.parts[p](s)));
    }
  }
  if (b.attr) {
    for (const a of Object.keys(b.attr)) {
      const v = b.attr[a](s);
      const on = a === "disabled" || a === "placeholder" ? lcControls(el) : [el];
      (on.length ? on : [el]).forEach((t) => lcSetAttr(t, a, v));
    }
  }
  if (b.items) {
    const items = lcList(b.items(s)).map(lcText);
    const sig = JSON.stringify(items);
    if (el.lcItems !== sig) {
      el.lcItems = sig;
      el.textContent = "";
      for (const x of items) el.appendChild(document.createElement("li")).textContent = x;
    }
  }
  if (b.cls) {
    for (const c of Object.keys(b.cls)) el.classList.toggle(c, !!b.cls[c](s));
  }
  if (b.style) {
    for (const p of Object.keys(b.style)) {
      const v = lcText(b.style[p](s));
      if (v === "") el.style.removeProperty(p);
      else el.style.setProperty(p, v);
    }
  }
  if (b.model) lcModel(el, b.model);
}

// 双向：状态 → 控件（这里）；控件 → 状态（第一次画的时候挂上监听）。
function lcModel(el, m) {
  const v = state[m.name];
  lcControls(el).forEach((c) => {
    const radio = c.type === "radio";
    if (radio) c.checked = lcText(v) === c.value;
    else if (m.prop === "checked") c.checked = !!v;
    else if (m.num ? document.activeElement !== c || lcNum(c.value) !== v : c.value !== lcText(v)) c.value = lcText(v);
    if (c.lcModel) return;
    c.lcModel = true;
    c.addEventListener(radio || c.type === "checkbox" || c.tagName === "SELECT" ? "change" : "input", () => {
      if (radio) {
        if (c.checked) state[m.name] = m.num ? lcNum(c.value) : c.value;
      } else if (m.prop === "checked") state[m.name] = c.checked;
      else state[m.name] = m.num ? lcNum(c.value) : c.value;
    });
  });
}
''';
