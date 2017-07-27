package com.fuse.StreamingPlayer;

import android.app.NotificationManager;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.AsyncTask;
import android.support.v7.app.NotificationCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.view.KeyEvent;

import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;

public final class ArtworkMediaNotification
{
    static String _cachedArtworkURL = null;
    static Bitmap _cachedArtwork = null;

    static void FreeCached()
    {
        _cachedArtwork.recycle();
        _cachedArtwork = null;
    }

    static boolean IsRemoteFile(String url)
    {
        try
        {
            URI u = new URI(url);
            return "http".equalsIgnoreCase(u.getScheme())
                    || "https".equalsIgnoreCase(u.getScheme());
        }
        catch (URISyntaxException e)
        {
            return false;
        }
    }

    private class DownloadArtworkBitmapTask extends AsyncTask<String, Void, Bitmap>
    {
        protected Bitmap doInBackground(String... urls)
        {
            if (urls.length > 0)
            {
                String urlStr = urls[0];
                if (_cachedArtworkURL !=null && _cachedArtworkURL.equals(urlStr))
                {
                    return _cachedArtwork;
                }
                else if (IsRemoteFile(urlStr))
                {
                    return LoadRemote(urlStr);
                }
                else
                {
                    return LoadLocal(urlStr);
                }
            }
            return null;
        }

        Bitmap LoadRemote(String urlStr)
        {
            try
            {
                URL url = new URL(urlStr);
                Bitmap myBitmap = BitmapFactory.decodeStream(url.openConnection().getInputStream());
                _cachedArtwork = myBitmap;
                _cachedArtworkURL = urlStr;
                return myBitmap;
            }
            catch (IOException e)
            {
                Logger.Log("We were not able to get a bitmap of the artwork");
                return null;
            }
        }

        Bitmap LoadLocal(String urlStr)
        {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
            return BitmapFactory.decodeFile(urlStr, options);
        }

        protected void onPostExecute(Bitmap result)
        {
            if (result != null)
            {
                setArtworkBitmap(result);
            }
        }
    }

    private MediaSessionCompat _session;
    private StreamingAudioService _service;
    private int _primaryActionIcon;
    private String _primaryActionTitle;
    private int _primaryActionKeyEvent;
    private MediaMetadataCompat.Builder _metadataBuilder;

    private ArtworkMediaNotification(MediaMetadataCompat metadata, MediaSessionCompat session, StreamingAudioService service, String urlStr,
                                     int primaryActionIcon, String primaryActionTitle, int primaryActionKeyEvent)
    {
        _session = session;
        _service = service;
        _primaryActionIcon = primaryActionIcon;
        _primaryActionTitle = primaryActionTitle;
        _primaryActionKeyEvent = primaryActionKeyEvent;
        _metadataBuilder = new MediaMetadataCompat.Builder(metadata);
        if (urlStr!=null)
        {
            new DownloadArtworkBitmapTask().execute(urlStr);
        }
        else
        {
            setArtworkBitmap(null);
        }
    }

    public void setArtworkBitmap(Bitmap bmp)
    {
        // Time to make the notifications
        NotificationCompat.Builder builder = MediaStyleHelper.makeBuilder(_service, _session);

        // actions
        builder.addAction(generateAction(android.R.drawable.ic_media_previous, "Previous", KeyEvent.KEYCODE_MEDIA_PREVIOUS));
        builder.addAction(generateAction(_primaryActionIcon, _primaryActionTitle, _primaryActionKeyEvent));
        builder.addAction(generateAction(android.R.drawable.ic_media_next, "Next", KeyEvent.KEYCODE_MEDIA_NEXT));

        // style
        NotificationCompat.MediaStyle style = new NotificationCompat.MediaStyle().setMediaSession(_session.getSessionToken());
        style.setShowActionsInCompactView(0, 1, 2); // indexed into the actions above by order they were added :/ ew
        builder.setStyle(style);

        // icon
        builder.setSmallIcon(android.R.drawable.ic_media_play);
        if (bmp != null)
        {
            builder.setLargeIcon(bmp);
            //This lets the album art be visible as the background while in the lock screen
            _metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp);
            _session.setMetadata(_metadataBuilder.build());
        }

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
        new ArtworkMediaNotification(service._metadataBuilder.build(), session, service, track.ArtworkUrl, primaryActionIcon, primaryActionTitle, primaryActionKeyEvent);
    }
}
