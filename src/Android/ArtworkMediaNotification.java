package com.fuse.StreamingPlayer;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.session.MediaSession;
import android.os.AsyncTask;
import android.support.v4.view.KeyEventCompat;
import android.support.v7.app.NotificationCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.view.KeyEvent;

import java.io.IOException;
import java.net.URL;

public final class ArtworkMediaNotification
{
    private class DownloadArtworkBitmapTask extends AsyncTask<String, Void, Bitmap>
    {

        protected Bitmap doInBackground(String... urls)
        {
            if (urls.length > 0)
            {
                try
                {
                    URL url = new URL(urls[0]);
                    Bitmap myBitmap = BitmapFactory.decodeStream(url.openConnection().getInputStream());
                    return myBitmap;
                }
                catch (IOException e)
                {
                    Logger.Log("We were not able to get a bitmap of the artwork");
                }
            }
            return null;
        }

        protected void onPostExecute(Bitmap result)
        {
            if (result != null)
            {
                setArtworkBitmap(result);
            }
        }
    }

    private Track _currentTrack;
    private MediaSessionCompat _session;
    private StreamingAudioService _service;
    private int _primaryActionIcon;
    private String _primaryActionTitle;
    private int _primaryActionKeyEvent;

    private ArtworkMediaNotification(Track track, MediaSessionCompat session, StreamingAudioService service, String urlStr,
                                     int primaryActionIcon, String primaryActionTitle, int primaryActionKeyEvent)
    {
        _session = session;
        _currentTrack = track;
        _service = service;
        _primaryActionIcon = primaryActionIcon;
        _primaryActionTitle = primaryActionTitle;
        _primaryActionKeyEvent = primaryActionKeyEvent;
        new DownloadArtworkBitmapTask().execute(urlStr);
    }

    public void setArtworkBitmap(Bitmap bmp)
    {
        //This lets the album art be visible as the background while in the lock screen
        MediaMetadataCompat.Builder metadataBuilder = new MediaMetadataCompat.Builder();
        metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp);
        _session.setMetadata(metadataBuilder.build());

        // Time to make the notifications
        NotificationCompat.Builder builder = MediaStyleHelper.makeBuilder(_service, _session);

        // style
        NotificationCompat.MediaStyle style = new NotificationCompat.MediaStyle().setMediaSession(_session.getSessionToken());
        style.setShowActionsInCompactView(0, 1, 2, 3, 4);
        builder.setStyle(style);

        // icon
        builder.setSmallIcon(android.R.drawable.ic_media_play);
        if (bmp != null)
            builder.setLargeIcon(bmp);

        // actions
        builder.addAction(generateAction(android.R.drawable.ic_media_previous, "Previous", KeyEvent.KEYCODE_MEDIA_PREVIOUS));
        builder.addAction(generateAction(_primaryActionIcon, _primaryActionTitle, _primaryActionKeyEvent));
        builder.addAction(generateAction(android.R.drawable.ic_media_next, "Next", KeyEvent.KEYCODE_MEDIA_NEXT));

        // dispatch
        NotificationManager notificationManager = (NotificationManager) _service.getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(1, builder.build());
    }

    public NotificationCompat.Action generateAction(int icon, String title, int mediaKeyEvent)
    {
        // mediaKeyEvent should be something like KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        return new NotificationCompat.Action(icon, title, MediaStyleHelper.getActionIntent(_service, mediaKeyEvent));
    }

    public static void Notify(Track track, MediaSessionCompat session, StreamingAudioService service,
                              int primaryActionIcon, String primaryActionTitle, int primaryActionKeyEvent)
    {
        //Async task for getting artwork bitmap and assigning it to the media session
        new ArtworkMediaNotification(track, session, service, track.ArtworkUrl, primaryActionIcon, primaryActionTitle, primaryActionKeyEvent);
    }
}
