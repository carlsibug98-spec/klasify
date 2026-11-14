import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';

ClassItem validClass({
  String subject = 'Math',
  String room = '101',
  String professor = 'Prof. Cruz',
  int day = 1,
  int start = 480,
  int end = 540,
}) => ClassItem(
  subject: subject,
  room: room,
  professor: professor,
  day: day,
  startMinutes: start,
  endMinutes: end,
);

void main() {
  group('DatabaseHelper.validateClass', () {
    test('accepts a valid class', () {
      expect(() => DatabaseHelper.validateClass(validClass()), returnsNormally);
    });

    test('rejects a blank or too-short subject', () {
      expect(
        () => DatabaseHelper.validateClass(validClass(subject: ' ')),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(subject: 'M')),
        throwsArgumentError,
      );
    });

    test('rejects blank room and too-short professor', () {
      expect(
        () => DatabaseHelper.validateClass(validClass(room: '  ')),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(professor: 'P')),
        throwsArgumentError,
      );
    });

    test('rejects invalid day and times', () {
      expect(
        () => DatabaseHelper.validateClass(validClass(day: 0)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(day: 8)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(start: -1)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(start: 1440)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(start: 600, end: 600)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(start: 700, end: 650)),
        throwsArgumentError,
      );
      expect(
        () => DatabaseHelper.validateClass(validClass(end: 1441)),
        throwsArgumentError,
      );
    });
  });

  test(
    'overlap validation catches nested intervals but allows adjacent ones',
    () {
      const outer = ClassItem(
        subject: 'Outer',
        room: '101',
        professor: 'Prof. Cruz',
        day: 1,
        startMinutes: 480,
        endMinutes: 720,
      );
      const nested = ClassItem(
        subject: 'Nested',
        room: '102',
        professor: 'Prof. Lee',
        day: 1,
        startMinutes: 540,
        endMinutes: 600,
      );
      const adjacent = ClassItem(
        subject: 'Adjacent',
        room: '103',
        professor: 'Prof. Kim',
        day: 1,
        startMinutes: 720,
        endMinutes: 780,
      );

      DatabaseHelper.validateNoOverlaps([outer, adjacent]);
      expect(
        () => DatabaseHelper.validateNoOverlaps([outer, nested, adjacent]),
        throwsArgumentError,
      );
    },
  );
}
