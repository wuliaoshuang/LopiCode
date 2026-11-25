// 新积木一致性样本的请求和写死的预期（接口见 backend_lang_blocks_routes.dart）。
import 'backend_lang_blocks.dart';

const List<LangBlocksCase> langBlocksCases = [
  LangBlocksCase('/basics?n=95&t=x', '{"bk":"二","ch":"好","d":{"a":1,"b":"二","c":[],"z":null},"dg":1,"extra":["九十五"],"first":10,"grade":"A","kind":"叉","none":null,"xs":[10,20,3,4]}'),
  LangBlocksCase('/basics?n=75&t=y', '{"bk":"二","ch":"好","d":{"a":1,"b":"二","c":[],"z":null},"dg":1,"extra":["是歪"],"first":10,"grade":"B","kind":"歪","none":null,"xs":[10,20,3,4]}'),
  LangBlocksCase('/basics?n=5&t=q', '{"bk":"二","ch":"好","d":{"a":1,"b":"二","c":[],"z":null},"dg":1,"extra":[],"first":10,"grade":"C","kind":"别的","none":null,"xs":[10,20,3,4]}'),
  LangBlocksCase('/basics?n=-1', '{"bk":"二","ch":"好","d":{"a":1,"b":"二","c":[],"z":null},"dg":1,"extra":[],"first":10,"grade":"?","kind":"别的","none":null,"xs":[10,20,3,4]}'),
  LangBlocksCase('/loops', '[0,1,2,"f5",5,3,1,0,0.5,1,"0:a","1:b","10=x","b=2","中=true","r","r",1,2,4]'),
  LangBlocksCase(
    '/logic',
    '{"a":false,"b":true,"c":true,"c1":"成立","c2":"不成立","conv":[12.5,0,"3","[1,\\"a\\"]",false,true],"cp":[1,2,"只加在复制品上"],"d":false,"neg":-5,"negText":-2.5,"nul":null,"side":[1],"types":[true,false,true,true,true,true,true,false]}',
  ),
  LangBlocksCase('/math?n=7', '[3,-3,-2,2,3.5,4,0,7,2,1024,0,1,-1,true,true,4]'),
  LangBlocksCase('/math?n=-7', '[3,-3,-2,2,3.5,4,0,2,-7,1024,0,1,-1,true,true,4]'),
  LangBlocksCase(
    '/text?s=abcab',
    '{"badJson":null,"case":["abcab","  ABCAB\\t","  abcab\\t"],"charAt":["b",null],"chars":["a","😀","中"],"fromJson":{"a":1.5,"k":[1,2,{"深":null}]},"has":[true,true,true],"indexOf":[1,-1],"len":5,"repeat":"哈哈哈","replace":"a[B]ca[B]","split":["a","ca",""],"substring":"bc","template":"你好，abcab！3 岁，{没有} 原样","toJson":"{\\"a\\":true,\\"b\\":[1,\\"二\\",null]}"}',
  ),
  LangBlocksCase(
    '/text?s=%E4%BD%A0b%F0%9F%98%80',
    '{"badJson":null,"case":["你b😀","  你B😀\\t","  你b😀\\t"],"charAt":["b",null],"chars":["a","😀","中"],"fromJson":{"a":1.5,"k":[1,2,{"深":null}]},"has":[false,false,false],"indexOf":[1,-1],"len":3,"repeat":"哈哈哈","replace":"你[B]😀","split":["你","😀"],"substring":"b😀","template":"你好，你b😀！3 岁，{没有} 原样","toJson":"{\\"a\\":true,\\"b\\":[1,\\"二\\",null]}"}',
  ),
  LangBlocksCase(
    '/text',
    '{"badJson":null,"case":["","  \\t","  \\t"],"charAt":[null,null],"chars":["a","😀","中"],"fromJson":{"a":1.5,"k":[1,2,{"深":null}]},"has":[false,false,false],"indexOf":[-1,-1],"len":0,"repeat":"哈哈哈","replace":"","split":[""],"substring":"","template":"你好，！3 岁，{没有} 原样","toJson":"{\\"a\\":true,\\"b\\":[1,\\"二\\",null]}"}',
  ),
  LangBlocksCase(
    '/lists',
    '{"concat":[1,"二",[]],"contains":[true,false],"get":"b","indexOf":[2,-1],"join":"头-b-1-a-2","len":5,"popped":"尾","range":[1,5,9],"rangeDown":[3,2,1],"rangeZero":[],"reverse":[2,"a",1,"b","头"],"slice":["b",1],"sort":[1,2,"a","b","头"],"xs":["头","b",1,"a",2]}',
  ),
  LangBlocksCase(
    '/dicts',
    '{"d":{"10":"十","a":1,"b":2},"field":2,"get":[1,"十",null],"has":[true,false],"keys":["10","a","b"],"len":3,"merge":{"10":"十","a":"盖掉","b":2,"z":null},"pairs":[["10","十"],["a",1],["b",2]],"values":["十",1,2]}',
  ),
  LangBlocksCase('/mix/early', '第 3 遍就返回', method: 'POST', status: 201, type: 'text/plain', body: '{"count":2}'),
  LangBlocksCase('/mix/a', '{"count":2,"ids":[1,2],"last":2,"total":103}', method: 'POST', body: '{"count":2}'),
  LangBlocksCase('/mix/b', '{"count":5,"ids":[1,2,1],"last":3,"total":106}', method: 'POST', body: '{"count":3}'),
  LangBlocksCase('/mix/c', '{"count":5,"ids":[1,2,1],"last":null,"total":100}', method: 'POST', body: '{}'),
  LangBlocksCase('/oops', '{"error":"服务器内部出错"}', status: 500),
  // 出过错以后服务还活着，变量还是每次请求从头来
  LangBlocksCase('/loops', '[0,1,2,"f5",5,3,1,0,0.5,1,"0:a","1:b","10=x","b=2","中=true","r","r",1,2,4]'),
];

/// “写到日志”积木的输出（一行一条）。
const List<String> langBlocksLogLines = ['mix 103', 'mix 106', 'mix 100'];
