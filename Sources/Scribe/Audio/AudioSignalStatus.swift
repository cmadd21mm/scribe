import AVFoundation

/// A small, thread-safe snapshot produced by each recorder. File growth alone
/// cannot prove capture is working: Core Audio can write valid AAC packets
/// whose samples are all digital zero.
struct AudioSignalStatus: Equatable, Sendable {
    let capturedFrames: Int64
    let peak: Float

    var hasBuffers: Bool { capturedFrames > 0 }
    var hasSignal: Bool { peak > 0.000_001 }

    static func peak(in buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return 0 }
        var result: Float = 0
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            for audioBuffer in buffers {
                guard let raw = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
                let samples = raw.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    result = max(result, abs(samples[index]))
                }
            }
        case .pcmFormatInt16:
            for audioBuffer in buffers {
                guard let raw = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.stride
                let samples = raw.assumingMemoryBound(to: Int16.self)
                for index in 0..<count {
                    result = max(result, Float(abs(Int(samples[index]))) / 32_768)
                }
            }
        case .pcmFormatInt32:
            for audioBuffer in buffers {
                guard let raw = audioBuffer.mData else { continue }
                let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int32>.stride
                let samples = raw.assumingMemoryBound(to: Int32.self)
                for index in 0..<count {
                    result = max(result, Float(abs(Int64(samples[index]))) / 2_147_483_648)
                }
            }
        default:
            break
        }
        return result
    }
}
