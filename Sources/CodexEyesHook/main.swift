import Foundation
import CodexEyesCore

// Passive observer: no authorization decisions, conversation text or tool inputs retained.
var input = Data()
while input.count <= 1_048_576 {
    let chunk = FileHandle.standardInput.readData(ofLength: 65536)
    if chunk.isEmpty { break }
    input.append(chunk)
}
if input.count <= 1_048_576,
   let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
   let event = HookEvent(input: object) {
    try? HookRecorder.record(event)
}
// Stop hooks require JSON on successful stdout. Empty JSON has no control effects.
print("{}")
