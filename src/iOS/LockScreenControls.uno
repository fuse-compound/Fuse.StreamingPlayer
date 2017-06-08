using Uno;
using Uno.UX;
using Uno.Threading;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    [ForeignInclude(Language.ObjC, "AVFoundation/AVFoundation.h")]
    [ForeignInclude(Language.ObjC, "MediaPlayer/MediaPlayer.h")]
    [ForeignInclude(Language.ObjC, "AudioToolbox/AudioToolbox.h")]
    [Require("Xcode.Framework", "MediaPlayer")]
    [Require("Xcode.Plist.Element", "<key>UIBackgroundModes</key><array><string>audio</string></array>")]
    extern(iOS) static class LockScreenMediaControlsiOSImpl
    {
        static bool _initialized = false;

        static public void Init()
        {
            if (_initialized) return;

            debug_log("Registering handlers");
            RegisterHandlers(Next,Previous,Play,Pause,Seek);
            StreamingPlayer.HasNextChanged += OnHasNextChanged;
            StreamingPlayer.HasPreviousChanged += OnHasPreviousChanged;
            _initialized = true;
        }

        static void OnHasPreviousChanged(bool has)
        {
            if (has)
                ShowPreviousButton();
            else
                HidePreviousButton();
        }


        static void OnHasNextChanged(bool has)
        {
            if (has)
                ShowNextButton();
            else
                HideNextButton();
        }

        static void Next()
        {
            StreamingPlayer.Next();
        }
        static void Previous()
        {
            StreamingPlayer.Previous();
        }


        static void Play()
        {
            StreamingPlayer.Resume();
        }

        static void Pause()
        {
            StreamingPlayer.Pause();
        }

        static void Seek(double posInSec)
        {
            debug_log("seek from lock screen");
            var duration = StreamingPlayer.Duration;
            if (duration == 0.0)
                return;
            var progress = posInSec / duration;
            StreamingPlayer.Seek(progress);
        }

        [Foreign(Language.ObjC)]
        static void HidePreviousButton()
        @{
            MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
            commandCenter.previousTrackCommand.enabled = false;
        @}

        [Foreign(Language.ObjC)]
        static void ShowPreviousButton()
        @{
            MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
            commandCenter.previousTrackCommand.enabled = true;
        @}

        [Foreign(Language.ObjC)]
        static void HideNextButton()
        @{
            MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
            commandCenter.nextTrackCommand.enabled = false;
        @}

        [Foreign(Language.ObjC)]
        static void ShowNextButton()
        @{
            MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
            commandCenter.nextTrackCommand.enabled = true;
        @}

        [Foreign(Language.ObjC)]
        static void RegisterHandlers(Action next, Action previous, Action play, Action pause, Action<double> seek)
        @{
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];

            NSError *setCategoryError = nil;
            BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];
            if (!success) { NSLog(@"Error setting category"); }

            NSError *activationError = nil;
            success = [audioSession setActive:YES error:&activationError];
            if (!success) { NSLog(@"Error setting active audio session"); }


            MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
            [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
                NSLog(@"Play button pressed");
                play();
                return MPRemoteCommandHandlerStatusSuccess;
            }];
            [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
                NSLog(@"Pause button pressed");
                pause();
                return MPRemoteCommandHandlerStatusSuccess;
            }];
            [commandCenter.nextTrackCommand addTargetWithHandler:^(MPRemoteCommandEvent *event) {
                // Begin playing the current track.
                NSLog(@"Remote control: next track command");
                next();
                return MPRemoteCommandHandlerStatusSuccess;
            }];
            [commandCenter.previousTrackCommand addTargetWithHandler:^(MPRemoteCommandEvent *event) {
                // Begin playing the current track.
                NSLog(@"Remote control: previous track command");
                previous();
                return MPRemoteCommandHandlerStatusSuccess;
            }];

            //NSLog(@"current API iOS Version: %f", NSFoundationVersionNumber);
            //NSLog(@"required API iOS Version: %f", NSFoundationVersionNumber_iOS_9_0);
            NSOperatingSystemVersion ios9_0_0 = (NSOperatingSystemVersion){9, 0, 0};
            if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios9_0_0]) {
                [commandCenter.changePlaybackPositionCommand addTargetWithHandler:^(MPRemoteCommandEvent *event) {
                        MPChangePlaybackPositionCommandEvent* seekEvent = (MPChangePlaybackPositionCommandEvent*)event;
                        NSTimeInterval posTime = seekEvent.positionTime;
                        //NSLog(@"Remote control: seek to pos command: %f", posTime);
                        seek(posTime);
                        return MPRemoteCommandHandlerStatusSuccess;
                    }];
            }
        @}
    }
}
