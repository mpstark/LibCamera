---------------
-- LIBCAMERA --
---------------
local MAJOR, MINOR = "LibCamera-1.0", 3;
local LibCamera = LibStub:NewLibrary(MAJOR, MINOR);

if (not LibCamera) then
    return;
end

LibCamera.frame = LibCamera.frame or CreateFrame("Frame");


------------
-- LOCALS --
------------
local onUpdateFunc = {};


--------------
-- ONUPDATE --
--------------
local lastUpdate;
local MAX_UPDATE_TIME = 1.0/120.0;
local function FrameOnUpdate(self, time)

    if (not lastUpdate or (lastUpdate + MAX_UPDATE_TIME) < GetTime()) then

        -- Calling the update function of reactive zoom easing
        -- may call SetZoomUsingCVar() (if it misses the mark),
        -- which will itself insert a new update function into
        -- onUpdateFunc. Inserting into a table while traversing
        -- can lead to "invalid key to 'next'" errors. So we have
        -- to copy the table before we traverse it.
        local onUpdateFuncCopy = {}
        for k, func in pairs(onUpdateFunc) do
            onUpdateFuncCopy[k] = func;
        end

        -- However, setting entries to nil while traversing a table is possible.
        for k, func in pairs(onUpdateFuncCopy) do
            if (func() == nil) then
                onUpdateFunc[k] = nil;
            end
        end

        lastUpdate = GetTime();
    end

    -- remove onupdate if there isn't anything to check
    if (next(onUpdateFunc) == nil) then
        LibCamera.frame:SetScript("OnUpdate", nil);
    end

end

local function SetupOnUpdate()
    -- if we have checks to do and there isn't an OnUpdate on the frame, set it up
    if (next(onUpdateFunc) ~= nil and LibCamera.frame:GetScript("OnUpdate") == nil) then
        LibCamera.frame:SetScript("OnUpdate", FrameOnUpdate);

        -- force the next update to happen on the NEXT frame
        lastUpdate = GetTime();
    end
end

local function RegisterOnUpdateFunc(func)
    local updateFunc = func;
    if (type(func) == 'table' and func.updateFunc) then
        updateFunc = func.updateFunc;
    end

    -- add to the list
    onUpdateFunc[func] = updateFunc;

    -- make sure that an OnUpdate script is on our frame
    SetupOnUpdate();
end

local function CancelOnUpdateFunc(func)
    if (onUpdateFunc[func]) then
        -- remove from the list
        onUpdateFunc[func] = nil;

        if (func.callback) then
            func.callback(true);
        end
    end
end


-------------
-- UTILITY --
-------------
local function getZoomSpeed()
    return tonumber(GetCVar("cameraZoomSpeed"));
end

local function getYawSpeed()
    return tonumber(GetCVar("cameraYawMoveSpeed"));
end

local function getPitchSpeed()
    return tonumber(GetCVar("cameraPitchMoveSpeed"));
end


-- (t == 0)   If currentTime (t) is 0 we return beginValue (b).
-- (t == d)   If currentTime (t) is the duration (d), we return beginValue + change (b+c).
-- The question is how we get from the former to the latter.
local function easeInOutQuad(t, b, c, d)
    t = t / d * 2;
    if t < 1 then
        return c / 2 * (t * t) + b;
    else
        return -c / 2 * ((t - 1) * (t - 3) - 1) + b;
    end
end

local function getEaseVelocity(easingFunc, increment, t, b, c, d, ...)
    -- approximate the velocity of the easing function at the given time
    local halfIncrement = increment/2.0;

    if (t > halfIncrement and (t + halfIncrement < d)) then
        return (easingFunc(t + halfIncrement, b, c, d, ...) - easingFunc(t - halfIncrement, b, c, d, ...))/increment;
    elseif (t < halfIncrement and (t + increment < d)) then
        -- before halfIncrement, which means that can can't trust anything before t
        return (easingFunc(t + increment, b, c, d, ...) - easingFunc(t, b, c, d, ...))/increment;
    elseif (t + halfIncrement > d) then
        -- after the last increment, can't go beyond d
        return (easingFunc(t, b, c, d, ...) - easingFunc(t - increment, b, c, d, ...))/increment;
    end
