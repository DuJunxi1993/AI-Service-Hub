import XCTest
@testable import AiServiceHubCore

final class ComposePortParserTests: XCTestCase {
    private let yaml = """
    services:
      shipyard:
        image: some/image:latest
        ports:
          - "8156:8156"
          - "8157:8157"
      napcat:
        image: another/image
        ports:
          - "127.0.0.1:6099:6099"
          - "6099"
    """

    func testParsesSimpleMapping() {
        let ports = ComposePortParser.parseServicePorts(yaml: yaml, serviceName: "shipyard")
        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports[0].hostPort, 8156)
        XCTAssertEqual(ports[0].containerPort, 8156)
        XCTAssertEqual(ports[1].hostPort, 8157)
    }

    func testParsesIPPrefixedMapping() {
        let ports = ComposePortParser.parseServicePorts(yaml: yaml, serviceName: "napcat")
        XCTAssertEqual(ports.count, 2)
        XCTAssertEqual(ports[0].hostIP, "127.0.0.1")
        XCTAssertEqual(ports[0].hostPort, 6099)
        XCTAssertEqual(ports[0].containerPort, 6099)
    }

    func testShortSyntaxUsesSamePort() {
        let ports = ComposePortParser.parseServicePorts(yaml: yaml, serviceName: "napcat")
        XCTAssertEqual(ports[1].hostPort, 6099)
        XCTAssertEqual(ports[1].containerPort, 6099)
    }

    func testUnknownServiceReturnsEmpty() {
        let ports = ComposePortParser.parseServicePorts(yaml: yaml, serviceName: "does-not-exist")
        XCTAssertTrue(ports.isEmpty)
    }

    func testProtocolSuffixIsIgnored() {
        let single = """
        services:
          app:
            ports:
              - "8156:8156:tcp"
        """
        let ports = ComposePortParser.parseServicePorts(yaml: single, serviceName: "app")
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].hostPort, 8156)
    }

    func testPortRangeExpands() {
        let single = """
        services:
          app:
            ports:
              - "8156-8158:8156-8158"
        """
        let ports = ComposePortParser.parseServicePorts(yaml: single, serviceName: "app")
        XCTAssertEqual(ports.count, 3)
        XCTAssertEqual(ports.map(\.hostPort), [8156, 8157, 8158])
    }
}
