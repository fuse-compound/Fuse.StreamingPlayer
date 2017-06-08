var Observable = require("FuseJS/Observable");
var MediaQuery = require("FuseJS/MediaQuery");
var StreamingPlayer = require("FuseJS/StreamingPlayer");

var tracks = Observable();

var paramObs = this.Parameter.onValueChanged(module, function(param) {
    MediaQuery.tracks({ "artist": param["artistID"] }).then(function(tracksArray) {
		var tmp = tracksArray.map(function(track, index) {
			return {
				"id": index,
				"name": track["title"],
				"artist": track["artist"],
				"url": track["path"],
				"artworkUrl":"https://everyweeks.com/pZ2j56doGB6c0ykra8lXMj7nuNTDsT79-logo.png",
				"duration": track["duration"]
			};
		});
        tracks.addAll(tmp);
		StreamingPlayer.setPlaylist(tmp);
		// StreamingPlayer.resume();
		// StreamingPlayer.play(tmp[0]);
    }).catch(function(e) {
        console.log("Well damn:" + e);
    });
});

var backClicked = function() {
    // stop stuff
	StreamingPlayer.stop();
    router.goto("artists");
};

var prevClicked = function() {
    StreamingPlayer.previous();
};

var nextClicked = function() {
	StreamingPlayer.next();
};

module.exports = {
    backClicked: backClicked,
	prevClicked: prevClicked,
	nextClicked: nextClicked,
    tracks: tracks
};
