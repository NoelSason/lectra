import Foundation

struct PairingCredentials {
    let deviceID: String
    let deviceToken: String
}

enum PairingParseError: Error {
    case missingParams
    case invalidDeviceID
}

func parsePairingLink(_ rawURL: String) throws -> PairingCredentials {
    guard let components = URLComponents(string: rawURL) else {
        throw PairingParseError.missingParams
    }

    let queryItems = components.queryItems ?? []
    let deviceID = queryItems.first(where: { $0.name == "device" })?.value ?? ""
    let deviceToken = queryItems.first(where: { $0.name == "token" })?.value ?? ""

    guard !deviceID.isEmpty, !deviceToken.isEmpty else {
        throw PairingParseError.missingParams
    }

    guard UUID(uuidString: deviceID) != nil else {
        throw PairingParseError.invalidDeviceID
    }

    return PairingCredentials(deviceID: deviceID, deviceToken: deviceToken)
}
