import Foundation
import UIKit

protocol ModelSoundProtocol {
    
    var trackUrl: String { get set }
    var trackFileName: String? { get set }
    var trackIsDownloaded: Bool { get }
    var trackDuration: String { get }
    var trackName: String { get }
    var image: UIImage? { get }
}

extension ModelSoundProtocol {
    
//    var trackIsDownloaded: Bool {
//        return ModelDownloadManager().isDownloadedTrackForModel(self)
//    }
//    var trackDuration: String {
//        if let trackFileName = trackFileName {
//            return SoundPlayer.sharedInstance.loadTrackDuration(trackName: trackFileName) ?? "    "
//        }
//        return "    "
//    }
    
}

func ==<T:ModelSoundProtocol>(lhs: T, rhs: T) -> Bool {
    return lhs.trackUrl == rhs.trackUrl
}
