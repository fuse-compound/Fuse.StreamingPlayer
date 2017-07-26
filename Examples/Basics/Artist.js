var Observable = require("FuseJS/Observable");
var MediaQuery = require("FuseJS/MediaQuery");

var artists = Observable({"name":"jim"});

var refreshClicked = function() {
	artists.clear();
	MediaQuery.artists({}).then(function(artistArray) {
		console.log("results: " + JSON.stringify(artistArray));
		artists.addAll(artistArray);
	}).catch(function(e) {
		console.log("Well damn:" + e);
	});
};

var trackClicked = function(item) {
	console.log("play all of: " + JSON.stringify(item.data.name));
	router.goto("play", { "artistID" : item.data.name });
};

module.exports = {
	artists: artists,
	refreshClicked: refreshClicked,
	trackClicked: trackClicked
};
