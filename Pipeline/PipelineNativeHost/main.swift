import Foundation
import SwiftData
import PipelineKit

// MARK: - Chrome Native Messaging Protocol
//
// Messages use a 4-byte (UInt32, little-endian) length prefix followed by
// a JSON payload on stdin/stdout.
// Chrome spawns a new host process for each sendNativeMessage() call.

let expectedOrigin = "chrome-extension://\(Constants.BrowserExtensions.Chrome.extensionID)/"
if let callerOrigin = CommandLine.arguments.dropFirst().first,
   callerOrigin != expectedOrigin {
    writeMessage([
        "success": false,
        "error": "Unauthorized Chrome extension origin: \(callerOrigin)"
    ])
    exit(1)
}

func readMessage() -> [String: Any]? {
    // Read 4-byte length prefix (little-endian UInt32)
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    let bytesRead = fread(&lengthBytes, 1, 4, stdin)
    guard bytesRead == 4 else { return nil }

    let length = UInt32(lengthBytes[0])
        | (UInt32(lengthBytes[1]) << 8)
        | (UInt32(lengthBytes[2]) << 16)
        | (UInt32(lengthBytes[3]) << 24)

    guard length > 0, length < 1_048_576 else { return nil } // Max 1MB

    var buffer = [UInt8](repeating: 0, count: Int(length))
    let dataRead = fread(&buffer, 1, Int(length), stdin)
    guard dataRead == Int(length) else { return nil }

    let data = Data(buffer)
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

func writeMessage(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

    let length = UInt32(data.count)
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    lengthBytes[0] = UInt8(length & 0xFF)
    lengthBytes[1] = UInt8((length >> 8) & 0xFF)
    lengthBytes[2] = UInt8((length >> 16) & 0xFF)
    lengthBytes[3] = UInt8((length >> 24) & 0xFF)

    fwrite(lengthBytes, 1, 4, stdout)
    _ = data.withUnsafeBytes { buffer in
        fwrite(buffer.baseAddress, 1, data.count, stdout)
    }
    fflush(stdout)
}

// MARK: - Entry Point

guard let message = readMessage() else {
    writeMessage(["error": "Failed to read message"])
    exit(1)
}

guard let command = message["command"] as? String else {
    writeMessage(["error": "Missing 'command' field"])
    exit(1)
}

var response: [String: Any] = [:]
let group = DispatchGroup()
group.enter()

Task {
    switch command {
    case "parse":
        response = await NativeMessageHandler.handleParse(message: message)
    case "check-duplicate":
        response = await NativeMessageHandler.handleDuplicateCheck(message: message)
    default:
        response = ["error": "Unknown command: \(command)"]
    }
    group.leave()
}

while group.wait(timeout: .now()) == .timedOut {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
}

writeMessage(response)
