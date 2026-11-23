/// Camera Live capture is unavailable until camera validation succeeds.
/// Keep archived files and the ordinary camera viewfinder unchanged.
bool get cameraLiveAvailable => false;
const cameraLiveUnavailableMessage = 'Live 暂不可用';
