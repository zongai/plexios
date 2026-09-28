import CoreVideo
import Foundation
import Metal
import MetalKit
import simd

/// Renders `CVPixelBuffer` (NV12 / 420v) via Metal. Never uses UIImage.
final class MetalVideoRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineNV12: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var mvpBuffer: MTLBuffer?
    private var currentPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()

    var aspectMode: VideoAspectMode = .fit
    private(set) var videoSize: CGSize = .zero
    private var drawableSize: CGSize = .zero

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device,
              let queue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard status == kCVReturnSuccess, let cache else { return nil }
        textureCache = cache

        mvpBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.size,
            options: .storageModeShared
        )
        buildPipelines()
    }

    func attach(to view: MTKView) {
        view.device = device
        view.delegate = self
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.enableSetNeedsDisplay = true
        view.isPaused = true
    }

    /// Present a decoded frame (from VideoToolbox). Triggers redraw.
    func enqueue(_ frame: VideoFrame, on view: MTKView?) {
        lock.lock()
        currentPixelBuffer = frame.pixelBuffer
        videoSize = CGSize(width: frame.width, height: frame.height)
        lock.unlock()
        if let view {
            DispatchQueue.main.async {
                view.setNeedsDisplay()
            }
        }
    }

    func clear(on view: MTKView?) {
        lock.lock()
        currentPixelBuffer = nil
        videoSize = .zero
        lock.unlock()
        view?.setNeedsDisplay()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
        updateMVP()
    }

    func draw(in view: MTKView) {
        lock.lock()
        let pixelBuffer = currentPixelBuffer
        lock.unlock()

        guard let pixelBuffer,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipeline = pipelineNV12,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let cache = textureCache
        else {
            return
        }

        drawableSize = view.drawableSize
        updateMVP()

        guard let (texY, texUV) = makeNV12Textures(from: pixelBuffer, cache: cache) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        if let mvpBuffer {
            encoder.setVertexBuffer(mvpBuffer, offset: 0, index: 0)
        }
        encoder.setFragmentTexture(texY, index: 0)
        encoder.setFragmentTexture(texUV, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Private

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "videoVertex")
        desc.fragmentFunction = library.makeFunction(name: "videoFragmentNV12")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineNV12 = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func updateMVP() {
        guard let mvpBuffer else { return }
        let matrix = aspectMatrix(
            video: videoSize,
            view: drawableSize,
            mode: aspectMode
        )
        mvpBuffer.contents().assumingMemoryBound(to: simd_float4x4.self).pointee = matrix
    }

    private func aspectMatrix(video: CGSize, view: CGSize, mode: VideoAspectMode) -> simd_float4x4 {
        guard video.width > 0, video.height > 0, view.width > 0, view.height > 0 else {
            return matrix_identity_float4x4
        }
        let videoAspect = Float(video.width / video.height)
        let viewAspect = Float(view.width / view.height)
        var sx: Float = 1
        var sy: Float = 1
        switch mode {
        case .fit:
            if videoAspect > viewAspect {
                sy = viewAspect / videoAspect
            } else {
                sx = videoAspect / viewAspect
            }
        case .fill:
            if videoAspect > viewAspect {
                sx = videoAspect / viewAspect
            } else {
                sy = viewAspect / videoAspect
            }
        case .stretch:
            sx = 1
            sy = 1
        }
        return simd_float4x4(
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func makeNV12Textures(
        from pixelBuffer: CVPixelBuffer,
        cache: CVMetalTextureCache
    ) -> (MTLTexture, MTLTexture)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // 8-bit biplanar NV12 / 420v
        let yPlane: OSType = format
        _ = yPlane

        var cvTexY: CVMetalTexture?
        var cvTexUV: CVMetalTexture?
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .r8Unorm,
            width,
            height,
            0,
            &cvTexY
        )
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .rg8Unorm,
            width / 2,
            height / 2,
            1,
            &cvTexUV
        )
        guard yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
              let cvTexY, let cvTexUV,
              let texY = CVMetalTextureGetTexture(cvTexY),
              let texUV = CVMetalTextureGetTexture(cvTexUV)
        else { return nil }
        return (texY, texUV)
    }
}
