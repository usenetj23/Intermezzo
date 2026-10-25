import XCTest
@testable import IntermezzoKit

final class MessagesStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: MessagesStore.readKey)
        UserDefaults.standard.removeObject(forKey: MessagesStore.breakEveryKey)
    }

    func testCatalogIsUniqueAndNonEmpty() {
        XCTAssertGreaterThanOrEqual(MessagesCatalog.all.count, 10)
        let ids = Set(MessagesCatalog.all.map { $0.id })
        XCTAssertEqual(ids.count, MessagesCatalog.all.count)
        for message in MessagesCatalog.all {
            XCTAssertFalse(message.title.isEmpty)
            XCTAssertFalse(message.body.isEmpty)
            XCTAssertFalse(message.breakHint.isEmpty)
        }
    }

    func testMarkReadAndMarkAllRead() {
        let store = MessagesStore()
        guard let first = MessagesCatalog.all.first else { return }
        XCTAssertTrue(store.isUnread(first))
        store.markRead(id: first.id)
        XCTAssertFalse(store.isUnread(first))
        store.markAllRead()
        XCTAssertTrue(MessagesCatalog.all.allSatisfy { !store.isUnread($0) })
    }

    func testMessageForBreakCadence() {
        let store = MessagesStore()
        UserDefaults.standard.set(3, forKey: MessagesStore.breakEveryKey)
        // breaks 0,1 show nothing; break index 2 (third) shows first unread.
        XCTAssertNil(store.messageForBreak(breakIndex: 0, enabled: true))
        XCTAssertNil(store.messageForBreak(breakIndex: 1, enabled: true))
        let shown = store.messageForBreak(breakIndex: 2, enabled: true)
        XCTAssertEqual(shown?.id, MessagesCatalog.all[0].id)
        // disabled => nil
        XCTAssertNil(store.messageForBreak(breakIndex: 5, enabled: false))
        // all read => nil
        store.markAllRead()
        XCTAssertNil(store.messageForBreak(breakIndex: 8, enabled: true))
    }
}

final class HealthMessagesTests: XCTestCase {
    func testEvidenceMessagesArePresentAndCiteSources() {
        let ids = Set(MessagesCatalog.all.map(\.id))
        for id in ["blink-rate", "screen-setup", "lighting-glare", "blue-light", "break-science",
                   "screen-time-limit", "move-more", "posture-variety", "evidence-quality"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        for m in HealthMessages.all {
            XCTAssertTrue(m.body.contains("Źródła:"), "\(m.id) has no sources line")
            XCTAssertTrue(m.body.contains("To nie porada medyczna") || m.id != "evidence-quality")
        }
    }

    func testWelcomeStaysFirst() {
        XCTAssertEqual(MessagesCatalog.all.first?.id, "welcome")
        XCTAssertEqual(Set(MessagesCatalog.all.map(\.id)).count, MessagesCatalog.all.count)
    }
}
