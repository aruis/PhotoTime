import Foundation
import Testing
@testable import PhotoTime

@MainActor
struct ExportViewModelAssetFilterTests {
    @Test
    func problematicFilterIncludesPreflightAndExportFailures() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        let c = URL(fileURLWithPath: "/tmp/c.jpg")

        viewModel.imageURLs = [a, b, c]
        viewModel.failedAssetNames = ["c.jpg"]
        viewModel.preflightReport = PreflightReport(
            scannedCount: 3,
            issues: [
                PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix),
                PreflightIssue(index: 1, fileName: "b.jpg", message: "low res", severity: .shouldReview)
            ]
        )

        viewModel.fileListFilter = .problematic
        let fileNames = viewModel.filteredImageURLsForDisplay.map(\.lastPathComponent)

        #expect(fileNames == ["a.jpg", "b.jpg", "c.jpg"])
    }

    @Test
    func problematicAssetsAreSortedBeforeNormalAssets() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/alpha.jpg")
        let b = URL(fileURLWithPath: "/tmp/bravo.jpg")
        let c = URL(fileURLWithPath: "/tmp/charlie.jpg")

        viewModel.imageURLs = [b, c, a]
        viewModel.preflightReport = PreflightReport(
            scannedCount: 3,
            issues: [
                PreflightIssue(index: 1, fileName: "charlie.jpg", message: "missing", severity: .mustFix)
            ]
        )

        let ordered = viewModel.orderedImageURLsForDisplay.map(\.lastPathComponent)
        #expect(ordered.first == "charlie.jpg")
    }

    @Test
    func focusIssueReturnsExpectedAssetURLAndSwitchesProblematicFilter() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/alpha.jpg")
        let b = URL(fileURLWithPath: "/tmp/bravo.jpg")
        viewModel.imageURLs = [a, b]

        let issue = PreflightIssue(index: 1, fileName: "bravo.jpg", message: "missing", severity: .mustFix)
        let focused = viewModel.focusAssetForIssue(issue)

        #expect(focused?.lastPathComponent == "bravo.jpg")
        #expect(viewModel.fileListFilter == .problematic)
    }

    @Test
    func focusProblematicAssetsPrefersFirstMustFixIssue() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/alpha.jpg")
        let b = URL(fileURLWithPath: "/tmp/bravo.jpg")
        let c = URL(fileURLWithPath: "/tmp/charlie.jpg")
        viewModel.imageURLs = [a, b, c]
        viewModel.preflightReport = PreflightReport(
            scannedCount: 3,
            issues: [
                PreflightIssue(index: 0, fileName: "alpha.jpg", message: "review", severity: .shouldReview),
                PreflightIssue(index: 2, fileName: "charlie.jpg", message: "must fix", severity: .mustFix)
            ]
        )

        let focused = viewModel.focusOnProblematicAssets()

        #expect(focused?.lastPathComponent == "charlie.jpg")
        #expect(viewModel.fileListFilter == .problematic)
    }

    @Test
    func focusProblematicAssetsFallsBackToFirstIssueWhenNoMustFix() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/alpha.jpg")
        let b = URL(fileURLWithPath: "/tmp/bravo.jpg")
        viewModel.imageURLs = [a, b]
        viewModel.preflightReport = PreflightReport(
            scannedCount: 2,
            issues: [
                PreflightIssue(index: 1, fileName: "bravo.jpg", message: "review", severity: .shouldReview)
            ]
        )

        let focused = viewModel.focusOnProblematicAssets()

        #expect(focused?.lastPathComponent == "bravo.jpg")
        #expect(viewModel.fileListFilter == .problematic)
    }

    @Test
    func preflightIssueFilterCanShowOnlyMustFixOrReview() {
        let viewModel = ExportViewModel()
        viewModel.preflightReport = PreflightReport(
            scannedCount: 2,
            issues: [
                PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix),
                PreflightIssue(index: 1, fileName: "b.jpg", message: "low res", severity: .shouldReview)
            ]
        )

        viewModel.preflightIssueFilter = .mustFix
        #expect(viewModel.filteredPreflightIssues.count == 1)
        #expect(viewModel.filteredPreflightIssues.first?.severity == .mustFix)

        viewModel.preflightIssueFilter = .review
        #expect(viewModel.filteredPreflightIssues.count == 1)
        #expect(viewModel.filteredPreflightIssues.first?.severity == .shouldReview)
    }

    @Test
    func ignoredPreflightIssueIsHiddenUntilRestored() {
        let viewModel = ExportViewModel()
        let mustFix = PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix)
        let review = PreflightIssue(index: 1, fileName: "b.jpg", message: "low res", severity: .shouldReview)
        viewModel.preflightReport = PreflightReport(scannedCount: 2, issues: [mustFix, review])

        #expect(viewModel.filteredPreflightIssues.count == 2)
        #expect(viewModel.preflightIssueTags(for: "a.jpg").contains("必须修复"))

        viewModel.toggleIgnoreIssue(mustFix)
        #expect(viewModel.filteredPreflightIssues.count == 1)
        #expect(viewModel.filteredPreflightIssues.first?.fileName == "b.jpg")
        #expect(!viewModel.preflightIssueTags(for: "a.jpg").contains("必须修复"))

        viewModel.toggleIgnoreIssue(mustFix)
        #expect(viewModel.filteredPreflightIssues.count == 2)
        #expect(viewModel.preflightIssueTags(for: "a.jpg").contains("必须修复"))
    }

    @Test
    func mustFixFileFilterOnlyShowsMustFixAssets() {
        let viewModel = ExportViewModel()
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        let c = URL(fileURLWithPath: "/tmp/c.jpg")
        viewModel.imageURLs = [a, b, c]
        viewModel.preflightReport = PreflightReport(
            scannedCount: 3,
            issues: [
                PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix),
                PreflightIssue(index: 1, fileName: "b.jpg", message: "low res", severity: .shouldReview)
            ]
        )

        viewModel.fileListFilter = .mustFix
        #expect(viewModel.filteredImageURLsForDisplay.map(\.lastPathComponent) == ["a.jpg"])

        let mustFixIssue = PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix)
        viewModel.toggleIgnoreIssue(mustFixIssue)
        #expect(viewModel.filteredImageURLsForDisplay.isEmpty)
    }

    @Test
    func restoreAllIgnoredIssuesBringsBackAllPreflightItems() {
        let viewModel = ExportViewModel()
        let mustFix = PreflightIssue(index: 0, fileName: "a.jpg", message: "missing", severity: .mustFix)
        let review = PreflightIssue(index: 1, fileName: "b.jpg", message: "low res", severity: .shouldReview)
        viewModel.preflightReport = PreflightReport(scannedCount: 2, issues: [mustFix, review])

        viewModel.toggleIgnoreIssue(mustFix)
        viewModel.toggleIgnoreIssue(review)
        #expect(viewModel.filteredPreflightIssues.isEmpty)

        viewModel.restoreAllIgnoredIssues()
        #expect(viewModel.filteredPreflightIssues.count == 2)
        #expect(viewModel.ignoredIssueCount == 0)
    }
}
