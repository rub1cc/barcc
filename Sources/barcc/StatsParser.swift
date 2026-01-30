import Foundation

// MARK: - JSONL Models

struct UsageEntry: Codable {
    let type: String
    let timestamp: String
    let sessionId: String?
    let message: MessageContent?
    let requestId: String?
    let uuid: String?
}

struct MessageContent: Codable {
    let id: String?      // messageId for deduplication
    let model: String?
    let usage: TokenUsage?
}

struct TokenUsage: Codable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?

    var inputTokens: Int { input_tokens ?? 0 }
    var outputTokens: Int { output_tokens ?? 0 }
    var cacheCreationTokens: Int { cache_creation_input_tokens ?? 0 }
    var cacheReadTokens: Int { cache_read_input_tokens ?? 0 }
}

// MARK: - Computed Stats

struct TodayStats {
    let messages: Int
    let sessions: Int
    let toolCalls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let cost: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

struct ModelStats: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let cost: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

struct DailyCost: Identifiable {
    let id = UUID()
    let date: Date
    let cost: Double
    let tokens: Int
}

struct DailyBreakdown: Identifiable {
    let id = UUID()
    let date: Date
    let dateString: String
    let models: [String]
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

// MARK: - Pricing

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double
    let cacheCreationPerMillion: Double

    // Tiered pricing above 200k tokens
    let inputPerMillionAbove200k: Double?
    let outputPerMillionAbove200k: Double?
    let cacheReadPerMillionAbove200k: Double?
    let cacheCreationPerMillionAbove200k: Double?