end

local function rebaseEaseTime(easingFunc, precision, x, t, b, c, d, ...)
    -- basically, what this tries to do, is to move the t (time) around
    -- so that it matches the provided x (position) within the given easing function

    -- in other words:
    -- we have some amount of error between where we actually are, and where we were supposed to be
    -- so we jump forward/backwards on the time line to compensate

    local currentValue = easingFunc(t, b, c, d, ...);
    local tPrime = t;
    local difference = x - currentValue;
    local change = math.min(d-t, d/12.0);
    local lastWasForward;
    local numIter = 0;

    while ((math.abs(difference) > precision) and (numIter < 100)) do
        if ((difference > 0 and c > 0) or (difference < 0 and c < 0)) then
            -- if we swapped directions, then divide by 2
            if (lastWasForward ~= nil and not lastWasForward) then
                change = change / 2.0;
            end

            -- ahead of time
            tPrime = tPrime + change;

            lastWasForward = true;
        else
            -- if we swapped directions, then divide by 2
            if (lastWasForward) then
                change = change / 2.0;
            end

            -- behind time
            tPrime = tPrime - change;

            lastWasForward = false;
        end

        -- recompute
        currentValue = easingFunc(tPrime, b, c, d, ...);
        difference = x - currentValue;
        numIter = numIter + 1;
    end

    return tPrime;
end


-------------
-- ZOOMING --
-------------
local function reallyStopZooming()
    -- print("reallyStopZooming")

    MoveViewOutStart(0);
    MoveViewInStart(0);
    MoveViewInStop();
    MoveViewOutStop();
end

local easingZoom;
local MAX_POS_ERROR = 0.5;
function LibCamera:SetZoom(endValue, duration, easingFunc, callback)

    -- print("SetZoom", endValue, duration)

    -- start every zoom by making sure that we stop zooming
    self:StopZooming();

    -- assume easeInOutQuad if not provided
    if (not easingFunc) then
        easingFunc = easeInOutQuad;
    end

    -- we want to start the counter on the frame the zoom started
    local beginTime;
    local beginValue;
    local change;
    local frameCount = 0;

    -- create a closure, for OnUpdate
    local func = function()

        -- func() gets called one frame after SetZoom(). This is why we set the values here!
        beginTime = beginTime or GetTime();
        beginValue = beginValue or GetCameraZoom();
        change = change or (endValue - beginValue);

        frameCount = frameCount + 1;

        local currentTime = GetTime();
        local currentValue = GetCameraZoom();

        local beyondPosition = (change > 0 and currentValue >= endValue) or (change < 0 and currentValue <= endValue);

        -- Still in time and not yet beyond destination position.
        if not beyondPosition and beginTime + duration > currentTime then

            local interval = 1.0/60.0;

            local t = currentTime - beginTime;
            local expectedValue = easingFunc(t, beginValue, change, duration);
            local posError = currentValue - expectedValue;

            if (frameCount > 1) then
                -- we're off the mark, try to rebase our time so that we're in the right time for our current position
                -- don't try to do this on the first frame
                if (math.abs(posError) > MAX_POS_ERROR) then

                    -- print("Got a position error of", posError, "-> expectedValue", expectedValue, "!= currentValue", currentValue)

                    local tPrime = rebaseEaseTime(easingFunc, 0.005, currentValue, t, beginValue, change, duration);

                    -- If the actual value is still within our expected duration time window...
                    if (tPrime > 0 and tPrime < duration) then

                        local tDiff = tPrime - t;

                        -- Let's henceforth pretend that beginTime = beginTime - tDiff
                        -- and that we are at t = currentTime - beginTime.
                        beginTime = beginTime - tDiff;
                        t = currentTime - beginTime;
                    end
                end
            end

            local speed;

            -- If we have not yet reached the last two invervals.
            if (duration - t > 2*interval) then
                speed = getEaseVelocity(easingFunc, interval, t, beginValue, change, duration);
            else
                -- use linear speed on the last two possible frames
                -- linear assuming next frame is on interval time
                speed = (endValue - currentValue)/interval;
            end

            -- speed didn't return, which generally means that the duration was shorter than the framerate
            if (not speed) then
                return nil;
            end



            if (speed > 0) then
                MoveViewOutStart(speed/getZoomSpeed());
            elseif (speed < 0) then
                MoveViewInStart(-speed/getZoomSpeed());
            end


            return true;
        else

            -- we're done, either out of time, or beyond position
            self:StopZooming();

            -- Make a correction when reactive zoom misses the target.
            -- 0.05 is the smallest increment possible for OldCameraZoomIn/OldCameraZoomOut.
            if (math.abs(currentValue - endValue) > 0.05) then
                -- print("Ups, going back from", currentValue, "to", endValue)
                self:SetZoomUsingCVar(endValue, .1, callback);
                return nil;
            end

            -- call the callback if provided
            if (callback) then
                -- Not necessary to call callback() here, because it was already called as easingZoom.callback by StopZooming() above.
                -- callback();

                if (easingZoom) then
                    easingZoom.callback = nil;
                end
            end;
            return nil;
        end
    end

    -- register OnUpdate, to call every frame until done
    easingZoom = {};
    easingZoom.callback = callback;
    easingZoom.updateFunc = func;
    RegisterOnUpdateFunc(easingZoom);
