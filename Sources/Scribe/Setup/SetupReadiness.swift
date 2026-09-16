import Foundation

enum SetupReadiness {
    static func microphoneNeedsReview(reportedDenied: Bool, verifiedThisLaunch: Bool) -> Bool {
        reportedDenied && !verifiedThisLaunch
    }

    static func canFinish(transcriptionEnabled: Bool, modelInstalled: Bool, audioVerified: Bool, transcriptionVerified: Bool) -> Bool {
        audioVerified && (!transcriptionEnabled || (modelInstalled && transcriptionVerified))
    }
}

/// Save both outcomes together so an incomplete check remains explainable after relaunch.
struct AudioSetupVerification: Codable, Equatable {
    let microphone: Bool
    let systemAudio: Bool

    var passed: Bool { microphone && systemAudio }
    var detail: String {
        switch (microphone, systemAudio) {
        case (true, true): "Both tracks passed the audio test."
        case (true, false): "Your microphone passed. Mac audio was quiet: check your sound output and volume, then try again. Scribe will play the test chime automatically."
        case (false, true): "Mac audio passed. Your microphone was quiet: run the audio check again and say a complete sentence."
        case (false, false): "Neither track detected sound. Check your microphone and sound output, then try again. Speak the sentence shown; Scribe will play the test chime automatically."
        }
    }

    static func load(from defaults: UserDefaults) -> Self? {
        if let data = defaults.data(forKey: "scribe.setup.audioTracks"),
           let result = try? JSONDecoder().decode(Self.self, from: data) { return result }
        // Older builds only recorded the combined result. A failed result
        // cannot tell us which track was missing.
        return defaults.bool(forKey: "scribe.setup.audioVerified")
            ? Self(microphone: true, systemAudio: true) : nil
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "scribe.setup.audioTracks")
        defaults.set(passed, forKey: "scribe.setup.audioVerified")
    }
}

/// Names are user-confirmed labels, never inferred identities from mixed audio.
enum SpeakerIdentity {
    static func initialNames(for meeting: MeetingRecord, profileName: String) -> [String: String] {
        var names = meeting.speakerNames
        for line in meeting.transcript where names[line.rawSpeaker] == nil {
            switch line.rawSpeaker {
            case "me": names["me"] = profileName.isEmpty ? "Me" : profileName
            case "them": names["them"] = "Others"
            default: names[line.rawSpeaker] = line.rawSpeaker.capitalized
            }
        }
        return names
    }

    static func seedProfile(in directory: URL, name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = directory.appendingPathComponent("speaker-names.json")
        guard !name.isEmpty, !FileManager.default.fileExists(atPath: url.path) else { return }
        try JSONEncoder().encode(["me": name]).write(to: url, options: .atomic)
    }

    static func suggestions(attendees: [String], ownName: String) -> [String] {
        let ownName = ownName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(Set(attendees.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(ownName) != .orderedSame }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
