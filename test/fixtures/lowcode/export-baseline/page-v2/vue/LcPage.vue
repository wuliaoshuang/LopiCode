<script setup>
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份脚本：
// - 页面变量是下面的 ref；每个“处理”是一个函数，模板里用 @click / @input 挂在控件上。
// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木：它改的是下面“控件属性”里的 ref，模板绑定着它们。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
import { ref } from "vue";
import LcComponent from "./components/LcComponent.vue";

// 页面变量
const count = ref(0);

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

// 点击「按钮“加一”」时
function onClick_n3_h1(event) {
  count.value = 1;
}
</script>

<template>
  <main class="lc-page n-root">
    <p class="lc-text n-n1">标题</p>
    <div class="lc-row n-n2">
      <button type="button" class="lc-button n-n3" @click="onClick_n3_h1">加一</button>
      <p class="lc-text n-n4">0</p>
    </div>
    <LcComponent class="lc-component n-n5" />
    <div class="lc-container n-n6">
    </div>
  </main>
</template>

<style scoped>
.lc-page, .lc-container, .lc-row, .lc-column, .lc-card, .lc-text, .lc-button, .lc-image, .lc-input, .lc-list, .lc-divider, .lc-spacer, .lc-component {
  box-sizing: border-box;
}

.lc-page {
  font-family: system-ui, -apple-system, "PingFang SC", "Noto Sans SC", sans-serif;
  color: #222435;
}

.lc-page, .lc-container, .lc-column, .lc-card {
  display: flex;
  flex-direction: column;
}

.lc-row {
  display: flex;
  flex-direction: row;
}

.lc-page {
  min-height: 100vh;
}

.lc-card {
  box-shadow: 0 1px 3px rgba(0, 0, 0, .2);
}

.lc-text {
  margin: 0;
  line-height: 1.5;
}

.lc-button {
  border: 0;
  cursor: pointer;
  font: inherit;
}

.lc-input {
  border: 1px solid #b1c0c8;
  font: inherit;
  padding: 10px 12px;
  min-width: 0;
}

.lc-image {
  display: block;
  max-width: 100%;
  object-fit: cover;
  background: #d3dee4;
}

.lc-list {
  margin: 0;
  padding-left: 20px;
  line-height: 1.75;
}

.lc-divider {
  border: 0;
  border-top: 1px solid #d3dee4;
  margin: 0;
  align-self: stretch;
}

.n-root {
  padding: 16px;
  background: #f6f7fb;
  gap: 12px;
}

.n-n1 {
  font-size: 1.5em;
  font-weight: 700;
}

.n-n2 {
  align-self: stretch;
  gap: 8px;
  justify-content: space-between;
}

.n-n6 {
  align-self: stretch;
  min-height: 48px;
}
</style>
