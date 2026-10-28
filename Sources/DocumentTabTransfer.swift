import AppKit

/// A drag-scoped, source-owned record of events actually dequeued after the drag began.
/// `endedAt(.none)` and NSApp.currentEvent are deliberately not release evidence.
final class DragReleaseSignal {
    private var active: (token: UUID, startedAt: TimeInterval, sourceWindowNumber: Int,
                         released: Bool, canceled: Bool)?
    private var vetoed = Set<UUID>()

    func arm(token: UUID, after timestamp: TimeInterval, sourceWindowNumber: Int) {
        active = (token, timestamp, sourceWindowNumber, false, vetoed.contains(token))
    }
    func observeDequeued(_ event: NSEvent) {
        guard var state = active else { return }
        if event.type == .keyDown && event.keyCode == 53 {
            state.canceled = true
            vetoed.insert(state.token)
        }
        else if event.type == .leftMouseUp && !state.canceled &&
                    event.timestamp > state.startedAt &&
                    event.windowNumber == state.sourceWindowNumber { state.released = true }
        active = state
    }
    func positivelyReleased(token: UUID) -> Bool {
        active.map { $0.token == token && $0.released && !$0.canceled } ?? false
    }
    func disarm(token: UUID) {
        if active?.token == token { active = nil }
    }
}

/// The actual application event dequeue is the sole production signal source.
final class DocumentDragApplication: NSApplication {
    static weak var activeReleaseSignal: DragReleaseSignal?
    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue: Bool) -> NSEvent? {
        let event = super.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: dequeue)
        if dequeue, let event { Self.activeReleaseSignal?.observeDequeued(event) }
        return event
    }
}

/// A process-local reference to one live document, never a serialized file or map.
struct DocumentDragToken {
    let id: UUID
    let documentID: UUID
    let sourceWindowID: UUID
    let sourceIndex: Int
}

final class DocumentTabTransfer {
    static let pasteboardType = NSPasteboard.PasteboardType("local.openmindflow.document-tab")
    var eligibleWindows: (() -> [WindowSession])?
    var isOverVisibleAppWindow: ((CGPoint) -> Bool)?
    var createEmptyWindow: (() -> WindowSession?)?
    private struct Entry {
        let token: DocumentDragToken
        let document: DocumentSession
        let source: WindowSession
        let generation: UInt64
    }
    private var pending: [UUID: Entry] = [:]
    /// Optional reparent hook permits a failure after AppKit has changed the view hierarchy.
    var reparent: ((DocumentSession, WindowSession) throws -> Void)?

    func begin(document: DocumentSession, source: WindowSession) -> UUID {
        let token = DocumentDragToken(id: UUID(), documentID: source.tabStrip.id(for: document),
                                      sourceWindowID: source.id,
                                      sourceIndex: source.documents.firstIndex(where: { $0 === document }) ?? -1)
        pending[token.id] = Entry(token: token, document: document, source: source,
                                  generation: source.transferGeneration)
        return token.id
    }

    func cancel(token: UUID) { pending.removeValue(forKey: token) }

    func liveSource(for token: UUID) -> WindowSession? {
        guard let entry = pending[token] else { return nil }
        let source = entry.source
        guard source.isTransferLive, entry.token.sourceWindowID == source.id,
              entry.token.documentID == source.tabStrip.id(for: entry.document),
              source.transferGeneration == entry.generation,
              source.documents.indices.contains(entry.token.sourceIndex),
              source.documents[entry.token.sourceIndex] === entry.document,
              entry.document.window === source.window else { return nil }
        return source
    }

    func canAccept(token: UUID, in target: WindowSession) -> Bool {
        liveSource(for: token) != nil && target.isTransferLive &&
        eligibleWindows?().contains(where: { $0 === target }) == true &&
        target.tabStrip.window === target.window
    }

