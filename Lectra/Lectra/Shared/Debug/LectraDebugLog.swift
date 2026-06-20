import Foundation

nonisolated func LectraDebugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
