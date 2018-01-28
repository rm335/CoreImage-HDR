//
//  MTKP-HDR.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 24.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage
import MetalKit
import MetalPerformanceShaders
import MetalKitPlus

public struct MTKPHDR {
    
    public static func makeHDR(ImageBracket: [CIImage], exposureTimes: [Float], cameraParameters: CameraParameter, context: CIContext? = nil) -> CIImage {
        
        let MaxImageCount = 5
        guard ImageBracket.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard exposureTimes.count == ImageBracket.count else {
            fatalError("Each of the \(ImageBracket.count) input images require an exposure time. Only \(exposureTimes.count) could be found.")
        }
        guard cameraParameters.responseFunction.count.isPowerOfTwo() else {
            fatalError("Length of Camera Response is not a power of two.")
        }
        
        var assets = MTKPAssets(ResponseEstimator.self)
        let textureLoader = MTKTextureLoader(device: MTKPDevice.device)
        let inputImages = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: MTKPDevice.device))}
        
        
        let HDRTexDescriptor = inputImages.first!.getDescriptor()
        HDRTexDescriptor.pixelFormat = .rgba16Float
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        
        guard
            let minMaxTexture = MTKPDevice.device.makeTexture(descriptor: descriptor),
            let HDRTexture = MTKPDevice.device.makeTexture(descriptor: HDRTexDescriptor),
            let MPSHistogramBuffer = MTKPDevice.device.makeBuffer(length: calculation.histogramSize(forSourceFormat: HDRTexture.pixelFormat), options: .storageModeShared),
            let MPSMinMaxBuffer = MTKPDevice.device.makeBuffer(length: 2 * MemoryLayout<float3>.size, options: .storageModeShared)
        else  {
                fatalError()
        }
        
        
        
        let cameraShifts = [int2](repeating: int2(0,0), count: inputImages.count)
        
        let HDRShaderIO = HDRCalcShaderIO(inputTextures: inputImages,
                                          maximumLDRCount: MaxImageCount,
                                          HDRImage: HDRTexture,
                                          exposureTimes: exposureTimes,
                                          cameraShifts: cameraShifts,
                                          cameraParameters: cameraParameters)
        
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRTexture, darkestImage: inputImages[0])
        
        assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        
        let computer = HDRComputer(assets: assets)
        
        // generate HDR image
        computer.encode("makeHDR")
        MPSMinMax.encode(commandBuffer: computer.commandBuffer, sourceTexture: HDRTexture, destinationTexture: minMaxTexture)
        computer.copy(texture: minMaxTexture, toBuffer: MPSMinMaxBuffer)
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        var MinMax = Array(UnsafeBufferPointer(start: MPSMinMaxBuffer.contents().assumingMemoryBound(to: float3.self), count: 2))
        
        // CLIP UPPER 1% OF PIXEL VALUES TO DISCARD NUMERICAL OUTLIERS
        // ... for that, get a histogram
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encodeMPSHistogram(forImage: HDRTexture,
                                    MTLHistogramBuffer: MPSHistogramBuffer,
                                    minPixelValue: vector_float4(MinMax.first!, 0),
                                    maxPixelValue: vector_float4(MinMax.last!, 1))
        
        
        
        let HDRConfiguration: [String:Any] = [kCIImageProperties : ImageBracket.first!.properties]
        
        return CIImage(mtlTexture: HDRTexture, options: HDRConfiguration)!
    }
}
