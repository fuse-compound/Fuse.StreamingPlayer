package com.fuse.StreamingPlayer;

import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.RemoteException;
import android.os.SystemClock;
import android.support.v4.app.NotificationManagerCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaButtonReceiver;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.SparseArray;
import android.view.KeyEvent;

import java.util.ArrayList;
import java.util.Stack;

public final class StreamingAudioService
        extends Service
        implements MediaPlayer.OnPreparedListener, MediaPlayer.OnErrorListener, MediaPlayer.OnCompletionListener, AudioManager.OnAudioFocusChangeListener
{
    // Service
    LocalBinder _binder = new LocalBinder();

    // Player
    MediaSessionCompat _session;
    AudioManager _audioManager;
    MediaPlayer _player;

    // State
    PlaybackStateCompat.Builder _playbackStateBuilder = new PlaybackStateCompat.Builder();
    MediaMetadataCompat.Builder _metadataBuilder = new MediaMetadataCompat.Builder();
    AndroidPlayerState _state = AndroidPlayerState.Idle; // it's not pretty having this duplication but for now this is used when communicating with uno/js
    boolean _prepared = false;

    // Uno interaction
    StreamingAudioClient _streamingAudioClient;

    //--------------------------

    private SparseArray<Track> _tracks = new SparseArray<>();
    private ArrayList<Integer> _trackPlaylist = new ArrayList<Integer>();
    private int _currentTrackUID = -1; // Must only EVER be set by MakeTrackCurrentByUID(uid)
    private Stack<Integer> _trackHistory = new Stack<Integer>();
    private int _trackPlaylistCurrentIndex = -1;
    private int _trackHistoryCurrentIndex = -1; // set to -1 every time we move structurally.

    private int peekNth(Stack<Integer> stack, int n)
    {
        return stack.get(stack.size() - (1 + n));
    }

    private void pushToHistory(int uid)
    {
        _trackHistory.push(uid);
    }

    void PushCurrentToHistory()
    {
        int cur = _trackPlaylistCurrentIndex;
        if (cur >= 0)
        {
            pushToHistory(_trackPlaylist.get(cur));
        }
    }

    // Query Playlist and History

    private int PlaylistNextTrackUID()
    {
        int i = _trackPlaylistCurrentIndex + 1;
        if (i >= _trackPlaylist.size())
            return -1;
        return _trackPlaylist.get(i);
    }

    private int PlaylistPrevTrackUID()
    {
        int i = _trackPlaylistCurrentIndex - 1;
        if (i < 0)
            return -1;
        return _trackPlaylist.get(i);
    }

    private int HistoryNextTrackUID()
    {
        int i = _trackHistoryCurrentIndex - 1;
        if (i < 0)
            return -1;
        return peekNth(_trackHistory, i);
    }

    private int HistoryPrevTrackUID()
    {
        int i = _trackHistoryCurrentIndex + 1;
        if (i >= _trackHistory.size())
            return -1;
        return peekNth(_trackHistory, i);
    }

    // Modify Playlist and History

    private void DropFuture()
    {
        if (_trackHistoryCurrentIndex>-1)
        {
            for (int i = 0; i < _trackHistoryCurrentIndex; i++)
            {
                _trackHistory.pop();
            }
            _trackHistoryCurrentIndex = -1;
        }
    }

    private int MoveToNextPlaylistTrack()
    {
        int uid = PlaylistNextTrackUID();
        if (uid >=0)
        {
            // If we were playing from history then we dont want to push the current
            // track to history as it is already there.
            boolean wasntPlayingFromHistory = _trackHistoryCurrentIndex == -1;

            // If we were in the history then moving structurally starts making a new
            // history. This means we drop the future.
            DropFuture();

            if (wasntPlayingFromHistory)
            {
                PushCurrentToHistory();
            }

            // Modify our position in the playlist
            _trackPlaylistCurrentIndex += 1;
        }
        return uid;
    }

    private int MoveToPrevPlaylistTrack()
    {
        int uid = PlaylistPrevTrackUID();
        if (uid >=0)
        {
            // If we were playing from history then we dont want to push the current
            // track to history as it is already there.
            boolean wasntPlayingFromHistory = _trackHistoryCurrentIndex == -1;

            // If we were in the history then moving structurally starts making a new
            // history. This means we drop the future.
            DropFuture();

            if (wasntPlayingFromHistory)
            {
                PushCurrentToHistory();
            }

            // Modify our position in the playlist
            _trackPlaylistCurrentIndex -= 1;
        }
        return uid;
    }

    private int MoveBackInHistory()
    {
        int uid = HistoryPrevTrackUID();
        if (uid >=0)
        {
            _trackHistoryCurrentIndex += 1;
            int playlistIndex = _trackPlaylist.indexOf(uid); // -1 if not found
            if (playlistIndex >= 0)
                _trackPlaylistCurrentIndex = playlistIndex;
        }
        return uid;
    }

    private int MoveForwardInHistory()
    {
        int uid = HistoryNextTrackUID();
        if (uid >=0)
        {
            _trackHistoryCurrentIndex -= 1;
            int playlistIndex = _trackPlaylist.indexOf(uid); // -1 if not found
            if (playlistIndex >= 0)
                _trackPlaylistCurrentIndex = playlistIndex;
            return uid;
        }
        else
        {
            return MoveToNextPlaylistTrack();
        }
    }

    private void ClearHistory()
    {
        // neccesary when people want to set the playlist and not let it be possible
        // to go back in history to tracks not in the playlist.
        _trackHistory.clear();
        _trackHistoryCurrentIndex = -1;

        // We no longer need any tracks that arent in the playlist as there is no way
        // to navigate to them
        ArrayList<Track> keep = new ArrayList<>();

        for (int uid: _trackPlaylist)
            keep.add(_tracks.get(uid));

        _tracks.clear();

        for (Track track: keep)
            _tracks.put(track.UID, track);
    }

    private void SetPlaylist(Track[] tracks)
    {
        _trackPlaylist.clear();

        ArrayList<Integer> uids = new ArrayList<>();

        for (Track track : tracks)
        {
            _tracks.put(track.UID, track);
            _trackPlaylist.add(track.UID);
        }

        _trackPlaylistCurrentIndex = _trackPlaylist.indexOf(_currentTrackUID);
    }


    //-------------------------
    // Control of the current Track

    private void MakeTrackCurrentByUID(int uid)
    {
        // This is the only way to request a change in CurrentTrack.
        // Moving in the playlist and history is just changing the focus
        // of those things.

        if (_prepared)
        {
            _prepared = false;
            _player.stop();
            _player.reset();
        }

        int originalUID = _currentTrackUID;
        if (uid >= 0)
        {
            try
            {
                _player.reset();
                _state = AndroidPlayerState.Initialized;

                Track track = _tracks.get(uid);
                if (track == null) throw new AssertionError();

                _player.setDataSource(track.Url);

                setPlaybackState(PlaybackStateCompat.STATE_BUFFERING, 0);
                _prepared = false;

                _currentTrackUID = uid;

                _player.prepareAsync();
            }
            catch (Exception e)
            {
                // {TODO} move to error state
            }
        } else {
            _currentTrackUID = -1;
        }

        if (_currentTrackUID != originalUID && _session!=null)
        {
            _trackPlaylistCurrentIndex = _trackPlaylist.indexOf(_currentTrackUID);
            Track track = _tracks.get(uid);
            Bundle extras = new Bundle();
            extras.putParcelable("track", track);
            _session.sendSessionEvent("trackChanged", extras);
        }
    }

    @Override
    public void onPrepared(MediaPlayer mp)
    {
        _prepared = true;
        setPlaybackState(PlaybackStateCompat.STATE_BUFFERING, 0);
        _player.setLooping(false);
        _player.start();
        setPlaybackState(PlaybackStateCompat.STATE_PLAYING, 0);
    }

    private Track GetCurrentTrack()
    {
        return _tracks.get(_currentTrackUID);
    }

    //---------------------------


    public void setAudioClient(StreamingAudioClient bgp)
    {
        _streamingAudioClient = bgp;
    }

    @Override
    public void onCreate()
    {
        _audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        _player = new MediaPlayer();
        _player.setOnErrorListener(this);
        _player.setOnPreparedListener(this);
        _player.setOnCompletionListener(this);

        try
        {
            initMediaSessions();
            startNoisyReceiver();
        }
        catch (RemoteException e)
        {
            com.fuse.AndroidInteropHelper.UncheckedThrow(e);
        }
    }

    @Override
    public void onDestroy()
    {
        _session.setActive(false);
        _audioManager.abandonAudioFocus(this);
        stopNoisyReciever();
        _session.release();
        NotificationManagerCompat.from(this).cancel(ArtworkMediaNotification.ID);
        super.onDestroy();
    }

    private void initMediaSessions() throws RemoteException
    {
        _session = new MediaSessionCompat(getApplicationContext(), "FuseStreamingPlayerSession");
        _session.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);
        _session.setActive(true);

        _session.setCallback(new MediaSessionCompat.Callback()
        {
            @Override
            public void onPlay()
            {
                super.onPlay();
                if (tryTakeAudioFocus())
                {
                    if (_currentTrackUID>-1)
                    {
                        Resume();
                    }
                    else
                    {
                        Next();
                    }
                }
            }

            @Override
            public void onPause()
            {
                super.onPause();
                Pause();
            }

            @Override
            public void onSkipToNext()
            {
                super.onSkipToNext();
                Next();
            }

            @Override
            public void onSkipToPrevious()
            {
                super.onSkipToPrevious();
                Previous();
            }

            @Override
            public void onStop()
            {
                super.onStop();
                Stop();
            }

            @Override
            public void onSeekTo(long pos)
            {
                super.onSeekTo(pos);
                Seek((int) pos * 1000);
            }

            @Override
            public void onCustomAction(String action, Bundle extras)
            {
                super.onCustomAction(action, extras);
                if (action.equals("SetPlaylist"))
                {
                    SetPlaylist((Track[])extras.getParcelableArray("tracks"));
                }
                else if (action.equals("Forward"))
                {
                    Forward();
                }
                else if (action.equals("Backward"))
                {
                    Backward();
                }
            }
        });

        if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
        {
            Intent mediaButtonIntent = new Intent(Intent.ACTION_MEDIA_BUTTON);
            mediaButtonIntent.setClass(this, MediaButtonReceiver.class);
            PendingIntent pendingIntent = PendingIntent.getBroadcast(this, 0, mediaButtonIntent, 0);
            _session.setMediaButtonReceiver(pendingIntent);
        }
    }

    private boolean tryTakeAudioFocus()
    {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        int result = audioManager.requestAudioFocus(this, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
        return result == AudioManager.AUDIOFOCUS_GAIN;
    }

    private void setPlaybackState(int newState) // PlaybackStateCompat.STATE_YYY
    {
        setPlaybackState(newState, _player.getCurrentPosition());
    }

    public void KillNotificationPlayer()
    {
        // NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
        // notificationManager.cancel(ArtworkMediaNotification.ID);
        NotificationManagerCompat.from(this).cancel(ArtworkMediaNotification.ID);
    }

    private void setPlaybackState(int newState, int position) // PlaybackStateCompat.STATE_YYY
    {
        // Vars we can mutate for result
        AndroidPlayerState oldUnoState = _state;
        AndroidPlayerState unoState;
        int notifKeycode = -1;
        int notifIcon = -1;
        String notifText = "<invalid>";

        // Begin
        _playbackStateBuilder.setState(newState, position, 1f);

        switch (newState)
        {
            case PlaybackStateCompat.STATE_STOPPED:
            {
                unoState = AndroidPlayerState.Idle;
                break;
            }
            case PlaybackStateCompat.STATE_PAUSED:
            {
                unoState = AndroidPlayerState.Paused;
                notifKeycode = KeyEvent.KEYCODE_MEDIA_PLAY;
                notifIcon = android.R.drawable.ic_media_play;
                notifText = "MakeTrackCurrentByUID";
                break;
            }
            case PlaybackStateCompat.STATE_BUFFERING:
            {
                unoState = AndroidPlayerState.Preparing;
                break;
            }
            case PlaybackStateCompat.STATE_PLAYING:
            {
                unoState = AndroidPlayerState.Started;
                notifIcon = android.R.drawable.ic_media_pause;
                notifText = "Pause";
                notifKeycode = KeyEvent.KEYCODE_MEDIA_PAUSE;

                _playbackStateBuilder.setActions(PlaybackStateCompat.ACTION_PLAY |
                        PlaybackStateCompat.ACTION_PLAY_PAUSE |
                        PlaybackStateCompat.ACTION_PAUSE |
                        PlaybackStateCompat.ACTION_STOP |
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT |
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS |
                        PlaybackStateCompat.ACTION_SEEK_TO |
                        PlaybackStateCompat.ACTION_PLAY_FROM_URI);
                break;
            }
            default:
                return;
        }

        // update session
        _session.setPlaybackState(_playbackStateBuilder.build());
        UpdateMetadata();

        // and the notification if needed
        if (notifKeycode != -1)
        {
            Track track = GetCurrentTrack();
            if (track!=null)
            {
                UpdateMetadata();
                ArtworkMediaNotification.Notify(track, _session, this, notifIcon, notifText, notifKeycode);
            } else {
                KillNotificationPlayer();
            }
        }

        // and uno
        if (unoState != oldUnoState)
        {
            _state = unoState;
            _streamingAudioClient.OnInternalStatusChanged(unoState.toInt());
        }
    }

    private void UpdateMetadata()
    {
        if (GetCurrentTrack() != null)
        {
            _metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_TITLE, GetCurrentTrack().Name);
            _metadataBuilder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, GetCurrentTrack().Artist);
            _metadataBuilder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, (long)GetCurrentTrack().Duration);
            _session.setMetadata(_metadataBuilder.build());
        }
    }

    private BroadcastReceiver _noisyReceiver = new BroadcastReceiver()
    {
        @Override
        public void onReceive(Context context, Intent intent)
        {
            if (_player != null && _player.isPlaying())
                Pause();
        }
    };

    private void startNoisyReceiver()
    {
        IntentFilter filter = new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY);
        registerReceiver(_noisyReceiver, filter);
    }

    private void stopNoisyReciever()
    {
        unregisterReceiver(_noisyReceiver);
    }

    //
    // Actions
    //

    private void Resume()
    {
        if (_prepared)
        {
            if (_player.isPlaying())
            {
                _player.seekTo(0);
                setPlaybackState(PlaybackStateCompat.STATE_PLAYING, 0);
            }
            else
            {
                if (tryTakeAudioFocus())
                {
                    _player.start();
                    setPlaybackState(PlaybackStateCompat.STATE_PLAYING, _player.getCurrentPosition());
                }
            }
        }
    }

    private void Seek(int milliseconds)
    {
        if (_prepared)
        {
            _player.seekTo(milliseconds);
            // We dont use our setPlaybackState as we don't want to touch the notification
            int currentState = (int)_session.getController().getPlaybackState().getState();
            _playbackStateBuilder.setState(currentState, _player.getCurrentPosition(), 1f);
            _session.setPlaybackState(_playbackStateBuilder.build());
        }
    }

    private void Next()
    {
        MakeTrackCurrentByUID(MoveToNextPlaylistTrack());
    }

    private void Previous()
    {
        MakeTrackCurrentByUID(MoveToPrevPlaylistTrack());
    }

    private void Forward()
    {
        MakeTrackCurrentByUID(MoveForwardInHistory());
    }

    private void Backward()
    {
        MakeTrackCurrentByUID(MoveBackInHistory());
    }

    private void Pause()
    {
        if (_state == AndroidPlayerState.Started)
        {
            _player.pause();
            setPlaybackState(PlaybackStateCompat.STATE_PAUSED);
        }
    }

    private void Stop()
    {
        _prepared = false;
        _player.stop();
        _player.reset();
        _audioManager.abandonAudioFocus(this);
        setPlaybackState(PlaybackStateCompat.STATE_STOPPED, 0);
        //
        KillNotificationPlayer();
        // {TODO} why stop the service?
        Intent intent = new Intent(getApplicationContext(), StreamingAudioService.class);
        stopService(intent);
        //
        MakeTrackCurrentByUID(-1);
    }

    //
    // Events
    //

    @Override
    public void onCompletion(MediaPlayer mp)
    {
        Next();
    }

    @Override
    public boolean onError(MediaPlayer mp, int what, int extra)
    {
        // {TODO} move to error state?
        return true;
    }

    @Override
    public void onAudioFocusChange(int focusChange)
    {
        switch (focusChange)
        {
            case AudioManager.AUDIOFOCUS_LOSS:
            {
                if (_player.isPlaying())
                    Stop();
                break;
            }
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
            {
                Pause();
                break;
            }
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
            {
                if (_player != null)
                    _player.setVolume(0.3f, 0.3f);
                break;
            }
            case AudioManager.AUDIOFOCUS_GAIN:
            {
                if (_player != null)
                {
                    if (!_player.isPlaying())
                        Resume();
                    _player.setVolume(1.0f, 1.0f);
                }
                break;
            }
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId)
    {
        // Simply routes everything through to the media session callback
        // then all we have to do is control everything via MEDIA_BUTTON events
        // (this is the recommended googly way)
        MediaButtonReceiver.handleIntent(_session, intent);
        return super.onStartCommand(intent, flags, startId);
    }

    //
    // Binder
    //
    public class LocalBinder extends Binder
    {
        public StreamingAudioService getService()
        {
            // Return this instance of LocalService so clients can call public methods
            return StreamingAudioService.this;
        }
    }

    @Override
    public IBinder onBind(Intent intent)
    {
        return _binder;
    }


    @Override
    public boolean onUnbind(Intent intent)
    {
        _session.release();
        return super.onUnbind(intent);
    }

    // Interfaces
    public static abstract class StreamingAudioClient extends MediaControllerCompat.Callback
    {
        private MediaControllerCompat _controller;
        private PlaybackStateCompat _lastPlayerState;
        private Track _currentTrack = null;

        public abstract void OnCurrentTrackChanged(Track track);
        public abstract void OnInternalStatusChanged(int i);

        public StreamingAudioClient(StreamingAudioService service) throws RemoteException
        {
            _controller = new MediaControllerCompat(service.getApplicationContext(), service._session.getSessionToken());
            _controller.registerCallback(this);
        }

        public final void Play()
        {
            _controller.getTransportControls().play();
        }

        public final void Pause()
        {
            _controller.getTransportControls().pause();
        }

        public final void Stop()
        {
            _controller.getTransportControls().stop();
        }

        public final void Next()
        {
            _controller.getTransportControls().skipToNext();
        }

        public final void Previous()
        {
            _controller.getTransportControls().skipToPrevious();
        }

        public final void Forward()
        {
            _controller.getTransportControls().sendCustomAction("Forward", new Bundle());
        }

        public final void Backward()
        {
            _controller.getTransportControls().sendCustomAction("Backward", new Bundle());
        }

        public final void Seek(long position)
        {
            _controller.getTransportControls().seekTo(position);
        }

        public final double GetCurrentPosition()
        {
            if (_lastPlayerState == null)
            {
                return 0;
            }
            else
            {
                long currentPosition = _lastPlayerState.getPosition();
                if (_lastPlayerState.getState() != PlaybackStateCompat.STATE_PAUSED)
                {
                    long timeDelta = SystemClock.elapsedRealtime() - _lastPlayerState.getLastPositionUpdateTime();
                    currentPosition += (int) timeDelta * _lastPlayerState.getPlaybackSpeed();
                }
                return currentPosition / 1000.0;
            }
        }

        public void SetPlaylist(Track[] tracks)
        {
            Bundle bTrack = new Bundle();
            bTrack.putParcelableArray("tracks", tracks);
            _controller.getTransportControls().sendCustomAction("SetPlaylist", bTrack);
        }

        @Override
        public void onPlaybackStateChanged(PlaybackStateCompat state)
        {
            super.onPlaybackStateChanged(state);
            _lastPlayerState = state;
        }

        @Override
        public void onSessionEvent(String event, Bundle extras)
        {
            super.onExtrasChanged(extras);

            if (event.equals("trackChanged"))
            {
                _currentTrack = (Track)extras.getParcelable("track");
                OnCurrentTrackChanged(_currentTrack);
            }
        }

        public final double GetCurrentTrackDuration()
        {
            if (_currentTrack != null)
                return _currentTrack.Duration;
            else
                return 0;
        }
    }
}
