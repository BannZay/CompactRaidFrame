function Lerp(startValue, endValue, amount)
    return (1 - amount) * startValue + amount * endValue;
end

function Clamp(value, min, max)
    if value > max then
        return max;
    elseif value < min then
        return min;
    end
    return value;
end

function Saturate(value)
    return Clamp(value, 0.0, 1.0);
end

function Wrap(value, max)
    return (value - 1) % max + 1;
end

function ClampDegrees(value)
    return ClampMod(value, 360);
end

function ClampMod(value, mod)
    return ((value % mod) + mod) % mod;
end

function NegateIf(value, condition)
    return condition and -value or value;
end

function PercentageBetween(value, startValue, endValue)
    if startValue == endValue then
        return 0.0;
    end
    return (value - startValue) / (endValue - startValue);
end

function ClampedPercentageBetween(value, startValue, endValue)
    return Saturate(PercentageBetween(value, startValue, endValue));
end

local TARGET_FRAME_PER_SEC = 60.0;
function DeltaLerp(startValue, endValue, amount, timeSec)
    return Lerp(startValue, endValue, Saturate(amount * timeSec * TARGET_FRAME_PER_SEC));
end

function FrameDeltaLerp(startValue, endValue, amount)
    return DeltaLerp(startValue, endValue, amount, GetTickTime());
end

function RandomFloatInRange(minValue, maxValue)
    return Lerp(minValue, maxValue, math.random());
end

function Round(value)
    if value < 0.0 then
        return math.ceil(value - .5);
    end
    return math.floor(value + .5);
end

function Square(value)
    return value * value;
end

function CalculateDistanceSq(x1, y1, x2, y2)
    local dx = x2 - x1;
    local dy = y2 - y1;
    return (dx * dx) + (dy * dy);
end

function CalculateDistance(x1, y1, x2, y2)
    return math.sqrt(CalculateDistanceSq(x1, y1, x2, y2));
end

function CalculateAngleBetween(x1, y1, x2, y2)
    return math.atan2(y2 - y1, x2 - x1);
end
