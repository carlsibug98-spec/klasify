import 'package:flutter/services.dart';

/// Character rules shared by manual class entry and import review.
abstract final class ClassTextInputRules {
  static final RegExp _lettersOrNumbers = RegExp(
    r'[\p{L}\p{N}]',
    unicode: true,
  );
  static final RegExp _subjectCharacters = RegExp(
    r"[\p{L}\p{M}\p{N} .,&/()+#:'\u2019-]",
    unicode: true,
  );
  static final RegExp _roomCharacters = RegExp(
    r"[\p{L}\p{M}\p{N} .,#&/()'\u2019-]",
    unicode: true,
  );
  static final RegExp _professorCharacters = RegExp(
    r"[\p{L}\p{M}\p{N} .',@\u2019-]",
    unicode: true,
  );

  static final TextInputFormatter subjectFormatter =
      FilteringTextInputFormatter.allow(_subjectCharacters);
  static final TextInputFormatter roomFormatter =
      FilteringTextInputFormatter.allow(_roomCharacters);
  static final TextInputFormatter professorFormatter =
      FilteringTextInputFormatter.allow(_professorCharacters);

  static bool isValidSubject(String value) =>
      _isValid(value, _subjectCharacters);

  static bool isValidRoom(String value) => _isValid(value, _roomCharacters);

  static bool isValidProfessor(String value) =>
      _isValid(value, _professorCharacters);

  static bool _isValid(String value, RegExp allowedCharacters) {
    final text = value.trim();
    return _lettersOrNumbers.hasMatch(text) &&
        text.runes.every(
          (rune) => allowedCharacters.hasMatch(String.fromCharCode(rune)),
        );
  }
}
