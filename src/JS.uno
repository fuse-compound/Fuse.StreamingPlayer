using Fuse;
using Uno;
using Uno.UX;
using Fuse.Scripting;
using Fuse.Platform;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    [UXGlobalModule]
    public class StreamingPlayerModule : NativeEventEmitterModule
    {

        static StreamingPlayerModule _instance;
        static bool _playerInitialized;

        static int _playlistLength = 0;
        static int _currentTrackIndex = -1;
        static int GetCurrentTrackIndex() { return _currentTrackIndex; }

        public StreamingPlayerModule(): base(true, "statusChanged", "currentTrackChanged")
        {
            if (_instance != null) return;
            _instance = this;

            if (!_playerInitialized)
                _playerInitialized = StreamingPlayer.Init();

            if (!Marshal.CanConvertClass(typeof(Track)))
                Marshal.AddConverter(new TrackConverter());

            Resource.SetGlobalKey(_instance, "FuseJS/StreamingPlayer");
            AddMember(new NativeFunction("next", (NativeCallback)Next));
            AddMember(new NativeFunction("previous", (NativeCallback)Previous));
            AddMember(new NativeFunction("setPlaylist", (NativeCallback)SetPlaylist));
            AddMember(new NativeFunction("play", (NativeCallback)Play));
            AddMember(new NativeFunction("pause", (NativeCallback)Pause));
            AddMember(new NativeFunction("resume", (NativeCallback)Resume));
            AddMember(new NativeFunction("stop", (NativeCallback)Stop));
            AddMember(new NativeFunction("seek", (NativeCallback)Seek));

            AddMember(new NativeProperty<PlayerStatus,string>("status", GetStatus, null, PlayerStatusConverter.Convert));

            // we let the impl decide how to report this
            AddMember(new NativeProperty<double,double>("duration", GetDuration));
            AddMember(new NativeProperty<double,double>("progress", GetProgress));

            AddMember(new NativeProperty<int,int>("currentTrack", GetCurrentTrackIndex));
            AddMember(new NativeProperty<bool, bool>("hasNext", GetHasNext, null, null));
            AddMember(new NativeProperty<bool, bool>("hasPrevious", GetHasPrevious, null, null));

            var statusChanged = new NativeEvent("statusChanged");
            On("statusChanged", statusChanged);
            AddMember(statusChanged);

            var currentTrackChanged = new NativeEvent("currentTrackChanged");
            On("currentTrackChanged", currentTrackChanged);
            AddMember(currentTrackChanged);

            StreamingPlayer.StatusChanged += OnStatusChanged;
            StreamingPlayer.CurrentTrackChanged += OnCurrentTrackChanged;
        }

        bool CanCallBackToJS
        {
            get
            {
                return Fuse.Platform.Lifecycle.State == ApplicationState.Foreground
                    || Fuse.Platform.Lifecycle.State == ApplicationState.Interactive;
            }
        }

        void OnStatusChanged(PlayerStatus status)
        {
            Emit("statusChanged", status.Stringify());
        }

        void OnCurrentTrackChanged(int index)
        {
            _currentTrackIndex = index;
            Emit("statusChanged");
        }

        public object Next(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            debug_log("Next was called from JS");
            StreamingPlayer.Next();
            return null;
        }

        public object Previous(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Previous();
            return null;
        }

        public object SetPlaylist(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            var trackArray = args[0] as IArray;
            if (trackArray != null)
            {
                List<Track> tracks = new List<Track>();
                for (var i = 0; i < trackArray.Length; i++)
                {
                    var a = trackArray[i];
                    var track = Marshal.ToType<Track>(a);
                    if (a != null)
                        tracks.Add(track);
                }
                _playlistLength = tracks.Count;
                StreamingPlayer.SetPlaylist(tracks.ToArray());
            }
            else
            {
                _playlistLength = 0;
                StreamingPlayer.SetPlaylist(null);
            }
            return null;
        }

        PlayerStatus GetStatus()
        {
            if (!_playerInitialized) return PlayerStatus.Stopped;
            return StreamingPlayer.Status;
        }

        double GetDuration()
        {
            if (!_playerInitialized) return 0;
            return StreamingPlayer.Duration;
        }

        double GetProgress()
        {
            if (!_playerInitialized) return 0;
            return StreamingPlayer.Progress;
        }

        object Play(Context c, object[] args)
        {
            StreamingPlayer.Play();
            return null;
        }

        object Resume(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Resume();
            return null;
        }

        object Seek(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Seek(args.ValueOrDefault<double>(0, 0.0));
            return null;
        }

        object[] Pause(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Pause();
            return null;
        }

        object[] Stop(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Stop();
            return null;
        }

        //
        // GetHasNext & GetHasPrevious are really just convenience functions. They dont communicate
        // with the play, they just rely on what can be currently know of the player state
        //
        bool GetHasNext()
        {
            if (!_playerInitialized) return false;
            return _currentTrackIndex + 1 < _playlistLength;
        }

        bool GetHasPrevious()
        {
            if (!_playerInitialized) return false;
            return _currentTrackIndex - 1 >= 0;
        }
    }
}
