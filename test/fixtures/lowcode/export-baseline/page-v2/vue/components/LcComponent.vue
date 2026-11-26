<script setup>
// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 自定义组件：问候卡

defineProps({
  title: { type: String, default: "标题" },
});
</script>

<template>
  <div class="lc-card n-c1-k1">
    <p class="lc-text n-c1-k2">{{ title }}</p>
  </div>
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

.n-c1-k1 {
  padding: 12px;
  gap: 8px;
}
</style>
