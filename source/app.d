import core.sys.windows.windows;

import bindbc.glfw;
import bindbc.loader;
import erupted;

import erupted.platform_extensions;
mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;

mixin(bindGLFW_Vulkan);

///
extern (C) void keyCallback(GLFWwindow* window, int key, int scancode,
							int action, int mods) nothrow
{
	if (action == GLFW_PRESS)
	{
		if (key == GLFW_KEY_ESCAPE)
		{
			glfwSetWindowShouldClose(window, true);
		}
	}
}

/**
* Device.
*/
VkInstance createInstance()
{
	VkApplicationInfo appInfo = {
		sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
		apiVersion: VK_API_VERSION_1_2,
	};

	VkInstanceCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		pApplicationInfo: &appInfo,
	};

	debug
	{
		const(char)*[] debugLayers = [
			"VK_LAYER_KHRONOS_validation"
		];
		createInfo.ppEnabledLayerNames = debugLayers.ptr;
		createInfo.enabledLayerCount = cast(uint) debugLayers.length;
	}

	const(char)*[] extensions = [
		VK_KHR_SURFACE_EXTENSION_NAME,
		VK_KHR_WIN32_SURFACE_EXTENSION_NAME
	];

	createInfo.ppEnabledExtensionNames = extensions.ptr;
	createInfo.enabledExtensionCount = cast(uint) extensions.length;

	VkInstance instance;
	assert(vkCreateInstance(&createInfo, null, &instance) == VkResult.VK_SUCCESS);
	return instance;
}

void main()
{
	// window initialization.
	version(Windows)
	{
		const rc = loadGLFW("lib/glfw3.dll");
		assert(rc == glfwSupport);
	}
	assert(glfwInit() != 0);
	assert(glfwVulkanSupported() != 0);
	glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

	// vulkan initialization.
	import erupted.vulkan_lib_loader : loadGlobalLevelFunctions;
	loadGlobalLevelFunctions();

	VkInstance instance = createInstance();
	scope(exit)
	{
		if (instance != VK_NULL_HANDLE)
		{
			vkDestroyInstance(instance, null);
		}
	}

	// create window.
	auto window = glfwCreateWindow(1024, 768, "kegon", null, null);
	assert(window !is null);
	scope(exit) glfwDestroyWindow(window);
	glfwSetKeyCallback(window, &keyCallback);

	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();
	}
}