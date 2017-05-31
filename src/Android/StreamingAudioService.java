package com.fuse.StreamingPlayer;

import android.app.NotificationManager;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Binder;
import android.os.IBinder;
import android.os.RemoteException;
import android.support.v4.app.NotificationManagerCompat;
import android.support.v4.media.session.MediaButtonReceiver;
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
    AndroidPlayerState _state = AndroidPlayerState.Idle; // TODO can we merge this with android's state stuff?
    boolean _prepared = false;

    // Uno interaction
    StreamingAudioClient _streamingAudioClient;
    ArrayList<Track> _playlist = new ArrayList<Track>();
    Track _currentTrack;


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
            public boolean onMediaButtonEvent(Intent mediaButtonEvent)
            {
                return super.onMediaButtonEvent(mediaButtonEvent);
            }

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
                Logger.Log("Skipping from media notification: " + _currentTrack.Name);
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
        });
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

        // and the notification if needed
        if (notifKeycode != -1)
            ArtworkMediaNotification.Notify(_currentTrack, _session, this, notifIcon, notifText, notifKeycode);

        // and uno
        if (unoState != oldUnoState)
        {
            _state = unoState;
            _streamingAudioClient.OnInternalStatusChanged(unoState.toInt());
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


    public int CurrentTrackIndex()
    {
        return _playlist.indexOf(_currentTrack);
    }

    public double GetCurrentPosition()
    {
        if (_prepared)
        {
            return _player.getCurrentPosition();
        }
        return 0.0;
    }

    public double GetCurrentTrackDuration()
    {
        if (_prepared)
        {
            return _player.getDuration();
        }
        return 0.0;
    }

    public Track GetCurrentTrack()
    {
        return _currentTrack;
    }

    public boolean HasNext()
    {
        int currentIndex = CurrentTrackIndex();
        int playlistSize = _playlist.size();
        return currentIndex > -1 && currentIndex < playlistSize - 1;
    }

    public boolean HasPrevious()
    {
        int currentIndex = CurrentTrackIndex();
        return currentIndex > 0;
    }

    //
    // Actions
    //

    public void Play(Track track)
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

        _currentTrack = track;
        if (_streamingAudioClient != null)
        {
            _streamingAudioClient.OnCurrentTrackChanged();
            _streamingAudioClient.OnHasPrevNextChanged();
        }
    }

    public void Resume()
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

    public void Seek(int milliseconds)
    {
        if (_prepared)
        {
            _player.seekTo(milliseconds);
        }
    }

    public void SetPlaylist(Track[] tracks)
    {
        _playlist.clear();
        Collections.addAll(_playlist, tracks);
        _streamingAudioClient.OnHasPrevNextChanged();
    }

    public void AddTrack(Track track)
    {
        _playlist.add(track);
    }

    public void Next()
    {
        if (HasNext())
        {
            Play(_playlist.get(CurrentTrackIndex() + 1));
        }
        _streamingAudioClient.OnHasPrevNextChanged();
    }

    public void Previous()
    {
        if (HasPrevious())
        {
            Play(_playlist.get(CurrentTrackIndex() - 1));
        }
        _streamingAudioClient.OnHasPrevNextChanged();
    }

    public void Pause()
    {
        if (_state == AndroidPlayerState.Started)
        {
            _player.pause();
            setPlaybackState(PlaybackStateCompat.STATE_PAUSED);
        }
    }

    public void Stop()
    {
        _prepared = false;
        _player.stop();
        _player.reset();
        _audioManager.abandonAudioFocus(this);
        setPlaybackState(PlaybackStateCompat.STATE_STOPPED, 0);
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

    //
    // Events received from controls or other systems
    //
    // Simply routes everything through to the media session callback
    // then all we have to do is control everything via MEDIA_BUTTON events
    // (this is the recommended googly way
    //
    @Override
    public int onStartCommand(Intent intent, int flags, int startId)
    {
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
    public interface StreamingAudioClient
    {
        void OnStatusChanged();

        void OnHasPrevNextChanged();

        void OnCurrentTrackChanged();

        void OnInternalStatusChanged(int i);
    }
}
