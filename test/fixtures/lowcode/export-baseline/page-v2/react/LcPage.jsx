// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份代码：
// - 页面变量在 lcVars 里，逻辑里读或改到的控件属性在 lcUi 里。它们是 useRef 里的普通对象：读到的永远是最新的值，
//   写完马上生效（请求回来、等一会儿之后也一样）。每次写完调用 lcRefresh()，React 才会重新画界面。
// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木（改的是 lcUi）。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
import React, { useRef, useState } from "react";
import "./lc-base.css";
import "./LcPage.css";
import LcComponent from "./components/LcComponent.jsx";

// —— 小工具 ——
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

export default function LcPage() {
  // 页面变量
  const lcVars = useRef({
    count: 0,
  }).current;
  // 控件属性：逻辑里读或改到的那些（下面的界面绑定着它们）
  const lcUi = useRef({
  }).current;
  // 改了上面两样以后调用它，让 React 重新画一遍界面
  const [, lcSetTick] = useState(0);
  function lcRefresh() {
    lcSetTick((n) => n + 1);
  }

  // 点击「按钮“加一”」时
  function onClick_n3_h1(event) {
    lcVars.count = 1;
    lcRefresh();
  }

  // —— 界面 ——
  return (
    <main className="lc-page n-root">
      <p className="lc-text n-n1">标题</p>
      <div className="lc-row n-n2">
        <button type="button" className="lc-button n-n3" onClick={onClick_n3_h1}>加一</button>
        <p className="lc-text n-n4">0</p>
      </div>
      <LcComponent className="lc-component n-n5" />
      <div className="lc-container n-n6">
      </div>
    </main>
  );
}
