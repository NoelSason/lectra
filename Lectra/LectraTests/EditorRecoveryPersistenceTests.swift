import XCTest
@testable import Lectra

private actor GenerationRecorder {
    private var generations: [UInt64] = []

    func append(_ generation: UInt64) {
        generations.append(generation)
    }

    func values() -> [UInt64] {
        generations
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor AsyncSignal {
    private var signaled = false

    func signal() {
        signaled = true
    }

    func isSignaled() -> Bool {
        signaled
    }
}

final class EditorRecoveryPersistenceTests: XCTestCase {
    func testSnapshotIncludesActiveStrokeWithoutMutatingDrawingOrEmittingChange() {
        let canvas = VectorInkCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setDrawing(InkPageDrawing(strokes: [makeStroke(x: 0.1, y: 0.2)]))

        var changeCount = 0
        canvas.onDrawingChanged = { _ in
            changeCount += 1
        }

        canvas.testingSetActiveStroke(
            normalizedPoints: [
                InkPoint(x: 0.45, y: 0.55, force: 1.0),
                InkPoint(x: 0.62, y: 0.74, force: 1.0),
            ],
            width: 1.6
        )

        let snapshot = canvas.snapshotDrawing()

        XCTAssertEqual(snapshot.strokes.count, 2)
        XCTAssertEqual(snapshot.strokes[1].points.count, 2)
        XCTAssertEqual(canvas.currentDrawing().strokes.count, 1)
        XCTAssertEqual(changeCount, 0)
    }

    func testRecoveryWorkerCoalescesRapidRequestsToLatestGeneration() async {
        let prepared = GenerationRecorder()
        let committed = GenerationRecorder()
        let gate = AsyncGate()
        let firstPrepareStarted = AsyncSignal()
        let latestCommitFinished = AsyncSignal()

        let worker = RecoveryPersistenceWorker(
            prepareOperation: { payload in
                await prepared.append(payload.generation)
                if payload.generation == 1 {
                    await firstPrepareStarted.signal()
                    await gate.wait()
                }

                return RecoveryPreparedWrite(
                    generation: payload.generation,
                    documentId: payload.documentId,
                    drawingsData: Data([UInt8(payload.generation)]),
                    metadata: DocumentLocalMetadata()
                )
            },
            commitOperation: { preparedWrite in
                await committed.append(preparedWrite.generation)
                if preparedWrite.generation == 3 {
                    await latestCommitFinished.signal()
                }
            }
        )

        await worker.schedule(makePayload(generation: 1))
        await assertEventually {
            await firstPrepareStarted.isSignaled()
        }

        await worker.schedule(makePayload(generation: 2))
        await worker.schedule(makePayload(generation: 3))
        await gate.open()

        await assertEventually {
            await latestCommitFinished.isSignaled()
        }

        let preparedValues = await prepared.values()
        let committedValues = await committed.values()

        XCTAssertEqual(preparedValues, [1, 3])
        XCTAssertEqual(committedValues, [3])
    }

    private func makePayload(generation: UInt64) -> RecoveryPersistencePayload {
        RecoveryPersistencePayload(
            generation: generation,
            documentId: UUID(),
            lastOpenedPage: 0,
            dirtyPageIndexes: [0],
            drawings: [0: InkPageDrawing(strokes: [makeStroke(x: 0.2, y: 0.3)])],
            editedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeStroke(x: CGFloat, y: CGFloat) -> InkStroke {
        InkStroke(
            points: [
                InkPoint(x: x, y: y, force: 1.0),
                InkPoint(x: min(x + 0.1, 0.95), y: min(y + 0.1, 0.95), force: 1.0),
            ],
            width: 1.2,
            color: InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1),
            blendMode: .normal
        )
    }

    private func assertEventually(
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @Sendable () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Condition was not met before timeout.", file: file, line: line)
    }
}
