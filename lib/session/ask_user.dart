// ask_user 工具：一次可以带几个问题，每个问题单选或多选，用户都可以自己写。
// 旧的单问题写法（question + options）照常可用，而且走的还是原来那张卡。
// 这里只管：读参数、限制数量、把回答整理成给模型看的文字。卡片怎么画在 lib/ui/chat_question_multi.dart。
import 'package:lopicode/agent/agent_tools.dart';

/// 一次最多问几个问题（多出来的不问，并告诉模型）。
const int kAskMaxQuestions = 4;

/// 每个问题最多几个选项（多出来的丢掉）。
const int kAskMaxOptions = 6;

/// 一个问题。
class QuestionPart {
  const QuestionPart(this.question, {this.options = const [], this.multiple = false});
  final String question;
  final List<String> options;

  /// true＝可以选多个。
  final bool multiple;
}

/// 读完参数的结果：要问的问题，和因为超过上限没问的个数。
typedef AskPlan = ({List<QuestionPart> parts, int dropped});

List<String> _options(Object? raw) => {
  for (final o in raw is List ? raw : const <Object?>[])
    if (o is String && o.trim().isNotEmpty) o.trim(),
}.take(kAskMaxOptions).toList();

/// 从工具参数里读出问题。`questions`（新写法）优先；没有就读 `question` + `options`（旧写法）。
/// 一个能问的都没有时抛 [ToolArgError]。
AskPlan parseAskArgs(Map<String, dynamic> args) {
  final all = <QuestionPart>[];
  final raw = args['questions'];
  if (raw is List) {
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        all.add(QuestionPart(item.trim()));
      } else if (item is Map) {
        final q = item['question'];
        if (q is! String || q.trim().isEmpty) continue;
        all.add(QuestionPart(q.trim(), options: _options(item['options']), multiple: item['multiple'] == true));
      }
    }
  }
  if (all.isEmpty) {
    final q = args['question'];
    if (q is String && q.trim().isNotEmpty) all.add(QuestionPart(q.trim(), options: _options(args['options']), multiple: args['multiple'] == true));
  }
  if (all.isEmpty) throw ToolArgError('缺少要问的问题：给 question（一个问题），或 questions（最多 $kAskMaxQuestions 个问题的列表）');
  final parts = all.take(kAskMaxQuestions).toList();
  return (parts: parts, dropped: all.length - parts.length);
}

/// 用户对一个问题的回答：勾的选项 + 自己写的话（都可以没有）。
typedef PartAnswer = ({List<String> picked, String written});

String _one(QuestionPart part, PartAnswer a) {
  final written = a.written.trim();
  final picked = [
    for (final o in part.options)
      if (a.picked.contains(o)) o,
  ];
  if (picked.isEmpty && written.isEmpty) return '（用户没有回答）';
  if (picked.isEmpty) return written;
  return written.isEmpty ? picked.join('；') : '${picked.join('；')}；用户另外写的：$written';
}

/// 把几个问题的回答整理成一段给模型看的文字（会原样作为卡片的回答交回去）。
String formatAnswers(List<QuestionPart> parts, List<PartAnswer> answers) =>
    [for (var i = 0; i < parts.length; i++) '${i + 1}. ${parts[i].question}\n   回答：${_one(parts[i], i < answers.length ? answers[i] : (picked: const <String>[], written: ''))}'].join('\n');

/// 步骤列表里“向你提问”后面显示什么：一个问题就是它本身，多个写“N 个问题：第一个…”。
String askSummary(Map<String, dynamic> args) {
  try {
    final parts = parseAskArgs(args).parts;
    return parts.length == 1 ? parts.single.question : '${parts.length} 个问题：${parts.first.question}';
  } on ToolArgError {
    return '';
  }
}

/// 发给模型的工具定义。
Map<String, dynamic> askUserSpec() => toolSpec('ask_user', '需要用户拿主意时向用户提问并等他回答。一次可以问 1 到 $kAskMaxQuestions 个问题（相关的问题放在一次里问，不要连着调用几次）。每个问题给 2 到 4 个选项，用户也可以自己写别的回答。', {
  'questions': {
    'type': 'array',
    'description': '要问的问题，最多 $kAskMaxQuestions 个',
    'items': {
      'type': 'object',
      'properties': {
        'question': {'type': 'string', 'description': '要问的问题'},
        'options': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选的回答，最多 $kAskMaxOptions 个',
        },
        'multiple': {'type': 'boolean', 'description': 'true＝可以选多个；不写是只选一个'},
      },
      'required': ['question'],
    },
  },
  'question': {'type': 'string', 'description': '只问一个问题时的简写（和 questions 二选一）'},
  'options': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': '简写时的可选回答',
  },
});
