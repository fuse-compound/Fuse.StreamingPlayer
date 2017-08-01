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
        static List<Track> _pendingPlaylist;
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

            HookOntoRawActivityEvents();
            _initialized = true;
            return true;
        }

        [Foreign(Language.Java)]
        static void HookOntoRawActivityEvents()
        @{
            com.fuse.Activity.SubscribeToLifecycleChange(new com.fuse.Activity.ActivityListener()
            {
                @Override public void onStop() {}
                @Override public void onStart() {}
                @Override public void onWindowFocusChanged(boolean hasFocus) {}
                @Override public void onPause() {}
                @Override public void onResume() {}
                @Override public void onConfigurationChanged(android.content.res.Configuration config) {}
                @Override public void onDestroy()
                {
                    debug_log("--- shutting down ---");
                    com.fuse.StreamingPlayer.StreamingAudioService svc = (com.fuse.StreamingPlayer.StreamingAudioService)@{_service:Get()};
                    if (svc != null)
                    {
                        svc.KillNotificationPlayer();
                    }
                }
            });
        @}

        static void OnPermitted(PlatformPermission permission)
        {
            _permittedToPlay = true;
        }

        static void OnRejected(Exception e)
        {
            debug_log "StreamingPlayer was not given permissions to play local files: " + e.Message;
            _permittedToPlay = false;
            Status = PlayerStatus.Error;
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
                            @Override public void OnCurrentTrackChanged(Track track)
                            {
                                if (track!=null)
                                    @{StreamingPlayer.OnCurrentTrackChanged(Track):Call(@{Track(int, string, string, string, string, double):New(track.UID, track.Name, track.Artist, track.Url, track.ArtworkUrl, track.Duration)})};
                                else
                                    @{StreamingPlayer.OnCurrentTrackChanged(Track):Call(null)};
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
                    debug_log("Music player service disconnection");
                    @{Status:Set(@{PlayerStatus.Error})};
                }
            };
            return connection;
        @}

        //------------------------------------------------------------
        // Events

        static public event Action<Track> CurrentTrackChanged;
        static public event StatusChangedHandler StatusChanged;

        static void OnStatusChanged()
        {
            if (StatusChanged != null)
                StatusChanged(Status);
        }

        static void OnCurrentTrackChanged(Track track)
        {
            CurrentTrackChanged(track);
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
        static public void SetPlaylist(List<Track> tracks)
        {
            if (tracks!=null)
            {
                if (_service == null)
                    CreateService();

                if (IsConnected)
                {
                    SetPlaylistImpl(_client, tracks, tracks.Count);
                } else {
                    _pendingPlaylist = tracks;
                }
            }
        }

        [Foreign(Language.Java)]
        static void SetPlaylistImpl(Java.Object client, object unoTracks, int len)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;

            java.util.ArrayList<Track> tracks = new java.util.ArrayList<Track>();

            for (int i =0; i<len; i++)
                tracks.add((Track)@{NthToJavaTrack(object,int):Call(unoTracks, i)});

            sClient.SetPlaylist(tracks.toArray(new Track[tracks.size()]));
        @}

        static Java.Object NthToJavaTrack(object boxedArr, int n)
        {
            var arr = (List<Track>)boxedArr;
            var track = arr[n];
            return ToJavaTrack(track);
        }

        static Java.Object ToJavaTrack(Track track)
        {
            return ToJavaTrack(track.UID, track.Name, track.Artist, track.Url, track.ArtworkUrl, track.Duration);
        }

        [Foreign(Language.Java)]
        static Java.Object ToJavaTrack(int uid, string name, string artist, string url, string artworkUrl, double duration)
        @{
            return new Track(uid, name, artist, url, artworkUrl, duration);
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

        static public void Forward()
        {
            if (IsConnected)
                ForwardImpl(_client);
        }

        static public void Backward()
        {
            if (IsConnected)
                BackwardImpl(_client);
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

        [Foreign(Language.Java)]
        static void BackwardImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Backward();
        @}

        [Foreign(Language.Java)]
        static void ForwardImpl(Java.Object client)
        @{
            StreamingAudioService.StreamingAudioClient sClient = (StreamingAudioService.StreamingAudioClient)client;
            sClient.Forward();
        @}
    }
}
