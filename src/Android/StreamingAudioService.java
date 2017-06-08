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
import android.support.v4.app.BundleCompat;
import android.support.v4.app.NotificationManagerCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaButtonReceiver;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.view.KeyEvent;

import java.util.ArrayList;
import java.util.Collections;

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
    AndroidPlayerState _state = AndroidPlayerState.Idle; // TODO can we merge this with android's state stuff?
    boolean _prepared = false;

    // Uno interaction
    StreamingAudioClient _streamingAudioClient;
    ArrayList<Track> _playlist = new ArrayList<Track>();
    Track _currentTrack;

    public synchronized Track GetCurrentTrack()
    {
        return _currentTrack;
    }
    public synchronized void SetCurrentTrack(Track track)
    {
        _currentTrack = track;
    }

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
        NotificationManagerCompat.from(this).cancel(1);
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
                    Resume();
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
                Logger.Log("Skipping from media notification: " + GetCurrentTrack().Name);
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
                NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
                notificationManager.cancel(1);
                Intent intent = new Intent(getApplicationContext(), StreamingAudioService.class);
                stopService(intent);
            }

            @Override
            public void onSeekTo(long pos)
            {
                super.onSeekTo(pos);
                Seek((int) pos);
            }

            @Override
            public void onCustomAction(String action, Bundle extras)
            {
                super.onCustomAction(action, extras);
                if (action.equals("Resume"))
                {
                    Resume();
                }
                else if (action.equals("PlayTrack"))
                {
                    Play((Track) extras.getParcelable("track"));
                }
                else if (action.equals("SetPlaylist"))
                {
                    SetPlaylist((Track[])extras.getParcelableArray("tracks"));
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
                notifKeycode = KeyEvent.KEYCODE_MEDIA_PLAY;
                notifIcon = android.R.drawable.ic_media_play;
                notifText = "Play";
                break;
            }
            case PlaybackStateCompat.STATE_PAUSED:
            {
                unoState = AndroidPlayerState.Paused;
                notifKeycode = KeyEvent.KEYCODE_MEDIA_PLAY;
                notifIcon = android.R.drawable.ic_media_play;
                notifText = "Play";
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
            UpdateMetadata();
            ArtworkMediaNotification.Notify(GetCurrentTrack(), _session, this, notifIcon, notifText, notifKeycode);
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

    private void Play(Track track)
    {
        if (_prepared)
        {
            _prepared = false;
            _player.stop();
            _player.reset();
        }
        try
        {
            _player.reset();
            _state = AndroidPlayerState.Initialized;
            Logger.Log("SetDataSource: state: " + _state);
            _player.setDataSource(track.Url);
            setPlaybackState(PlaybackStateCompat.STATE_BUFFERING, 0);
            _player.prepareAsync();
        }
        catch (Exception e)
        {
            Logger.Log("Exception while setting MediaPlayer DataSource");
        }

        SetCurrentTrack(track);
    }

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
        }
    }

    private void SetPlaylist(Track[] tracks)
    {
        _playlist.clear();
        Collections.addAll(_playlist, tracks);
    }

    private void AddTrack(Track track)
    {
        _playlist.add(track);
    }

    private void Next()
    {
        if (HasNext())
        {
            Play(_playlist.get(CurrentTrackIndex() + 1));
        }
    }

    private void Previous()
    {
        if (HasPrevious())
        {
            Play(_playlist.get(CurrentTrackIndex() - 1));
        }
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
    }

    //
    // Public Functions
    //
    // These will need to be removed. See the note in the StreamingAudioClient class for why
    // these exist.
    //

    public synchronized int CurrentTrackIndex()
    {
        return _playlist.indexOf(GetCurrentTrack());
    }

    public synchronized double GetCurrentTrackDuration()
    {
        if (_prepared)
        {
            return _player.getDuration();
        }
        return 0.0;
    }

    public synchronized boolean HasNext()
    {
        int currentIndex = CurrentTrackIndex();
        int playlistSize = _playlist.size();
        return currentIndex > -1 && currentIndex < playlistSize - 1;
    }

    public synchronized boolean HasPrevious()
    {
        int currentIndex = CurrentTrackIndex();
        return currentIndex > 0;
    }

    //
    // Events
    //

    @Override
    public void onPrepared(MediaPlayer mp)
    {
        _prepared = true;
        setPlaybackState(PlaybackStateCompat.STATE_BUFFERING, 0);
        _player.setLooping(false);
        _player.start();
        setPlaybackState(PlaybackStateCompat.STATE_PLAYING, 0);
    }

    @Override
    public void onCompletion(MediaPlayer mp)
    {
        Logger.Log("Android track completed");
        Next();
    }

    @Override
    public boolean onError(MediaPlayer mp, int what, int extra)
    {
        Logger.Log("Error while mediaplayer in state: " + _state);
        Logger.Log("We did get an error: what:" + what + ", extra:" + extra);
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
        private StreamingAudioService _service;  // {TODO} See note below in
        private PlaybackStateCompat _lastPlayerState;

        public abstract void OnCurrentTrackChanged();
        public abstract void OnInternalStatusChanged(int i);

        public StreamingAudioClient(StreamingAudioService service) throws RemoteException
        {
            _service = service; // {TODO} See note below in
            _controller = new MediaControllerCompat(service.getApplicationContext(), service._session.getSessionToken());
            _controller.registerCallback(this);
        }

        public final void Play(Track track)
        {
            Bundle bTrack = new Bundle();
            bTrack.putParcelable("track", track);
            _controller.getTransportControls().sendCustomAction("PlayTrack", bTrack);
        }

        public final void Resume()
        {
            _controller.getTransportControls().sendCustomAction("Resume", null);
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

        public final void Seek(long position)
        {
            _controller.getTransportControls().seekTo(position);
        }

        public final double GetCurrentPosition()
        {
            long currentPosition = _lastPlayerState.getPosition();
            if (_lastPlayerState.getState() != PlaybackStateCompat.STATE_PAUSED) {
                long timeDelta = SystemClock.elapsedRealtime() - _lastPlayerState.getLastPositionUpdateTime();
                currentPosition += (int) timeDelta * _lastPlayerState.getPlaybackSpeed();
            }
            return currentPosition;
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

        //
        // {TODO} This sucks, we are force to do this hacky stuff as the playlist is not controlled
        //        by the android api.
        //        What I want to do is use the MediaSession's queue so that we dont have to manage
        //        it, we dont need our own track items and also so things work with more google
        //        systems.
        //        However android's QueueItem is final and is missing a bunch of data we want
        //        (e.g. artist). This means we still need to keep our own playlist so we have
        //        the details we need to populate the metadata. If we only allowed local files then
        //        we wouldnt need to provide our own metadata as we could use the metadata querying
        //        system of the platform, however we also need streaming from the web.
        //
        //        I'm pretty sick on android audio right now and just want to get a v1 out. We can
        //        revisit this over time to make is solid
        //

        public final int CurrentTrackIndex()
        {
            return _service.CurrentTrackIndex();
        }

        public final Track GetCurrentTrack()
        {
            return _service.GetCurrentTrack();
        }

        public final double GetCurrentTrackDuration()
        {
            return _service.GetCurrentTrackDuration();
        }

        public final boolean HasNext()
        {
            return _service.HasNext();
        }

        public final boolean HasPrevious()
        {
            return _service.HasPrevious();
        }
    }
}
