import UIKit
import PhotosUI
import Vision

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var saliencySegment: UISegmentedControl!

    private var selectedImage: UIImage? // PHPicker から取得した画像

    private let salientAttentionLayer = CALayer()
    private let salientObjectsLayer = CAShapeLayer()
    // 画面回転時の Saliency の座標再計算用
    private var salientObjectsPathTransform = CGAffineTransform.identity
    private var saliencyObservation: VNSaliencyImageObservation?

    // MARK: - LifeCycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNotification()

        imageView.layer.addSublayer(salientAttentionLayer)
        salientObjectsLayer.strokeColor = #colorLiteral(red: 1, green: 0.5781051517, blue: 0, alpha: 1)
        salientObjectsLayer.fillColor = nil

        imageView.layer.addSublayer(salientObjectsLayer)
        salientAttentionLayer.opacity = 0.5
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeNotification()
    }

    // MARK: - IBAction

    @IBAction func presentPHPicker(_ sender: Any) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    @IBAction func changeSaliency(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            resetSaliencyLayer()
        case 1:
            objectSaliency()
        case 2:
            attentionSaliency()
        default:
            assertionFailure("unexpected select")
        }
    }

    // MARK: - notification

    private func setupNotification() {
        let center = NotificationCenter.default
        let name = UIDevice.orientationDidChangeNotification
        center.addObserver(self,
                           selector: #selector(orientationDidChange(_:)),
                           name: name,
                           object: nil)
    }

    private func removeNotification() {
        let center = NotificationCenter.default
        let name = UIDevice.orientationDidChangeNotification
        center.removeObserver(self, name: name, object: nil)
    }

    @objc
    private func orientationDidChange(_ notification: NSNotification) {
        guard let obs = saliencyObservation,
              let img = imageView.image else {
            saliencySegment.selectedSegmentIndex = 0
            resetSaliencyLayer()
            return
        }
        updateLayersGeometry(image: img)
        drawSaliencyLayer(observation: obs)
    }

    // MARK: - Saliency

    private func objectSaliency() {
        let objectRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        saliencyDetector(request: objectRequest)
    }

    private func attentionSaliency() {
        let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        saliencyDetector(request: attentionRequest)
    }

    private func saliencyDetector(request: VNImageBasedRequest) {
        guard let uiImage = selectedImage,
              let input = uiImage.pixelBuffer() else { return }
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: input,
                                                   options: [:])
        try? requestHandler.perform([request])

        guard let obs = request.results?.first as? VNSaliencyImageObservation else { return }
        saliencyObservation = obs

        drawSaliencyLayer(observation: obs)
    }

    // MARK: - Saliency Layer

    private func drawSaliencyLayer(observation obs: VNSaliencyImageObservation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.salientAttentionLayer.contents = self.createHeatMapMask(from: obs)
            self.salientObjectsLayer.path = self.createSalientObjectsBoundingBoxPath(transform: self.salientObjectsPathTransform)
        }
    }

    private func resetSaliencyLayer() {
        saliencyObservation = nil
        DispatchQueue.main.async {
            self.salientAttentionLayer.contents = nil
            self.salientObjectsLayer.path = nil
            self.loadViewIfNeeded()
        }
    }

    private func createHeatMapMask(from observation: VNSaliencyImageObservation) -> CGImage? {
        let pixelBuffer = observation.pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let vector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let saliencyImage = ciImage.applyingFilter("CIColorMatrix", parameters: ["inputBVector": vector])
        return CIContext().createCGImage(saliencyImage, from: saliencyImage.extent)
    }

    private func createSalientObjectsBoundingBoxPath(transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        if let salientObjects = saliencyObservation?.salientObjects {
            for object in salientObjects {
                let bbox = object.boundingBox
                path.addRect(bbox, transform: transform)
            }
        }
        return path
    }

}

extension ViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)

        guard let itemProvider = results.first?.itemProvider,
              itemProvider.canLoadObject(ofClass: UIImage.self) else { return }

        saliencySegment.selectedSegmentIndex = 0
        resetSaliencyLayer()

        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
            guard let self = self,
                  let img = image as? UIImage else { return }

            self.selectedImage = img
            DispatchQueue.main.async {
                self.imageView.image = img
                self.updateLayersGeometry(image: img)
            }
        }
    }

    private func updateLayersGeometry(image: UIImage) {
        // https://qiita.com/fr0g_fr0g/items/35339e0b9d977a404a22
        salientAttentionLayer.frame = AVMakeRect(aspectRatio: image.size,
                                             insideRect: imageView.bounds)
        salientObjectsLayer.frame = AVMakeRect(aspectRatio: image.size,
                                               insideRect: imageView.bounds)

        // transform to convert from normalized coordinates to layer's coordinates
        let scaleT = CGAffineTransform(scaleX: salientObjectsLayer.bounds.width,
                                       y: -salientObjectsLayer.bounds.height)
        let translateT = CGAffineTransform(translationX: 0,
                                           y: salientObjectsLayer.bounds.height)
        salientObjectsPathTransform = scaleT.concatenating(translateT)
    }
}

// https://stackoverflow.com/questions/54354138/how-can-you-make-a-cvpixelbuffer-directly-from-a-ciimage-instead-of-a-uiimage-in
extension UIImage {
    func pixelBuffer() -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)

        guard (status == kCVReturnSuccess) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.translateBy(x: 0, y: size.height)
        context?.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context!)
        draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }
}
