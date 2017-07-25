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

        // Playlist, History & Current

        static Dictionary<int, Track> _tracks = new Dictionary<int, Track>();
        static List<int> _trackPlaylist = new List<int>();
        static int _currentTrackUID = -1;
        static List<int> _trackHistory = new List<int>();
        static int _trackPlaylistCurrentIndex = -1;
        static int _trackHistoryCurrentIndex = -1;

        static int PlaylistNextTrackUID()
        {
            int i = _trackPlaylistCurrentIndex + 1;
            if (i >= _trackPlaylist.Count)
                return -1;
            return _trackPlaylist[i];
        }

        static int PlaylistPrevTrackUID()
        {
            int i = _trackPlaylistCurrentIndex - 1;
            if (i < 0)
                return -1;
            return _trackPlaylist[i];
        }

        static int HistoryAt(int index)
        {
            return _trackHistory[_trackHistory.Count - (1 + index)];
        }

        static int HistoryNextTrackUID()
        {
            int i = _trackHistoryCurrentIndex - 1;
            if (i < 0)
                return -1;
            return HistoryAt(i);
        }

        static int HistoryPrevTrackUID()
        {
            int i = _trackHistoryCurrentIndex + 1;
            if (i >= _trackHistory.Count)
                return -1;
            return HistoryAt(i);
        }

        // Modify Playlist and History

        static int MoveToNextPlaylistTrack() // THIS NEEDS TO CHOP OFF THE END OF THE HISTORY BEFORE PUSH
        {
            int uid = PlaylistNextTrackUID();
            if (uid >=0)
            {
                int cur = _trackPlaylistCurrentIndex;
                _trackPlaylistCurrentIndex += 1;
                if (cur >= 0)
                {
                    _trackHistory.Add(uid);
                    _trackHistoryCurrentIndex = 0;
                }
            }
            return uid;
        }

        static int MoveToPrevPlaylistTrack()
        {
            int uid = PlaylistPrevTrackUID();
            if (uid >=0)
            {
                int cur = _trackPlaylistCurrentIndex;
                _trackPlaylistCurrentIndex -= 1;
                _trackHistory.Add(uid);
                _trackHistoryCurrentIndex = 0;
            }
            return uid;
        }

        static int MoveToIndexedPlaylistTrack(int index)
        {
            if (index>=0 && index<_trackPlaylist.Count)
            {
                int uid = _trackPlaylist[index];
                if (uid >= 0)
                {
                    int cur = _trackPlaylistCurrentIndex;
                    _trackPlaylistCurrentIndex -= index;
                    _trackHistory.Add(uid);
                    _trackHistoryCurrentIndex = 0;
                }
                return uid;
            }
            return -1;
        }

        static int MoveBackInHistory()
        {
            int uid = HistoryPrevTrackUID();
            if (uid >=0)
            {
                _trackHistoryCurrentIndex += 1;
                int playlistIndex = _trackPlaylist.IndexOf(uid); // -1 if not found
                if (playlistIndex >= 0)
                    _trackPlaylistCurrentIndex = playlistIndex;
            }
            return uid;
        }

        static int MoveForwardInHistory()
        {
            int uid = HistoryNextTrackUID();
            if (uid >=0)
            {
                _trackHistoryCurrentIndex -= 1;
                int playlistIndex = _trackPlaylist.IndexOf(uid); // -1 if not found
                if (playlistIndex >= 0)
                    _trackPlaylistCurrentIndex = playlistIndex;
                return uid;
            }
            else
            {
                return MoveToNextPlaylistTrack();
            }
        }

        static void ClearHistory()
        {
            // neccesary when people want to set the playlist and not let it be possible
            // to go back in history to tracks not in the playlist.
            _trackHistory.Clear();
            _trackHistoryCurrentIndex = -1;

            // We no longer need any tracks that arent in the playlist as there is no way
            // to navigate to them
            List<Track> keep = new List<Track>();

            foreach (int uid in _trackPlaylist)
                keep.Add(_tracks[uid]);

            _tracks.Clear();

            foreach (Track track in keep)
                _tracks.Add(track.UID, track);
        }

        public static void SetPlaylist(Track[] tracks)
        {
            _trackPlaylist.Clear();

            List<int> uids = new List<int>();

            foreach (Track track in tracks)
            {
                _tracks.Add(track.UID, track);
                _trackPlaylist.Add(track.UID);
            }

            _trackPlaylistCurrentIndex = _trackPlaylist.IndexOf(_currentTrackUID);
        }

        //----------------------------
        // Control of the current Track

        static public void MakeTrackCurrentByUID(int uid)
        {
            Track track;
            int originalUID = _currentTrackUID;
            if (uid >= 0)
            {
                track = _tracks[uid];

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

                if (_internalState == iOSPlayerState.Initialized)
                {
                    PlayImpl(_player);
                }

                _currentTrackUID = uid;
            }
            else
            {
                _currentTrackUID = -1;
                track = null;
            }

            if (_currentTrackUID != originalUID)
            {
                _trackPlaylistCurrentIndex = _trackPlaylist.IndexOf(_currentTrackUID);
                CurrentTrackChanged(track);
                OnHasNextOrHasPreviousChanged();
            }
        }

        static public double Duration
        {
            get { return (_player != null) ? GetDuration(_player) : 0.0; }
        }

        static public double Progress
        {
            get { return (_player != null) ? GetPosition(_player) : 0.0; }
        }

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

        static bool IsLikelyToKeepUp
        {
            get { return GetIsLikelyToKeepUp(_player); }
        }

        static public Track CurrentTrack
        {
            get
            {
                return _tracks[_currentTrackUID];
            }
        }

        static void OnIsLikelyToKeepUpChanged()
        {
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

        static void PlayerItemDidReachEnd()
        {
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

        static public void Play()
        {
            MakeTrackCurrentByUID(_currentTrackUID);
        }

        static public void Resume()
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
                SetPosition(_player, 0.0);
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _statusName);
                ObserverProxy.RemoveObserver(CurrentPlayerItem, _isPlaybackLikelyToKeepUp);
                StopAndRelease(_player);
                Status = PlayerStatus.Stopped;
                _internalState = iOSPlayerState.Unknown;
                _player = null;
                MakeTrackCurrentByUID(-1);
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

        static ObjC.Object CurrentPlayerItem { get { return GetCurrentPlayerItem(_player); } }

        [Foreign(Language.ObjC)]
        static ObjC.Object GetCurrentPlayerItem(ObjC.Object player)
        @{
            AVPlayer* p = (AVPlayer*)player;
            return p.currentItem;
        @}

        static public bool Init()
        {
            LockScreenMediaControlsiOSImpl.Init();
            if (!DidAddAVPlayerItemDidPlayToEndTimeNotification)
            {
                ObserveAVPlayerItemDidPlayToEndTimeNotification(PlayerItemDidReachEnd, CurrentPlayerItem);
                DidAddAVPlayerItemDidPlayToEndTimeNotification = true;
            }
            return true;
        }

        public static void Next()
        {
            MakeTrackCurrentByUID(MoveToNextPlaylistTrack());
        }

        public static void Previous()
        {
            MakeTrackCurrentByUID(MoveToPrevPlaylistTrack());
        }

        public static void Forward()
        {
            MakeTrackCurrentByUID(MoveForwardInHistory());
        }

        public static void Backward()
        {
            MakeTrackCurrentByUID(MoveBackInHistory());
        }

        static void OnHasNextOrHasPreviousChanged()
        {
            if (HasNextChanged != null)
            {
                var hasNext = PlaylistNextTrackUID() > -1;
                HasNextChanged(hasNext);
            }
            if (HasPreviousChanged != null)
            {
                var hasPrev = PlaylistPrevTrackUID() > -1;
                HasPreviousChanged(hasPrev);
            }
        }
    }
}
