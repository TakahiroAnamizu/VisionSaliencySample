import UIKit
import PhotosUI

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func presentPHPicker(_ sender: Any) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

}

extension ViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)

        guard let itemProvider = results.first?.itemProvider,
              itemProvider.canLoadObject(ofClass: UIImage.self) else { return }

        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
            guard let self = self,
                  let img = image as? UIImage else { return }

            DispatchQueue.main.async {
                self.imageView.image = img
            }
        }
    }
}
