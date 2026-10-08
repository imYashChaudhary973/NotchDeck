import AppKit
import SwiftUI
import Testing
@testable import NotchDeck

@MainActor
struct DragDescriptionTests {
    private func pasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        write(pasteboard)
        return pasteboard
    }

    private func describe(_ pasteboard: NSPasteboard) -> String {
        defer { pasteboard.releaseGlobally() }
        return NotchHostingView<EmptyView>.describe(pasteboard)
    }

    @Test func singleFileIsDescribedByName() {
        let board = pasteboard { $0.writeObjects([URL(fileURLWithPath: "/tmp/Report.pdf") as NSURL]) }
        #expect(describe(board) == "Report.pdf")
    }

    @Test func multipleFilesAreCounted() {
        let board = pasteboard {
            $0.writeObjects([
                URL(fileURLWithPath: "/tmp/a.txt") as NSURL,
                URL(fileURLWithPath: "/tmp/b.txt") as NSURL,
                URL(fileURLWithPath: "/tmp/c.txt") as NSURL,
            ])
        }
        #expect(describe(board) == "3 items")
    }

    @Test func webLinkIsDescribedByHost() {
        let board = pasteboard { $0.writeObjects([URL(string: "https://www.apple.com/mac/")! as NSURL]) }
        #expect(describe(board) == "www.apple.com")
    }

    @Test func textIsNeverQuoted() {
        let board = pasteboard { $0.setString("my secret password", forType: .string) }
        #expect(describe(board) == "Text")
    }

    @Test func emptyPasteboardIsAGenericItem() {
        let board = pasteboard { _ in }
        #expect(describe(board) == "Item")
    }
}
