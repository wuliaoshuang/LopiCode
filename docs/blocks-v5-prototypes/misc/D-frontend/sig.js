// 草稿：最小“状态 / 派生 / 跟着变”运行时（约 70 行），只为验证第 4 节的语义，不是产品代码。
let cur = null, queue = new Set(), scheduled = false, depth = 0;
function track(src){ if(cur){ src.subs.add(cur); cur.deps.add(src); } }
function drop(node){ for(const d of node.deps) d.subs.delete(node); node.deps.clear(); }
function notify(src){ for(const s of [...src.subs]) s.mark(); }
function state(v){ const s={subs:new Set(), get(){track(s);return v;}, set(n){ if(Object.is(n,v))return; v=n; notify(s);} }; return s; }
function derived(fn){ const d={subs:new Set(),deps:new Set(),dirty:true,val:undefined,busy:false,
  mark(){ if(!d.dirty){ d.dirty=true; notify(d);} },
  get(){ track(d); if(d.dirty){ if(d.busy) throw new Error("派生值绕回了自己"); d.busy=true; drop(d); const p=cur; cur=d; try{ d.val=fn(); } finally{ cur=p; d.busy=false; } d.dirty=false; } return d.val; } }; return d; }
function effect(fn){ const e={deps:new Set(),clean:null,dead:false,
  mark(){ if(!e.dead){ queue.add(e); if(!scheduled){ scheduled=true; queueMicrotask(flush);} } },
  run(){ if(e.dead)return; if(e.clean){ const c=e.clean; e.clean=null; c(); } drop(e); const p=cur; cur=e; try{ const r=fn(); if(typeof r==="function") e.clean=r; } finally{ cur=p; } },
  stop(){ e.dead=true; if(e.clean) e.clean(); drop(e); queue.delete(e);} }; e.run(); return e; }
function flush(){ scheduled=false; if(++depth>100){ depth=0; queue.clear(); throw new Error("跟着变的积木互相触发超过 100 轮"); }
  const q=[...queue]; queue.clear(); for(const e of q) e.run(); if(queue.size) flush(); depth=0; }
// —— 假控件 ——
const el={text:"",shown:true,writes:0};
const tick=()=>new Promise(r=>setTimeout(r,0));
const out=[]; const ok=(name,cond)=>out.push((cond?"通过":"失败")+"  "+name);
(async()=>{
  // 1 先写后读立刻生效
  const n=state(0); n.set(n.get()+1); n.set(n.get()+1); ok("1 先写后读立刻生效（连加两次得 2）", n.get()===2);
  // 2 绑定：文字跟着变；一轮里改 3 次只写 1 次控件
  const dbl=derived(()=>n.get()*2); effect(()=>{ el.text="两倍是 "+dbl.get(); el.writes++; });
  const w0=el.writes; n.set(3); n.set(4); n.set(5); ok("2a 派生值同步可读（改完马上读得 10）", dbl.get()===10);
  ok("2b 这一刻控件还没改（等这一轮做完）", el.text==="两倍是 4"); await tick();
  ok("2c 一轮改 3 次，控件只写 1 次", el.text==="两倍是 10" && el.writes===w0+1);
  // 3 菱形：a→b,c→d，d 只算 1 次、不出现半新半旧
  const a=state(1); let calc=0; const b=derived(()=>a.get()+1), c=derived(()=>a.get()*10);
  const d=derived(()=>{calc++; return b.get()+c.get();}); const seen=[]; effect(()=>seen.push(d.get()));
  a.set(2); await tick(); ok("3 菱形依赖：只看到 12 和 23，d 共算 2 次", seen.join()==="12,23" && calc===2);
  // 4 依赖会变：开关关掉以后不再跟着另一个变
  const on=state(true), x=state("x1"); let runs=0; effect(()=>{ runs++; if(on.get()) x.get(); });
  on.set(false); await tick(); const r1=runs; x.set("x2"); await tick(); ok("4 条件里的依赖关掉后不再触发", runs===r1);
  // 5 值没变不触发
  const r2=el.writes; n.set(5); await tick(); ok("5 设成同一个值不触发", el.writes===r2);
  // 6 收尾：重跑前和停掉时各叫一次
  const k=state(0); const log=[]; const e=effect(()=>{ const v=k.get(); log.push("开"+v); return ()=>log.push("收"+v); });
  k.set(1); await tick(); e.stop(); k.set(2); await tick(); ok("6 收尾顺序 开0,收0,开1,收1；停掉后不再跑", log.join()==="开0,收0,开1,收1");
  // 7 在“跟着变”里改它自己看的状态：到 100 轮报错而不是卡死
  const z=state(0); let err=null; process.once("uncaughtException",x=>{err=x;}); effect(()=>{ z.set(z.get()+1); });
  await tick(); await tick(); ok("7 自己触发自己：报错停下（"+(err&&err.message)+"）", !!err);
  // 8 派生值绕回自己
  let d1,d2; d1=derived(()=>d2.get()); d2=derived(()=>d1.get()); let e8=null; try{ d1.get(); }catch(x){ e8=x; } ok("8 派生值互相绕：报错", !!e8);
  console.log(out.join("\n"));
})();
