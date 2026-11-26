// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份脚本：
// - 页面变量都在 state 里；每个“处理”是下面的一个函数；最后的 lcStart 把它们挂到控件上。
// - 变量改了以后，界面上不会自动跟着变（没有数据绑定）。要让界面变，用“改控件”积木（下面的 lcSet）。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）；除以 0 的结果也当 0。要拼文字用“拼成文字”。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
"use strict";

// 页面变量
const state = {
  count: 0,
};

// —— 小工具（每份导出都一样）——
// 转成数字：输入框里读到的是文字，做加减乘除前要先转。转不了的（空的、不是数字的文字）当 0。
function lcNum(v) {
  const n = typeof v === "string" ? Number(v.trim()) : Number(v);
  return Number.isFinite(n) ? n : 0;
}

// 转成文字。数字去掉浮点误差（0.1 + 0.2 显示成 0.3）。
function lcText(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "number") return String(Number(v.toPrecision(12)));
  return String(v);
}

// “等于”：类型一样直接比；不一样就都转成文字再比（所以输入框里的 "5" 等于数字 5）。
function lcEq(a, b) {
  return typeof a === typeof b ? a === b : lcText(a) === lcText(b);
}

// 输入事件里，输入框现在的内容。
function lcEventValue(event) {
  const el = event && event.target;
  return el && el.value !== null && el.value !== undefined ? String(el.value) : "";
}

// 按控件 id 找页面上的元素（导出的 HTML 里每个控件都带 class "n-<id>"）。找不到返回 null。
function lcEl(id) {
  return document.querySelector(".n-" + id);
}

// 读控件：文字 / 输入内容 / 是否显示。
function lcGet(id, prop) {
  const el = lcEl(id);
  if (prop === "visible") return !!el && el.style.display !== "none";
  if (!el) return "";
  const v = prop === "value" ? el.value : el.textContent;
  return v === null || v === undefined ? "" : String(v);
}

// 改控件。显示 / 隐藏用 style.display：隐藏设成 "none"，显示时清掉这一条，让样式表里原来的 display（比如 flex）重新生效。
function lcSet(id, prop, value) {
  const el = lcEl(id);
  if (!el) return;
  if (prop === "text") el.textContent = value;
  else if (prop === "value") el.value = value;
  else if (prop === "visible") el.style.display = value ? "" : "none";
  else if (prop === "bg") el.style.background = value;
  else if (prop === "color") el.style.color = value;
  else if (prop === "placeholder") el.placeholder = value;
  else if (prop === "src") {
    if (el.tagName === "IMG") el.src = value;
    else {
      // 没填图片地址的图片导出的是一个占位的 <div>，没有 src：改成背景图。
      el.style.backgroundImage = "url(" + JSON.stringify(value) + ")";
      el.style.backgroundSize = "cover";
      el.style.backgroundPosition = "center";
    }
  }
}

// 给控件挂事件。
function lcOn(id, type, handler) {
  const el = lcEl(id);
  if (el) el.addEventListener(type, handler);
}

// 点击「按钮“加一”」时
function onClick_n3_h1(event) {
  state.count = 1;
}

// 页面准备好以后：把处理挂到控件上，再执行“页面打开时”的处理。
function lcStart() {
  lcOn("n3", "click", onClick_n3_h1);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", lcStart);
} else {
  lcStart();
}
