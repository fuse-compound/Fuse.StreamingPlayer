var StreamingPlayer = require("FuseJS/StreamingPlayer");
var Observable = require('FuseJS/Observable');
var Timer = require("FuseJS/Timer");

//-------------------------------

var progress = Observable(0.0);
var isInteracting = false;
var duration = Observable(0.0);
var sliderValue = Observable(0.0);
var endInteractionTimeout = null;
var timer = null;

function deleteTimer(){
	if (timer !== null)
		Timer.delete(timer);
}

function createNewTimer() {
	deleteTimer();
	timer = Timer.create(function() {
		if (!isInteracting) {
			duration.value = StreamingPlayer.duration;
			progress.value = StreamingPlayer.progress;
		}
	}, 100, true);
}

//-------------------------------

var interacting = function() {
	console.log("interacting");
	if (endInteractionTimeout !== null) {
		console.log("interacting: clearTimeout");
		clearTimeout(endInteractionTimeout);
	}
	isInteracting = true;
};


var seekToSliderValue = function() {
	if (isInteracting) {
		console.log("seekToSliderValue");
		if (sliderValue.value)
		{
			console.log("seekToSliderValue: " + sliderValue.value);
			StreamingPlayer.seek(sliderValue.value);
		}
		endInteractionTimeout = setTimeout(function() {
			isInteracting = false;
		}, 500);
	}
};

progress.addSubscriber(function(x) {
	if (isInteracting || duration.value==0)
		return;
	var ret = x.value / duration.value;
	console.log("progress callback - progress: " + x.value + "setting slider to: " + ret);
	sliderValue.value = ret;
});

sliderValue.onValueChanged(function(val) {
	if (isInteracting)
	{
		var newVal = (val * duration.value);
		console.log("slideValue changed: setting progress to " + newVal);
		progress.value = newVal;
	}
});

timer = createNewTimer();

module.exports = {
	seekToSliderValue : seekToSliderValue,
	interacting : interacting,
	isInteracting : isInteracting,
	sliderValue : sliderValue
};
