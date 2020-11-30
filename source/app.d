version(Windows) import core.sys.windows.windows;
import std.stdio;
import std.string;

import bindbc.glfw;
import bindbc.loader;
import erupted;

import erupted.platform_extensions;
mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;

mixin(bindGLFW_Vulkan);
version(Windows) mixin(bindGLFW_Windows);

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
		pNext: null,
		apiVersion: VK_API_VERSION_1_2,
	};

	VkInstanceCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		pNext: null,
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

uint getGraphicsFamilyIndex(VkPhysicalDevice physicalDevice)
{
	uint queueCount;
	vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, null);

	auto queues = new VkQueueFamilyProperties[](queueCount);
	vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, queues.ptr);

	foreach (i; 0 .. queueCount)
	{
		if (queues[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)
		{
			return i;
		}
	}

	return VK_QUEUE_FAMILY_IGNORED;
}

VkPhysicalDevice pickPhysicalDevice(VkPhysicalDevice* physicalDevices, uint physicalDeviceCount)
{
	VkPhysicalDevice preferred;
	VkPhysicalDevice fallback;

	foreach (i; 0 .. physicalDeviceCount)
	{
		VkPhysicalDeviceProperties props;
		vkGetPhysicalDeviceProperties(physicalDevices[i], &props);

		writefln("GPU%d: %s", i, props.deviceName);

		uint familyIndex = getGraphicsFamilyIndex(physicalDevices[i]);
		if (familyIndex == VK_QUEUE_FAMILY_IGNORED)
		{
			continue;
		}
		if (!vkGetPhysicalDeviceWin32PresentationSupportKHR(physicalDevices[i], familyIndex))
		{
			continue;
		}
		if (props.apiVersion < VK_API_VERSION_1_2)
		{
			continue;
		}

		if (preferred == VkPhysicalDevice.init && props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
		{
			preferred = physicalDevices[i];
		}
		if (fallback == VkPhysicalDevice.init)
		{
			fallback = physicalDevices[i];
		}
	}

	VkPhysicalDevice result = preferred != VkPhysicalDevice.init ? preferred : fallback;
	if (result != VkPhysicalDevice.init)
	{
		VkPhysicalDeviceProperties props;
		vkGetPhysicalDeviceProperties(result, &props);
	}
	else
	{
		writeln("ERROR: No GPU found");
	}
	return result;
}

VkDevice createDevice(VkInstance instance, VkPhysicalDevice physicalDevice, uint familyIndex)
{
	float[1] queuePriorities = [1.0f];
	VkDeviceQueueCreateInfo queueInfo = {
		sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex: familyIndex,
		queueCount: 1,
		pQueuePriorities: queuePriorities.ptr,
	};

	const(char)*[] extensions = [
		VK_KHR_SWAPCHAIN_EXTENSION_NAME,
	];

	VkPhysicalDeviceFeatures2 features = {
		sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
	};
	features.features.multiDrawIndirect = true;
	features.features.pipelineStatisticsQuery = true;
	features.features.shaderInt16 = true;
	features.features.shaderInt64 = true;

	VkPhysicalDeviceVulkan12Features features12 = {
		sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		drawIndirectCount: true,
		storageBuffer8BitAccess: true,
		uniformAndStorageBuffer8BitAccess: true,
		storagePushConstant8: true,
		shaderFloat16: true,
		shaderInt8: true,
		samplerFilterMinmax: true,
		scalarBlockLayout: true,
	};

	VkDeviceCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		queueCreateInfoCount: 1,
		pQueueCreateInfos: &queueInfo,
		ppEnabledExtensionNames: extensions.ptr,
		enabledExtensionCount: cast(uint) extensions.length,
		pNext: &features,
	};
	features.pNext = &features12;

	VkDevice device;
	assert(vkCreateDevice(physicalDevice, &createInfo, null, &device) == VkResult.VK_SUCCESS);
	return device;
}

/**
*  Swapchain
*/
VkSurfaceKHR createSurface(VkInstance instance, GLFWwindow* window)
{
	version(Windows)
	{
		VkWin32SurfaceCreateInfoKHR createInfo = {
			sType: VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
			hinstance: GetModuleHandle(null),
			hwnd: glfwGetWin32Window(window),
		};
		VkSurfaceKHR surface;
		assert(vkCreateWin32SurfaceKHR(instance, &createInfo, null, &surface) == VkResult.VK_SUCCESS);
		return surface;
	}
	else static assert(false, "Unsupported platform.");
}

