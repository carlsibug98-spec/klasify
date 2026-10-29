// Local diagnostic script: printing is its purpose.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() {
  final out = jsonDecode(
    File('build/bench4_out.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ocr = jsonDecode(
    File('test/fixtures/bench4_ocr_lines.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  for (final photo in ['r4_chat_single_msg.png', 'r4_chat_bubbles.png']) {
    print('=== $photo ===');
    final best = (out[photo]['t2'] as Map)['candidate'] as String;
    print('chosen: $best');
    final cands = (ocr[photo]['candidates'] as List).cast<Map>();
    for (final c in cands) {
      if (c['label'] == best) {
        print('CHOSEN frags:');
        for (final f in (c['frags'] as List)) {
          print('  |${f['text']}|');
        }
      }
    }
  }
}