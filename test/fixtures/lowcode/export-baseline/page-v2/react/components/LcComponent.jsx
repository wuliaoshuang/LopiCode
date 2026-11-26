// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 自定义组件：问候卡
import React from "react";
import "../lc-base.css";
import "./LcComponent.css";

export default function LcComponent({ title = "标题", className, style, ...lcRest }) {
  return (
    <div {...lcRest} className={"lc-card n-c1-k1" + (className ? " " + className : "")} style={style}>
      <p className="lc-text n-c1-k2">{title}</p>
    </div>
  );
}
