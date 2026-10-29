import XCTest
import CoreGraphics
@testable import CodexEyesCore

final class AccountHeatmapLayoutTests: XCTestCase {
    func testHistoryUsesFullAvailableWidthAndContentDeterminesHeight() {
        let layout = AccountHeatmapLayout(columns: 34, availableWidth: 540)
        XCTAssertEqual(layout.width, 540, accuracy: 0.001)
        XCTAssertEqual(layout.rect(column: 33, row: 6).maxX, 540, accuracy: 0.001)
        XCTAssertEqual(layout.height, layout.gridHeight + 26)
        XCTAssertLessThan(layout.height, 166)
    }
    func testEveryTileCenterMapsToTheSameRowAndColumn() throws {
        for width: CGFloat in [400, 540, 700] {
            let layout = AccountHeatmapLayout(columns: 34, availableWidth: width)
            for column in 0..<34 {
                for row in 0..<7 {
                    let rect = layout.rect(column: column, row: row)
                    let cell = try XCTUnwrap(layout.cell(at: CGPoint(x: rect.midX, y: rect.midY)))
                    XCTAssertEqual(cell.column, column); XCTAssertEqual(cell.row, row)
                }
            }
            XCTAssertNil(layout.cell(at: CGPoint(x: -1, y: 0)))
            XCTAssertNil(layout.cell(at: CGPoint(x: 0, y: layout.gridHeight + 1))) // Month labels are not days.
            XCTAssertNil(layout.cell(at: CGPoint(x: layout.width, y: 0)))
        }
    }
    func testLongHistoryKeepsAllColumnsAndShortHistoryAvoidsOversizedTiles() throws {
        let long = AccountHeatmapLayout(columns: 200, availableWidth: 540)
        XCTAssertEqual(long.columns, 200); XCTAssertEqual(long.side, 8)
        XCTAssertGreaterThan(long.width, 540)
        let last = long.rect(column: 199, row: 6)
        XCTAssertEqual(try XCTUnwrap(long.cell(at: CGPoint(x: last.midX, y: last.midY))).column, 199)
        XCTAssertEqual(AccountHeatmapLayout(columns: 1, availableWidth: 540).side, 20)
    }
}
