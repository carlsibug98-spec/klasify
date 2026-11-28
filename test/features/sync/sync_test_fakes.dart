import 'package:klasify/features/sync/domain/entities/sync_change.dart';
import 'package:klasify/features/sync/domain/entities/sync_record.dart';
import 'package:klasify/features/sync/domain/entities/sync_record_kind.dart';
import 'package:klasify/features/sync/domain/repositories/sync_ports.dart';

class FakeLocalStore implements SyncLocalStore {
  String deviceIdValue = 'device-1';
  DateTime? lastPush;
  DateTime? lastPull;
  List<SyncClassChange> classes = [];
  List<SyncEventChange> events = [];
  List<SyncStatusChange> statuses = [];
  Map<int, int> classIds = {};
  final Map<String, DateTime?> localStamps = {};
  DateTime? purgedBefore;
  bool pruneCalled = false;
  int pendingChanges = 0;

  final List<String> calls = [];
  final List<SyncClassRecord> appliedClasses = [];
  final List<SyncEventRecord> appliedEvents = [];
  final List<SyncStatusRecord> appliedStatuses = [];
  final List<SyncOfficeRecord> appliedOffices = [];

  @override
  Future<String> deviceId() async => deviceIdValue;

  @override
  Future<DateTime?> lastPushAt() async => lastPush;

  @override
  Future<DateTime?> lastPullAt() async => lastPull;

  @override
  Future<List<SyncClassChange>> changedClasses(DateTime since) async => classes;

  @override
  Future<List<SyncEventChange>> changedEvents(DateTime since) async => events;

  @override
  Future<List<SyncStatusChange>> changedStatuses(DateTime since) async =>
      statuses;

  @override
  Future<Map<int, int>> classServerIds() async => classIds;

  @override
  Future<DateTime?> localUpdatedAt(SyncRecordKind kind, int serverId) async =>
      localStamps['${kind.name}:$serverId'];

  @override
  Future<void> setClassServerId(int localId, int serverId) async {
    calls.add('setClassServerId');
    classIds[localId] = serverId;
  }

  @override
  Future<void> setEventServerId(int localId, int serverId) async {
    calls.add('setEventServerId');
  }

  @override
  Future<void> setClassStatusServerId(int localId, int serverId) async {
    calls.add('setClassStatusServerId');
  }

  @override
  Future<void> applyClass(SyncClassRecord row) async {
    calls.add('applyClass');
    appliedClasses.add(row);
  }

  @override
  Future<void> applyEvent(SyncEventRecord row) async {
    calls.add('applyEvent');
    appliedEvents.add(row);
  }

  @override
  Future<void> applyStatus(SyncStatusRecord row) async {
    calls.add('applyStatus');
    appliedStatuses.add(row);
  }

  @override
  Future<void> applyOfficeStatus(SyncOfficeRecord row) async {
    calls.add('applyOfficeStatus');
    appliedOffices.add(row);
  }

  @override
  Future<void> pruneUnadoptedOfficeStatuses() async {
    calls.add('pruneUnadoptedOfficeStatuses');
    pruneCalled = true;
  }

  @override
  Future<void> purgeDeleted(DateTime? pushedBefore) async {
    calls.add('purgeDeleted');
    purgedBefore = pushedBefore;
  }

  @override
  Future<void> setLastPushAt(DateTime value) async {
    calls.add('setLastPushAt');
    lastPush = value;
  }

  @override
  Future<void> setLastPullAt(DateTime value) async {
    calls.add('setLastPullAt');
    lastPull = value;
  }

  @override
  Future<int> pendingChangeCount() async => pendingChanges;
}

class FakeRemoteGateway implements SyncRemoteGateway {
  SyncPushBatch? pushedBatch;
  String? pushToken;
  SyncPushAck pushAck = const SyncPushAck(
    serverTime: null,
    classes: [],
    events: [],
    classStatuses: [],
  );
  SyncPullBatch pullBatch = const SyncPullBatch(
    serverTime: null,
    classes: [],
    events: [],
    classStatuses: [],
    officeStatuses: [],
  );
  String? pullToken;
  String? pullDeviceId;
  DateTime? pullSince;
  Object? pushError;
  Object? pullError;
  int pushCalls = 0;
  int pullCalls = 0;
  void Function()? onPush;
  void Function()? onPull;

