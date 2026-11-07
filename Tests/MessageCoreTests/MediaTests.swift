import Foundation
import ImageIO
import CoreGraphics
import XCTest
@testable import MessageCore

final class MediaTests: XCTestCase {
    let server = URL(string: "https://q.trap.jp")!
    let id = "01a159af-bfae-7290-aac2-a25a63323d37"

    func testOnlyServerFileEndpointIsAuthenticated() throws {
        for raw in ["/files/\(id)", "/api/v3/files/\(id)", "https://q.trap.jp/files/\(id)"] {
            let value = try MediaURLPolicy.resolve(raw, server: server)
            XCTAssertTrue(value.authenticated)
            XCTAssertEqual(value.url.absoluteString, "https://q.trap.jp/api/v3/files/\(id)")
        }
        for raw in ["https://example.com/photo.png", "https://q.trap.jp/other.png", "https://evil.example/api/v3/files/\(id)"] {
            XCTAssertFalse(try MediaURLPolicy.resolve(raw, server: server).authenticated)
        }
    }

    func testUnsafeURLsAreRejected() {
        for raw in ["http://example.com/a", "file:///etc/passwd", "data:image/png;base64,AA", "//evil.example/a", "https://user:pass@example.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://192.168.1.1/a", "https://[::1]/a", "https://device.local/a", "https://example.com:1234/a", "/api/v3/logout", "https://example.com/\nsecret"] {
            XCTAssertThrowsError(try MediaURLPolicy.resolve(raw, server: server), raw)
        }
    }

    func testMarkdownImagesAndCode() {
        let blocks = MessageParser.parse("before ![alt](https://example.com/a.png) after")
        guard case .paragraph(let spans) = blocks.first else { return XCTFail() }
        XCTAssertTrue(spans.contains { $0.attachment == .image(MessageImage(url: "https://example.com/a.png", alt: "alt")) })
        XCTAssertEqual(spans.map(\.text).joined(), "before alt after")
        guard case .paragraph(let code) = MessageParser.parse("`![alt](https://example.com/a.png)`").first else { return XCTFail() }
        XCTAssertTrue(code.allSatisfy { $0.attachment == nil })
    }
}

private final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path == "/missing" ? 404 : ["/redirect", "/loop", "/downgrade", "/local", "/no-location"].contains(path) ? 302 : 200
        let mime = path == "/html" ? "text/html" : "image/png"
        let length = path == "/huge-header" ? "99999999" : "-1"
        var headers = ["Content-Type": mime, "Content-Length": length]
        let destinations = ["/redirect": "/good", "/loop": "/loop", "/downgrade": "http://example.com/good", "/local": "https://127.0.0.1/good"]
        headers["Location"] = destinations[path]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/huge-stream" {
            client?.urlProtocol(self, didLoad: Data(repeating: 0, count: ImageHTTPClient.maximumBytes + 1))
        } else { client?.urlProtocol(self, didLoad: Data([1, 2, 3])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension MediaTests {
    func testImageHTTPFailuresAndSizeLimits() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocol.self]
        let client = ImageHTTPClient(configuration: config)
        let good = try await client.data(for: URLRequest(url: URL(string: "https://example.com/good")!))
        XCTAssertEqual(good, Data([1, 2, 3]))
        let redirected = try await client.data(for: URLRequest(url: URL(string: "https://example.com/redirect")!))
        XCTAssertEqual(redirected, good)
        for path in ["missing", "no-location", "loop", "downgrade", "local", "html", "huge-header", "huge-stream"] {
            do {
                _ = try await client.data(for: URLRequest(url: URL(string: "https://example.com/\(path)")!))
                XCTFail("Should fail: \(path)")
            } catch { XCTAssertTrue(error is ImageLoadError, "Unexpected error for \(path): \(error)") }
        }
    }
}

extension MediaTests {
    func testEmptyAndStyledImageAltStillProducesOneImage() {
        for source in ["![](https://example.com/a.png)", "![a **bold** alt](https://example.com/a.png)"] {
            let resources = MessagePresentation.resources(in: MessageParser.parse(source), revealed: [])
            XCTAssertEqual(resources, [.image("https://example.com/a.png")])
        }
    }
}

extension MediaTests {
    func testImageAltFormattingDoesNotSplitImageOrCorruptURL() {
        for source in ["![a **bold** alt](https://example.com/a.png)", "![alt :stamp:](https://example.com/:stamp:.png)"] {
            guard case .paragraph(let spans) = MessageParser.parse(source).first else { return XCTFail() }
            let images = spans.compactMap { span -> MessageImage? in
                if case .image(let image) = span.attachment { return image }; return nil
            }
            XCTAssertEqual(images.count, 1)
            XCTAssertFalse(images[0].alt.contains("\u{E000}"))
            XCTAssertFalse(images[0].url.contains("%EE%80"))
        }
        for raw in ["https://localhost./a", "https://0x7f.0.0.1/a"] {
            XCTAssertThrowsError(try MediaURLPolicy.resolve(raw, server: server))
        }
    }
}

extension MediaTests {
    func testImageDecoderRejectsBrokenImagesAndLimitsDecodedSize() throws {
        let context = CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8,
                                bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let source = context.makeImage()!
        let png = NSMutableData()
        let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, source, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try ImageThumbnailDecoder.thumbnail(png as Data, maximumPixels: 120)
        XCTAssertEqual(thumbnail.width, 120)
        XCTAssertEqual(thumbnail.height, 60)
        XCTAssertThrowsError(try ImageThumbnailDecoder.thumbnail(Data(), maximumPixels: 120))
        XCTAssertThrowsError(try ImageThumbnailDecoder.thumbnail(Data("<svg></svg>".utf8), maximumPixels: 120))
        XCTAssertThrowsError(try ImageThumbnailDecoder.thumbnail(png as Data, maximumPixels: 100_000))
        XCTAssertThrowsError(try ImageThumbnailDecoder.thumbnail(Data(repeating: 0, count: ImageHTTPClient.maximumBytes + 1), maximumPixels: 120))
    }
}


extension MediaTests {
    func testRedirectCredentialsNeverCrossOriginsOrReturn() throws {
        var original = URLRequest(url: URL(string: "https://q.trap.jp/api/v3/files/\(id)")!)
        original.setValue("r_session=test-only", forHTTPHeaderField: "Cookie")
        original.setValue("Bearer test-only", forHTTPHeaderField: "Authorization")
        let same = try ImageRedirectPolicy.request(location: "/image.png", from: original)
        XCTAssertEqual(same.value(forHTTPHeaderField: "Cookie"), "r_session=test-only")
        let external = try ImageRedirectPolicy.request(location: "https://cdn.example.com/image.png?signature=test", from: same)
        XCTAssertNil(external.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(external.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(external.url?.query, "signature=test")
        let back = try ImageRedirectPolicy.request(location: original.url!.absoluteString, from: external)
        XCTAssertNil(back.value(forHTTPHeaderField: "Cookie"))
        XCTAssertThrowsError(try ImageRedirectPolicy.request(location: "http://example.com/a", from: original))
        XCTAssertThrowsError(try ImageRedirectPolicy.request(location: "https://user:pass@example.com/a", from: original))
    }
}
