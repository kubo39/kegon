module kegon.common;

import std.conv : to;
import std.exception : enforce;

import erupted;
public import bindbc.glfw;

version(Windows)
{
    import core.sys.windows.windows;
    import erupted.platform_extensions;
    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;

    mixin(bindGLFW_Windows);
}

void enforceVK(VkResult result)
{
    enforce(result == VkResult.VK_SUCCESS, result.to!string);
}