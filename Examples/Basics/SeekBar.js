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
	if (endInteractionTimeout !== null)
		clearTimeout(endInteractionTimeout);
	isInteracting = true;
};


var seekToSliderValue = function() {
	if (!isInteracting)
		return;
	if (sliderValue.value)
		StreamingPlayer.seek(sliderValue.value);
	endInteractionTimeout = setTimeout(function() { isInteracting = false; }, 500);
};

progress.addSubscriber(function(x) {
	if (isInteracting || duration.value==0)
		return;
	sliderValue.value = (x.value / duration.value);
});

sliderValue.onValueChanged(function(val) {
	if (isInteracting)
		progress.value = (val * duration.value);;
});

timer = createNewTimer();

module.exports = {
	seekToSliderValue : seekToSliderValue,
	interacting : interacting,
	isInteracting : isInteracting,
	sliderValue : sliderValue
};
