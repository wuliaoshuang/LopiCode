interface Todo { id: number; title: string; done: boolean }
function add(list: Todo[], title: string): Todo[] {
  return [...list, { id: list.length + 1, title, done: false }];
}
const total = <T extends { done: boolean }>(xs: T[]): number => xs.filter((x) => !x.done).length;
let todos: Todo[] = [];
todos = add(todos, '买菜');
todos = add(todos, '写作业');
console.log(JSON.stringify(todos), total(todos));
