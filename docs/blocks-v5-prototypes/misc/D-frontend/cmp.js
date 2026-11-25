// 对照：页面逻辑的 lcNum / lcText / lcEq 与后端小库 toNum / fmtNum / eq 在边角输入上是否一致
function lcNum(v){const n=typeof v==="string"?Number(v.trim()):Number(v);return Number.isFinite(n)?n:0;}
function lcText(v){if(v===null||v===undefined)return "";if(typeof v==="number")return String(Number(v.toPrecision(12)));return String(v);}
const src=require('fs').readFileSync(process.argv[2],'utf8');
const m=/const NUM = (\/.*\/);/.exec(src);
console.log('NUM regex in runtime_node.dart:', m&&m[1]);
const NUM=eval(m[1]);
const fin=n=>Number.isFinite(n)?n:0;
function toNum(v){if(typeof v==="number")return fin(v);if(typeof v==="string")return NUM.test(v)?fin(Number(v)):0;return v===true?1:0;}
for(const s of ["5"," 5 ","0x10","1e3","","abc","5.","  ",".5","+5","-0","１２","Infinity","1_000","0b11",true,null,"12abc","\n7\t"]) {
  const a=lcNum(s), b=toNum(s);
  console.log(JSON.stringify(s).padEnd(12), 'lcNum=',a,' toNum=',b, a===b?'':'  <-- 不同');
}
for (const n of [0.1+0.2, 1e21, 1e-7, 123456789012345680, -0, 1/3, 1e15, 2**53]) console.log('lcText', lcText(n));
