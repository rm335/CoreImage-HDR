//
//  CoreImage_HDRTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import ImageIO
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR


class CoreImage_HDRTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    
    var URLs:[URL] = []
    var Testimages:[CIImage] = []
    var ExposureTimes:[Float] = []
    var library:MTLLibrary?
    var textureLoader:MTKTextureLoader!
    
    override func setUp() {
        super.setUp()
        
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRProcessor.self))
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
    
        let imageNames = ["01-qianyuan-1:250", "02-qianyuan-1:125", "03-qianyuan-1:60", "04-qianyuan-1:30", "05-qianyuan-1:15"]
        
        /* Why does the Bundle Assets never contain images? Probably a XCode bug.
        Add an Asset catalogue to this test bundle and try to load any image. */
        //let AppBundle = Bundle(for: CoreImage_HDRTests.self)  // or: HDRProcessor.self, if assets belong to the other target
        //let imagePath = AppBundle.path(forResource: "myImage", ofType: "jpg")
        
        // WORKAROUND: load images from disk
        URLs = imageNames.map{FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codes/Testpics/QianYuan/" + $0 + ".jpg")}
        
        Testimages = URLs.map{
            guard let image = CIImage(contentsOf: $0) else {
                fatalError("Could not load TestImages needed for testing!")
            }
            return image
        }
        
        // load exposure times
        ExposureTimes = Testimages.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        textureLoader = MTKTextureLoader(device: self.device)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testHDR() {
        let camParams = CameraParameter(withTrainingWeight: 4)
        let imageExtent = Testimages.first!.extent
        
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRProcessor.apply(withExtent: imageExtent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : self.ExposureTimes,
                                                     "CameraParameter" : camParams])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/noobs.png"))
        
        XCTAssertTrue(true)
    }
    
    func testWithResponse() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 12)
        let imageExtent = Testimages.first!.extent
        
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        metaComp.estimate(cameraParameters: &camParams, iterations: 10)
        
        
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRProcessor.apply(withExtent: imageExtent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : self.ExposureTimes,
                                                     "CameraParameter" : camParams])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/result.png"))
        
        XCTAssertTrue(true)
    }
}
