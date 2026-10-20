# Task 1 report

**Status:** DONE

- Tests written before implementation in `Tests/MapModelTests.swift`. The requested command initially exited 1 because `Sources/MapModel.swift` did not yet exist. After adding only the model's type declarations, the same command exited 1 with the expected missing-method compiler errors (`addChild`, `addSibling`, `rename`, `toggleFold`, `remove`, `undo`, `redo`).
- Implemented tree edits, root-deletion rejection, selection updates, and snapshot undo/redo in `Sources/MapModel.swift`; no dependencies added.
- Final command: `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindnode-model-tests && /tmp/mindnode-model-tests`
- Final result: exit 0; `model tests passed`.
- Unrelated existing workspace changes in `docs/superpowers/plans/2026-10-20-native-editor.md` and `docs/static-evidence.md` were left untouched and excluded from this commit.

## Important review findings follow-up

- Added assert-based coverage for adding to a folded parent: the new child is selected and visible, and a single undo restores both the folded parent and previous selection; redo reapplies both. Added a three-level subtree sequence checking deep sibling insertion order/titles/selection, insertion undo/redo, deletion of a parent with descendants, and deletion undo/redo restoring exact descendant IDs, order, titles, and selection.
- RED (tests changed, model unchanged): `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindnode-model-tests && /tmp/mindnode-model-tests` exited 133 with `main/MapModelTests.swift:65: Assertion failed` (folded parent remained folded).
- Model fix: `addChild()` unfolds its parent after `save()` in the same edit as child insertion; snapshot undo restores fold and selection together.
- GREEN (after model fix): `swiftc Sources/MapModel.swift Tests/MapModelTests.swift -o /tmp/mindnode-model-tests && /tmp/mindnode-model-tests` exited 0 and printed `model tests passed`.
