import AppKit

/// A process-local reference to one live document, never a serialized file or map.
struct DocumentDragToken {
    let id: UUID
    let documentID: UUID
    let sourceWindowID: UUID
    let sourceIndex: Int
}

final class DocumentTabTransfer {
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
            if target.tabRoot.workbench !== oldTargetWorkbench { target.tabRoot.display(oldTargetWorkbench) }
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
