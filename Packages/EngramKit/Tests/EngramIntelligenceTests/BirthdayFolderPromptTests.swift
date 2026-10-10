import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// P33 — une fête a son dossier (« Anniversaires ») et c'est une chose à retenir, pas une tâche.
struct BirthdayFolderPromptTests {
    @Test func theInstructionsSendBirthdaysToTheirOwnFolder() {
        let system = CloudPrompt.system
        #expect(system.contains("Anniversaires"))
        #expect(!system.contains("file it with the family or friends"))
        #expect(system.localizedCaseInsensitiveContains("not a task"))
        #expect(CloudPrompt.version == "p33-cloud-v1")
    }

    @Test func theEvaluationExpectsTheBirthdayFolder() {
        let birthdays = EvaluationSet.cases.filter { BirthdayParser.isOnlyABirthday($0.sentence) }
        #expect(birthdays.count >= 2)
        #expect(birthdays.allSatisfy { $0.accepts(categoryPath: ["Anniversaires"]) && !$0.accepts(categoryPath: ["Famille"]) })
    }

    #if canImport(FoundationModels)
    @Test func theAppleInstructionsSendBirthdaysToTheirOwnFolderToo() {
        #expect(AnalysisPrompt.instructions.contains("Anniversaires"))
        #expect(!AnalysisPrompt.instructions.contains("file it with the family or"))
        #expect(AnalysisPrompt.version == "p33-v1")
    }
    #endif
}