VkFormat getSwapchainFormat(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
	uint formatCount = 0;
	assert(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, null) == VkResult.VK_SUCCESS);
	assert(formatCount > 0);

	auto formats = new VkSurfaceFormatKHR[](formatCount);
	assert(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, formats.ptr) == VkResult.VK_SUCCESS);

	if (formatCount == 1 && formats[0].format == VK_FORMAT_UNDEFINED)
	{
		return VK_FORMAT_R8G8B8A8_UNORM;
	}

	foreach (i; 0 .. formatCount)
	{
		if (formats[i].format == VK_FORMAT_R8G8B8A8_UNORM || formats[i].format == VK_FORMAT_B8G8R8A8_UNORM)
			return formats[i].format;
	}

	return formats[0].format;
}

VkSwapchainKHR createSwapchain(VkDevice device, VkSurfaceKHR surface, VkFormat format, uint familyIndex, int width, int height)
{
	VkSwapchainCreateInfoKHR createInfo = {
		sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
		surface: surface,
		minImageCount: 2,
		imageFormat: format,
		imageColorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
		imageArrayLayers: 1,
		imageUsage: VK_IMAGE_USAGE_TRANSFER_DST_BIT,
		queueFamilyIndexCount: 1,
		pQueueFamilyIndices: &familyIndex,
		presentMode: VK_PRESENT_MODE_FIFO_KHR,
	};
	createInfo.imageExtent.width = width;
	createInfo.imageExtent.height = height;
	VkSwapchainKHR swapchain;
	assert(vkCreateSwapchainKHR(device, &createInfo, null, &swapchain) == VkResult.VK_SUCCESS);
	return swapchain;
}

shared static this()
{
	// window initialization
	version(Windows)
	{
		const rc = loadGLFW("lib/glfw3.dll");
		assert(rc == glfwSupport);
		assert(loadGLFW_Windows);
	}
	assert(glfwInit() != 0);
	assert(glfwVulkanSupported() != 0);
	glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

	// vulkan initialization.
	import erupted.vulkan_lib_loader : loadGlobalLevelFunctions;
	loadGlobalLevelFunctions();
}

shared static ~this()
{
	glfwTerminate();
}

void main()
{
	VkInstance instance = createInstance();
	scope(exit) vkDestroyInstance(instance, null);
	loadInstanceLevelFunctions(instance);

	VkPhysicalDevice[16] physicalDevices;
	uint physicalDeviceCount = cast(uint) physicalDevices.length;
	assert(vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, physicalDevices.ptr) == VkResult.VK_SUCCESS);
	VkPhysicalDevice physicalDevice = pickPhysicalDevice(physicalDevices.ptr, physicalDeviceCount);
	assert(physicalDevice != VkPhysicalDevice.init);

	uint extensionCount = 0;
	assert(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, null) == VkResult.VK_SUCCESS);
	auto extensions = new VkExtensionProperties[](extensionCount);
	assert(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, extensions.ptr) == VkResult.VK_SUCCESS);

	VkPhysicalDeviceProperties props;
	vkGetPhysicalDeviceProperties(physicalDevice, &props);
	assert(props.limits.timestampComputeAndGraphics);

	const uint familyIndex = getGraphicsFamilyIndex(physicalDevice);
	assert(familyIndex != VK_QUEUE_FAMILY_IGNORED);

	VkDevice device = createDevice(instance, physicalDevice, familyIndex);
	scope(exit)
	{
		vkDeviceWaitIdle(device);
		vkDestroyDevice(device, null);
	}
	loadDeviceLevelFunctions(instance);

	// create window.
	auto window = glfwCreateWindow(1024, 768, "kegon", null, null);
	assert(window !is null);
	scope(exit) glfwDestroyWindow(window);
	glfwSetKeyCallback(window, &keyCallback);

	VkSurfaceKHR surface = createSurface(instance, window);
	assert(surface);
	scope(exit) vkDestroySurfaceKHR(instance, surface, null);

	VkBool32 presentSupported = VK_FALSE;
	assert(vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, familyIndex, surface, &presentSupported) == VkResult.VK_SUCCESS);
	assert(presentSupported);

	VkFormat swapchainFormat = getSwapchainFormat(physicalDevice, surface);

	int windowWidth, windowHeight;
	glfwGetWindowSize(window, &windowWidth, &windowHeight);
	VkSwapchainKHR swapchain = createSwapchain(device, surface, swapchainFormat, familyIndex, windowWidth, windowHeight);

	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();
	}
}