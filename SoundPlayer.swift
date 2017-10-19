import Foundation
import AVFoundation
import AudioToolbox
import MediaPlayer

//TODO: Fix notifications name. Adding postfix "2" - isn't solve a problem

let AudioPlayerOnTrackChangedNotification = "AudioPlayerOnTrackChangedNotification"
let AudioPlayerOnTrackChangedNotification2 = "AudioPlayerOnTrackChangedNotification2"
let AudioPlayerOnPlaybackStateChangedNotification = "AudioPlayerOnPlaybackStateChangedNotification"

class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    
    let audioSession = AVAudioSession.sharedInstance()
    let commandCenter = MPRemoteCommandCenter.shared()
    let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    var notificationCenter = NotificationCenter.default
    
    static let sharedInstance = SoundPlayer()
    
    var player: AVAudioPlayer?
    var timer: Timer?
    var nextItemIndex: Int?
    var previousItemIndex: Int?
    var isPause = false
    open var playbackItems: [ModelSoundProtocol]?
    open var currentPlaybackItem: ModelSoundProtocol?
    open var nextPlaybackItem: ModelSoundProtocol? {
        guard let playbackItems = self.playbackItems, let currentPlaybackItem = self.currentPlaybackItem else { return nil }
        
        for (index,item) in playbackItems.enumerated() {
            if item.trackFileName == currentPlaybackItem.trackFileName {
                nextItemIndex = index + 1
                if nextItemIndex! >= playbackItems.count { return nil }
            }
        }
        
        return playbackItems[nextItemIndex!]
    }
    open var previousPlaybackItem: ModelSoundProtocol? {
        guard let playbackItems = self.playbackItems, let currentPlaybackItem = self.currentPlaybackItem else { return nil }
        
        for (index,item) in playbackItems.enumerated() {
            if item.trackFileName == currentPlaybackItem.trackFileName {
                previousItemIndex = index - 1
                if previousItemIndex! < 0 { return nil }
            }
        }
        return playbackItems[previousItemIndex!]
    }
    
    var nowPlayingInfo: [String : AnyObject]?

    open var currentTime: TimeInterval? {
        return self.player?.currentTime
    }
    
    open var duration: TimeInterval? {
        return self.player?.duration
    }
    
    open var isPlaying: Bool {
        return self.player?.isPlaying ?? false
    }
    
    struct CurrentTrack {
        let track: ModelSoundProtocol?
        let currentTime: TimeInterval?
        let duration: TimeInterval?
        let isPlaying: Bool?
    }
    
    override init() {
        super.init()
        try! self.audioSession.setCategory(AVAudioSessionCategoryPlayback)
        try! self.audioSession.setActive(true)
        self.configureCommandCenter()
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    open func playItems(_ playbackItems: [ModelSoundProtocol], firstItem: ModelSoundProtocol? = nil) {
        self.playbackItems = playbackItems
        if playbackItems.count == 0 {
            self.endPlayback()
            return
        }
        let playbackItem = firstItem ?? self.playbackItems!.first!
        self.playItem(playbackItem)
    }

    
    func playItem(_ playbackItem: ModelSoundProtocol) {
        if playbackItem.trackFileName != nil {
        let soundUrl = StorageManager.getSoundUrl(playbackItem)
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: soundUrl) else {
            self.endPlayback()
            return
        }
        if self.player?.url == soundUrl {
        if self.isPlaying == true {
            self.pause()
            isPause = true
        } else {
            self.play()
            isPause = false
        }
            return
        }
        
        if let currentVolume = self.player?.volume {
        audioPlayer.volume = currentVolume
        }
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        
        self.player = audioPlayer
        self.currentPlaybackItem = playbackItem
        self.updateNowPlayingInfoForCurrentPlaybackItem()
        self.updateCommandCenter()
        configureTimer()
        notifyOntrackChanged2()
        }
    }
    
    open func togglePlayPause() {
        if self.isPlaying {
            self.pause()
        }
        else {
            self.play()
        }
    }

    open func play() {
        self.player?.play()
        self.updateNowPlayingInfoElapsedTime()
        self.notifyOnPlaybackStateChanged()
    }
    
    open func pause() {
        self.player?.pause()
        self.updateNowPlayingInfoElapsedTime()
        self.notifyOnPlaybackStateChanged()
    }
    
    open func nextTrack() {
        guard let nextPlaybackItem = self.nextPlaybackItem else { return }
        self.playItem(nextPlaybackItem)
        self.updateCommandCenter()
        notifyOntrackChanged2()
    }
    
    open func previousTrack() {
        guard let previousPlaybackItem = self.previousPlaybackItem else { return }
        self.playItem(previousPlaybackItem)
        self.updateCommandCenter()
        notifyOntrackChanged2()
    }
    
    open func seekTo(_ timeInterval: TimeInterval) {
        self.player?.currentTime = timeInterval
        self.updateNowPlayingInfoElapsedTime()
    }
    
    
    //MARK: - Command Center
    
    func updateCommandCenter() {
        guard let playbackItems = self.playbackItems, let currentPlaybackItem = self.currentPlaybackItem else { return }
        
        self.commandCenter.previousTrackCommand.isEnabled = currentPlaybackItem.trackFileName != playbackItems.first!.trackFileName
        self.commandCenter.nextTrackCommand.isEnabled = currentPlaybackItem.trackFileName != playbackItems.last!.trackFileName
    }
    
    func configureCommandCenter() {
        self.commandCenter.playCommand.addTarget (handler: { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let sself = self else { return .commandFailed }
            sself.play()
            return .success
        })
        
        self.commandCenter.pauseCommand.addTarget (handler: { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let sself = self else { return .commandFailed }
            sself.pause()
            return .success
        })
        
        self.commandCenter.nextTrackCommand.addTarget (handler: { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let sself = self else { return .commandFailed }
            sself.nextTrack()
            return .success
        })
        
        self.commandCenter.previousTrackCommand.addTarget (handler: { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let sself = self else { return .commandFailed }
            sself.previousTrack()
            return .success
        })
        
    }

    func updateNowPlayingInfoForCurrentPlaybackItem() {
        guard let audioPlayer = self.player, let currentPlaybackItem = self.currentPlaybackItem else {
            self.configureNowPlayingInfo(nil)
            return
        }
        
        let nowPlayingInfo = [MPMediaItemPropertyTitle: currentPlaybackItem.trackName ,
                              MPMediaItemPropertyPlaybackDuration: audioPlayer.duration,
                              MPMediaItemPropertyArtwork : MPMediaItemArtwork(image: currentPlaybackItem.image!),
                              MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1.0 as Float)] as [String : Any]
        