end

local cvarZoom;
local oldSpeed;
function LibCamera:SetZoomUsingCVar(endValue, duration, callback)

    -- start every zoom by making sure that we stop zooming
    self:StopZooming();

    local beginValue = GetCameraZoom();
    local change = endValue - beginValue;
    local speed = math.abs(math.min(50, math.abs((change/duration))));

    local startTime = GetTime();
    local endTime = startTime + duration;

    oldSpeed = getZoomSpeed();

    -- set the zoom cvar to what will get us to the endValue in the duration
    SetCVar("cameraZoomSpeed", speed);

    local triggeredZoom = false;

    local lastValue = GetCameraZoom();
    local func = function()
        -- trigger zoom only once but ON THE NEXT FRAME
        -- this is because you can only do one CameraZoom___ function once a frame
        if (not triggeredZoom) then
            -- actually trigger the zoom
            -- second parameter is just to let other addons know that this is zoom triggered by an addon
            if (change > 0) then
                CameraZoomOut(change, true);
            elseif (change < 0) then
                CameraZoomIn(-change, true);
            end

            triggeredZoom = true;
        end

        local currentValue = GetCameraZoom();

        -- check if we've got beyond the position that we were aiming for
        -- local beyondPosition = (change > 0 and currentValue >= endValue) or (change < 0 and currentValue <= endValue);
        local goingWrongWay = (change > 0 and lastValue > currentValue) or (change < 0 and lastValue < currentValue);
        local timeOver = endTime < GetTime()

        lastValue = currentValue;

        if (not timeOver and not goingWrongWay) then
            -- we're still zooming or we should be
            return true;
        else
            -- we should have stopped zooming
            self:StopZooming();
            if (callback) then
                callback();

                if (cvarZoom) then
                    cvarZoom.callback = nil;
                end
            end;
            return nil;
        end
    end

    -- register OnUpdate, to call every frame until done
    cvarZoom = {};
    cvarZoom.callback = callback;
    cvarZoom.updateFunc = func;
    RegisterOnUpdateFunc(cvarZoom);
end

local customZoom;
function LibCamera:CustomZoom(zoomFunction, callback)
    self:StopZooming();

    local lastSpeed = 0;
    local func = function()
        local speed = zoomFunction();

        if (not speed) then
            -- zoom function returned nil, stop the camera zoom, unregister the function
            self:StopZooming();
            if (callback) then
                callback();

                if (customZoom) then
                    customZoom.callback = nil;
                end
            end
            return nil;
        end

        if (speed == 0 and lastSpeed ~= 0) then
            reallyStopZooming();
        elseif (speed > 0) then
            MoveViewOutStart(speed/getZoomSpeed());
        elseif (speed < 0) then
            MoveViewInStart(-speed/getZoomSpeed());
        end

        lastSpeed = speed;
        return true;
    end

    -- register OnUpdate, to call every frame until done
    customZoom = {};
    customZoom.callback = callback;
    customZoom.updateFunc = func;
    RegisterOnUpdateFunc(customZoom);
