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

    private let projectsPath: String
    private var pollingTimer: Timer?
    private var seenRequests = Set<String>()

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
        loadStats()
        setupPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    func loadStats() {
        seenRequests.removeAll()

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectsPath) else { return }

        // Find all JSONL files
        let enumerator = fileManager.enumerator(atPath: projectsPath)
        var jsonlFiles: [String] = []
        while let element = enumerator?.nextObject() as? String {
            if element.hasSuffix(".jsonl") {
                jsonlFiles.append("\(projectsPath)/\(element)")
            }
        }

        // Parse entries from all files
        var allEntries: [(entry: UsageEntry, model: String, usage: TokenUsage)] = []
        let decoder = JSONDecoder()

        for filePath in jsonlFiles {
            guard let content = fileManager.contents(atPath: filePath),
                  let text = String(data: content, encoding: .utf8) else { continue }

            for line in text.components(separatedBy: .newlines) {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let entry = try? decoder.decode(UsageEntry.self, from: lineData),
                      entry.type == "assistant",
                      let model = entry.message?.model,
                      let usage = entry.message?.usage else { continue }

                // Deduplicate by messageId:requestId (same as ccusage)
                let messageId = entry.message?.id ?? ""
                let requestId = entry.requestId ?? ""
                let key = "\(messageId):\(requestId)"

                if seenRequests.contains(key) { continue }
                seenRequests.insert(key)

                allEntries.append((entry, model, usage))
            }
        }

        // Group by date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let today = dateFormatter.string(from: Date())
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

        for (entry, model, usage) in allEntries {
            let entryDate: String
            if let date = isoFormatter.date(from: entry.timestamp) {
                entryDate = dateFormatter.string(from: date)
            } else {
                // Try parsing without fractional seconds
                let altFormatter = ISO8601DateFormatter()
                if let date = altFormatter.date(from: entry.timestamp) {
                    entryDate = dateFormatter.string(from: date)
                } else {
                    continue
                }
            }

            let priceModel = pricing[model] ?? defaultPricing
            let entryCost = priceModel.calculateCost(
                input: usage.inputTokens,
                output: usage.outputTokens,
                cacheRead: usage.cacheReadTokens,
                cacheCreation: usage.cacheCreationTokens
            )

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

        // Build today stats
        todayStats = TodayStats(
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
        modelStats = models.sorted { $0.cost > $1.cost }
        totalCost = allTimeCost
        totalSessions = sessions.count
        totalMessages = allEntries.count

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
        weeklyStats = weeklyCosts

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
        monthlyStats = monthlyCosts

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
        dailyBreakdown = breakdowns.sorted { $0.date > $1.date }

        lastUpdated = Date()
    }

    private func setupPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadStats()
        }
    }
}
