function lcNum(v){const n=typeof v==="string"?Number(v.trim()):Number(v);return Number.isFinite(n)?n:0;}
function lcText(v){if(v===null||v===undefined)return "";if(typeof v==="number")return String(Number(v.toPrecision(12)));return String(v);}
// fmtNum：照 lib/backend/runtime_node.dart 第 43–53 行抄的
function fmtNum(n){if(!Number.isFinite(n)||n===0)return "0";if(Number.isInteger(n)&&Math.abs(n)<1e15)return String(n);
 const m=/^(-?)([0-9])(?:\.([0-9]+))?e([+-][0-9]+)$/.exec(n.toExponential(11));const digits=(m[2]+(m[3]||"")).replace(/0+$/,"");const e=Number(m[4]);
 if(e>=15||e<-7)return m[1]+digits[0]+(digits.length>1?"."+digits.slice(1):"")+"e"+e;
 if(e>=digits.length-1)return m[1]+digits+"0".repeat(e-digits.length+1);
 if(e>=0)return m[1]+digits.slice(0,e+1)+"."+digits.slice(e+1);return m[1]+"0."+"0".repeat(-e-1)+digits;}
const NUM=/^[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*$/;
const toNum=v=>typeof v==="number"?(Number.isFinite(v)?v:0):typeof v==="string"?(NUM.test(v)?Number(v):0):v===true?1:0;
for(const n of [0.1+0.2,1e21,1e-7,1e-8,123456789012345680,1/3,2**53,1.5e15]) console.log(n,'lcText=',lcText(n),'fmtNum=',fmtNum(n),lcText(n)===fmtNum(n)?'':'<-- 不同');
for(const s of ["\u00a05","\u30005","0o17","\f5"]) console.log(JSON.stringify(s),'lcNum=',lcNum(s),'toNum=',toNum(s),lcNum(s)===toNum(s)?'':'<-- 不同');
let c=0;for(let i=0,n=Math.min(lcNum("2.5"),10000);i<n;i++)c++;console.log('重复 "2.5" 次：页面逻辑做',c,'遍；核心 times 规矩＝去掉小数＝',Math.trunc(2.5),'遍');
