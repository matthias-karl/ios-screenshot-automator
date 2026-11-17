import Testing
@testable import ScreenshotProtocol

@Suite struct ShotProtocolTests {
    @Test func attachmentNameAddsPrefix() {
        #expect(ShotProtocol.attachmentName(for: "01_Home") == "sa2v2__01_Home")
    }

    @Test func parsesBareName() {
        #expect(ShotProtocol.parse(attachmentName: "sa2v2__01_Home") == .shot("01_Home"))
    }

    @Test func parsesXcodeExportedName() {
        let exported = "sa2v2__01_Home_0_5F2C1E9A-1B2C-4D3E-8F90-123456789ABC.png"
        #expect(ShotProtocol.parse(attachmentName: exported) == .shot("01_Home"))
    }

    @Test func reportsOtherProtocolVersion() {
        #expect(ShotProtocol.parse(attachmentName: "sa2v3__x") == .otherVersion(3))
    }

    @Test func ignoresForeignAttachments() {
        #expect(ShotProtocol.parse(attachmentName: "Screenshot_1") == nil)
    }

    @Test func validatesShotNames() {
        #expect(ShotProtocol.isValidShotName("01_Home-dark"))
        #expect(!ShotProtocol.isValidShotName("a b"))
        #expect(!ShotProtocol.isValidShotName("../x"))
        #expect(!ShotProtocol.isValidShotName(""))
    }
}
