import Foundation

public enum PhysicalDeviceEvidenceState: String, Codable, Equatable, Sendable {
    case notRun
    case passed
    case failed
    case unknown
}

public struct PhysicalDeviceEnvironmentEvidence: Codable, Equatable, Sendable {
    public let state: PhysicalDeviceEvidenceState
    public let deviceModel: String?
    public let osVersion: String?
    public let osBuild: String?
    public let xcodeVersion: String?
    public let xcodeBuild: String?
    public let sdkVersion: String?
    public let sourceRevision: String?
    public let provisioningState: String?
    public let offlineAfterProvisioning: PhysicalDeviceEvidenceState
    public let cancellationBehavior: PhysicalDeviceEvidenceState
    public let peakMemoryBytes: UInt64?
    public let peakMemoryMeasurementSource: String?
    public let thermalObservation: String?
    public let batteryObservation: String?
    public let unknownMeasurements: [String]

    public init(
        state: PhysicalDeviceEvidenceState,
        deviceModel: String? = nil,
        osVersion: String? = nil,
        osBuild: String? = nil,
        xcodeVersion: String? = nil,
        xcodeBuild: String? = nil,
        sdkVersion: String? = nil,
        sourceRevision: String? = nil,
        provisioningState: String? = nil,
        offlineAfterProvisioning: PhysicalDeviceEvidenceState = .unknown,
        cancellationBehavior: PhysicalDeviceEvidenceState = .unknown,
        peakMemoryBytes: UInt64? = nil,
        peakMemoryMeasurementSource: String? = nil,
        thermalObservation: String? = nil,
        batteryObservation: String? = nil,
        unknownMeasurements: [String] = []
    ) {
        self.state = state
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.xcodeVersion = xcodeVersion
        self.xcodeBuild = xcodeBuild
        self.sdkVersion = sdkVersion
        self.sourceRevision = sourceRevision
        self.provisioningState = provisioningState
        self.offlineAfterProvisioning = offlineAfterProvisioning
        self.cancellationBehavior = cancellationBehavior
        self.peakMemoryBytes = peakMemoryBytes
        self.peakMemoryMeasurementSource = peakMemoryMeasurementSource
        self.thermalObservation = thermalObservation
        self.batteryObservation = batteryObservation
        self.unknownMeasurements = unknownMeasurements.sorted()
    }

    public static let notRun = PhysicalDeviceEnvironmentEvidence(
        state: .notRun,
        offlineAfterProvisioning: .notRun,
        cancellationBehavior: .notRun,
        unknownMeasurements: [
            "batteryObservation",
            "deviceModel",
            "offlineAfterProvisioning",
            "osBuild",
            "osVersion",
            "peakMemoryBytes",
            "peakMemoryMeasurementSource",
            "provisioningState",
            "sdkVersion",
            "thermalObservation",
            "xcodeBuild",
            "xcodeVersion",
        ]
    )
}

public struct PhysicalDevicePerformanceBudget: Codable, Equatable, Sendable {
    public let maximumColdModelLoadSeconds: Double
    public let maximumWarmFirstTokenSeconds: Double
    public let maximumWarmGenerationSeconds: Double
    public let minimumWarmTokensPerSecond: Double
    public let maximumPeakMemoryBytes: UInt64
    public let disallowedThermalStates: [String]
    public let requireOfflineAfterProvisioning: Bool
    public let requireCancellation: Bool

    public init(
        maximumColdModelLoadSeconds: Double,
        maximumWarmFirstTokenSeconds: Double,
        maximumWarmGenerationSeconds: Double,
        minimumWarmTokensPerSecond: Double,
        maximumPeakMemoryBytes: UInt64,
        disallowedThermalStates: [String],
        requireOfflineAfterProvisioning: Bool,
        requireCancellation: Bool
    ) {
        self.maximumColdModelLoadSeconds = maximumColdModelLoadSeconds
        self.maximumWarmFirstTokenSeconds = maximumWarmFirstTokenSeconds
        self.maximumWarmGenerationSeconds = maximumWarmGenerationSeconds
        self.minimumWarmTokensPerSecond = minimumWarmTokensPerSecond
        self.maximumPeakMemoryBytes = maximumPeakMemoryBytes
        self.disallowedThermalStates = disallowedThermalStates
        self.requireOfflineAfterProvisioning = requireOfflineAfterProvisioning
        self.requireCancellation = requireCancellation
    }
}

