import Compression
import CryptoKit
import CZstd
import Foundation
import zlib

public struct LiveUsageReading: Equatable, Sendable {
    public let orgUuid: String?
    public let accountUuid: String?
    public let fiveHourPercent: Int?
    public let sevenDayPercent: Int?
    public let extraUsagePercent: Int?
    public let fiveHourResetsAt: Date?
    public let sevenDayResetsAt: Date?
    public let updatedAt: Date
    public let source: UsageDataSource

    public init(
        orgUuid: String?,
        accountUuid: String? = nil,
        fiveHourPercent: Int?,
        sevenDayPercent: Int?,
        extraUsagePercent: Int? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayResetsAt: Date? = nil,
        updatedAt: Date,
        source: UsageDataSource
    ) {
        self.orgUuid = orgUuid
        self.accountUuid = accountUuid
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.extraUsagePercent = extraUsagePercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayResetsAt = sevenDayResetsAt
        self.updatedAt = updatedAt
        self.source = source
    }
}

/// Reads live, read-only local Anthropic usage telemetry written by Claude Desktop's HTTP disk cache
/// (`Cache/Cache_Data/<sha1_le64>_0`) and Claude Code CLI (`~/.claude.json` `cachedUsageUtilization`).
///
/// Zero network calls, zero Keychain access, zero Cookies access — O(1) direct file lookup per org.
public final class LiveUsageReader: @unchecked Sendable {
    private static let simpleHeaderMagic: UInt64 = 0xfcfb6d1ba7725c30
    private static let simpleEOFMagicBytes: [UInt8] = [0xd8, 0x41, 0x0d, 0x97, 0x45, 0x6f, 0xfa, 0xf4]
    private static let maxDecompressedBytes = 512 * 1024

    private struct CachedFileReading {
        let modDate: Date
        let size: Int64
        let reading: LiveUsageReading?
    }

    private let claudeCLIStateFile: URL
    private let lock = NSLock()
    private var fileCache: [String: CachedFileReading] = [:]

    public init(
        claudeCLIStateFile: URL = URL(
            fileURLWithPath: ("~/.claude.json" as NSString).expandingTildeInPath,
            isDirectory: false
        )
    ) {
        self.claudeCLIStateFile = claudeCLIStateFile
    }

    // MARK: - Deterministic Chromium Simple Cache Key Hashing

