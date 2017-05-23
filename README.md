# LibCamera
A World of Warcraft library addon for applying camera motion in a smooth manner using easing functions.

## Usage:
As with any LibStub based libary, get a library access object first
```
local LibCamera = LibStub("LibCamera-1.0");
```
### LibCamera:SetZoom(endValue, duration\[, easingFunc\]\[, callback\])
Starts zooming to `endValue` over `duration` using an optional `easingFunc`, calling the optional `callback` once done

If `easingFunc` is not given, a quadratic in/out easing function is used

`LibCamera:SetZoom(5, 1); -- sets the zoom to 5 yards away from character over a second` 
### LibCamera:SetZoomUsingCVar(endValue, duration\[, callback\])
Uses `CameraZoomIn` or `CameraZoomOut` to set the camera zoom to `endValue` over `duration`, calling the optional `callback` once done

This will set the `CameraZoomSpeed` console variable before it starts zooming, and will set it back to it's original value when the zoom is finished.

Normally, you would use the normal `SetZoom` function, but there are points where it can be inaccurate due to undetectable (but mostly predictable) changes in the camera engine within WoW

### LibCamera:IsZooming()
Returns true if LibCamera is currently zooming

### LibCamera:StopZooming()
Stop any LibCamera zoom (and any zoom pending in World of Warcraft)

### LibCamera:Yaw(endValue, duration\[, easingFunc\]\[, callback\])
Starts yawing the camera by `endValue` over `duration` using an optional `easingFunc`, calling the optional `callback` once done

Positive values of `endValue` yaw the camera right, while negative values pitch the camera left

If `easingFunc` is not given, a quadratic in/out easing function is used

Will stop any previous yawing of the camera
`LibCamera:Yaw(90, 1); -- yaw the camera 90 degrees to the right over a second`

### LibCamera:BeginContinuousYaw(endSpeed, duration)
Begin continously yawing (positive speed, right; negative speed, left), starts at 0 speed and goes to `endSpeed` linearly over the provided duration

### LibCamera:IsYawing()
Returns true if LibCamera is currently yawing

### LibCamera:StopYawing()
Stops any yaw actions that LibCamera is executing (and any continuous yawing in WoW) and, if this cancels an existing yaw action, return the estimated number of degrees that has been covered

### LibCamera:Pitch(endValue, duration\[, easingFunc\]\[, callback\])
Starts pitching the camera by `endValue` over `duration` using an optional `easingFunc`, calling the optional `callback` once done

Positive values of `endValue` pitch the camera up (away from ground), while negative values pitch the camera down (towards ground)

If `easingFunc` is not given, a quadratic in/out easing function is used

Will stop any previous pitching of the camera

`LibCamera:Pitch(20, 1); -- yaw the camera 20 degrees up over a second`

### LibCamera:IsPitching()
Returns true if LibCamera is currently pitching

### LibCamera:StopPitching()
Stops any pitch actions that LibCamera is executing (and any continuous pitching in WoW) and, if this cancels an existing pitch action, return the estimated number of degrees that has been covered

### LibCamera:IsRotating()
Returns true if LibCamera is currently pitching or yawing

### LibCamera:StopRotating()
Stops any pitch or yaw actions that LibCamera is executing (and any continuous pitching/yawing in WoW) and returns any canceled yaw/pitch degrees
`local yaw, pitch = LibCamera:StopRotation()`