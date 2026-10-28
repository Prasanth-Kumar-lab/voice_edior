import 'mix_project.dart';

/// Reversible edit operation in Mix Studio (Command Pattern).
abstract class MixCommand {
  String get label;
  MixProject execute(MixProject current);
  MixProject undo(MixProject current);
}

/// Snapshot-backed command that stores deep-copied before/after project states.
class SnapshotMixCommand implements MixCommand {
  SnapshotMixCommand({
    required this.label,
    required MixProject before,
    required MixProject after,
  })  : _before = before.copyWith(),
        _after = after.copyWith();

  @override
  final String label;
  final MixProject _before;
  final MixProject _after;

  @override
  MixProject execute(MixProject current) => _after.copyWith();

  @override
  MixProject undo(MixProject current) => _before.copyWith();
}

/// Bounded Undo/Redo history stack supporting >= 50 steps (configured for 60 steps).
class UndoRedoStack {
  UndoRedoStack({this.maxSteps = 60});

  final int maxSteps;
  final List<MixCommand> _undoStack = <MixCommand>[];
  final List<MixCommand> _redoStack = <MixCommand>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;
  String? get nextUndoLabel => _undoStack.isEmpty ? null : _undoStack.last.label;
  String? get nextRedoLabel => _redoStack.isEmpty ? null : _redoStack.last.label;

  void push(MixCommand command) {
    _undoStack.add(command);
    if (_undoStack.length > maxSteps) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void recordChange({
    required String label,
    required MixProject before,
    required MixProject after,
  }) {
    push(SnapshotMixCommand(label: label, before: before, after: after));
  }

  MixProject? undo(MixProject current) {
    if (_undoStack.isEmpty) return null;
    final MixCommand cmd = _undoStack.removeLast();
    _redoStack.add(cmd);
    return cmd.undo(current);
  }

  MixProject? redo(MixProject current) {
    if (_redoStack.isEmpty) return null;
    final MixCommand cmd = _redoStack.removeLast();
    _undoStack.add(cmd);
    return cmd.execute(current);
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
