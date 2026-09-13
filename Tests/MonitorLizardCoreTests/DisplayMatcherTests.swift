import XCTest
import CoreGraphics
@testable import MonitorLizardCore

final class DisplayMatcherTests: XCTestCase {
    // Real values from this Mac (ioreg, 2026-09-12).
    static let dellPath = "IOService:/AppleARMPE/arm-io@10F00000/AppleSoCIO/dcpext0@B2E00000/AppleASCWrapV6/iop-dcpext0-nub/RTBuddy(DCPEXT0)/DCPEXT0Endpoint11/AFKDCPEXT0Endpoint11/AFKEPInterfaceServiceKextV2/dispext0:dcpav-service-epic:0/DCPAVServiceProxy"

    func testExtractsFramebufferNameFromServicePath() {
        XCTAssertEqual(DisplayMatcher.framebufferName(inAVServicePath: Self.dellPath), "dispext0")
        XCTAssertEqual(DisplayMatcher.framebufferName(inAVServicePath: "…/dispext3:dcpav-service-epic:0/DCPAVServiceProxy"), "dispext3")
        XCTAssertNil(DisplayMatcher.framebufferName(inAVServicePath: "IOService:/nothing/here"))
    }

    func testMatchesByProductAndSerialThroughTheFramebufferName() {
        let dell = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 825640780, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let tv = DisplayInfo(id: 7, name: "65S455", vendorID: 20588, productID: 38483, serial: 0, isBuiltIn: false, isMain: false, isTV: true, isHDMI: true)
        let builtIn = DisplayInfo(id: 1, name: "Color LCD", vendorID: 1552, productID: 41055, serial: 4251086178, isBuiltIn: true, isMain: false, isTV: false, isHDMI: false)
        let fbs = [
            FramebufferEntry(name: "dispext0", productID: 41200, serial: 825640780, entry: 10),
            FramebufferEntry(name: "dispext1", productID: 38483, serial: 0, entry: 11),
            FramebufferEntry(name: "disp0", productID: nil, serial: nil, entry: 12),
        ]
        let services = [
            AVServiceEntry(path: "…/dispext1:dcpav-service-epic:0/DCPAVServiceProxy", entry: 21),
            AVServiceEntry(path: Self.dellPath, entry: 20),
        ]
        let matched = DisplayMatcher.match(displays: [dell, tv, builtIn], framebuffers: fbs, services: services)
        XCTAssertEqual(matched[5]?.entry, 20)
        XCTAssertEqual(matched[7]?.entry, 21)
        XCTAssertNil(matched[1], "the built-in panel never gets a DDC service")
    }

    func testSingleExternalFallbackWhenAttributesAreMissing() {
        // Some framebuffers publish no ProductAttributes (seen on this Mac for idle dispext slots).
        let dell = DisplayInfo(id: 5, name: "DELL U3818DW", vendorID: 4268, productID: 41200, serial: 825640780, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let fbs = [FramebufferEntry(name: "dispext0", productID: nil, serial: nil, entry: 10)]
        let services = [AVServiceEntry(path: Self.dellPath, entry: 20)]
        XCTAssertEqual(DisplayMatcher.match(displays: [dell], framebuffers: fbs, services: services)[5]?.entry, 20)
    }

    func testNoFallbackWithTwoExternals() {
        let a = DisplayInfo(id: 5, name: "A", vendorID: 1, productID: 1, serial: 1, isBuiltIn: false, isMain: true, isTV: false, isHDMI: true)
        let b = DisplayInfo(id: 6, name: "B", vendorID: 2, productID: 2, serial: 2, isBuiltIn: false, isMain: false, isTV: false, isHDMI: true)
        let fbs = [FramebufferEntry(name: "dispext0", productID: nil, serial: nil, entry: 10)]
        let services = [AVServiceEntry(path: Self.dellPath, entry: 20)]
        XCTAssertTrue(DisplayMatcher.match(displays: [a, b], framebuffers: fbs, services: services).isEmpty)
    }

    func testDisplayInfoFromCoreDisplayDictionary() {
        let dict: [String: Any] = [
            "DisplayProductName": ["en_US": "DELL U3818DW"],
            "DisplayVendorID": 4268, "DisplayProductID": 41200, "DisplaySerialNumber": 825640780,
            "DisplayIsTV": 0, "IODisplayIsHDMISink": 1,
        ]
        let info = DisplayInfo.from(dictionary: dict, id: 5, isBuiltIn: false, isMain: true)
        XCTAssertEqual(info.name, "DELL U3818DW")
        XCTAssertEqual(info.productID, 41200)
        XCTAssertEqual(info.serial, 825640780)
        XCTAssertFalse(info.isTV)
        XCTAssertTrue(info.isHDMI)
    }

    func testDisplayInfoNamePrefersEnUSOverAlphabeticalOrder() {
        let dict: [String: Any] = ["DisplayProductName": ["de_DE": "Anzeige", "en_US": "DELL U3818DW"]]
        XCTAssertEqual(DisplayInfo.from(dictionary: dict, id: 5, isBuiltIn: false, isMain: true).name, "DELL U3818DW")
    }

    func testDisplayInfoNameFallsBackToPlainStringAndGeneric() {
        XCTAssertEqual(DisplayInfo.from(dictionary: ["DisplayProductName": "X"], id: 1, isBuiltIn: false, isMain: false).name, "X")
        XCTAssertEqual(DisplayInfo.from(dictionary: [:], id: 1, isBuiltIn: true, isMain: false).name, "Built-in Display")
        XCTAssertEqual(DisplayInfo.from(dictionary: [:], id: 1, isBuiltIn: false, isMain: false).name, "Display 1")
    }
}