    /// A successful destination consumes the token; no endedAt callback can repeat the move.
    @discardableResult func finish(token: UUID, locationOnScreen: CGPoint,
                                   operation: NSDragOperation, signal: DragReleaseSignal) -> Bool {
        defer { cancel(token: token) }
        guard operation.isEmpty, signal.positivelyReleased(token: token),
              let source = liveSource(for: token),
              locationOnScreen.x.isFinite, locationOnScreen.y.isFinite,
              let eligibleWindows, let isOverVisibleAppWindow,
              let createEmptyWindow else { return false }
        let windows = eligibleWindows().filter { $0.isTransferLive && $0.tabStrip.window === $0.window }
        guard windows.contains(where: { $0 === source }),
              // Canvas, chrome and another app window are never tear-off release destinations.
              !windows.contains(where: { $0.window.frame.contains(locationOnScreen) }),
              !isOverVisibleAppWindow(locationOnScreen) else { return false }
        let preexisting = Set(windows.map(ObjectIdentifier.init))
        guard let created = createEmptyWindow() else { return false }
        func discardNewEmptyWindow() {
            guard !preexisting.contains(ObjectIdentifier(created)),
                  created.documents.isEmpty, created.window.delegate === created else { return }
            created.window.close()
        }
        guard !preexisting.contains(ObjectIdentifier(created)),
              created.isTransferLive, created.documents.isEmpty,
              eligibleWindows().contains(where: { $0 === created }) else {
            discardNewEmptyWindow()
            return false
        }
        let wasVisible = source.window.isVisible
        guard move(token: token, to: created, insertion: 0) else {
            discardNewEmptyWindow()
            return false
        }
        if wasVisible { created.window.makeKeyAndOrderFront(nil) }
        return true
    }

    @discardableResult func move(token: UUID, to target: WindowSession, insertion: Int) -> Bool {
        guard let entry = pending[token] else { return false }
        let source = entry.source, document = entry.document
        guard source.isTransferLive, target.isTransferLive,
              entry.token.sourceWindowID == source.id,
              entry.token.documentID == source.tabStrip.id(for: document),
              source.transferGeneration == entry.generation,
              entry.token.sourceIndex >= 0,
              source.documents.indices.contains(entry.token.sourceIndex),
              source.documents[entry.token.sourceIndex] === document,
              document.window === source.window,
              (source === target || !target.documents.contains(where: { $0 === document })),
              (0...target.documents.count).contains(insertion) else { return false }
        if source === target {
            let adjusted = insertion > entry.token.sourceIndex ? insertion - 1 : insertion
            guard adjusted != entry.token.sourceIndex else { return false }
            source.transferReorder(from: entry.token.sourceIndex, to: adjusted)
            pending.removeValue(forKey: token)
            return true
        }
        // No hierarchy or ownership changes until both outgoing editors accept the transition.
        guard document.commitPendingEditors(),
              (source.active === document || (source.active?.commitPendingEditors() ?? true)),
              (target.active?.commitPendingEditors() ?? true) else { return false }
        let oldSourceWorkbench = source.tabRoot.workbench
        let oldTargetWorkbench = target.tabRoot.workbench
        do {
            try (reparent ?? { document, target in target.tabRoot.display(document.splitController) })(document, target)
        } catch {
            if target.tabRoot.workbench !== oldTargetWorkbench ||
                (oldTargetWorkbench != nil &&
                 (oldTargetWorkbench?.parent !== target.tabRoot ||
                  oldTargetWorkbench?.view.superview !== target.tabRoot.layoutView)) {
                target.tabRoot.display(oldTargetWorkbench)
            }
            if source.tabRoot.workbench !== oldSourceWorkbench ||
                (oldSourceWorkbench != nil &&
                 (oldSourceWorkbench?.parent !== source.tabRoot ||
                  oldSourceWorkbench?.view.superview !== source.tabRoot.layoutView)) {
                source.tabRoot.display(oldSourceWorkbench)
            }
            return false
        }
        source.transferDetach(document)
        target.transferAttach(document, at: insertion)
        pending.removeValue(forKey: token)
        if source.documents.isEmpty { source.window.close() }
        return true
    }
}
