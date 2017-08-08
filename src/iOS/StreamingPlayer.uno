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
        // Events
        static public event StatusChangedHandler StatusChanged;
        static public event Action<Track> CurrentTrackChanged;
        static internal event Action<bool> HasNextChanged;
        static internal event Action<bool> HasPreviousChanged;

        // Player State
        static ObjC.Object _player;
        static readonly string _statusName = "status";
        static readonly string _isPlaybackLikelyToKeepUp = "playbackLikelyToKeepUp";
        static iOSPlayerState _internalState = iOSPlayerState.Unknown;
        static PlayerStatus _status = PlayerStatus.Stopped;
        static bool DidAddAVPlayerItemDidPlayToEndTimeNotification = false;
        static int _currentTrackUID = -1;
        static ObjC.Object _currentlyObservedTrack;

        //------------------------------------------------------------

        static public bool Init()
        {
            LockScreenMediaControlsiOSImpl.Init();
            if (!DidAddAVPlayerItemDidPlayToEndTimeNotification)
            {
                ObserveAVPlayerItemDidPlayToEndTimeNotification(PlayerItemDidReachEnd);
                DidAddAVPlayerItemDidPlayToEndTimeNotification = true;
            }
            return true;
        }

        [Foreign(Language.ObjC)]
        static void ObserveAVPlayerItemDidPlayToEndTimeNotification(Action callback)
        @{
            // this is NSNotificationName on iOS 10 :|
            // maybe move this into a TargetSpecific type?
            NSString* notifName = AVPlayerItemDidPlayToEndTimeNotification;
            [[NSNotificationCenter defaultCenter]
                addObserverForName:notifName
                object:nil
                queue:nil
                usingBlock: ^void(NSNotification *note) { callback(); }
            ];
        @}

        //------------------------------------------------------------

        static public double Duration
        {
            get { return (_player != null) ? GetDuration(_player) : 0.0; }
        }

        static public double Progress
        {
            get { return (_player != null) ? GetPosition(_player) : 0.0; }
        }

        static bool IsLikelyToKeepUp
        {
            get { return GetIsLikelyToKeepUp(_player); }
        }


        static public Track CurrentTrack
        {
            get { return Playlist.TrackForID(_currentTrackUID); }
        }

        static public PlayerStatus Status
        {
            get
            {
                return _status;
            }
            private set
            {
                var orig = _status;
                _status = value;

                var handler = StatusChanged;
                if (handler != null && (_status != orig))
                {
                    handler(_status);
                }
            }
        }

        //------------------------------------------------------------

        static public void Play()
        {
            if (Status == PlayerStatus.Paused)
            {
                Resume();
            }
            else if (_currentTrackUID > -1)
            {
                MakeTrackCurrentByUID(_currentTrackUID);
            }
            else
            {
                Next();
            }
        }

        static internal void Resume()
        {
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
                PauseImpl(_player);
                Status = PlayerStatus.Stopped;
                _internalState = iOSPlayerState.Unknown;
                MakeTrackCurrentByUID(-1);
            }
        }

        public static void Next()
        {
            MakeTrackCurrentByUID(Playlist.MoveToNextPlaylistTrack());
        }

        public static void Previous()
        {
            MakeTrackCurrentByUID(Playlist.MoveToPrevPlaylistTrack());
        }

        public static void Forward()
        {
            MakeTrackCurrentByUID(Playlist.MoveForwardInHistory());
        }

        public static void Backward()
        {
            var uid = Playlist.MoveBackInHistory();
            if (uid > -1)
            {
                MakeTrackCurrentByUID(uid);
            }
        }

        static public void SwitchTrack(Track track)
        {
            var uid = Playlist.SetCurrentPlaylistTrack(track.UID);
            if (uid > -1)
            {
                MakeTrackCurrentByUID(uid);
            }
        }

        static public void Seek(double toProgress)
        {
            if (Status == PlayerStatus.Loading) return;
            var time = Duration * toProgress;
            SetPosition(_player, time);
            NowPlayingInfoCenter.SetProgress(toProgress * Duration);
        }

        static void OnInternalStateChanged()
        {
            var newState = GetInternalState(_player);
            var lastState = _internalState;
            switch (newState)
            {
                case 0: _internalState = iOSPlayerState.Unknown; break;
                case 1: _internalState = iOSPlayerState.Initialized; break;
                default: _internalState = iOSPlayerState.Error; break;
            }
            if (_internalState == iOSPlayerState.Initialized && _internalState != lastState)
            {
                PlayImpl(_player);
            }
        }

        static void OnIsLikelyToKeepUpChanged()
        {
            if (Status == PlayerStatus.Paused) return;

            var isLikelyToKeepUp = IsLikelyToKeepUp;
            if (isLikelyToKeepUp)
            {
                var rate = GetRate(_player);
                if (rate < 1.0)
                {
                    Resume();
                }
                Status = PlayerStatus.Playing;
            }
        }

        static void PlayerItemDidReachEnd()
        {
            if (_currentlyObservedTrack != null)
            {
                if (Playlist.PlaylistNextTrackUID() > -1)
                {
                    Forward();
                }
                else
                {
                    Stop();
                }
            }
        }

        [Foreign(Language.ObjC)]
        static ObjC.Object CurrentPlayerItem
        {
            get
            @{
                AVPlayer* p = (AVPlayer*)@{_player};
                return p.currentItem;
            @}
        }

        static void ObserveCurrent()
        {
            if (_currentlyObservedTrack != null)
            {
                Unobserve();
            }
            var item = CurrentPlayerItem;
            ObserverProxy.AddObserver(item, _isPlaybackLikelyToKeepUp, 0, OnIsLikelyToKeepUpChanged);
            ObserverProxy.AddObserver(item, _statusName, 0, OnInternalStateChanged);
            _currentlyObservedTrack = item;
        }

        static void Unobserve()
        {
            if (_currentlyObservedTrack != null)
            {
                ObserverProxy.RemoveObserver(_currentlyObservedTrack, _statusName);
                ObserverProxy.RemoveObserver(_currentlyObservedTrack, _isPlaybackLikelyToKeepUp);
                _currentlyObservedTrack = null;
            }
        }

        static public void ClearHistory()
        {
            Playlist.ClearHistory();
        }

        static public void MakeTrackCurrentByUID(int uid)
        {
            Track track;
            int originalUID = _currentTrackUID;
            if (uid >= 0)
            {
                track = Playlist.TrackForID(uid);

                Status = PlayerStatus.Loading;
                if (_player == null)
                {
                    // should only happen for the first track played
                    _player = Create(track.Url);
                    ObserveCurrent();
                }
                else
                {
                    _internalState = iOSPlayerState.Unknown;
                    AssignNewPlayerItemWithUrl(_player, track.Url);
                    ObserveCurrent();
                }

                NowPlayingInfoCenter.SetTrackInfo(track);

                if (_internalState == iOSPlayerState.Initialized)
                {
                    PlayImpl(_player);
                }

                _currentTrackUID = uid;
            }
            else
            {
                _currentTrackUID = -1;
                Unobserve();
                track = null;
            }

            if (_currentTrackUID != originalUID)
            {
                Playlist.SetPlaylistCurrent(_currentTrackUID);
                var handler = CurrentTrackChanged;
                if (handler != null)
                {
                    handler(track);
                }
                OnHasNextOrHasPreviousChanged();
            }
        }

        static void OnHasNextOrHasPreviousChanged()
        {
            var handler0 = HasNextChanged;
            if (handler0 != null)
            {
                var hasNext = Playlist.PlaylistNextTrackUID() > -1;
                handler0(hasNext);
            }
            var handler1 = HasPreviousChanged;
            if (handler1 != null)
            {
                var hasPrev = Playlist.PlaylistPrevTrackUID() > -1;
                handler1(hasPrev);
            }
        }

        public static void SetPlaylist(List<Track> tracks)
        {
            Playlist.SetPlaylist(tracks, _currentTrackUID);
        }

        [Foreign(Language.ObjC)]
        static float GetRate(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [p rate];
        @}

        [Foreign(Language.ObjC)]
        static int GetInternalState(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [[p currentItem] status];
        @}

        [Foreign(Language.ObjC)]
        static bool GetIsLikelyToKeepUp(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return [[p currentItem] isPlaybackLikelyToKeepUp];
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
    }
}
