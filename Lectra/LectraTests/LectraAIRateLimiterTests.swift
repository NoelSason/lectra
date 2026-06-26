import XCTest
@testable import Lectra

final class LectraAIRateLimiterTests: XCTestCase {
    func testBurstLimitRejectsRapidRequestsUntilWindowClears() async throws {
        let limiter = LectraAIRateLimiter(policy: .init(
            burstLimit: 2,
            burstWindow: 10,
            rollingLimit: 10,
            rollingWindow: 60
        ))
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        try await limiter.acquire(at: start)
        try await limiter.acquire(at: start.addingTimeInterval(1))

        do {
            try await limiter.acquire(at: start.addingTimeInterval(2))
            XCTFail("Expected rapid third request to be rate limited.")
        } catch let error as LectraAIRateLimitError {
            XCTAssertEqual(error.retryAfter, 8)
        }

        try await limiter.acquire(at: start.addingTimeInterval(10))
    }

    func testRollingLimitRejectsRequestsAcrossLongerWindow() async throws {
        let limiter = LectraAIRateLimiter(policy: .init(
            burstLimit: 10,
            burstWindow: 10,
            rollingLimit: 3,
            rollingWindow: 60
        ))
        let start = Date(timeIntervalSinceReferenceDate: 2_000)

        try await limiter.acquire(at: start)
        try await limiter.acquire(at: start.addingTimeInterval(15))
        try await limiter.acquire(at: start.addingTimeInterval(30))

        do {
            try await limiter.acquire(at: start.addingTimeInterval(45))
            XCTFail("Expected rolling-window request to be rate limited.")
        } catch let error as LectraAIRateLimitError {
            XCTAssertEqual(error.retryAfter, 15)
        }

        try await limiter.acquire(at: start.addingTimeInterval(60))
    }

    func testErrorMessageUsesHumanReadableCooldown() {
        XCTAssertEqual(
            LectraAIRateLimitError(retryAfter: 75).localizedDescription,
            "Intelligence is cooling down. Try again in 2 minutes."
        )
    }
}
