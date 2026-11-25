// 把 8.3、8.4 的伪代码手工改写成 JS，在假宿主（假存储、假地址栏）里跑库的用例。只验证库的逻辑，不验证积木系统。
const src=require("fs").readFileSync(__dirname+"/sig.js","utf8").split("// —— 假控件 ——")[0];
const {state,derived,effect}=new Function(src+";return {state,derived,effect};")();
const tick=()=>new Promise(r=>setTimeout(r,0));
const out=[];const ok=(n,c)=>out.push((c?"通过":"失败")+"  "+n);
// 状态.监听：取值变了才叫，登记时不先叫
function watch(get,cb){let first=true,old;return effect(()=>{const v=get();if(first){first=false;old=v;return;}if(!Object.is(v,old)){const o=old;old=v;cb(v,o);}});}
// 假存储
const disk=new Map();const 读本地=(k,d)=>{try{return disk.has(k)?JSON.parse(disk.get(k)):d;}catch{return d;}};const 存本地=(k,v)=>disk.set(k,JSON.stringify(v));
class 仓库{constructor(初值,键=null,形状对=()=>true){let v=初值;if(键!==null){const s=读本地(键,null);if(s!==null&&形状对(s))v=s;}this.格子=state(v);if(键!==null)watch(()=>this.格子.get(),n=>存本地(键,n));}
 现在(){return this.格子.get();} 取(f){return derived(()=>f(this.格子.get()));} 改(f){this.格子.set(f(this.格子.get()));}}
// 路由
const 拆段=p=>p.split("/").filter(s=>s!=="");
function 匹配(样子,路径){const a=拆段(样子),b=拆段(路径);if(a.length!==b.length)return{对上了:false,参数:{}};const 参数={};
 for(let i=0;i<a.length;i++){if(a[i].startsWith(":"))参数[a[i].slice(1)]=decodeURIComponent(b[i]);else if(a[i]!==b[i])return{对上了:false,参数:{}};}return{对上了:true,参数};}
// 假地址栏：加一条历史不触发事件；走几步要触发（异步）
const 地址={栈:["/"],位:0,听:[],现在(){return{井号后面:this.栈[this.位]};},加一条历史(u){this.栈=this.栈.slice(0,this.位+1);this.栈.push(u.replace(/^#/,""));this.位++;},
 走几步(n){const t=this.位+n;if(t<0||t>=this.栈.length)return;this.位=t;setTimeout(()=>this.听.forEach(f=>f(null)),0);},当前进后退(f){this.听.push(f);}};
const 路由表=state([]),位置=state({路径:"/",页面:null,参数:{}});
function 对一遍(){const p=地址.现在().井号后面||"/";for(const 条 of 路由表.get()){const r=匹配(条.样子,p);if(r.对上了){位置.set({路径:p,页面:条.页面,参数:r.参数});return;}}位置.set({路径:p,页面:null,参数:{}});}
const 登记=(样子,页面)=>路由表.set([...路由表.get(),{样子,页面}]);const 去=p=>{地址.加一条历史("#"+p);对一遍();};
const 当前页面=derived(()=>位置.get().页面),当前路径=derived(()=>位置.get().路径);
(async()=>{
 const 库存=new 仓库({数量:1});库存.改(d=>({...d,数量:d.数量+1}));ok("仓库 改了以后读到新值",库存.现在().数量===2);
 const 形状=s=>s&&typeof s==="object"&&typeof s.数量==="number";
 const 甲=new 仓库({数量:1},"库存",形状);甲.改(()=>({数量:5}));ok("仓库 这一刻还没存盘（监听是攒着的）",!disk.has("库存"));await tick();
 const 乙=new 仓库({数量:1},"库存",形状);ok("仓库 关掉再开还在",乙.现在().数量===5);
 存本地("库存","乱七八糟");const 丙=new 仓库({数量:1},"库存",形状);ok("仓库 形状不对就用初值",丙.现在().数量===1);
 const 件=库存.取(d=>d.数量*10);ok("仓库 取出来的派生值",件.get()===20);库存.改(d=>({数量:3}));ok("仓库 派生值跟着变",件.get()===30);
 ok("匹配 带参数",匹配("/detail/:id","/detail/42").参数.id==="42");ok("匹配 段数不同",匹配("/a/:id","/a").对上了===false);
 ok("匹配 中文和空格",匹配("/s/:词","/s/%E4%BD%A0%20%E5%A5%BD").参数.词==="你 好");ok("匹配 根路径",匹配("/","/").对上了===true);
 let 坏=null;try{匹配("/s/:x","/s/%E4%ZZ");}catch(e){坏=e.name;}ok("匹配 坏的百分号编码会出错（"+坏+"）——伪代码里没接住，是个漏洞",坏==="URIError");
 地址.当前进后退(()=>对一遍());登记("/","首页");登记("/detail/:id","详情页");对一遍();ok("路由 一开始是首页",当前页面.get()==="首页");
 去("/detail/7");ok("路由 去了以后当前页面跟着变",当前页面.get()==="详情页"&&位置.get().参数.id==="7");
 去("/");地址.走几步(-1);ok("路由 后退的那一刻还没变（事件是过后才来的）",当前路径.get()==="/");await tick();ok("路由 后退以后回到详情",当前路径.get()==="/detail/7");
 去("/nothing");ok("路由 没对上时页面是空",当前页面.get()===null);
 console.log(out.join("\n"));})();
