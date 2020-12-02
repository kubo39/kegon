module kegon.common;

public import bindbc.glfw;

version(Windows)
{
    import core.sys.windows.windows;
    import erupted.platform_extensions;
    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;

    mixin(bindGLFW_Windows);
}