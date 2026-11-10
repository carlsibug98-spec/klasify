# Office Management (Super Admin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Super admins create, rename, and retire campus offices in-app; the Today strip paginates 4+ offices with a soft edge blur.

**Architecture:** Offices remain rows in `office_statuses` (no new table): POST inserts, rename = tombstone-old + insert-new (rides the existing sync tombstone path), retire = soft delete (`deleted=1`). Pull wire format is unchanged — only the Flutter cache learns to honor `deleted`. Client gains three `AuthService` wrappers, a shared name sheet, a "Manage office" section in the existing editor sheet, and converts the strip to a `PageView` for 4+ offices.

**Tech Stack:** PHP 8 (zero-Composer, no framework) + MySQL; Flutter/Dart (sqflite, provider-style singletons); PHP parity harness (`php-backend/tests/run.php` against `klasify_test` DB); flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-10-office-management-design.md` (approved; read it — this plan argues from it).

## Global Constraints

- Never commit `mockup_*.html`, `profile_mockup.html`, `.taste-skill/` — stage explicit paths only, never `git add -A`/`git add .`.
- `docs/sync_api_contract.md` is frozen **except** the deliberate update in this feature, which commits in the SAME commit as the server changes.
- PHP stays zero-Composer; deployment is robocopy to `C:\xampp\htdocs\klasify-api\` (exclude `tests`).
- All client changes TDD; full `flutter test` green and `flutter analyze` clean before the final commit.
- Test commands: `& "C:\xampp\php\php.exe" php-backend\tests\run.php` (~instant), `flutter analyze` (~16s), `flutter test` (~7 min, run backgrounded).
- PowerShell: git stderr lines can fake "exit code 1" — judge success by the ref-update line.
- Error contract everywhere: `{ "error": ..., "code": ... }`.

## Review Focus

1. **Office names with spaces / mixed case** ("Health Services") go into URL path segments — must be `Uri.encodeComponent`-encoded client-side and `rawurldecode`d server-side; duplicates checked case-insensitively. *(Pinned: Task 1 dup test uses `'library'` vs `'Library'`; Task 5 uses `Uri.encodeComponent`.)*
2. **Rename/retire while a phone was offline:** the old office key arrives later as a pull tombstone; the local cache must delete the row or the office renders forever. *(Pinned: Task 2 tombstone test.)*
3. **Whitespace-only or padded names** (`'  Library  '`, `'   '`) must trim before validation/uniqueness on both server and client. *(Pinned: Task 1 validation tests; Task 3 trimmed-name test.)*
4. **Large text scale in pager mode:** pager tiles use a fixed height (106px) while the ≤3 row keeps `IntrinsicHeight`; at accessibility text scale >1.3 the pager tile may clip its sub line. Not covered by automated tests — device check item.
5. **Retiring every office:** list and strip must fall back to the existing "No offices yet" / empty-strip states (strip returns `SizedBox.shrink`). *(Pinned: Task 1 retire-to-empty assertion; Task 6 keeps the ≤3 empty behavior.)*

---

### Task 1: Server office CRUD + de-seeding + contract (TDD)

**Files:**
- Modify: `php-backend/tests/admin_test.php` (office tests at lines 142–224)
- Modify: `php-backend/src/admin.php` (lines 9, 102–162)
- Modify: `php-backend/index.php` (route table, lines 52–57)
- Modify: `docs/sync_api_contract.md` (Admin endpoints table ~lines 209–215, error table ~237–244)
- Deploy: `C:\xampp\htdocs\klasify-api\`

**Interfaces:**
- Produces (later tasks consume these exact routes/codes): `POST /admin/offices` `{name}` → 201 `{office:{id,office_name,status,custom_message,user_id,updated_at}}`; `PATCH /admin/offices/:office` `{name}` → 200 `{ok:true}`; `DELETE /admin/offices/:office` → 200 `{ok:true}`; errors: 403 `FORBIDDEN`, 404 `OFFICE_NOT_FOUND`, 409 `OFFICE_EXISTS`, 422 `VALIDATION_ERROR`. `GET /admin/office-statuses` no longer seeds; `PATCH /admin/office-statuses/:office` requires an existing active row (404 `OFFICE_NOT_FOUND`, no insert branch).
- Test helpers already available: `db_reset()`, `seed_user([...])`, `act_as(id)`, `run_handler('name', 'path-arg'?)`, `set_body([...])`, `T()->eq/truthy`, `fetch_one(...)`, `RAWDT_RX`.

- [ ] **Step 1: Rewrite + add the failing PHP tests** in `php-backend/tests/admin_test.php`

Replace the four existing office tests (lines 142–224) with:

```php
T()->test('office list: no seeding, empty is valid', function () {
    db_reset();
    seed_user(['email' => 'oa@test.com', 'role' => 'super_admin']);
    act_as(1);
    $r = run_handler('admin_list_offices');
    T()->eq(200, $r['status'], 'list status');
    T()->eq([], $r['body']['offices'] ?? null, 'fresh DB yields empty list');
});

