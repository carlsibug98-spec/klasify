// Debug: parse one line through CorScheduleParser and print the result.
import '../../../lib/features/schedule_import/utils/cor_schedule_parser.dart';

void main(List<String> args) {
  final line = args[0];
  print('input : $line');
  final rows = CorScheduleParser.parse(line);
  for (final r in rows) {
    print('row   : ${r.subject} | day=${r.day} | ${r.startMinutes}-'
        '${r.endMinutes} | room=${r.room} | prof=${r.professor}');
  }
  if (rows.isEmpty) print('rows  : (none)');
}
