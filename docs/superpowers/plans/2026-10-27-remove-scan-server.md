# Plan: remove the optional scan-server feature (Task 21)

User: "Remove the optional feature scan server feature, retrieve the claim
works offline." — delete the PaddleOCR-VL self-hosted server feature
end-to-end and restore the unconditional offline claims (now true again).

## Removal matrix

| Surface | Action |
|---|---|
| `paddle_ocr_vl_client.dart` | Delete file (only user is schedule_ocr_service) |
| `markdown_to_text.dart` | Delete file (only user is the VL pass) |
| `schedule_ocr_service.dart` | Remove vlBaseUrl field, `_tryVlScan`, the VL pass in scanImage, both imports |
| `import_schedule_screen.dart` | Remove `_vlUrlKey`, `_vlUrlController` (+dispose), `_loadVlServerUrl` (+init call), `_saveVlServerUrl`, `_vlServerCard` (+its call site), `_ocrService.vlBaseUrl` assignment |
| Chip | Revert to static **'Works offline'** |
| Picker footer | Revert to unconditional "Your timetable stays on your device. No internet connection is needed." |
| 20 MB error | Restore "reliable on-device processing" |
| `AndroidManifest.xml` (main) | Remove the `INTERNET` permission + comment (no network feature remains) |
| README | Remove server section/bullet/structure line; revert intro, step 3, OCR-limitations, INTERNET note, local-data nuance |
| FULL_APP_AUDIT.md banner | Drop "optional self-hosted scan server" mention |
| Coach tour fix (Task 20) | **Stays** — unrelated to the server |

Verified: no test references the feature; no other prefs reader of
`paddle_ocr_vl_url`; client uses only dart:io/dart:convert (no pubspec
dependency to remove). Task 20's truthful-claim edits revert cleanly because
removal makes the original absolute claims true again.

## Verification

- flutter analyze (expect ≤ 7 pre-existing, 0 new — and unused-import would
  surface if SharedPreferences/http imports dangle)
- Full suite 344 pass / 12 skip / 0 fail (no goldens pin the picker/server)
- dart format touched files; commit; worklog Task 21; keepsafe backup