    /// Computes Chromium Simple Cache's 64-bit little-endian SHA-1 entry filename prefix (16 lowercase hex chars).
    public static func simpleCacheHashHex(for key: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(key.utf8))
        var value: UInt64 = 0
        for (idx, byte) in digest.prefix(8).enumerated() {
            value |= UInt64(byte) << UInt64(idx * 8)
        }
        return String(format: "%016llx", value)
    }

    /// Returns all known Chromium Simple Cache keys Claude Desktop uses for an organization's `/usage` endpoint.
    public static func candidateUsageCacheKeys(for orgUuid: String) -> [String] {
        let urls = [
            "https://claude.ai/api/organizations/\(orgUuid)/usage?via=plan",
            "https://claude.ai/api/organizations/\(orgUuid)/usage?cedar_ember=1&skip_spend=1",
            "https://claude.ai/api/organizations/\(orgUuid)/usage"
        ]
        var keys: [String] = []
        keys.reserveCapacity(urls.count * 2)
        for u in urls {
            keys.append("1/0/\(u)")
            keys.append("1/0/_dk_https://claude.ai https://claude.ai \(u)")
        }
        return keys
    }

    /// Returns exact candidate file paths inside `<profileDir>/Cache/Cache_Data/` for watching or O(1) lookup.
    public static func candidateCacheFileURLs(in profileDir: URL, orgUuid: String) -> [URL] {
        let cacheDir = profileDir
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("Cache_Data", isDirectory: true)
        return candidateUsageCacheKeys(for: orgUuid).map { key in
            cacheDir.appendingPathComponent("\(simpleCacheHashHex(for: key))_0", isDirectory: false)
        }
    }

    // MARK: - Public API

    /// Reads the freshest live `/usage` cache response for `orgUuid` inside `profileDir` in O(1) time.
    public func readFreshestCacheUsage(in profileDir: URL, orgUuid: String) -> LiveUsageReading? {
        let fm = FileManager.default
        let cacheDir = profileDir
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent("Cache_Data", isDirectory: true)
        guard fm.fileExists(atPath: cacheDir.path) else { return nil }

        var freshest: LiveUsageReading?
        for key in Self.candidateUsageCacheKeys(for: orgUuid) {
            let fileName = "\(Self.simpleCacheHashHex(for: key))_0"
            let fileURL = cacheDir.appendingPathComponent(fileName, isDirectory: false)
            guard fm.fileExists(atPath: fileURL.path) else { continue }
            guard let reading = readSimpleCacheFileCached(fileURL: fileURL, expectedOrgUuid: orgUuid) else {
                continue
            }
            if let existing = freshest {
                if reading.updatedAt > existing.updatedAt {
                    freshest = reading
                }
            } else {
                freshest = reading
            }
        }
        return freshest
    }

    /// Reads Claude Code CLI's local `cachedUsageUtilization` from `~/.claude.json`, if present.
    public func readClaudeCLIUsage() -> LiveUsageReading? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeCLIStateFile.path) else { return nil }
        let vals = try? claudeCLIStateFile.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mdate = vals?.contentModificationDate ?? .distantPast
        let size = Int64(vals?.fileSize ?? 0)
        let cacheKey = "cli|\(claudeCLIStateFile.path)"

        lock.lock()
        let cached = fileCache[cacheKey]
        lock.unlock()

        if let cached, cached.modDate == mdate, cached.size == size {
            return cached.reading
        }

        let parsed = parseClaudeCLIStateFile(at: claudeCLIStateFile)
        lock.lock()
        fileCache[cacheKey] = CachedFileReading(modDate: mdate, size: size, reading: parsed)
        lock.unlock()
        return parsed
    }

    // MARK: - Chromium Simple Cache Binary Parsing

    private func readSimpleCacheFileCached(fileURL: URL, expectedOrgUuid: String) -> LiveUsageReading? {
        let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mdate = vals?.contentModificationDate ?? .distantPast
        let size = Int64(vals?.fileSize ?? 0)
        guard size > 48, size <= Int64(Self.maxDecompressedBytes) else { return nil }

        let cacheKey = fileURL.path
        lock.lock()
        let cached = fileCache[cacheKey]
        lock.unlock()

        if let cached, cached.modDate == mdate, cached.size == size {
            return cached.reading
        }

        let parsed = parseSimpleCacheFile(at: fileURL, modDate: mdate, expectedOrgUuid: expectedOrgUuid)
        lock.lock()
        fileCache[cacheKey] = CachedFileReading(modDate: mdate, size: size, reading: parsed)
        lock.unlock()
        return parsed
    }

    /// Exposed internally for unit testing Chromium Simple Cache binary parsing & decompression.
    public func parseSimpleCacheFile(
        at fileURL: URL,
        modDate: Date,
        expectedOrgUuid: String
    ) -> LiveUsageReading? {
        guard let raw = try? Data(contentsOf: fileURL), raw.count >= 48 else { return nil }
        return parseSimpleCacheData(raw, fallbackDate: modDate, expectedOrgUuid: expectedOrgUuid)
    }

    public func parseSimpleCacheData(
        _ raw: Data,
        fallbackDate: Date,
        expectedOrgUuid: String
    ) -> LiveUsageReading? {
        guard raw.count >= 48 else { return nil }

        // 1. Validate SimpleFileHeader (24 bytes): magic(8) version(4) key_length(4) key_hash(4) pad(4)
        let magic = readLE64(raw, at: 0)
        guard magic == Self.simpleHeaderMagic else { return nil }
        let keyLength = Int(readLE32(raw, at: 12))
        guard keyLength > 0, keyLength <= 4096, 24 + keyLength < raw.count else { return nil }

        let keyData = raw.subdata(in: 24..<(24 + keyLength))
        guard let keyString = String(data: keyData, encoding: .utf8),
              keyString.localizedCaseInsensitiveContains(expectedOrgUuid),
              keyString.contains("/usage") else {
            return nil
        }

        // 2. Locate Stream 1 (HTTP response body) between header+key and first SimpleFileEOF magic
        let bodyStart = 24 + keyLength
        let eofMagic = Data(Self.simpleEOFMagicBytes)
        guard let eof1Range = raw.range(of: eofMagic, options: [], in: bodyStart..<raw.count) else {
            return nil
        }
        let bodyData = raw.subdata(in: bodyStart..<eof1Range.lowerBound)
        guard !bodyData.isEmpty else { return nil }

        // 3. Extract Stream 0 (HTTP response headers) for Date & Content-Encoding if present
        var contentEncoding: String?
        var httpDate: Date?
        let stream0Start = eof1Range.lowerBound + 24
        if stream0Start < raw.count {
            let stream0End = raw.range(of: eofMagic, options: [], in: stream0Start..<raw.count)?.lowerBound ?? raw.count
            if stream0End > stream0Start {
                let headerSlice = raw.subdata(in: stream0Start..<stream0End)
                let (enc, date) = parseHTTPHeaderHints(from: headerSlice)
                contentEncoding = enc
                httpDate = date
            }
        }

        // 4. Decompress response payload (ZSTD / Gzip / Brotli / Deflate / Plain JSON)
        guard let jsonData = decompressPayload(bodyData, contentEncoding: contentEncoding) else {
            return nil
        }

        return parseUsageJSON(
            jsonData,
            orgUuid: expectedOrgUuid,
            accountUuid: nil,
            preferredDate: httpDate ?? fallbackDate,
            source: .liveCache
        )
    }

    // MARK: - Multi-Codec Native Decompression

    public func decompressPayload(_ data: Data, contentEncoding: String?) -> Data? {
        guard !data.isEmpty else { return nil }
        let enc = contentEncoding?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Direct plain JSON check
        if data.first == 0x7B /* '{' */ {
            return data
        }

        // ZSTD magic bytes: 28 B5 2F FD
        let isZstdMagic = data.count >= 4
            && data[data.startIndex] == 0x28
            && data[data.startIndex + 1] == 0xB5
            && data[data.startIndex + 2] == 0x2F
            && data[data.startIndex + 3] == 0xFD
        if isZstdMagic || enc == "zstd" {
            if let out = decompressZstd(data) { return out }
        }

        // Gzip magic bytes: 1F 8B
        let isGzipMagic = data.count >= 2
            && data[data.startIndex] == 0x1F
            && data[data.startIndex + 1] == 0x8B
        if isGzipMagic || enc == "gzip" {
            if let out = decompressZlib(data, windowBits: 16 + MAX_WBITS) { return out }
        }

        if enc == "br" {
            if let out = decompressAppleCompression(data, algorithm: COMPRESSION_BROTLI) { return out }
        }

        if enc == "deflate" {
            if let out = decompressZlib(data, windowBits: MAX_WBITS) { return out }
            if let out = decompressZlib(data, windowBits: -MAX_WBITS) { return out }
        }

        // Fallback attempts when HTTP headers weren't parsed
        if let out = decompressAppleCompression(data, algorithm: COMPRESSION_BROTLI), out.first == 0x7B {
            return out
        }
        return nil
    }

    public func decompressZstd(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        guard let dstream = ZSTD_createDStream() else { return nil }
        defer { ZSTD_freeDStream(dstream) }

        let initResult = ZSTD_initDStream(dstream)
        guard ZSTD_isError(initResult) == 0 else { return nil }

        let chunkCapacity = max(4096, Int(ZSTD_DStreamOutSize()))
        var outChunk = [UInt8](repeating: 0, count: chunkCapacity)
        var output = Data()
        output.reserveCapacity(min(input.count * 4, 16_384))

        let success = input.withUnsafeBytes { rawBuf -> Bool in
            guard let basePtr = rawBuf.baseAddress else { return false }
            var inBuf = ZSTD_inBuffer(src: basePtr, size: rawBuf.count, pos: 0)

            while inBuf.pos < inBuf.size {
                var produced: Int = 0
                var frameResult: Int = 0
                let hadError: Bool = outChunk.withUnsafeMutableBytes { outRaw in
                    guard let outPtr = outRaw.baseAddress else { return true }
                    var outBuf = ZSTD_outBuffer(dst: outPtr, size: chunkCapacity, pos: 0)
                    let ret = ZSTD_decompressStream(dstream, &outBuf, &inBuf)
                    if ZSTD_isError(ret) != 0 {
                        return true
                    }
                    produced = outBuf.pos
                    frameResult = ret
                    return false
                }
                if hadError { return false }
                if produced > 0 {
                    if output.count + produced > Self.maxDecompressedBytes { return false }
                    output.append(contentsOf: outChunk[0..<produced])
                }
                // Stop cleanly once a complete ZSTD frame finishes (ignores any trailing cache key hash)
                if frameResult == 0 && !output.isEmpty {
                    break
                }
                if produced == 0 && frameResult > 0 && inBuf.pos >= inBuf.size {
                    break
                }
            }
            return !output.isEmpty
        }

        return success ? output : nil
    }

    private func decompressZlib(_ input: Data, windowBits: Int32) -> Data? {
        guard !input.isEmpty else { return nil }
        var stream = z_stream()
        let status = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)

        let ok = input.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.bindMemory(to: Bytef.self).baseAddress else { return false }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(rawBuf.count)

            while true {
                let rc: Int32 = buffer.withUnsafeMutableBufferPointer { dst in
                    stream.next_out = dst.baseAddress
                    stream.avail_out = uInt(dst.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = buffer.count - Int(stream.avail_out)
                if produced > 0 {
                    if output.count + produced > Self.maxDecompressedBytes { return false }
                    output.append(contentsOf: buffer[0..<produced])
                }
                if rc == Z_STREAM_END { return !output.isEmpty }
                if rc != Z_OK { return false }
                if stream.avail_in == 0 && produced == 0 { return !output.isEmpty }
            }
        }
        return ok ? output : nil
    }

    private func decompressAppleCompression(_ input: Data, algorithm: compression_algorithm) -> Data? {
        guard !input.isEmpty else { return nil }
        var dstSize = min(max(input.count * 6, 8192), Self.maxDecompressedBytes)
        for _ in 0..<3 {
            var dst = [UInt8](repeating: 0, count: dstSize)
            let decodedCount = input.withUnsafeBytes { raw -> Int in
                guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&dst, dstSize, src, input.count, nil, algorithm)
            }
            if decodedCount > 0 && decodedCount < dstSize {
                return Data(dst[0..<decodedCount])
            }
            if dstSize >= Self.maxDecompressedBytes { break }
            dstSize = min(dstSize * 2, Self.maxDecompressedBytes)
        }
        return nil
    }

    // MARK: - JSON & HTTP Header Parsers

    private struct UsageAPIResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        struct ExtraUsage: Decodable {
            let is_enabled: Bool?
            let utilization: Double?
        }
        struct LimitEntry: Decodable {
            let kind: String?
            let percent: Double?
            let resets_at: String?
        }
        struct Breakdown: Decodable {
            let as_of: String?
        }

        let five_hour: Window?
        let seven_day: Window?
        let extra_usage: ExtraUsage?
        let limits: [LimitEntry]?
        let seven_day_breakdown: Breakdown?
    }

    private func parseUsageJSON(
        _ data: Data,
        orgUuid: String?,
        accountUuid: String?,
        preferredDate: Date,
        source: UsageDataSource
    ) -> LiveUsageReading? {
        guard let decoded = try? JSONDecoder().decode(UsageAPIResponse.self, from: data) else {
            return nil
        }

        let sessionLimit = decoded.limits?.first { $0.kind == "session" }
        let weeklyLimit = decoded.limits?.first { $0.kind == "weekly_all" }

        let fhDouble = decoded.five_hour?.utilization ?? sessionLimit?.percent
        let sdDouble = decoded.seven_day?.utilization ?? weeklyLimit?.percent
        let xuDouble: Double? = {
            guard let extra = decoded.extra_usage else { return nil }
            if extra.is_enabled == false && extra.utilization == nil { return nil }
            return extra.utilization
        }()

        guard fhDouble != nil || sdDouble != nil || xuDouble != nil else { return nil }

        let fhPct = fhDouble.map { max(0, min(100, Int(round($0)))) }
        let sdPct = sdDouble.map { max(0, min(100, Int(round($0)))) }
        let xuPct = xuDouble.map { max(0, min(100, Int(round($0)))) }

        let fhResets = (decoded.five_hour?.resets_at ?? sessionLimit?.resets_at).flatMap(Self.parseISO8601)
        let sdResets = (decoded.seven_day?.resets_at ?? weeklyLimit?.resets_at).flatMap(Self.parseISO8601)

        var timestamp = preferredDate
        if let asOfStr = decoded.seven_day_breakdown?.as_of,
           let asOfDate = Self.parseISO8601(asOfStr),
           asOfDate > timestamp {
            timestamp = asOfDate
        }

        return LiveUsageReading(
            orgUuid: orgUuid,
            accountUuid: accountUuid,
            fiveHourPercent: fhPct,
            sevenDayPercent: sdPct,
            extraUsagePercent: xuPct,
            fiveHourResetsAt: fhResets,
            sevenDayResetsAt: sdResets,
            updatedAt: timestamp,
            source: source
        )
    }

    private struct CLIStateFile: Decodable {
        struct CachedUsage: Decodable {
            let fetchedAtMs: Double?
            let accountUuid: String?
            let utilization: UsageAPIResponse?
        }
        let cachedUsageUtilization: CachedUsage?
    }

    private func parseClaudeCLIStateFile(at url: URL) -> LiveUsageReading? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CLIStateFile.self, from: data),
              let cached = decoded.cachedUsageUtilization,
              let fetchedAtMs = cached.fetchedAtMs,
              let util = cached.utilization,
              let accountUuid = cached.accountUuid else {
            return nil
        }

        let sessionLimit = util.limits?.first { $0.kind == "session" }
        let weeklyLimit = util.limits?.first { $0.kind == "weekly_all" }

        let fhDouble = util.five_hour?.utilization ?? sessionLimit?.percent
        let sdDouble = util.seven_day?.utilization ?? weeklyLimit?.percent
        guard fhDouble != nil || sdDouble != nil else { return nil }

        let fhPct = fhDouble.map { max(0, min(100, Int(round($0)))) }
        let sdPct = sdDouble.map { max(0, min(100, Int(round($0)))) }
        let xuPct = util.extra_usage?.utilization.map { max(0, min(100, Int(round($0)))) }
        let fhResets = (util.five_hour?.resets_at ?? sessionLimit?.resets_at).flatMap(Self.parseISO8601)
        let sdResets = (util.seven_day?.resets_at ?? weeklyLimit?.resets_at).flatMap(Self.parseISO8601)

        return LiveUsageReading(
            orgUuid: nil,
            accountUuid: accountUuid.lowercased(),
            fiveHourPercent: fhPct,
            sevenDayPercent: sdPct,
            extraUsagePercent: xuPct,
            fiveHourResetsAt: fhResets,
            sevenDayResetsAt: sdResets,
            updatedAt: Date(timeIntervalSince1970: fetchedAtMs / 1000.0),
            source: .claudeCLI
        )
    }

    private func parseHTTPHeaderHints(from data: Data) -> (encoding: String?, date: Date?) {
        // Chromium pickles HTTP headers as null-separated ASCII strings inside Stream 0
        var encoding: String?
        var parsedDate: Date?
        let parts = data.split(separator: 0x00, omittingEmptySubsequences: true)
        for part in parts {
            guard part.count >= 6, part.count <= 160,
                  let s = String(data: Data(part), encoding: .ascii) else {
                continue
            }
            let lower = s.lowercased()
            if lower.hasPrefix("content-encoding:") {
                encoding = String(s.dropFirst("content-encoding:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.hasPrefix("date:") {
                let rawDate = String(s.dropFirst("date:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let d = Self.parseHTTPDate(rawDate) {
                    parsedDate = d
                }
            }
        }
        return (encoding, parsedDate)
    }

    private func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private func readLE64(_ data: Data, at offset: Int) -> UInt64 {
        let lo = UInt64(readLE32(data, at: offset))
        let hi = UInt64(readLE32(data, at: offset + 4)) << 32
        return lo | hi
    }

    public static func parseISO8601(_ str: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: str) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: str)
    }

    private static func parseHTTPDate(_ str: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return df.date(from: str)
    }
}
