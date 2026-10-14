import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import PasteLoom

@MainActor
final class ClipboardClassifierTests: XCTestCase {
    func testThemeSwitchAndPreferencePersistence() {
        let suite = "PasteLoomThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(PaperTheme.macosNative.rawValue, forKey: "themePreset")
        defaults.set(PaperAccent.terracotta.rawValue, forKey: "accentColor")
        defaults.set("dark", forKey: "appearanceMode")
        let restored = UserDefaults(suiteName: suite)!
        XCTAssertEqual(PaperTheme(rawValue: restored.string(forKey: "themePreset") ?? ""), .macosNative)
        XCTAssertEqual(PaperAccent(rawValue: restored.string(forKey: "accentColor") ?? ""), .terracotta)
        XCTAssertEqual(restored.string(forKey: "appearanceMode"), "dark")

        let light = PaperTheme.macosNative.palette(for: .light, accentOverride: nil)
        let dark = PaperTheme.macosNative.palette(for: .dark, accentOverride: nil)
        XCTAssertNotEqual(NSColor(light.background).description, NSColor(dark.background).description)
        XCTAssertNotEqual(NSColor(light.cardBackground).description, NSColor(dark.cardBackground).description)
        XCTAssertNotEqual(NSColor(light.accent).description,
                          NSColor(PaperTheme.macosNative.palette(for: .light, accentOverride: .terracotta).accent).description)
        XCTAssertEqual(PaperTheme.macosNative.name, "macOS 原生毛玻璃")
        XCTAssertFalse(light.isDark)
        XCTAssertTrue(dark.isDark)
        XCTAssertTrue(light.isFrostedGlass)
        XCTAssertTrue(dark.isFrostedGlass)
        XCTAssertEqual(AppearanceManager.effectiveColorScheme(for: "light"), .light)
        XCTAssertEqual(AppearanceManager.effectiveColorScheme(for: "dark"), .dark)
    }
    func testSourceMetadataResolverAndUnknownFallback() {
        let source = CaptureSource.resolve(displayName: " TextEdit ",
                                           bundleIdentifier: "com.apple.TextEdit")
        XCTAssertEqual(source?.name, "TextEdit")
        XCTAssertEqual(source?.bundleIdentifier, "com.apple.TextEdit")
        XCTAssertNil(CaptureSource.resolve(displayName: nil, bundleIdentifier: nil))
        XCTAssertNil(CaptureSource.resolve(displayName: "PasteLoom",
                                           bundleIdentifier: "com.gyryez.pasteloom.next"))
    }
    func testTypeExclusionsOnlySkipChosenCaptureKinds() {
        let policy = CaptureTypeExclusions(image: true, file: true)
        XCTAssertFalse(policy.excludes(.text("keep")))
        XCTAssertFalse(policy.excludes(.url("https://example.com")))
        XCTAssertTrue(policy.excludes(.image(Data([1]))))
        XCTAssertTrue(policy.excludes(.files([])))
    }

    func testURLCleanerRemovesTrackersButRetainsUsefulQueryAndFragment() {
        let original = "https://example.com/page?sku=123&utm_source=news&fbclid=abc&lang=zh#details"
        XCTAssertEqual(URLCleaner.clean(original), "https://example.com/page?sku=123&lang=zh#details")
        XCTAssertEqual(URLCleaner.clean("https://example.com/?sku=123"), "https://example.com/?sku=123")
        XCTAssertEqual(URLCleaner.clean("plain text"), "plain text")
    }

    func testURLClassificationKeepsOriginalString() {
        let raw = "https://example.com/test?x=1#part"
        let result = ClipboardClassifier.classify(.init(fileURLs: [], imageData: nil, urlString: nil, plainText: raw))
        guard case .url(let url) = result else { return XCTFail("Expected URL") }
        XCTAssertEqual(url, raw)
    }

    func testPriorityFileThenImageThenURLThenText() {
        let file = URL(fileURLWithPath: "/tmp/sample.png")
        let all = ClipboardSnapshot(fileURLs: [file], imageData: Data([1]), urlString: "https://example.com", plainText: "plain")
        guard case .files(let files) = ClipboardClassifier.classify(all) else { return XCTFail("Expected files") }
        XCTAssertEqual(files.map(\.url), [file])
        guard case .image = ClipboardClassifier.classify(.init(fileURLs: [], imageData: Data([1]), urlString: all.urlString, plainText: all.plainText)) else {
            return XCTFail("Expected image")
        }
        guard case .url = ClipboardClassifier.classify(.init(fileURLs: [], imageData: nil, urlString: all.urlString, plainText: all.plainText)) else {
            return XCTFail("Expected URL")
        }
        guard case .text = ClipboardClassifier.classify(.init(fileURLs: [], imageData: nil, urlString: nil, plainText: "plain")) else {
            return XCTFail("Expected text")
        }
    }

    func testMultiFileIsOneLogicalCaptureAndMissingFileIsSafe() {
        let urls = [URL(fileURLWithPath: "/tmp/first.txt"), URL(fileURLWithPath: "/tmp/missing-second.pdf")]
        let result = ClipboardClassifier.classify(.init(fileURLs: urls, imageData: nil, urlString: nil, plainText: nil))
        guard case .files(let files) = result else { return XCTFail("Expected one file group") }
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[1].name, "missing-second.pdf")
        XCTAssertEqual(files[1].fileExtension, "pdf")
    }
}