  @override
  Future<SyncPushAck> push({
    required String token,
    required SyncPushBatch batch,
  }) async {
    pushCalls++;
    pushToken = token;
    pushedBatch = batch;
    onPush?.call();
    if (pushError != null) throw pushError!;
    return pushAck;
  }

  @override
  Future<SyncPullBatch> pull({
    required String token,
    required String deviceId,
    required DateTime? since,
  }) async {
    pullCalls++;
    pullToken = token;
    pullDeviceId = deviceId;
    pullSince = since;
    onPull?.call();
    if (pullError != null) throw pullError!;
    return pullBatch;
  }
}

class FakeSession implements SyncSession {
  FakeSession({this.userId = 7});

  @override
  int? userId;
  bool loggedIn = true;
  String? token = 'token-7';
  bool pinResult = true;
  int generation = 1;
  bool changeUserOnPin = false;
  final List<int> writeGenerations = [];
  final List<void Function()> listeners = [];

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<String?> freshToken() async => loggedIn ? token : null;

  @override
  Future<bool> pinScope(int? userId) async {
    if (changeUserOnPin) this.userId = 8;
    return pinResult;
  }

  @override
  int get scopeGeneration => generation;

  @override
  Future<bool> writeIfCurrent(
    int generation,
    Future<void> Function() write,
  ) async {
    writeGenerations.add(generation);
    if (generation != this.generation) return false;
    await write();
    return true;
  }

  @override
  void addSessionListener(void Function() listener) => listeners.add(listener);

  @override
  void removeSessionListener(void Function() listener) =>
      listeners.remove(listener);
}

SyncClassChange classChange({int localId = 1}) => SyncClassChange(
  localId: localId,
  serverId: null,
  subject: 'Algebra',
  room: 'Room 1',
  professor: 'Prof',
  day: 1,
  startMinutes: 480,
  endMinutes: 540,
  deleted: false,
  updatedAt: DateTime.utc(2026, 1, 1),
);

SyncEventChange eventChange({int localId = 2}) => SyncEventChange(
  localId: localId,
  serverId: null,
  title: 'Assembly',
  venue: 'Gym',
  date: '2026-12-01',
  startMinutes: 600,
  category: 'school',
  department: null,
  broadcast: false,
  remindMe: true,
  leadMinutes: 30,
  deleted: false,
  updatedAt: DateTime.utc(2026, 1, 1),
);

SyncStatusChange statusChange({int localId = 3, int localClassId = 4}) =>
    SyncStatusChange(
      localId: localId,
      serverId: null,
      localClassId: localClassId,
      serverClassId: null,
      status: 'cancelled',
      startDate: '2026-11-18',
      endDate: '2026-11-18',
      deleted: false,
      updatedAt: '2026-11-18T08:00:00.000Z',
    );

SyncClassRecord classRecord({int serverId = 10}) => SyncClassRecord(
  serverId: serverId,
  localId: null,
  subject: 'Algebra',
  room: 'Room 1',
  professor: 'Prof',
  day: 1,
  startMinutes: 480,
  endMinutes: 540,
  deleted: false,
  updatedAt: '2026-01-05T00:00:00.000Z',
);

SyncEventRecord eventRecord({int serverId = 20}) => SyncEventRecord(
  serverId: serverId,
  localId: null,
  title: 'Assembly',
  venue: 'Gym',
  eventDate: '2026-12-01',
  startMinutes: 600,
  category: 'school',
  department: null,
  broadcast: false,
  reminderEnabled: true,
  leadMinutes: 30,
  deleted: false,
  updatedAt: '2026-01-05T00:00:00.000Z',
);

SyncStatusRecord statusRecord({int serverId = 30}) => SyncStatusRecord(
  serverId: serverId,
  localId: null,
  classId: 10,
  localClassId: null,
  status: 'cancelled',
  startDate: '2026-11-18',
  endDate: '2026-11-18',
  deleted: false,
  updatedAt: '2026-01-05T00:00:00.000Z',
);

SyncOfficeRecord officeRecord({int serverId = 40}) => SyncOfficeRecord(
  serverId: serverId,
  officeName: 'Registrar',
  department: 'CCS',
  status: 'open',
  customMessage: null,
  deleted: false,
  updatedAt: '2026-01-05T00:00:00.000Z',
);
