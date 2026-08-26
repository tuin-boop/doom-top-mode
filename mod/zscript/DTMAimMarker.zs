class DTMAimMarker : Actor
{
    Default
    {
        +NOINTERACTION
        +NOGRAVITY
        +FORCEXYBILLBOARD
        +BRIGHT
        RenderStyle "Add";
        Alpha 0.82;
        Scale 0.25;
    }

    override void Tick()
    {
        Super.Tick();
        if (!tracer || tracer.health <= 0)
        {
            Destroy();
            return;
        }
        SetOrigin(tracer.pos + (0, 0, tracer.height * 0.52), true);
    }

    States
    {
    Spawn:
        DTLK A 1 Bright;
        Loop;
    }
}
