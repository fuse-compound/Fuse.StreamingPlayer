using Uno;
using Uno.UX;
using Uno.Threading;
using Uno.Permissions;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    [ForeignInclude(Language.Java,
                    "com.fuse.StreamingPlayer.StreamingAudioService",
                    "com.fuse.StreamingPlayer.Track",
                    "java.lang.Exception",
                    "android.app.Activity",
                    "android.content.ComponentName",
                    "android.content.Context",
                    "android.content.Intent",
                    "android.content.ServiceConnection",
                    "android.os.IBinder",
                    "android.os.RemoteException",
                    "android.view.KeyEvent")]
    extern(Android) static class StreamingPlayer
    {
        //------------------------------------------------------------
        // State

        static Java.Object _service; //StreamingAudioService
        static Java.Object _serviceConnection; // ServiceConnection
        static Java.Object _binder; // StreamingAudioService.LocalBinder
        static Java.Object _client;

        static bool _initialized;
        static bool _permittedToPlay = false;
        static PlayerStatus _status = PlayerStatus.Stopped;
        static int _currentTrackIndex = -1;
        static Track[] _pendingPlaylist;
        static bool _pendingPlay = false;

        static public bool IsConnected
        {
            get { return _binder != null; }
        }

        static public double Progress
        {
            get { return IsConnected ? (GetProgress(_client) / 1000.0) : 0; }
        }

        static public double Duration
        {
            get { return IsConnected ? (GetDuration(_client) / 1000.0) : 0; }
        }

        static public PlayerStatus Status
        {
            get { return _status; }
            private set
            {
                var last = _status;
                _status = value;
                if (last != value)
                    OnStatusChanged();
            }
        }

        //------------------------------------------------------------
        // Initializing

        static public bool Init()
        {
            if (!_initialized)
                InternalStatusChanged(0);
            return true;
        }

        static void OnPermitted(PlatformPermission permission)
        {
            _permittedToPlay = true;
        }

        static void OnRejected(Exception e)
        {
            debug_log "StreamingPlayer was not given permissions to play local files: " + e.Message;
            _permittedToPlay = false;
        }

        static void CreateService()
        {
            var permissionPromise = Permissions.Request(Permissions.Android.WRITE_EXTERNAL_STORAGE);
            permissionPromise.Then(OnPermitted, OnRejected);

            _serviceConnection = CreateServiceConnection();
            StartService(_serviceConnection);
        }

        [Foreign(Language.Java)]
        static void StartService(Java.Object serviceConnection)
        @{
            ServiceConnection scon = (ServiceConnection)serviceConnection;
            try
            {
                Activity a = com.fuse.Activity.getRootActivity();
                Intent intent = new Intent(a, StreamingAudioService.class);
                intent.setPackage(a.getPackageName());
                intent.putExtra(Intent.EXTRA_KEY_EVENT, new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY));
                a.bindService(intent, scon, Context.BIND_AUTO_CREATE);
                a.startService(intent);
            }
            catch (Exception e)
            {
                android.util.Log.d("StreamingPlayer", "We were not able to create a media player :S" + e.toString());
            }
        @}

        [Foreign(Language.Java)]
        static Java.Object CreateServiceConnection()
        @{
            ServiceConnection connection =  new ServiceConnection()
            {
                public void onServiceConnected(ComponentName className, IBinder service)
                {
                    // Because we have bound to an explicit
                    // service that is running in our own process, we can
                    // cast its IBinder to a concrete class and directly access it.
                    StreamingAudioService.StreamingAudioClient client = null;
                    StreamingAudioService.LocalBinder binder = (StreamingAudioService.LocalBinder)service;
                    StreamingAudioService ourService = binder.getService();

                    // The client is how we communicate with the service, this makes sure our events flow
                    // through the same channels as all other events from the system's controls and thus
                    // simplify our handling logic
                    try
                    {
                        client = new StreamingAudioService.StreamingAudioClient(ourService)
                        {
                            @Override public void OnCurrentTrackChanged(int index)
                            {
                                @{StreamingPlayer.OnCurrentTrackChanged(int):Call(index)};
                            }
                            @Override public void OnInternalStatusChanged(int i)
                            {
                                @{StreamingPlayer.InternalStatusChanged(int):Call(i)};
                            }
                        };
                    }
                    catch (RemoteException e)
                    {
                        com.fuse.AndroidInteropHelper.UncheckedThrow(e);
                    }

                    // This is so the service can fire the callbacks
                    ourService.setAudioClient(client);

                    @{StreamingPlayer._service:Set(ourService)};
                    @{StreamingPlayer._binder:Set(binder)};
                    @{StreamingPlayer._client:Set(client)};
                    @{StreamingPlayer.ConnectedToBackgroundService():Call()};
                }
                // Called when the connection with the service disconnects unexpectedly
                public void onServiceDisconnected(ComponentName className)
                {
                    debug_log("Music player handle service disconnection");
                }
            };
            return connection;
        @}

        //------------------------------------------------------------
        // Events

        static public event Action<int> CurrentTrackChanged;
        static public event StatusChangedHandler StatusChanged;

        static void OnStatusChanged()
        {
            debug_log("Status changed (uno): " + Status);
            if (StatusChanged != null)
                StatusChanged(Status);
        }

        static void OnCurrentTrackChanged(int index)
        {
            debug_log("Current track changed");
            _currentTrackIndex = index;
            if (CurrentTrackChanged != null)
                CurrentTrackChanged(index);
        }

        static void InternalStatusChanged(int i)
        {
            // mapping the enum in AndroidPlayerState.java to uno
            switch (i)
            {
                case 0:
                case 1:
                    Status = PlayerStatus.Stopped;
                    break;
                case 2:
                case 3:
                    Status = PlayerStatus.Loading;
                    break;
                case 4:
                    Status = PlayerStatus.Playing;
                    break;
                case 5:
                    Status = PlayerStatus.Stopped;
                    break;
                case 6:
                    Status = PlayerStatus.Paused;
                    break;
                case 7:
                    Status = PlayerStatus.Stopped;
                    break;
                case 8:
                    Status = PlayerStatus.Error;
                    break;
                case 9:
                    Status = PlayerStatus.Stopped;
                    break;
            }
        }

        [Foreign(Language.Java)]
        static Java.Object ToJavaTrack(string name, string artist, string url, string artworkUrl, double duration)
        @{
            return new Track(name, artist, url, artworkUrl, duration);
        @}

        static public void Play()
        {
            if (_service == null)
                CreateService();

            if (IsConnected)
            {
                Status = PlayerStatus.Loading;
                PlayImpl(_client);
                _pendingPlay = false;
            } else {
                _pendingPlay = true;
            }
        }

        [Foreign(Language.Java)]
        static void PlayImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Play();
        @}


        static void ConnectedToBackgroundService()
        {
            if (_pendingPlaylist != null) {
                SetPlaylist(_pendingPlaylist);
                _pendingPlaylist = null;
            }
            if (_pendingPlay)
                Play();
        }



        static public void Resume()
        {
            if (IsConnected)
            {
                Status = PlayerStatus.Playing;
                ResumeImpl(_client);
            }
        }

        [Foreign(Language.Java)]
        static void ResumeImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Resume();
        @}

        static public void Seek(double toProgress)
        {
            if (IsConnected)
            {
                var timeMS = (int)(Duration * toProgress * 1000);
                SeekImpl(_client, timeMS);
            }
        }

        [Foreign(Language.Java)]
        static void SeekImpl(Java.Object client, int timeMS)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Seek(timeMS);
        @}

        [Foreign(Language.Java)]
        static double GetDuration(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            return sClient.GetCurrentTrackDuration();
        @}

        [Foreign(Language.Java)]
        static double GetProgress(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            return sClient.GetCurrentPosition();
        @}

        static public void Pause()
        {
            if (IsConnected)
            {
                Status = PlayerStatus.Paused;
                PauseImpl(_client);
            }
        }

        [Foreign(Language.Java)]
        static void PauseImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Pause();
        @}

        static public void Stop()
        {
            if (IsConnected)
            {
                Status = PlayerStatus.Paused;
                StopImpl(_client);
            }
        }

        [Foreign(Language.Java)]
        static void StopImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Stop();
        @}



        //int id, string name, string url, string artworkUrl, double duration
        static public void SetPlaylist(Track[] tracks)
        {
            if (_service == null)
                CreateService();

            if (IsConnected)
            {
                string[] names = new string[tracks.Length];
                string[] artists = new string[tracks.Length];
                string[] urls = new string[tracks.Length];
                string[] artworkUrls = new string[tracks.Length];
                double[] durations = new double[tracks.Length];

                for (int i = 0; i < tracks.Length; i++) {
                    var t = tracks[i];
                    names[i] = t.Name;
                    artists[i] = t.Artist;
                    urls[i] = t.Url;
                    artworkUrls[i] = t.ArtworkUrl;
                    durations[i] = t.Duration;
                }
                debug_log("Android: set current playlist");
                SetPlaylistImpl(_client, names, artists, urls, artworkUrls, durations);
            } else {
                debug_log("Android: caching as _pendingPlaylist");
                _pendingPlaylist = tracks;
            }
        }

        [Foreign(Language.Java)]
        static void SetPlaylistImpl(Java.Object client,
                             string[] names,
                             string[] artists,
                             string[] urls,
                             string[] artworkUrls,
                             double[] durations)
        @{
            String[] n = names.copyArray();
            String[] art = artists.copyArray();
            String[] u = urls.copyArray();
            String[] a = artworkUrls.copyArray();
            double[] d = durations.copyArray();

            Track[] tracks = new Track[n.length];

            for (int j = 0; j < n.length; j++) {
                Track t = new Track(n[j], art[j], u[j], a[j], d[j]);
                tracks[j] = t;
            }

            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.SetPlaylist(tracks);
        @}

        static public void Next()
        {
            if (IsConnected)
                NextImpl(_client);
        }

        static public void Previous()
        {
            if (IsConnected)
                PreviousImpl(_client);
        }

        [Foreign(Language.Java)]
        static void NextImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Next();
        @}

        [Foreign(Language.Java)]
        static void PreviousImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Previous();
        @}
    }
}
