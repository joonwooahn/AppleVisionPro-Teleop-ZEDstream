import Foundation
import AVFoundation
import VideoToolbox
import UIKit

// H.264 Annex B bytestream decoder using VideoToolbox.
final class H264AnnexBDecoder {
    private var decompressionSession: VTDecompressionSession?
    private var formatDesc: CMFormatDescription?
    private let decodeQueue = DispatchQueue(label: "h264.decode.queue")

    var onFrame: ((CGImage) -> Void)?

    deinit {
        if let s = decompressionSession {
            VTDecompressionSessionInvalidate(s)
        }
    }

    func configure(withSPS sps: Data, pps: Data) {
        print("[VideoDecoder] Configuring with SPS: \(sps.count) bytes, PPS: \(pps.count) bytes")
        let spsPtr: UnsafePointer<UInt8> = sps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let ppsPtr: UnsafePointer<UInt8> = pps.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        var formatDescOut: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: [spsPtr, ppsPtr],
            parameterSetSizes: [sps.count, pps.count],
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDescOut
        )
        guard status == noErr, let fmt = formatDescOut else { 
            print("[VideoDecoder] Failed to create format description: \(status)")
            return 
        }
        print("[VideoDecoder] Format description created successfully")
        self.formatDesc = fmt

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer else { return }
                var cgImage: CGImage?
                VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
                if let cg = cgImage, let refCon = refCon {
                    let decoder = Unmanaged<H264AnnexBDecoder>.fromOpaque(refCon).takeUnretainedValue()
                    DispatchQueue.main.async { decoder.onFrame?(cg) }
                }
            },
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        var session: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: fmt,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard createStatus == noErr, let s = session else { 
            print("[VideoDecoder] Failed to create decompression session: \(createStatus)")
            return 
        }
        print("[VideoDecoder] Decompression session created successfully")
        self.decompressionSession = s
    }

    func decode(nal: Data) {
        guard let session = decompressionSession, let fmt = formatDesc else { 
            print("[VideoDecoder] Cannot decode - session or format not ready")
            return 
        }
        decodeQueue.async {
            var nalWithLength = Data()
            var length = UInt32(nal.count).bigEndian
            nalWithLength.append(Data(bytes: &length, count: 4))
            nalWithLength.append(nal)

            var blockBuffer: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                     memoryBlock: nil,
                                                     blockLength: nalWithLength.count,
                                                     blockAllocator: nil,
                                                     customBlockSource: nil,
                                                     offsetToData: 0,
                                                     dataLength: nalWithLength.count,
                                                     flags: 0,
                                                     blockBufferOut: &blockBuffer) == kCMBlockBufferNoErr, let bb = blockBuffer else { return }

            nalWithLength.withUnsafeBytes { rawBuffer in
                _ = CMBlockBufferReplaceDataBytes(with: rawBuffer.baseAddress!, blockBuffer: bb, offsetIntoDestination: 0, dataLength: nalWithLength.count)
            }

            var sampleBuffer: CMSampleBuffer?
            let sampleSizes: [Int] = [nalWithLength.count]
            guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                            dataBuffer: bb,
                                            formatDescription: fmt,
                                            sampleCount: 1,
                                            sampleTimingEntryCount: 0,
                                            sampleTimingArray: nil,
                                            sampleSizeEntryCount: 1,
                                            sampleSizeArray: sampleSizes,
                                            sampleBufferOut: &sampleBuffer) == noErr, let sb = sampleBuffer else { return }

            VTDecompressionSessionDecodeFrame(session, sampleBuffer: sb, flags: [], frameRefcon: nil, infoFlagsOut: nil)
        }
    }
}