public struct TranslationQualityCriterion: Codable, Equatable, Sendable {
    public let identifier: String
    public let description: String
    public let minimumScore: Int
    public let hardGate: Bool

    public init(
        identifier: String,
        description: String,
        minimumScore: Int,
        hardGate: Bool
    ) {
        self.identifier = identifier
        self.description = description
        self.minimumScore = minimumScore
        self.hardGate = hardGate
    }
}

public struct TranslationQualityRubric: Codable, Equatable, Sendable {
    public let scoreScale: String
    public let criteria: [TranslationQualityCriterion]

    public init(
        scoreScale: String,
        criteria: [TranslationQualityCriterion]
    ) {
        self.scoreScale = scoreScale
        self.criteria = criteria
    }
}

public struct PhysicalDeviceEvaluationContract: Codable, Equatable, Sendable {
    public let version: String
    public let performance: PhysicalDevicePerformanceBudget
    public let quality: TranslationQualityRubric
    public let batteryPolicy: String

    public init(
        version: String,
        performance: PhysicalDevicePerformanceBudget,
        quality: TranslationQualityRubric,
        batteryPolicy: String
    ) {
        self.version = version
        self.performance = performance
        self.quality = quality
        self.batteryPolicy = batteryPolicy
    }

    public static let p02d1V1 = PhysicalDeviceEvaluationContract(
        version: "p0.2d1-v1",
        performance: PhysicalDevicePerformanceBudget(
            maximumColdModelLoadSeconds: 8,
            maximumWarmFirstTokenSeconds: 1.5,
            maximumWarmGenerationSeconds: 4,
            minimumWarmTokensPerSecond: 10,
            maximumPeakMemoryBytes: 1_610_612_736,
            disallowedThermalStates: ["serious", "critical"],
            requireOfflineAfterProvisioning: true,
            requireCancellation: true
        ),
        quality: TranslationQualityRubric(
            scoreScale: "0=incorrect, 1=partially acceptable, 2=acceptable",
            criteria: [
                TranslationQualityCriterion(
                    identifier: "meaning",
                    description: "Preserves the intended meaning without material omission or inversion.",
                    minimumScore: 2,
                    hardGate: true
                ),
                TranslationQualityCriterion(
                    identifier: "pronouns-and-omitted-subjects",
                    description: "Resolves Indonesian pronouns and omitted subjects consistently with context.",
                    minimumScore: 1,
                    hardGate: false
                ),
                TranslationQualityCriterion(
                    identifier: "family-relationships",
                    description: "Preserves kinship roles and family relationships without invention.",
                    minimumScore: 1,
                    hardGate: false
                ),
                TranslationQualityCriterion(
                    identifier: "slang-and-tone",
                    description: "Preserves particles, slang, humor, register, and conversational tone naturally.",
                    minimumScore: 1,
                    hardGate: false
                ),
                TranslationQualityCriterion(
                    identifier: "polish-grammar",
                    description: "Produces understandable, natural Polish with acceptable grammar.",
                    minimumScore: 1,
                    hardGate: false
                ),
                TranslationQualityCriterion(
                    identifier: "hallucinations",
                    description: "Adds no unsupported facts, speakers, relationships, or events.",
                    minimumScore: 2,
                    hardGate: true
                ),
                TranslationQualityCriterion(
                    identifier: "quoted-reference-handling",
                    description: "Uses quoted replies and reference context without confusing them with the target message.",
                    minimumScore: 1,
                    hardGate: false
                ),
            ]
        ),
        batteryPolicy: "Record battery level/charging state before and after the full synthetic pass; treat it as an observation, not a hard gate, because one short run is too coarse for a reliable percentage budget."
    )
}
