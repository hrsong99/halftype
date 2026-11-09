import Foundation
import Testing
@testable import HalftypeCore

@Test func anAdapterSaysWhatItLearnedFrom() throws {
    #expect(AdapterInfo.title(name: "john-2026-11-09") == "Nov 9")
    #expect(AdapterInfo.title(name: "john-2026-11-09-2") == "Nov 9 (2)")
    #expect(AdapterInfo.title(name: "john-2026-11-09-cloud") == "john-2026-11-09-cloud")  // not a train.sh name: shown as it is
    #expect(AdapterInfo.title(name: "mine") == "mine")
    let run = try JSONDecoder().decode(AdapterInfo.self, from: Data(#"{"model":"kanana","rank":8,"rows":3014,"from":"2026-08-09","to":"2026-11-09","gpu":"NVIDIA L4"}"#.utf8))
    #expect(run.note == "3,014 messages, Aug 9 – Nov 9")
    #expect(AdapterInfo(rows: 2986).note == "2,986 messages")
    #expect(AdapterInfo().note == nil)
}
