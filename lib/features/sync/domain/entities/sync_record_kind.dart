/// Which pulled aggregate a conflict came from.
///
/// Kept in the domain so application logic can ask the local store for the
/// stored timestamp without knowing SQLite table names.
enum SyncRecordKind { classItem, event, status }