//        if let image = UIImage(named: currentPlaybackItem.albumImageName) {
//            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
//        }
        
        self.configureNowPlayingInfo(nowPlayingInfo as [String : AnyObject]?)
        self.updateNowPlayingInfoElapsedTime()
    }
    
    func updateNowPlayingInfoElapsedTime() {
        guard var nowPlayingInfo = self.nowPlayingInfo, let audioPlayer = self.player else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: audioPlayer.currentTime as Double);
        
        self.configureNowPlayingInfo(nowPlayingInfo)
    }
    
    func configureNowPlayingInfo(_ nowPlayingInfo: [String: AnyObject]?) {
        self.nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        self.nowPlayingInfo = nowPlayingInfo
    }
    
    //MARK: - AVAudioPlayerDelegate
    
    open func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.nextPlaybackItem == nil {
            self.endPlayback()
        }
        else {
            self.nextTrack()
        }
    }
    
    func endPlayback() {
        self.currentPlaybackItem = nil
        self.player = nil
        
        self.updateNowPlayingInfoForCurrentPlaybackItem()
        self.notifyOnTrackChanged()
        self.notifyOntrackChanged2()
    }
    
    open func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        self.notifyOnPlaybackStateChanged()
    }
    
    open func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        if AVAudioSessionInterruptionOptions(rawValue: UInt(flags)) == .shouldResume {
            self.play()
        }
    }
    //MARK: TIMER
    func configureTimer() {
        timer?.invalidate()
        self.timer = Timer.every(0.5) { [weak self] in
            guard let sself = self else { return }
            sself.notifyOnPlaybackStateChanged()
            sself.notifyOnTrackChanged()
        }
    }
    
    //MARK: Notifications
    
    func notifyOnPlaybackStateChanged() {
     //   print("post")
       self.notificationCenter.post(name: Notification.Name(rawValue:AudioPlayerOnPlaybackStateChangedNotification),
            object: CurrentTrack(track: currentPlaybackItem,
                                  currentTime: currentTime,
                                   duration: duration,
                                    isPlaying: isPlaying))
    }
    
    func notifyOnTrackChanged() {
        self.notificationCenter.post(name: Notification.Name(rawValue: AudioPlayerOnTrackChangedNotification), object: CurrentTrack(track: currentPlaybackItem,
                                  currentTime: currentTime,
                                   duration: duration,
                                    isPlaying: isPlaying))
    }
    
    func notifyOntrackChanged2() {
        self.notificationCenter.post(name: Notification.Name(rawValue: AudioPlayerOnTrackChangedNotification2), object: nil )
    }
    
    func loadTrackDuration(trackName: String) -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let soundUrl = documentsURL.appendingPathComponent("\(trackName)")
        do {
            let helpPlayer = try AVAudioPlayer(contentsOf: soundUrl)
            return helpPlayer.duration.positionalTime
        } catch let error {
            print(error.localizedDescription)
        }
        
        
        return nil
    }
}