end


-- A function to function to check if zooming is in progress.
function LibCamera:IsZooming()
    return (easingZoom ~= nil) or (cvarZoom ~= nil) or (customZoom ~= nil);
end


-- Set not_really argument to skip the final call of reallyStopZooming().
-- Needed for when a mouse-wheel non-reactive zoom interrupts a zoom easing
-- currently in progress. If we execute reallyStopZooming() the non-reactive zoom
-- will have no effect.
function LibCamera:StopZooming(not_really)

    -- print("StopZooming")

    -- if we currently have something running, make sure to cancel it!
    if (easingZoom) then
        CancelOnUpdateFunc(easingZoom);
        easingZoom = nil;
    end

    if (customZoom) then
        CancelOnUpdateFunc(customZoom);
        customZoom = nil;
    end

    if (cvarZoom) then
        CancelOnUpdateFunc(cvarZoom);
        cvarZoom = nil;

        -- restore old speed if we had one
        if (oldSpeed) then
            SetCVar("cameraZoomSpeed", oldSpeed);
            oldSpeed = nil;
        end
    end

    if not_really then return end

    reallyStopZooming();
end







--------------
-- ROTATION --
--------------
local easingYaw;
local lastYaw;
function LibCamera:Yaw(endValue, duration, easingFunc, callback)

    if duration == 0 then
        duration = 0.05
    end

    -- start every yaw
    self:StopYawing();

    -- assume easeInOutQuad if not provided
    if (not easingFunc) then
        easingFunc = easeInOutQuad;
    end

    local beginValue = 0;
    local change = endValue - beginValue;
    local beginTime;

    -- create a closure, for OnUpdate
    local func = function()
        local currentTime = GetTime();
        beginTime = beginTime or GetTime();

        if (beginTime + duration > currentTime) then
            -- still in time
            local speed = getEaseVelocity(easingFunc, 1.0/60.0, currentTime - beginTime, beginValue, change, duration);

            -- this is the elasped yaw, used if we canceled ahead of time
            lastYaw = easingFunc(currentTime - beginTime, beginValue, change, duration);

            if (speed > 0) then
                MoveViewRightStart(speed/getYawSpeed());
            elseif (speed < 0) then
                MoveViewLeftStart(-speed/getYawSpeed());
            end

            return true;
        else
            -- stop the camera, we're there
            lastYaw = nil;
            self:StopYawing();

            -- call the callback if provided
            if (callback) then
                callback();

                if (easingYaw) then
                    easingYaw.callback = nil;
                end
            end

            return nil;
        end
    end

    -- register OnUpdate, to call every frame until done
    easingYaw = {};
    easingYaw.callback = callback;
    easingYaw.updateFunc = func;
    RegisterOnUpdateFunc(easingYaw);
end

local continuousYaw;
local elaspedYaw;
function LibCamera:BeginContinuousYaw(endSpeed, duration)
    self:StopYawing();

    local beginTime;
    local lastSpeed, lastTime;
    local isCoasting = false;

    elaspedYaw = 0;

    local func = function()
        local speed = endSpeed;
        local currentTime = GetTime();
        beginTime = beginTime or GetTime();

        -- accumulate the yaw into elapsed yaw, so that we can return it when we stop
        if (lastSpeed and lastTime) then
            elaspedYaw = elaspedYaw + (lastSpeed * (currentTime - lastTime))
        end
        lastTime = GetTime();

        if (beginTime + duration > currentTime) then
            -- linear increase of velocity
            speed = endSpeed * (currentTime - beginTime) / duration;

            if (speed > 0) then
                MoveViewRightStart(speed/getYawSpeed());
            elseif (speed < 0) then
                MoveViewLeftStart(-speed/getYawSpeed());
            end

            lastSpeed = speed;

            return true;
        else
            -- start yawing at the endSpeed if we haven't already
            if (not isCoasting) then
                if (speed > 0) then
                    MoveViewRightStart(speed/getYawSpeed());
                elseif (speed < 0) then
                    MoveViewLeftStart(-speed/getYawSpeed());
                end

                lastSpeed = speed;
                isCoasting = true;
            end
            return true;
        end
    end

    -- register OnUpdate, to call every frame until done
    continuousYaw = {};
    continuousYaw.updateFunc = func;
    RegisterOnUpdateFunc(continuousYaw);
