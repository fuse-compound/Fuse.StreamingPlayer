using Uno;
using Uno.UX;
using Uno.Threading;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{

    internal enum iOSPlayerState
    {
        Unknown, Initialized, Error
    }

    [ForeignInclude(Language.ObjC, "AVFoundation/AVFoundation.h")]
    [ForeignInclude(Language.ObjC, "MediaPlayer/MediaPlayer.h")]
    [Require("Xcode.Framework", "MediaPlayer")]
    [Require("Xcode.Framework", "CoreImage")]
    [ForeignInclude(Language.ObjC, "CoreImage/CoreImage.h")]
    extern(iOS) static class StreamingPlayer
    {

        static readonly string _statusName = "status";
        static readonly string _isPlaybackLikelyToKeepUp = "playbackLikelyToKeepUp";

        static ObjC.Object _player;
        static ObjC.Object CurrentPlayerItem
        {
            get { return GetCurrentPlayerItem(_player); }
        }

        static List<Track> _tracks = new List<Track>();

        static public event StatusChangedHandler StatusChanged;
        static public event Action<int> CurrentTrackChanged;
        static internal event Action<bool> HasNextChanged;
        static internal event Action<bool> HasPreviousChanged;

        static iOSPlayerState _internalState = iOSPlayerState.Unknown;

        static void OnIsLikelyToKeepUpChanged()
        {
            debug_log("OnIsLikelyToKeepUpChanged");
            if (Status == PlayerStatus.Paused)
                return;
            var isLikelyToKeepUp = IsLikelyToKeepUp;
            if (isLikelyToKeepUp) {
                var newState = GetStatus(_player);
                var rate = GetRate(_player);
                if (rate < 1.0) {
                    Resume();
                }
                Status = PlayerStatus.Playing;
            }
        }

        [Foreign(Language.ObjC)]
        static float GetRate(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [p rate];
        @}

        static public void Play(Track track)
        {
            debug_log("Play UNO called");
            Status = PlayerStatus.Loading;
            if (_player == null){
                _player = Create(track.Url);
                ObserverProxy.AddObserver(CurrentPlayerItem, _isPlaybackLikelyToKeepUp, 0, OnIsLikelyToKeepUpChanged);
                ObserverProxy.AddObserver(CurrentPlayerItem, _statusName, 0, OnInternalStateChanged);
            }
            else
            {
                _internalState = iOSPlayerState.Unknown;
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _statusName);
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _isPlaybackLikelyToKeepUp);

                AssignNewPlayerItemWithUrl(_player, track.Url);

                ObserverProxy.AddObserver(CurrentPlayerItem, _isPlaybackLikelyToKeepUp, 0, OnIsLikelyToKeepUpChanged);
                ObserverProxy.AddObserver(CurrentPlayerItem, _statusName, 0, OnInternalStateChanged);
            }

            NowPlayingInfoCenter.SetTrackInfo(track);

            CurrentTrack = track;
            if (_internalState == iOSPlayerState.Initialized) {
                PlayImpl(_player);
            }
        }

        static void PlayerItemDidReachEnd()
        {
            debug_log("We did reach the end of our track");
            Next();
        }

        [Foreign(Language.ObjC)]
        static void ObserveAVPlayerItemDidPlayToEndTimeNotification(Action callback, ObjC.Object playerItem)
        @{
            // this is NSNotificationName on iOS 10 :| maybe move this into a TargetSpecific type?
            NSString* notifName = AVPlayerItemDidPlayToEndTimeNotification;
            AVPlayerItem* pi = (AVPlayerItem*)playerItem;
            [[NSNotificationCenter defaultCenter]
                addObserverForName:notifName
                object:pi
                queue:nil
                usingBlock: ^void(NSNotification *note) {
                    NSLog(@"Note %a", note.name);
                    callback();
                }
            ];
        @}

        static public void Resume()
        {
            debug_log("Resume UNO called");
            if (_player != null)
            {
                PlayImpl(_player);
                Status = PlayerStatus.Playing;
            }
        }

        static public void Pause()
        {
            if (_player != null)
            {
                PauseImpl(_player);
                Status = PlayerStatus.Paused;
            }
        }

        static public void Stop()
        {
            if (_player != null)
            {
                SetPosition(_player, 0.0);
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _statusName);
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _isPlaybackLikelyToKeepUp);
                StopAndRelease(_player);
                Status = PlayerStatus.Stopped;
                _internalState = iOSPlayerState.Unknown;
                _player = null;
            }
        }

        static public void Seek(double toProgress)
        {
            if (Status == PlayerStatus.Loading)
                return;
            var time = Duration * toProgress;
            SetPosition(_player, time);
            NowPlayingInfoCenter.SetProgress(toProgress * Duration);
        }

        static public double Duration
        {
            get { return (_player != null) ? GetDuration(_player) : 0.0; }
        }

        static public double Progress
        {
            get { return (_player != null) ? GetPosition(_player) : 0.0; }
        }

        static PlayerStatus _status = PlayerStatus.Stopped;
        static public PlayerStatus Status
        {
            get
            {
                if (_player != null)
                {
                    switch (_internalState)
                    {
                        case iOSPlayerState.Unknown:
                            return PlayerStatus.Stopped;
                        case iOSPlayerState.Initialized:
                            return _status;
                        default:
                            return PlayerStatus.Error;
                    }
                }
                return PlayerStatus.Error;
            }
            private set
            {
                _status = value;
                OnStatusChanged();
            }
        }

        static string InternalStateToString(int s)
        {
            switch (s)
            {
                case 0: return "Unknown";
                case 1: return "Initialized";
                default: return "Error";
            }
        }

        static void OnInternalStateChanged()
        {
            var newState = GetStatus(_player);
            var lastState = _internalState;
            switch (newState)
            {
                case 0: _internalState = iOSPlayerState.Unknown; break;
                case 1: _internalState = iOSPlayerState.Initialized; break;
                default: _internalState = iOSPlayerState.Error; break;
            }
            if (_internalState == iOSPlayerState.Initialized && _internalState != lastState)
                PlayImpl(_player);
        }

        static void OnStatusChanged()
        {
            if (_internalState == iOSPlayerState.Initialized && Status == PlayerStatus.Stopped)
                PlayImpl(_player);

            if (StatusChanged != null)
                StatusChanged(Status);
        }

        static bool IsLikelyToKeepUp
        {
            get { return GetIsLikelyToKeepUp(_player); }
        }

        [Foreign(Language.ObjC)]
        static bool GetIsLikelyToKeepUp(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [[p currentItem] isPlaybackLikelyToKeepUp];
        @}

        [Foreign(Language.ObjC)]
        static int GetStatus(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [[p currentItem] status];
        @}

        [Foreign(Language.ObjC)]
        static void StopAndRelease(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            [p pause];
        @}

        [Foreign(Language.ObjC)]
        static ObjC.Object Create(string url)
        @{
            return [[AVPlayer alloc] initWithURL:[[NSURL alloc] initWithString: url]];
        @}

        [Foreign(Language.ObjC)]
        static void AssignNewPlayerItemWithUrl(ObjC.Object player, string url)
        @{
            AVPlayer* p = (AVPlayer*)player;
            p.rate = 0.0f;
            AVPlayerItem* item = [[AVPlayerItem alloc] initWithURL: [[NSURL alloc] initWithString: url]];
            [p replaceCurrentItemWithPlayerItem: item];
        @}

        [Foreign(Language.ObjC)]
        static void PlayImpl(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            [p play];
        @}

        [Foreign(Language.ObjC)]
        static void PauseImpl(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            [p pause];
        @}

        [Foreign(Language.ObjC)]
        static double GetDuration(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return CMTimeGetSeconds([[[p currentItem] asset] duration]);
        @}

        [Foreign(Language.ObjC)]
        static double GetPosition(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return CMTimeGetSeconds([[p currentItem] currentTime]);
        @}


        [Foreign(Language.ObjC)]
        static void SetPosition(ObjC.Object player, double position)
        @{
            AVPlayer* p = (AVPlayer*)player;
            [p seekToTime: CMTimeMake(position * 1000, 1000)];
        @}

        [Foreign(Language.ObjC)]
        static ObjC.Object GetCurrentPlayerItem(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return p.currentItem;
        @}

        static bool DidAddAVPlayerItemDidPlayToEndTimeNotification = false;
        static public bool Init()
        {
            LockScreenMediaControlsiOSImpl.Init();
            if (!DidAddAVPlayerItemDidPlayToEndTimeNotification)
            {
                debug_log("REGISTERING OBS");
                ObserveAVPlayerItemDidPlayToEndTimeNotification(PlayerItemDidReachEnd, CurrentPlayerItem);
                DidAddAVPlayerItemDidPlayToEndTimeNotification = true;
            }
            return true;
        }

        static Track _currentTrack;
        static public Track CurrentTrack
        {
            get
            {
                return _currentTrack;
            }
            set
            {
                _currentTrack = value;
                OnCurrentTrackChanged();
            }
        }

        static public bool HasNext
        {
            get
            {
                if (CurrentTrack == null) {
                    return false;
                }
                var index = _tracks.IndexOf(CurrentTrack);
                var ret = index > -1 && index < _tracks.Count - 1;
                return ret;
            }
        }

        static public bool HasPrevious
        {
            get
            {
                if (CurrentTrack == null)
                    return false;
                var ret = _tracks.IndexOf(CurrentTrack) > 0;
                return ret;
            }
        }

        static void OnCurrentTrackChanged()
        {
            if (CurrentTrackChanged != null)
                CurrentTrackChanged(_tracks.IndexOf(_currentTrack));
            OnHasNextOrHasPreviousChanged();
        }

        static public void SetPlaylist(Track[] tracks)
        {
            debug_log "iOS: setting playlist";
            _tracks.Clear();
            if (tracks == null)
            {
                debug_log("tracks was null. returning");
                return;
            }
            debug_log("tracks wasnt null. adding. CurrentTrack = >" + CurrentTrack + "<");
            foreach (var t in tracks)
            {
                _tracks.Add(t);
            }
            if (CurrentTrack==null)
                CurrentTrack = _tracks[0];
            else
                OnHasNextOrHasPreviousChanged();
        }

        static public void Next()
        {
            debug_log("UNO: trying next (hasnext=" + HasNext + ")");
            if (HasNext)
            {
                var newIndex = _tracks.IndexOf(CurrentTrack) + 1;
                var newTrack = _tracks[newIndex];
                Play(newTrack);
                CurrentTrack = newTrack;
            }
        }

        static public void Previous()
        {
            debug_log("UNO: trying previous (hasprevious=" + HasPrevious + ")");
            if (HasPrevious)
            {
                var newIndex = _tracks.IndexOf(CurrentTrack) - 1;
                var newTrack = _tracks[newIndex];
                Play(newTrack);
                CurrentTrack = newTrack;
            }
        }

        static void OnHasNextOrHasPreviousChanged()
        {
            if (HasNextChanged != null)
                HasNextChanged(HasNext);
            if (HasPreviousChanged != null)
                HasPreviousChanged(HasPrevious);
        }
    }
}