    func calculateCost(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Double {
        let threshold = 200_000

        func tieredCost(_ tokens: Int, _ basePrice: Double, _ tieredPrice: Double?) -> Double {
            if let tiered = tieredPrice, tokens > threshold {
                let baseCost = Double(threshold) / 1_000_000 * basePrice
                let tieredCost = Double(tokens - threshold) / 1_000_000 * tiered
                return baseCost + tieredCost
            }
            return Double(tokens) / 1_000_000 * basePrice
        }

        return tieredCost(input, inputPerMillion, inputPerMillionAbove200k) +
               tieredCost(output, outputPerMillion, outputPerMillionAbove200k) +
               tieredCost(cacheRead, cacheReadPerMillion, cacheReadPerMillionAbove200k) +
               tieredCost(cacheCreation, cacheCreationPerMillion, cacheCreationPerMillionAbove200k)
    }
}

// MARK: - Stats Parser

class StatsParser: ObservableObject {
    @Published var todayStats: TodayStats = TodayStats(messages: 0, sessions: 0, toolCalls: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, cost: 0)
    @Published var weeklyStats: [DailyCost] = []
    @Published var monthlyStats: [DailyCost] = []
    @Published var modelStats: [ModelStats] = []
    @Published var dailyBreakdown: [DailyBreakdown] = []
    @Published var totalMessages: Int = 0
    @Published var totalSessions: Int = 0
    @Published var totalCost: Double = 0
    @Published var lastUpdated: Date = Date()
    @Published var isLoading: Bool = false
    @Published var statusBarMode: StatusBarDisplayMode = .iconAndCost {
        didSet {
            UserDefaults.standard.set(statusBarMode.rawValue, forKey: statusBarModeKey)
        }
    }
    @Published var includeCacheTokens: Bool = true {
        didSet {
            UserDefaults.standard.set(includeCacheTokens, forKey: includeCacheTokensKey)
        }
    }
    @Published var refreshInterval: TimeInterval = 30 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: refreshIntervalKey)
            updatePollingTimer()
        }
    }
    @Published var dailySpendLimit: Double = 100 {
        didSet {
            UserDefaults.standard.set(dailySpendLimit, forKey: dailySpendLimitKey)
        }
    }

    private let projectsPath: String
    private var pollingTimer: Timer?
    private let statusBarModeKey = "statusBarMode"
    private let includeCacheTokensKey = "includeCacheTokens"
    private let refreshIntervalKey = "refreshInterval"
    private let dailySpendLimitKey = "dailySpendLimit"
    private var lastFileSnapshot: [String: FileSnapshot] = [:]
    private var lastStatsDayString: String?

    // Pricing per million tokens (calibrated to match Claude Code /cost)
    // Note: Max plan pricing differs from published API rates
    private let pricing: [String: ModelPricing] = [
        // Sonnet 4.5
        "claude-sonnet-4-5-20250929": ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75,
            inputPerMillionAbove200k: nil,
            outputPerMillionAbove200k: nil,
            cacheReadPerMillionAbove200k: nil,
            cacheCreationPerMillionAbove200k: nil
        ),
        // Opus 4.5 - adjusted for Max plan (~3x discount observed)
        "claude-opus-4-5-20251101": ModelPricing(
            inputPerMillion: 5.0,
            outputPerMillion: 25.0,
            cacheReadPerMillion: 0.50,
            cacheCreationPerMillion: 6.25,
            inputPerMillionAbove200k: nil,
            outputPerMillionAbove200k: nil,
            cacheReadPerMillionAbove200k: nil,
            cacheCreationPerMillionAbove200k: nil
        ),
        // Sonnet 3.5
        "claude-3-5-sonnet-20241022": ModelPricing(
            inputPerMillion: 3.0,
            outputPerMillion: 15.0,
            cacheReadPerMillion: 0.30,
            cacheCreationPerMillion: 3.75,
            inputPerMillionAbove200k: nil,
            outputPerMillionAbove200k: nil,
            cacheReadPerMillionAbove200k: nil,
            cacheCreationPerMillionAbove200k: nil
        ),
        // Haiku 3.5 - matches /cost output
        "claude-3-5-haiku-20241022": ModelPricing(
            inputPerMillion: 1.0,
            outputPerMillion: 5.0,
            cacheReadPerMillion: 0.10,
            cacheCreationPerMillion: 1.25,
            inputPerMillionAbove200k: nil,
            outputPerMillionAbove200k: nil,
            cacheReadPerMillionAbove200k: nil,
            cacheCreationPerMillionAbove200k: nil
        )
    ]

    // Default pricing (Sonnet-like)
    private let defaultPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheReadPerMillion: 0.30,
        cacheCreationPerMillion: 3.75,
        inputPerMillionAbove200k: nil,
        outputPerMillionAbove200k: nil,
        cacheReadPerMillionAbove200k: nil,
        cacheCreationPerMillionAbove200k: nil
    )

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.projectsPath = "\(homeDir)/.claude/projects"
        if let rawValue = UserDefaults.standard.string(forKey: statusBarModeKey),
           let savedMode = StatusBarDisplayMode(rawValue: rawValue) {
            statusBarMode = savedMode
        }
        if UserDefaults.standard.object(forKey: includeCacheTokensKey) != nil {
            includeCacheTokens = UserDefaults.standard.bool(forKey: includeCacheTokensKey)
        }
        let savedInterval = UserDefaults.standard.double(forKey: refreshIntervalKey)
        if savedInterval > 0 {
            refreshInterval = savedInterval
        }
        let savedLimit = UserDefaults.standard.double(forKey: dailySpendLimitKey)
        if savedLimit > 0 {
            dailySpendLimit = savedLimit
        }
        loadStats()
        setupPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    var todayTotalTokens: Int { todayStats.totalTokens }
    var todayDisplayTokens: Int {
        displayTokens(
            input: todayStats.inputTokens,
            output: todayStats.outputTokens,
            cacheRead: todayStats.cacheReadTokens,
            cacheCreation: todayStats.cacheCreationTokens
        )
    }
    var yesterdayCost: Double { weeklyStats.dropLast().last?.cost ?? 0 }
    var yesterdayTokens: Int { weeklyStats.dropLast().last?.tokens ?? 0 }
    var weekTotalCost: Double { weeklyStats.reduce(0) { $0 + $1.cost } }
    var weekTotalTokens: Int { weeklyStats.reduce(0) { $0 + $1.tokens } }
    var weekAvgCost: Double {
        guard !weeklyStats.isEmpty else { return 0 }
        return weekTotalCost / Double(weeklyStats.count)
    }
    var todayCostDelta: Double { todayStats.cost - yesterdayCost }
    var todayCostDeltaPercent: Double? {
        guard yesterdayCost > 0 else { return nil }
        return todayCostDelta / yesterdayCost
    }

    func displayTokens(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> Int {
        if includeCacheTokens {
            return input + output + cacheRead + cacheCreation
        }
        return input + output
    }

    func displayTokens(for day: DailyBreakdown) -> Int {
        displayTokens(
            input: day.inputTokens,
            output: day.outputTokens,
            cacheRead: day.cacheReadTokens,
            cacheCreation: day.cacheCreationTokens
        )
    }

    func loadStats() {
        guard !isLoading else { return }
        isLoading = true

        let startTime = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performLoadStats(startTime: startTime)
        }
    }

    private struct LoadResults {
        let todayStats: TodayStats
        let weeklyStats: [DailyCost]
        let monthlyStats: [DailyCost]
        let modelStats: [ModelStats]
        let dailyBreakdown: [DailyBreakdown]
        let totalMessages: Int
        let totalSessions: Int
        let totalCost: Double
    }

    private struct FileSnapshot: Equatable {
        let size: UInt64
        let modificationDate: Date
    }

    private func performLoadStats(startTime: Date) {
        var seenRequests = Set<String>()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectsPath) else {
            DispatchQueue.main.async { [weak self] in
                self?.finishLoading(startTime: startTime)
            }
            return
        }

        // Find all JSONL files
        let enumerator = fileManager.enumerator(atPath: projectsPath)
        var jsonlFiles: [String] = []
        var fileSnapshot: [String: FileSnapshot] = [:]
        var canUseSnapshot = true
        while let element = enumerator?.nextObject() as? String {
            if element.hasSuffix(".jsonl") {
                let filePath = "\(projectsPath)/\(element)"
                jsonlFiles.append(filePath)
                if canUseSnapshot {
                    guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                          let size = attributes[.size] as? NSNumber,
                          let modificationDate = attributes[.modificationDate] as? Date else {
                        canUseSnapshot = false
                        continue
                    }
                    fileSnapshot[filePath] = FileSnapshot(
                        size: size.uint64Value,
                        modificationDate: modificationDate
                    )
                }
            }
        }

        if canUseSnapshot, fileSnapshot == lastFileSnapshot, today == lastStatsDayString {
            DispatchQueue.main.async { [weak self] in
                self?.finishLoading(startTime: startTime)
            }
            return
        }

        // Parse entries from all files
        let decoder = JSONDecoder()

        // Group by date
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let altFormatter = ISO8601DateFormatter()
        altFormatter.formatOptions = [.withInternetDateTime]
        let calendar = Calendar.current

        // Calculate today's stats
        var todayInput = 0, todayOutput = 0, todayCacheRead = 0, todayCacheCreate = 0
        var todayCost: Double = 0
        var todaySessions = Set<String>()
        var todayMessages = 0

        // Calculate totals by model
        var modelTotals: [String: (input: Int, output: Int, cacheRead: Int, cacheCreate: Int)] = [:]
        var sessions = Set<String>()

        // Calculate daily stats with full breakdown
        struct DailyData {
            var models: Set<String> = []
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var cacheCreationTokens: Int = 0
            var cacheReadTokens: Int = 0
            var cost: Double = 0
        }
        var dailyData: [String: DailyData] = [:]

        var totalEntries = 0

        let parseEntryDate: (String) -> String? = { timestamp in
            if let date = isoFormatter.date(from: timestamp) ?? altFormatter.date(from: timestamp) {
                return dateFormatter.string(from: date)
            }
            return nil
        }

        for filePath in jsonlFiles {
            autoreleasepool {
                forEachLine(in: filePath) { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          let lineData = trimmed.data(using: .utf8),
                          let entry = try? decoder.decode(UsageEntry.self, from: lineData),
                          entry.type == "assistant",
                          let model = entry.message?.model,
                          let usage = entry.message?.usage,
                          let entryDate = parseEntryDate(entry.timestamp) else { return }

                    // Deduplicate by messageId:requestId (same as ccusage)
                    let messageId = entry.message?.id ?? ""
                    let requestId = entry.requestId ?? ""
                    let key = "\(messageId):\(requestId)"

                    if seenRequests.contains(key) { return }
                    seenRequests.insert(key)

                    let priceModel = pricing[model] ?? defaultPricing
                    let entryCost = priceModel.calculateCost(
                        input: usage.inputTokens,
                        output: usage.outputTokens,
                        cacheRead: usage.cacheReadTokens,
                        cacheCreation: usage.cacheCreationTokens
                    )

                    totalEntries += 1

                    // Track sessions
                    if let sessionId = entry.sessionId {
                        sessions.insert(sessionId)
                    }

                    // Model totals
                    var current = modelTotals[model] ?? (0, 0, 0, 0)
                    current.input += usage.inputTokens
                    current.output += usage.outputTokens
                    current.cacheRead += usage.cacheReadTokens
                    current.cacheCreate += usage.cacheCreationTokens
                    modelTotals[model] = current

                    // Daily breakdown
                    var daily = dailyData[entryDate] ?? DailyData()
                    daily.models.insert(model)
                    daily.inputTokens += usage.inputTokens
                    daily.outputTokens += usage.outputTokens
                    daily.cacheCreationTokens += usage.cacheCreationTokens
                    daily.cacheReadTokens += usage.cacheReadTokens
                    daily.cost += entryCost
                    dailyData[entryDate] = daily

                    // Today's stats
                    if entryDate == today {
                        todayInput += usage.inputTokens
                        todayOutput += usage.outputTokens
                        todayCacheRead += usage.cacheReadTokens
                        todayCacheCreate += usage.cacheCreationTokens
                        todayCost += entryCost
                        todayMessages += 1
                        if let sessionId = entry.sessionId {
                            todaySessions.insert(sessionId)
                        }
                    }
                }
            }
        }

        // Build today stats
        let todayStatsResult = TodayStats(
            messages: todayMessages,
            sessions: todaySessions.count,
            toolCalls: 0, // Not tracked in JSONL
            inputTokens: todayInput,
            outputTokens: todayOutput,
            cacheReadTokens: todayCacheRead,
            cacheCreationTokens: todayCacheCreate,
            cost: todayCost
        )

        // Build model stats
        var models: [ModelStats] = []
        var allTimeCost: Double = 0
        for (modelName, totals) in modelTotals {
            let displayName: String
            if modelName.contains("opus") {
                displayName = "Opus 4.5"
            } else if modelName.contains("haiku") {
                displayName = "Haiku 3.5"
            } else if modelName.contains("sonnet-4-5") {
                displayName = "Sonnet 4.5"
            } else {
                displayName = "Sonnet 3.5"
            }

            let priceModel = pricing[modelName] ?? defaultPricing
            let cost = priceModel.calculateCost(
                input: totals.input,
                output: totals.output,
                cacheRead: totals.cacheRead,
                cacheCreation: totals.cacheCreate
            )

            models.append(ModelStats(
                name: modelName,
                displayName: displayName,
                inputTokens: totals.input,
                outputTokens: totals.output,
                cacheReadTokens: totals.cacheRead,
                cacheCreationTokens: totals.cacheCreate,
                cost: cost
            ))
            allTimeCost += cost
        }
        let modelStatsResult = models.sorted { $0.cost > $1.cost }
        let totalCostResult = allTimeCost
        let totalSessionsResult = sessions.count
        let totalMessagesResult = totalEntries

        // Build weekly stats (last 7 days)
        var weeklyCosts: [DailyCost] = []
        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dateStr = dateFormatter.string(from: date)
            let daily = dailyData[dateStr]
            weeklyCosts.append(DailyCost(
                date: date,
                cost: daily?.cost ?? 0,
                tokens: (daily?.inputTokens ?? 0) + (daily?.outputTokens ?? 0) + (daily?.cacheReadTokens ?? 0) + (daily?.cacheCreationTokens ?? 0)
            ))
        }
        let weeklyStatsResult = weeklyCosts

        // Build monthly stats (last 30 days)
        var monthlyCosts: [DailyCost] = []
        for dayOffset in (0..<30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dateStr = dateFormatter.string(from: date)
            let daily = dailyData[dateStr]
            monthlyCosts.append(DailyCost(
                date: date,
                cost: daily?.cost ?? 0,
                tokens: (daily?.inputTokens ?? 0) + (daily?.outputTokens ?? 0) + (daily?.cacheReadTokens ?? 0) + (daily?.cacheCreationTokens ?? 0)
            ))
        }
        let monthlyStatsResult = monthlyCosts

        // Build full daily breakdown (sorted by date descending)
        var breakdowns: [DailyBreakdown] = []
        for (dateStr, data) in dailyData {
            if let date = dateFormatter.date(from: dateStr) {
                let modelDisplayNames = data.models.map { modelName -> String in
                    if modelName.contains("opus") { return "opus-4-5" }
                    else if modelName.contains("haiku") { return "haiku-4-5" }
                    else if modelName.contains("sonnet-4-5") { return "sonnet-4-5" }
                    else { return "sonnet-3-5" }
                }.sorted()

                breakdowns.append(DailyBreakdown(
                    date: date,
                    dateString: dateStr,
                    models: modelDisplayNames,
                    inputTokens: data.inputTokens,
                    outputTokens: data.outputTokens,
                    cacheCreationTokens: data.cacheCreationTokens,
                    cacheReadTokens: data.cacheReadTokens,
                    cost: data.cost
                ))
            }
        }
        let dailyBreakdownResult = breakdowns.sorted { $0.date > $1.date }

        let results = LoadResults(
            todayStats: todayStatsResult,
            weeklyStats: weeklyStatsResult,
            monthlyStats: monthlyStatsResult,
            modelStats: modelStatsResult,
            dailyBreakdown: dailyBreakdownResult,
            totalMessages: totalMessagesResult,
            totalSessions: totalSessionsResult,
            totalCost: totalCostResult
        )

        if canUseSnapshot {
            lastFileSnapshot = fileSnapshot
        }
        lastStatsDayString = today

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.todayStats = results.todayStats
            self.weeklyStats = results.weeklyStats
            self.monthlyStats = results.monthlyStats
            self.modelStats = results.modelStats
            self.dailyBreakdown = results.dailyBreakdown
            self.totalMessages = results.totalMessages
            self.totalSessions = results.totalSessions
            self.totalCost = results.totalCost
            self.lastUpdated = Date()
            self.finishLoading(startTime: startTime)
        }
    }

    private func finishLoading(startTime: Date) {
        // Minimum loading time for visual feedback
        let elapsed = Date().timeIntervalSince(startTime)
        let minDuration = 0.6
        if elapsed < minDuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + (minDuration - elapsed)) {
                self.isLoading = false
            }
        } else {
            isLoading = false
        }
    }

    private func setupPolling() {
        updatePollingTimer()
    }

    private func updatePollingTimer() {
        pollingTimer?.invalidate()
        let interval = max(refreshInterval, 10)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.loadStats()
        }
    }

    private func forEachLine(in filePath: String, handler: (String) -> Void) {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else { return }
        defer { try? fileHandle.close() }

        let chunkSize = 64 * 1024
        var buffer = Data()
        let newline = Data([0x0A])

        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let range = buffer.firstRange(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    handler(line)
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            handler(line)
        }
    }
}
