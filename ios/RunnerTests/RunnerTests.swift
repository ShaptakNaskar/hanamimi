import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testImportAndPlaybackCapabilities() {
    let info = Bundle.main.infoDictionary ?? [:]
    XCTAssertEqual(info["UIFileSharingEnabled"] as? Bool, true)
    XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    XCTAssertTrue((info["UIBackgroundModes"] as? [String] ?? []).contains("audio"))
    XCTAssertNil(info["NSMicrophoneUsageDescription"])
  }
}