end

function LibCamera:IsYawing()
    return (easingYaw ~= nil) or (continuousYaw ~= nil);
end

function LibCamera:StopYawing()
    local yawAmount;

    -- if we currently have something running, make sure to cancel it!
    if (easingYaw) then
        CancelOnUpdateFunc(easingYaw);
        easingYaw = nil;

        -- if we had a last yaw, make sure to save it, to return
        if (lastYaw) then
            yawAmount = lastYaw;
            lastYaw = nil;
        end
    end

    -- if we are continually yawing, then stop that
    if (continuousYaw) then
        CancelOnUpdateFunc(continuousYaw);
        continuousYaw = nil;

        -- return elapsed yaw
        if (elaspedYaw) then
            yawAmount = elaspedYaw;
            elaspedYaw = nil;
        end
    end

    -- this might be overkill, but we really want to make sure that the camera isn't moving!
    MoveViewLeftStop();
    MoveViewRightStop();

    return yawAmount;
end

local easingPitch;
local lastPitch;
function LibCamera:Pitch(endValue, duration, easingFunc, callback)

    if duration == 0 then
      duration = 0.05
    end

    -- start every pitch
    self:StopPitching();

    -- assume easeInOutQuad if not provided
    if (not easingFunc) then
        easingFunc = easeInOutQuad;
    end

    local beginValue = 0;
    local change = endValue - beginValue;
    local beginTime;

    -- create a closure, for OnUpdate
    local func = function()
        local currentTime = GetTime();
        beginTime = beginTime or GetTime();

        if (beginTime + duration > currentTime) then
            -- still in time
            local speed = getEaseVelocity(easingFunc, 1.0/60.0, currentTime - beginTime, beginValue, change, duration);

            -- this is the elasped pitch, used if we canceled ahead of time
            lastPitch = easingFunc(currentTime - beginTime, beginValue, change, duration);

            if (speed > 0) then
                MoveViewUpStart(speed/getPitchSpeed());
            elseif (speed < 0) then
                MoveViewDownStart(-speed/getPitchSpeed());
            end

            return true;
        else
            lastPitch = nil;

            -- stop the camera, we're there
            self:StopPitching();

            -- call the callback if provided
            if (callback) then
                callback();

                if (easingPitch) then
                    easingPitch.callback = nil;
                end
            end

            return nil;
        end
    end

    -- register OnUpdate, to call every frame until done
    easingPitch = {};
    easingPitch.callback = callback;
    easingPitch.updateFunc = func;
    RegisterOnUpdateFunc(easingPitch);
end

function LibCamera:IsPitching()
    return (easingPitch ~= nil);
end

function LibCamera:StopPitching()
    local pitchAmount;

    -- if we currently have something running, make sure to cancel it!
    if (easingPitch) then
        CancelOnUpdateFunc(easingPitch);
        easingPitch = nil;

        -- if we had a last pitch, make sure to save it, to return
        if (lastPitch) then
            pitchAmount = lastPitch;
            lastPitch = nil;
        end
    end

    -- this might be overkill, but we really want to make sure that the camera isn't moving!
    MoveViewUpStop();
    MoveViewDownStop();

    return pitchAmount;
end

function LibCamera:IsRotating()
    return (easingYaw ~= nil) or (continuousYaw ~= nil) or (easingPitch ~= nil);
end

function LibCamera:StopRotating()
    return self:StopYawing(), self:StopPitching();
end