T()->test('add office: 201 + row shape', function () {
    db_reset();
    seed_user(['email' => 'oa2@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    $r = run_handler('admin_add_office');
    T()->eq(201, $r['status'], 'create status');
    $o = $r['body']['office'] ?? [];
    T()->eq(['id', 'office_name', 'status', 'custom_message', 'user_id', 'updated_at'], array_keys($o), 'row keys');
    T()->eq('Library', $o['office_name'], 'name kept verbatim');
    T()->eq('open', $o['status'], 'new offices start open');
    T()->truthy($o['custom_message'] === null, 'note null');
    T()->truthy($o['user_id'] === 1, 'creator user_id');
    T()->truthy(preg_match(RAWDT_RX, (string)$o['updated_at']) === 1, 'raw updated_at');
    $r = run_handler('admin_list_offices');
    T()->eq(['Library'], array_column($r['body']['offices'] ?? [], 'office_name'), 'appears in list');
});

T()->test('add office: duplicate case-insensitive -> 409 OFFICE_EXISTS', function () {
    db_reset();
    seed_user(['email' => 'oa3@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    run_handler('admin_add_office');
    set_body(['name' => 'library']);
    $r = run_handler('admin_add_office');
    T()->eq(409, $r['status'], 'dup status');
    T()->eq('OFFICE_EXISTS', $r['body']['code'] ?? null, 'dup code');
    set_body(['name' => '  Library  ']);
    $r = run_handler('admin_add_office');
    T()->eq(409, $r['status'], 'padded dup status');
});

T()->test('add office: name validation -> 422', function () {
    db_reset();
    seed_user(['email' => 'oa4@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => '   ']);
    $r = run_handler('admin_add_office');
    T()->eq(422, $r['status'], 'blank name status');
    T()->eq('VALIDATION_ERROR', $r['body']['code'] ?? null, 'blank name code');
    set_body(['name' => str_repeat('x', 41)]);
    $r = run_handler('admin_add_office');
    T()->eq(422, $r['status'], '41-char name status');
    set_body(['name' => str_repeat('x', 40)]);
    T()->eq(201, run_handler('admin_add_office')['status'], '40-char name ok');
});

T()->test('rename office: keeps status+note, tombstones old key', function () {
    db_reset();
    seed_user(['email' => 'oa5@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    run_handler('admin_add_office');
    set_body(['status' => 'break', 'custom_message' => 'Back at 2pm']);
    run_handler('admin_update_office', 'Library');
    set_body(['name' => 'Learning Commons']);
    $r = run_handler('admin_rename_office', 'Library');
    T()->eq(200, $r['status'], 'rename status');
    T()->eq(['ok' => true], $r['body'], 'rename body');
    $r = run_handler('admin_list_offices');
    T()->eq(['Learning Commons'], array_column($r['body']['offices'] ?? [], 'office_name'), 'only new key listed');
    $new = fetch_one("SELECT status, custom_message FROM office_statuses WHERE office_name = 'Learning Commons'");
    T()->eq('break', $new['status'], 'status carried over');
    T()->eq('Back at 2pm', $new['custom_message'], 'note carried over');
    T()->eq(1, (int)fetch_one("SELECT deleted FROM office_statuses WHERE office_name = 'Library'")['deleted'], 'old key tombstoned');
});

T()->test('rename office: dup -> 409, unknown -> 404', function () {
    db_reset();
    seed_user(['email' => 'oa6@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Alpha']); run_handler('admin_add_office');
    set_body(['name' => 'Beta']);  run_handler('admin_add_office');
    set_body(['name' => 'beta']);
    $r = run_handler('admin_rename_office', 'Alpha');
    T()->eq(409, $r['status'], 'rename onto existing status');
    T()->eq('OFFICE_EXISTS', $r['body']['code'] ?? null, 'rename onto existing code');
    set_body(['name' => 'Whatever']);
    $r = run_handler('admin_rename_office', 'Nope');
    T()->eq(404, $r['status'], 'rename unknown status');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'rename unknown code');
    $r = run_handler('admin_retire_office', 'Nope');
    T()->eq(404, $r['status'], 'retire unknown status');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'retire unknown code');
});

T()->test('retire office: soft-deletes, list empties, availability PATCH then 404', function () {
    db_reset();
    seed_user(['email' => 'oa7@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Clinic']); run_handler('admin_add_office');
    $r = run_handler('admin_retire_office', 'Clinic');
    T()->eq(200, $r['status'], 'retire status');
    T()->eq(['ok' => true], $r['body'], 'retire body');
    T()->eq([], run_handler('admin_list_offices')['body']['offices'], 'gone from list');
    T()->eq(1, (int)fetch_one("SELECT deleted FROM office_statuses WHERE office_name = 'Clinic'")['deleted'], 'record kept, deleted=1');
    set_body(['status' => 'closed']);
    $r = run_handler('admin_update_office', 'Clinic');
    T()->eq(404, $r['status'], 'availability PATCH on retired office');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'retired office code');
});

T()->test('office CRUD is super_admin only', function () {
    db_reset();
    seed_user(['email' => 's@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 'a@test.com', 'role' => 'admin', 'department' => 'IT']);
    set_body(['name' => 'Library']);
    act_as(2);
    $r = run_handler('admin_add_office');
    T()->eq(403, $r['status'], 'dept admin add');
    T()->eq('FORBIDDEN', $r['body']['code'] ?? null, 'dept admin add code');
    set_body(['name' => 'X']);
    T()->eq(403, run_handler('admin_rename_office', 'Guidance')['status'], 'dept admin rename');
    T()->eq(403, run_handler('admin_retire_office', 'Guidance')['status'], 'dept admin retire');
});

T()->test('availability update: unknown office 404, invalid status 422, non-admin 403', function () {
    db_reset();
    seed_user(['email' => 'oa8@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['status' => 'closed']);
    $r = run_handler('admin_update_office', 'gym');
    T()->eq(404, $r['status'], 'unknown office now 404');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'unknown office code');
    set_body(['name' => 'Guidance']); run_handler('admin_add_office');
    set_body(['status' => 'nonsense']);
    T()->eq(422, run_handler('admin_update_office', 'Guidance')['status'], 'invalid status');
    seed_user(['email' => 'u@test.com', 'role' => 'user']);
    act_as(3);
    set_body(['status' => 'open']);
    T()->eq(403, run_handler('admin_update_office', 'Guidance')['status'], 'non-admin');
});
```

Delete the old `'office upsert update branch'` and `'office upsert create branch after hard delete'` and `'office boundaries...'` tests (superseded above). Rename's `run_handler('admin_update_office', 'Library')` exercises the updated availability route against a mixed-case key.

- [ ] **Step 2: Run the suite, expect FAILures**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`
Expected: the new tests FAIL (`undefined function admin_add_office` etc.); other suites unaffected.

- [ ] **Step 3: Implement the server changes** in `php-backend/src/admin.php`

- Delete `const OFFICES = [...]` (line 9).
- `admin_list_offices()`: remove the seeding `foreach (OFFICES ...)` block; keep the `$select` + mapping as-is.
- Add a super-only guard helper next to `admin_caller()`:

```php
/// admin_caller() + super_admin requirement. Returns the caller array.
function admin_super_caller(): array
{
    $caller = admin_caller();
    if ($caller['role'] !== 'super_admin') {
        throw new ApiError(403, 'Super admin required', 'FORBIDDEN');
    }
    return $caller;
}
```

- Add office helpers + handlers (after `admin_update_office`). Algorithm details that the tests do not determine:
  - `office_name_or_422(string $raw): string` — `trim($raw)`; reject if `''` or `mb_strlen > 40` with `ApiError(422, 'Invalid office name', 'VALIDATION_ERROR')`; return the trimmed name.
  - Uniqueness: `SELECT id FROM office_statuses WHERE LOWER(office_name) = LOWER(?) AND department IS NULL AND deleted = 0 LIMIT 1` — non-null ⇒ `ApiError(409, 'Office already exists', 'OFFICE_EXISTS')`.
  - Row lookup by path key: `trim(rawurldecode($key))`, then `SELECT ... FROM office_statuses WHERE office_name = ? AND department IS NULL AND deleted = 0 LIMIT 1` (exact, case-sensitive match on the stored key) — null ⇒ `ApiError(404, 'Office not found', 'OFFICE_NOT_FOUND')`.
  - `admin_add_office(): void` — `admin_super_caller()`; `$name = office_name_or_422(js_text(read_json_body()['name'] ?? null))`; uniqueness check; `INSERT INTO office_statuses (user_id, office_name, department, status) VALUES (?,?,NULL,'open')`; re-fetch the row and `send_json(201, ['office' => <same shape as admin_list_offices rows>])`.
  - `admin_rename_office(string $office): void` — `admin_super_caller()`; find row by key (404); `$newName = office_name_or_422(...)`; uniqueness check excluding the current row's id (`AND id <> ?`); then two writes: `UPDATE office_statuses SET deleted = 1, updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?` (old row) and `INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (?,?,NULL,<old status>,<old custom_message>)` with the NEW name. `send_json(200, ['ok' => true])`.
  - `admin_retire_office(string $office): void` — `admin_super_caller()`; find row by key (404); `UPDATE office_statuses SET deleted = 1, updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?`; `send_json(200, ['ok' => true])`.
- `admin_update_office()` (availability): replace the `OFFICES` const check with the row-lookup-404 helper; delete the `else { INSERT ... }` create branch — only the UPDATE branch remains.

- [ ] **Step 4: Register the routes** in `php-backend/index.php` (append after the existing office-statuses lines):

```php
    ['POST',   '#^/admin/offices$#',                   'admin_add_office'],
    ['PATCH',  '#^/admin/offices/([^/]+)$#',           'admin_rename_office'],
    ['DELETE', '#^/admin/offices/([^/]+)$#',           'admin_retire_office'],
```

- [ ] **Step 5: Run the suite to green**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`
Expected: all cases pass, `failed 0`.

- [ ] **Step 6: Update the contract** in `docs/sync_api_contract.md`

- Admin endpoints table: change the `GET /admin/office-statuses` note to "returns active school-wide offices (no seeding; empty list is valid)"; change the `PATCH /admin/office-statuses/:office` note to "requires an existing active office (404 `OFFICE_NOT_FOUND` otherwise); school-wide"; append three rows:

```markdown
| POST | `/admin/offices` | `{ "name": "Library" }` | super_admin only. 201 with the created row; duplicates (case-insensitive) → 409 `OFFICE_EXISTS` |
| PATCH | `/admin/offices/:office` | `{ "name": "New name" }` | super_admin only. Renames (tombstones the old key, keeps status + note) |
| DELETE | `/admin/offices/:office` | — | super_admin only. Retires (soft delete, permanent in-app) |
```

- Error table: add `OFFICE_NOT_FOUND | 404 | No such active office` and `OFFICE_EXISTS | 409 | Office name already in use`.

- [ ] **Step 7: Commit (tests + server + routes + contract together)**

```powershell
git add php-backend/tests/admin_test.php php-backend/src/admin.php php-backend/index.php docs/sync_api_contract.md
git commit -m "feat(api): super-admin office CRUD (add/rename/retire) + de-seed office-statuses; contract updated"
```

- [ ] **Step 8: Deploy to XAMPP**

```powershell
robocopy "php-backend\src" "C:\xampp\htdocs\klasify-api\src" /MIR
Copy-Item "php-backend\index.php" "C:\xampp\htdocs\klasify-api\index.php" -Force
```

Check robocopy's exit banner (0–7 = success) and that `C:\xampp\htdocs\klasify-api\src\admin.php` contains `admin_add_office`. Do NOT copy `tests/`, `config.php`, or `*.md`.

---

### Task 2: Honor pull tombstones in the office cache

**Files:**
- Modify: `lib/database/database_helper.dart:177-188` (`upsertOfficeStatusFromServer`)
- Test: `test/office_statuses_db_test.dart`

**Interfaces:**
- Consumes: pull rows already carry `deleted: bool` (`php-backend/src/sync.php`, verified).
- Produces: `upsertOfficeStatusFromServer` deletes the local row when `data['deleted'] == true` — Task 5's rename/retire flows depend on this.

- [ ] **Step 1: Write the failing test** (append in `test/office_statuses_db_test.dart`, same harness style — sqflite_ffi, unique db name):

```dart
  test('a pulled tombstone deletes the cached office row', () async {
    final db = DatabaseHelper.instance;
    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'office_name': 'clinic',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });

    // The server retired guidance: pull delivers the row with deleted=true.
    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': true,
    });

    final names = (await db.getOfficeStatuses()).map((r) => r['office_name']);
    expect(names, ['clinic']);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/office_statuses_db_test.dart`
Expected: FAIL — guidance still cached.

- [ ] **Step 3: Implement** in `upsertOfficeStatusFromServer`, after the `office is! String` guard, before the insert:

```dart
    // Tombstone: the office was retired or renamed away on the server. The
    // local table has no deleted column, so the cached row is removed
    // outright — otherwise it would render on Today forever.
    if (data['deleted'] == true) {
      await db.delete('office_statuses', where: 'office_name = ?', whereArgs: [office]);
      notifyListeners();
      return;
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/office_statuses_db_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/database/database_helper.dart test/office_statuses_db_test.dart
git commit -m "fix(sync): drop locally cached offices when pull delivers a tombstone"
```

---

### Task 3: Shared office name sheet (add + rename)

**Files:**
- Create: `lib/widgets/office_name_sheet.dart`
- Test: `test/office_name_sheet_test.dart`

**Interfaces:**
- Produces (Task 4's rename row and Task 5's add row call this):

```dart
Future<bool> showOfficeNameSheet(
  BuildContext context, {
  required String title,          // 'Add office' | 'Rename office'
  required String ctaLabel,       // 'Add office' | 'Rename'
  String initialName = '',        // prefill (rename passes the current name)
  List<String> takenNames = const [], // names the new one must not equal
  required Future<void> Function(String name) onSave, // receives the TRIMMED name
})
```

- Failure contract identical to `showOfficeStatusEditorSheet`: CTA shows a 16px spinner + 'Saving…' while `onSave` runs, sheet non-dismissible mid-save (`PopScope(canPop: !_busy)`), failure → error toast + sheet stays open for retry, success pops `true`.

- [ ] **Step 1: Write the failing tests** (`test/office_name_sheet_test.dart`, MaterialApp + `AppTheme.light()`, open via a tap on a launcher button):

```dart
// Harness pattern:
Widget _host({List<String> taken = const [], String initial = ''}) =>
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showOfficeNameSheet(
                context,
                title: 'Add office',
                ctaLabel: 'Add office',
                initialName: initial,
                takenNames: taken,
                onSave: (name) async {
                  savedNames.add(name);
                  if (throwOnSave) throw Exception('server down');
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
```

Tests to write (names locked):
- `'empty name disables the CTA'` — CTA `onPressed` is null with an empty field.
- `'a name differing only in case is rejected inline'` — `taken: ['Library']`, enter `'library'` → inline error `'An office with this name already exists.'` visible and CTA disabled.
- `'leading/trailing spaces do not bypass the duplicate check'` — `taken: ['Library']`, enter `'  Library  '` → same error + disabled CTA.
- `'a valid name calls onSave with the trimmed name and pops true'` — enter `'  Health Services  '` → tap CTA → `savedNames == ['Health Services']`.
- `'a server failure keeps the sheet open with an error toast'` — `throwOnSave = true`, enter valid name, tap CTA → find `'Saving…'` during, then after settle: find toast text `"Couldn't save the office. Nothing changed. Try again."`, sheet still open (CTA visible again).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/office_name_sheet_test.dart`
Expected: FAIL — file/lib does not exist yet.

- [ ] **Step 3: Implement `lib/widgets/office_name_sheet.dart`**

Follow `office_status_editor_sheet.dart`'s structure exactly (same paddings, `AppTheme` label style, 52px FilledButton + 40px TextButton Cancel, `PopScope` busy guard). Behavior decisions locked:
- `TextField` `maxLength: 40`, `textCapitalization: TextCapitalization.words`, prefilled with `initialName`.
- Live validation on every change: trimmed empty → CTA disabled, no error; trimmed value case-insensitively equals any `takenNames` entry → inline error under the field (11px, `scheme.error`, fromLTRB(24, 4, 24, 0)) + CTA disabled; otherwise enabled.
- Error toast copy on failure: `"Couldn't save the office. Nothing changed. Try again."` via `showAppNotification(context, ..., kind: AppNotificationKind.error)`.
- Title line uses `theme.textTheme.titleLarge`; a one-line subtitle under it: `'Students see it on Today after the next sync.'` in `bodySmall`/`onSurfaceVariant` (same style as the editor sheet's subtitle).

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/office_name_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/office_name_sheet.dart test/office_name_sheet_test.dart
git commit -m "feat(offices): shared add/rename name sheet with inline duplicate check"
```

---

### Task 4: "Manage office" section in the availability editor sheet

**Files:**
- Modify: `lib/widgets/office_status_editor_sheet.dart`
- Test: `test/office_editor_manage_test.dart` (new)

**Interfaces:**
- Consumes: `showOfficeNameSheet` (Task 3).
- Produces (Task 5 wires these) — signature becomes:

```dart
Future<bool> showOfficeStatusEditorSheet(
  BuildContext context, {
  required String displayName,
  required String initialStatus,
  String? initialNote,
  required Future<void> Function(String status, String? note) onSave,
  List<String> otherOfficeNames = const [],       // rename dup pre-check
  Future<void> Function(String newName)? onRename, // null → no rename row
  Future<void> Function()? onRetire,               // null → no retire row
})
```

Return stays `bool`. The "MANAGE OFFICE" section renders iff `onRename != null || onRetire != null`.

- [ ] **Step 1: Write the failing tests** (`test/office_editor_manage_test.dart`):

Harness opens the sheet the same way Task 3's does, with recording callbacks (`renamedTo`, `retired`, counters). Tests (names locked):
- `'without manage callbacks there is no manage section'` — `find.text('MANAGE OFFICE')` findsNothing; `find.text('Rename office')` findsNothing; `find.text('Retire office')` findsNothing.
- `'super admin sees the manage section with both rows'` — pass both callbacks → `'MANAGE OFFICE'`, `'Rename office'`, `'Retire office'` all found.
- `'rename opens the name sheet prefilled and calls onRename'` — tap `'Rename office'` → pumpAndSettle → the name sheet's field holds the current display name; enter `'Learning Commons'`, tap the `'Rename'` CTA → `renamedTo == 'Learning Commons'` and the editor popped (`find.byType(TextField)` back to just the editor's note field… simplest: assert the recorded callback ran and `Navigator` popped — use the launcher's post-pop flag).
- `'retire shows the confirm dialog and confirm calls onRetire'` — tap `'Retire office'` → dialog shows `'Retire Guidance?'` and `'Students will no longer see it on Today. Its record stays on file.'`; tap `'Retire'` → `retired == true`, editor popped.
- `'retire cancel leaves the editor open'` — tap `'Retire office'`, tap `'Cancel'` in the dialog → editor still open, `retired == false`.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/office_editor_manage_test.dart`
Expected: FAIL — parameters don't exist yet (compile error in the harness).

- [ ] **Step 3: Implement** in `office_status_editor_sheet.dart`

- Thread the three new params through `showOfficeStatusEditorSheet` → `_OfficeStatusEditorSheet`.
- Insert the manage section between the note field block and the CTA, mirroring the availability group's container style (16px horizontal padding, same card container + 1px seams + 56px rows):
  - Label `'MANAGE OFFICE'` in the same `labelMedium`/`groupLabelColorOf` style as `'AVAILABILITY'`.
  - Row `'Rename office'` (`InkWell`, 56px, `onSurface` text, trailing `Icons.chevron_right_rounded`): disabled while `_busy`; on tap opens `showOfficeNameSheet(context, title: 'Rename office', ctaLabel: 'Rename', initialName: widget.displayName, takenNames: widget.otherOfficeNames, onSave: widget.onRename)`; when that returns true, pop the editor with `true`.
  - Row `'Retire office'` (destructive: text `scheme.error`, trailing `Icons.delete_outline_rounded` tinted `scheme.error`): on tap shows the confirm dialog (below).
- Retire confirm dialog — `showDialog<bool>` with: title `'Retire ${widget.displayName}?'` (`titleMedium`), body `'Students will no longer see it on Today. Its record stays on file.'`, actions `'Cancel'` (TextButton) and `'Retire'` (FilledButton, `backgroundColor: scheme.error`, `foregroundColor: scheme.onError`). Dialog state: while retiring, `'Retire'` is disabled and reads `'Retiring…'`; on failure show the toast `"Couldn't retire ${widget.displayName}. Nothing changed. Try again."` (error) and keep both dialog and editor open; on success pop dialog `true`, then pop editor `true`.

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/office_editor_manage_test.dart`
Expected: PASS. Also run `flutter test test/office_status_strip_test.dart` — unaffected, must stay green.

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/office_status_editor_sheet.dart test/office_editor_manage_test.dart
git commit -m "feat(offices): rename/retire manage section in the shared availability editor"
```

---

### Task 5: AuthService wrappers + screen wiring (Add row, manage callbacks, toasts)

**Files:**
- Modify: `lib/services/auth_service.dart` (after `adminSetOfficeStatus`, ~line 268; also line 263)
- Modify: `lib/screens/profile/admin_screen.dart` (`_editOffice` ~66–89, office group ~211–247)
- Modify: `lib/screens/home_screen.dart` (`_editOfficeStatus` ~261–297)

**Interfaces:**
- Consumes: Task 1 routes (via HTTP), Task 3 name sheet, Task 4 editor params.
- Produces: `AuthService.instance.adminAddOffice/adminRenameOffice/adminRetireOffice` (signatures below). Screen wiring has no widget-test harness (AuthService is a hard singleton with a live HTTP client) — it is verified by `flutter analyze` and on-device; the sheets and callbacks it passes are already fully tested.

- [ ] **Step 1: Add the three wrappers** to `auth_service.dart`:

```dart
  /// Admin: create a new school-wide office (super_admin only). Returns the
  /// created row (same shape as adminGetOfficeStatuses rows).
  Future<Map<String, dynamic>> adminAddOffice(String name) async {
    final data = await _api('POST', '/admin/offices', body: {'name': name}) as Map<String, dynamic>;
    return (data['office'] as Map? ?? const {}).cast<Map<String, dynamic>>();
  }

  /// Admin: rename an office (super_admin only). The old key disappears at
  /// every phone's next sync; availability and note carry over.
  Future<void> adminRenameOffice(String office, String newName) async {
    await _api('PATCH', '/admin/offices/${Uri.encodeComponent(office)}', body: {'name': newName});
  }

  /// Admin: retire an office (super_admin only). Soft delete: students lose
  /// it at their next sync; the record stays on the server.
  Future<void> adminRetireOffice(String office) async {
    await _api('DELETE', '/admin/offices/${Uri.encodeComponent(office)}');
  }
```

Also change `adminSetOfficeStatus`'s path (line 263) to `'/admin/office-statuses/${Uri.encodeComponent(office)}'` — offices renamed to spaced names must still be PATCHable.

- [ ] **Step 2: Wire the Admin screen** (`admin_screen.dart`):

- `_editOffice`: when `_isSuper`, pass

```dart
      otherOfficeNames: [
        for (final o in _offices)
          if ((o['office_name'] as String? ?? '') != name) o['office_name'] as String? ?? '',
      ],
      onRename: _isSuper
          ? (newName) async {
              await AuthService.instance.adminRenameOffice(name, newName);
              if (mounted) {
                showAppNotification(
                  context,
                  "'${_titleCase(name)}' is now '$newName'. Students see the change after the next sync.",
                  kind: AppNotificationKind.success,
                );
              }
            }
          : null,
      onRetire: _isSuper
          ? () async {
              await AuthService.instance.adminRetireOffice(name);
              if (mounted) {
                showAppNotification(
                  context,
                  "$display retired. Students will no longer see it on Today.",
                  kind: AppNotificationKind.success,
                );
              }
            }
          : null,
```

(`display` already exists in `_editOffice`; add a tiny `_titleCase` helper or reuse the existing inline pattern `name[0].toUpperCase() + name.substring(1)`.) Keep the existing `syncNow()` + `_load()` after-pop block — it covers all three actions.

- Add-office: in the OFFICE AVAILABILITY `ProfileGroup.rows`, append after the office rows / empty-state row:

```dart
                    if (_isSuper)
                      ProfileRow(
                        icon: Icons.add,
                        title: 'Add office',
                        subtitle: 'New offices start Open',
                        onTap: () => unawaited(_addOffice()),
                      ),
```

- `_addOffice()` (new method, modeled on `_editOffice`): opens `showOfficeNameSheet(context, title: 'Add office', ctaLabel: 'Add office', takenNames: [current office names], onSave: (n) => AuthService.instance.adminAddOffice(n))`; on `true`: toast `"'$n' added. Students see it on Today after the next sync."` (success), `unawaited(SyncService.instance.syncNow())`, `await _load()`.

- [ ] **Step 3: Wire the Today editor entry** (`home_screen.dart` `_editOfficeStatus`): pass the same three params when `AuthService.instance.isSuperAdmin` (`otherOfficeNames` from `_offices` minus the current one; `onRename` fires the same rename toast; `onRetire` fires the same retire toast). The existing post-save pending/sync block already runs for rename and retire — leave it.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```powershell
git add lib/services/auth_service.dart lib/screens/profile/admin_screen.dart lib/screens/home_screen.dart
git commit -m "feat(offices): super-admin add/rename/retire wired into Admin screen and Today editor"
```

---

### Task 6: Today strip pager + edge blur for 4+ offices

**Files:**
- Modify: `lib/widgets/office_status_strip.dart`
- Test: `test/office_status_strip_test.dart` (6 existing tests)

**Interfaces:**
- Consumes: existing `OfficeStatusStrip` public API — unchanged (no signature change).
- Produces: ≤3 offices render exactly today's tree; >3 offices render a `PageView` (one office per swipe) with 2/7-width columns and a 52px edge blur.

- [ ] **Step 1: Write the failing tests** (append to `office_status_strip_test.dart`; the 5-office `_host` list already exists in the 'more than three' test):

```dart
  testWidgets('four offices switch the strip to a pager with an edge blur', (tester) async {
    await tester.pumpWidget(_host([
      _office('guidance'), _office('clinic'), _office('registrar'), _office('library'),
    ]));

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget); // right edge only, page 0
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('swiping advances exactly one office and flips the blur', (tester) async {
    await tester.pumpWidget(_host([
      _office('guidance'), _office('clinic'), _office('registrar'), _office('library'),
    ]));

    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(controller.viewportFraction, closeTo(2 / 7, 0.001));
    expect(controller.page, 0);

    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    expect(find.byType(BackdropFilter), findsNWidgets(2)); // both edges mid-strip
  });

  testWidgets('an empty office list renders nothing', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.byType(PageView), findsNothing);
    expect(find.text('CAMPUS OFFICES'), findsNothing);
  });

  testWidgets('three offices keep the non-pager row layout', (tester) async {
    await tester.pumpWidget(
      _host([_office('guidance'), _office('clinic'), _office('registrar')]),
    );
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a tap (no drag) still opens the office sheet', (tester) async {
    OfficeStatus? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: OfficeStatusStrip(
          offices: [_office('guidance'), _office('clinic'), _office('registrar'), _office('library')],
          isAdmin: true,
          onEditOffice: (o) => tapped = o,
        ),
      ),
    ));
    await tester.tap(find.text('guidance'));
    expect(tapped?.office, 'guidance');
  });
```

The existing 6 tests stay untouched — they must keep passing (the 5-office hint test now exercises the pager path, which still renders the hint text).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/office_status_strip_test.dart`
Expected: new tests FAIL (no PageView yet), existing 6 PASS.

- [ ] **Step 3: Implement** in `office_status_strip.dart`

- Convert to `StatefulWidget` (state: `PageController` + two edge-visibility bools). Public constructor/fields unchanged.
- ≤3 offices: keep the current `LayoutBuilder` → card `Container` → `SingleChildScrollView`/`IntrinsicHeight`/`Row` tree byte-for-byte.
- >3 offices: same card `Container`, but the child becomes a `Stack`:
  - `PageView.builder` with `controller: PageController(viewportFraction: 2 / 7, padEnds: false)`, `physics: const PageScrollPhysics()` — one office per swipe; each page child is `_OfficeTile` wrapped in a container that draws the 1px left hairline (`Border(left: BorderSide(color: cardBorderSideOf(scheme).color))`) for `index > 0`, with `padding` unchanged. The card's `clipBehavior: Clip.antiAlias` clips the peek.
  - Tile height: pager pages need a bounded height — use `SizedBox(height: _kPagerTileHeight)` around each page child, `const _kPagerTileHeight = 106.0`, with a comment deriving it (24 top row + 4 gap + 14.4 name line + 2 gap + 19.2 state line + 13 sub line + 28 vertical padding). The ≤3 row keeps `IntrinsicHeight` (no hardcode there).
  - Edges: two `IgnorePointer`-wrapped `_EdgeBlur` widgets, `Positioned` `top: 0, bottom: 0, width: 52` right/left, visible per scroll position.
  - Visibility: wrap the `PageView` in a `NotificationListener<ScrollNotification>`; `showRight = metrics.pixels < metrics.maxScrollExtent - 4`, `showLeft = metrics.pixels > 4`. Initial state (no notification yet): `showRight = true`, `showLeft = false`.
- `_EdgeBlur` (private): `ClipRect` → `ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: multi-stop gradient)` → `BackdropFilter(ImageFilter.blur(sigmaX: 8, sigmaY: 8))` → `Container(color: cardFillColorOf(scheme).withValues(alpha: 0.26))`. Gradient stops (from the approved mockup v16, soft): direction outward from the card (`centerLeft → centerRight` for the right edge, mirrored for left), colors `[transparent, black @ .45, black @ .82, black]`, stops `[0.0, 0.4, 0.74, 1.0]` — the mask fades the blur AND the tint in together; the half card dissolves into the card instead of smearing.

- [ ] **Step 4: Run to verify green**

Run: `flutter test test/office_status_strip_test.dart`
Expected: 11 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/widgets/office_status_strip.dart test/office_status_strip_test.dart
git commit -m "feat(today): office strip becomes a swipe pager with soft edge blur for 4+ offices"
```

---

### Task 7: Full verification, goldens, bookkeeping

**Files:**
- Modify: `php-backend/PROVENANCE.md` (patch-log entry)
- Modify: `docs/ROADMAP.md` (strike the office-CRUD entry)
- Possibly: golden image files under `test/**` (recapture only if a golden references the strip)

**Interfaces:**
- Consumes: all prior tasks complete and committed.

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 2: Full test suite** (backgrounded, ~7 min)

Run: `flutter test`
Expected: all green. If a golden test fails because the strip changed: recapture with `$env:TZ='Asia/Manila'; flutter test --update-goldens` during the daytime window (goldens only assert under explicit `--update-goldens` per repo policy), then commit the golden files explicitly by path.

- [ ] **Step 3: Bookkeeping**

- `php-backend/PROVENANCE.md`: append a patch-log entry describing the office-CRUD contract change (new routes, de-seeding, tombstone rename) and the deploy date.
- `docs/ROADMAP.md`: strike the office-CRUD backlog entry (mark done, reference the design doc path).

- [ ] **Step 4: Commit**

```powershell
git add php-backend/PROVENANCE.md docs/ROADMAP.md
git commit -m "docs: office-management cutover provenance + roadmap strike"
```

- [ ] **Step 5: Device verification (when wireless adb returns)**

`adb mdns services` → `adb connect <phone>` → `flutter build apk --debug` → `adb install -r build\app\outputs\flutter-apk\app-debug.apk` (keeps app data; TECNO signed in as `test@test.com`, super_admin). Verify: add "Library" → appears in Admin list + Today strip after sync; rename it; retire it → gone from Today; department-admin account sees no Add row and no manage section; 4+ offices swipe one-per-swipe with the soft blur.
