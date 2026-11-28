import '../domain/entities/sync_result.dart';
import 'pull_sync.dart';
import 'push_sync.dart';

/// Full sync: push then pull.
///
/// The pull is skipped when the push fails: applying server rows while
/// unserved local changes are stuck can silently overwrite them if the push
/// just missed the network. Nothing is lost by waiting; the next cycle pushes
/// first.
class SyncNow {
  const SyncNow({required this.push, required this.pull});

  final PushSync push;
  final PullSync pull;

  Future<SyncResult> call() async {
    final pushed = await push();
    if (!pushed.isSuccess) return pushed;
    return pull();
  }
}
