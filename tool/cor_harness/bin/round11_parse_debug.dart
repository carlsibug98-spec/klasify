// ignore_for_file: avoid_relative_lib_imports
// Debug: parse one line through CorScheduleParser and print the result.
import 'dart:io';
import '../../../lib/features/schedule_import/utils/cor_schedule_parser.dart';

void main(List<String> args) {
  final line = args[0];
  stdout.writeln('input : $line');
  final rows = CorScheduleParser.parse(line);
  for (final r in rows) {
    stdout.writeln('row   : ${r.subject} | day=${r.day} | ${r.startMinutes}-'
        '${r.endMinutes} | room=${r.room} | prof=${r.professor}');
  }
  if (rows.isEmpty) stdout.writeln('rows  : (none)');
}
