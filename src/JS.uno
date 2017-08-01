using Uno;
using Uno.UX;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;
using Fuse;
using Fuse.Platform;
using Fuse.Scripting;

namespace StreamingPlayer
{
    [UXGlobalModule]
    public class StreamingPlayerModule : NativeEventEmitterModule
    {

        static StreamingPlayerModule _instance;
        static bool _playerInitialized;
        static List<Track> _lastPlaylist = new List<Track>();
        static int _playlistLength = 0;
        static Track _currentTrack = null;

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
            AddMember(new NativeFunction("backward", (NativeCallback)Backward));
            AddMember(new NativeFunction("forward", (NativeCallback)Forward));
            AddMember(new NativeFunction("play", (NativeCallback)Play));
            AddMember(new NativeFunction("pause", (NativeCallback)Pause));
            AddMember(new NativeFunction("stop", (NativeCallback)Stop));
            AddMember(new NativeFunction("seek", (NativeCallback)Seek));

            AddMember(new NativeProperty<PlayerStatus,string>("status", GetStatus, null, PlayerStatusConverter.Convert));

            // we let the impl decide how to report this
            AddMember(new NativeProperty<double,double>("duration", GetDuration));
            AddMember(new NativeProperty<double,double>("progress", GetProgress));
            AddMember(new NativeProperty<Track,Fuse.Scripting.Object>("currentTrack", GetCurrentTrack, null, Track.ToJSObject));
            AddMember(new NativeProperty<List<Track>, Fuse.Scripting.Array>("playlist", GetPlaylist, SetPlaylist, ToScriptingArray));


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

        static Track GetCurrentTrack() { return _currentTrack; }

        void OnCurrentTrackChanged(Track track)
        {
            _currentTrack = track;
            Emit("currentTrackChanged");
        }

        void OnStatusChanged(PlayerStatus status)
        {
            Emit("statusChanged", status.Stringify());
        }

        public object Next(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Next();
            return null;
        }

        public object Previous(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Previous();
            return null;
        }

        public object Forward(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Forward();
            return null;
        }

        public object Backward(Context c, object[] args)
        {
            if (!_playerInitialized) return null;
            StreamingPlayer.Backward();
            return null;
        }

        static Fuse.Scripting.Array ToScriptingArray<T>(Context context, List<T> data)
        {
            var convertedArray = ((IEnumerable<T>)data).OfType<T,object>().ToArray();
            return context.NewArray(convertedArray);
        }

        static List<Track> GetPlaylist()
        {
            return _lastPlaylist;
        }

        public void SetPlaylist(Fuse.Scripting.Array trackArray)
        {
            if (!_playerInitialized) return;
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
                StreamingPlayer.SetPlaylist(tracks);
                _lastPlaylist = tracks;
            }
            else
            {
                _playlistLength = 0;
                StreamingPlayer.SetPlaylist(null);
                _lastPlaylist = new List<Track>();
            }
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
    }
}
