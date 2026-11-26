// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
import React from "react";
import "./lc-base.css";
import "./Demo.css";

export default function Demo() {
  // —— 界面 ——
  return (
    <main className="lc-page n-root">
      <p className="lc-text n-t1">{"欢迎 <b>'回来'<\/b> $5"}</p>
      <div className="lc-card n-card">
        <input className="lc-input n-in" placeholder={"手机号"} />
        <div className="lc-row n-row">
          <button type="button" className="lc-button n-b1">登录</button>
          <button type="button" className="lc-button n-b2">注册</button>
          <input className="lc-input n-in2" placeholder={"行内输入"} />
          <p className="lc-text n-tx">行内文本</p>
          <hr className="lc-divider n-dv" />
          <div className="lc-spacer n-sp"></div>
        </div>
      </div>
      <div className="lc-image n-img" role="img" aria-label="图片占位"></div>
      <img className="lc-image n-img2" src={"https://example.com/a.png"} alt="" />
      <ul className="lc-list n-ls">
        <li>一</li>
        <li>{"二 & 三"}</li>
      </ul>
      <div className="lc-column n-col">
        <div className="lc-container n-c1">
        </div>
      </div>
      <hr className="lc-divider n-dv2" />
      <div className="lc-spacer n-sp2"></div>
    </main>
  );
}
