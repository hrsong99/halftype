import Foundation
import Testing
@testable import HalftypeCore

@Test func anAdapterSaysWhatItLearnedFrom() throws {
    #expect(AdapterInfo.title(name: "john-2026-11-09-cloud") == "Nov 9")
    #expect(AdapterInfo.title(name: "john-2026-11-09-cloud-2") == "Nov 9 (2)")
    #expect(AdapterInfo.title(name: "john-2026-11-08") == "Nov 8")
    #expect(AdapterInfo.title(name: "mine") == "mine")
    let cloud = try JSONDecoder().decode(AdapterInfo.self, from: Data(#"{"model":"kanana","rank":8,"rows":3014,"from":"2026-08-09","to":"2026-11-09","gpu":"NVIDIA L4"}"#.utf8))
    #expect(cloud.note == "3,014 messages, Aug 9 – Nov 9 · trained on a rented GPU")
    #expect(AdapterInfo(rows: 2986, gpu: "Mac").note == "2,986 messages · trained on this Mac")
    #expect(AdapterInfo().note == nil)
}
