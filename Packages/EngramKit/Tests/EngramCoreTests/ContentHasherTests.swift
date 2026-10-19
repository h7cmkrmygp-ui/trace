import Testing
import Foundation
@testable import EngramCore

struct ContentHasherTests {
    @Test func sha256OfKnownVector() {
        #expect(ContentHasher.sha256Hex(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func textHashIgnoresWhitespaceDifferences() {
        #expect(ContentHasher.textHash("  a   b \n") == ContentHasher.textHash("a b"))
    }

    @Test func textHashKeepsCase() {
        #expect(ContentHasher.textHash("A b") != ContentHasher.textHash("a b"))
    }
}
