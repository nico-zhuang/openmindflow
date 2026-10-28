import AppKit
import Darwin

@main enum DocumentTabTransferTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let defaults = UserDefaults(suiteName: "local.openmindflow.transfer.\(UUID())")!
        let app = AppDelegate(defaults: defaults)
        let source = app.makeUnshownWindowSession(), target = app.makeUnshownWindowSession()
        let a = source.active!, d = target.active!
        source.onNewTab?(); let b = source.active!
        source.onNewTab?(); let c = source.active!
        let transfer = DocumentTabTransfer()
        func order(_ owner: WindowSession, _ expected: [DocumentSession]) {
            assert(owner.documents.count == expected.count)
            for (actual, wanted) in zip(owner.documents, expected) { assert(actual === wanted) }
        }
        func unchanged(_ token: UUID, _ reason: String, insertion: Int = 0) {
            let first = source.documents, second = target.documents
            let sourceActive = source.active, targetActive = target.active
            let firstParent = source.tabRoot.workbench, secondParent = target.tabRoot.workbench
            assert(!transfer.move(token: token, to: reason == "same-slot drop" ? source : target, insertion: insertion), reason)
            order(source, first); order(target, second)
            assert(source.active === sourceActive && target.active === targetActive)
            assert(source.tabRoot.workbench === firstParent && target.tabRoot.workbench === secondParent)
        }
        assert(source.activate(b))
        let reorder = transfer.begin(document: b, source: source)
        assert(transfer.move(token: reorder, to: source, insertion: 3))
        order(source, [a,c,b]); assert(source.active === b)
        unchanged(reorder, "replayed reorder")
        let noop = transfer.begin(document: b, source: source)
        unchanged(noop, "same-slot drop", insertion: 3)
        let rangeToken = transfer.begin(document: a, source: source)
        assert(!transfer.move(token: rangeToken, to: target, insertion: 9))
        order(source, [a,c,b]); order(target, [d])
        transfer.cancel(token: rangeToken)
        unchanged(rangeToken, "canceled token")
        let foreign = transfer.begin(document: d, source: source)
        unchanged(foreign, "foreign ownership")
        let stale = transfer.begin(document: c, source: source)
        assert(source.activate(c))
        source.remove(c)
        unchanged(stale, "removed original")
        source.insert(c, at: 1)
        assert(source.activate(c)) // Rebind a deliberately removed fixture before any later transfer.
        assert(c.window === source.window)
        unchanged(stale, "reinserted original remains stale")
        assert(source.activate(b))
        let oldModel = a.canvas.model, oldCanvas = a.canvas, oldSplit = a.splitController
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        var pattern = (base.path + "/openmindflow-transfer-XXXXXX").utf8CString
        let path = try pattern.withUnsafeMutableBufferPointer { bytes -> String in
            guard let address = bytes.baseAddress, let result = mkdtemp(address) else { throw POSIXError(.EIO) }
            return String(cString: result)
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var owner = stat()
        precondition(lstat(path, &owner) == 0 && owner.st_uid == getuid() && owner.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && owner.st_mode & 0o777 == 0o700 && directory.deletingLastPathComponent() == base && directory.resolvingSymlinksInPath().standardizedFileURL == directory)
        defer {
            var now = stat()
            if lstat(path, &now) == 0 && now.st_dev == owner.st_dev && now.st_ino == owner.st_ino && now.st_uid == getuid() && now.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && now.st_mode & 0o777 == 0o700 && directory.deletingLastPathComponent() == base && directory.resolvingSymlinksInPath().standardizedFileURL == directory { try? FileManager.default.removeItem(at: directory) }
        }
        let url = directory.appendingPathComponent("A.mflw")
        try a.saveCurrentMap(to: url)
        a.canvas.addMainNode()
        let dirty = a.dirty, archive = a.mindNodeArchive, identity = a.nativeIdentity
        let bytes = try Data(contentsOf: url)
        let undoRoots = a.canvas.model.roots
        let reject = transfer.begin(document: a, source: source)
        d.inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        unchanged(reject, "invalid target editor")
        d.inspector.noteTextView.string = ""
        b.inspector.noteTextView.string = String(repeating: "界", count: 22_000)
        unchanged(reject, "invalid outgoing source editor")
        b.inspector.noteTextView.string = ""
        assert(source.activate(a))
        let sourceTitle = source.window.title, targetTitle = target.window.title
        let sourceSelected = source.tabStrip.selectedID, targetSelected = target.tabStrip.selectedID
        let sourceRegistry = app.resolveSession(for: source.window)
        let targetRegistry = app.resolveSession(for: target.window)
        let failure = transfer.begin(document: a, source: source)
        transfer.reparent = { document, destination in
            destination.tabRoot.display(document.splitController)
            assert(document.splitController.parent === destination.tabRoot)
            assert(document.splitController.view.superview === destination.tabRoot.layoutView)
            throw POSIXError(.EIO)
        }
        unchanged(failure, "active source reparent refusal")
        assert(a.splitController === oldSplit && a.canvas === oldCanvas && a.canvas.model === oldModel)
        assert(a.splitController.parent === source.tabRoot)
        assert(a.splitController.view.superview === source.tabRoot.layoutView)
        assert(d.splitController.parent === target.tabRoot)
        assert(d.splitController.view.superview === target.tabRoot.layoutView)
        assert(a.window === source.window && d.window === target.window)
        assert(source.tabStrip.selectedID == sourceSelected && target.tabStrip.selectedID == targetSelected)
        assert(source.window.title == sourceTitle && target.window.title == targetTitle)
        assert(app.resolveSession(for: source.window) === sourceRegistry)
        assert(app.resolveSession(for: target.window) === targetRegistry)
        assert(a.dirty == dirty && a.mindNodeArchive == nil && archive == nil && a.fileURL == url && a.nativeIdentity == identity)
        let rollbackBytes = try Data(contentsOf: url)
        assert(rollbackBytes == bytes)
        transfer.reparent = nil
        let move = transfer.begin(document: a, source: source)
        assert(transfer.move(token: move, to: target, insertion: 0))
        order(source, [c,b]); order(target, [a,d])
        assert(source.active === c && target.active === a && a.window === target.window)
        assert(source.window.title == targetTitle) // The surviving C has the original untitled title.
        assert(target.window.title == sourceTitle) // The moved A retains its saved, dirty title.
        assert(a.canvas === oldCanvas && a.canvas.model === oldModel && a.splitController === oldSplit && a.dirty == dirty && a.mindNodeArchive == nil && archive == nil && a.fileURL == url && a.nativeIdentity == identity)
        assert(a.splitController.parent === target.tabRoot)
        assert(app.resolveSession(for: target.window) === a && app.primarySessionForTesting === a)
        try a.verifyNativeBaseline()
        let movedBytes = try Data(contentsOf: url)
        assert(movedBytes == bytes)
        a.canvas.undo(); assert(a.canvas.model.roots.count == undoRoots.count - 1)
        a.canvas.redo(); assert(a.canvas.model.roots == undoRoots)
        unchanged(move, "replayed cross-window token")
        let closeTarget = app.makeUnshownWindowSession()
        let closeToken = transfer.begin(document: b, source: source)
        closeTarget.window.close()
        assert(!transfer.move(token: closeToken, to: closeTarget, insertion: 0))
        order(source, [c,b])
        let last = app.makeUnshownWindowSession(), only = last.active!
        let lastToken = transfer.begin(document: only, source: last)
        assert(transfer.move(token: lastToken, to: target, insertion: 2))
        assert(last.documents.isEmpty && !app.windowSessions.contains(where: { $0 === last }))
        assert(target.documents.filter { $0 === only }.count == 1 && only.window === target.window)
        let strip = target.tabStrip
        strip.orientation = .horizontal
        assert(strip.insertionIndex(at: CGPoint(x: 76, y: 0)) == 0)
        assert(strip.insertionIndex(at: CGPoint(x: 78, y: 0)) == 1)
        strip.orientation = .vertical
        assert(strip.insertionIndex(at: CGPoint(x: 0, y: 17)) == 0)
        assert(strip.insertionIndex(at: CGPoint(x: 0, y: 18)) == 1)
        print("transactional reorder, transfer rollback, identity, private bytes and last-tab close passed")
    }
}
