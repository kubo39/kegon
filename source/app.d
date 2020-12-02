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
struct Swapchain
{
	VkSwapchainKHR swapchain;
	VkImage[] images;
	uint width;
	uint height;
	int imageCount;
}


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

VkSwapchainKHR createSwapchain(VkDevice device, VkSurfaceKHR surface, VkSurfaceCapabilitiesKHR surfaceCaps, uint familyIndex, VkFormat format)
{
	VkCompositeAlphaFlagBitsKHR surfaceComposite =
		(surfaceCaps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
		? VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
		: (surfaceCaps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR)
		? VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR
		: (surfaceCaps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR)
		? VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR
		: VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;

	VkSwapchainCreateInfoKHR createInfo = {
		sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
		surface: surface,
		minImageCount: 2,
		imageFormat: format,
		imageColorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
		imageArrayLayers: 1,
		imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
		queueFamilyIndexCount: 1,
		pQueueFamilyIndices: &familyIndex,
		presentMode: VK_PRESENT_MODE_FIFO_KHR,
		compositeAlpha: surfaceComposite,
	};
	createInfo.imageExtent.width = surfaceCaps.currentExtent.width;
	createInfo.imageExtent.height = surfaceCaps.currentExtent.height;

	VkSwapchainKHR swapchain;
	assert(vkCreateSwapchainKHR(device, &createInfo, null, &swapchain) == VkResult.VK_SUCCESS);
	return swapchain;
}

void createSwapchain(Swapchain* result, VkPhysicalDevice physicalDevice, VkDevice device, VkSurfaceKHR surface, uint familyIndex, VkFormat format)
{
	VkSurfaceCapabilitiesKHR surfaceCaps;
	assert(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &surfaceCaps) == VkResult.VK_SUCCESS);

	VkSwapchainKHR swapchain = createSwapchain(device, surface, surfaceCaps, familyIndex, format);

	uint imageCount = 0;
	assert(vkGetSwapchainImagesKHR(device, swapchain, &imageCount, null) == VkResult.VK_SUCCESS);

	auto images = new VkImage[](imageCount);
	assert(vkGetSwapchainImagesKHR(device, swapchain, &imageCount, images.ptr) == VkResult.VK_SUCCESS);

	result.swapchain = swapchain;
	result.images = images;
	result.width = surfaceCaps.currentExtent.width;
	result.height = surfaceCaps.currentExtent.height;
	result.imageCount = imageCount;
}

void destroySwapchain(VkDevice device, Swapchain* swapchain)
{
	vkDestroySwapchainKHR(device, swapchain.swapchain, null);
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

VkSemaphore createSemaphore(VkDevice device)
{
	VkSemaphoreCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
	};
	VkSemaphore semaphore;
	assert(vkCreateSemaphore(device, &createInfo, null, &semaphore) == VkResult.VK_SUCCESS);
	return semaphore;
}

VkCommandPool createCommandPool(VkDevice device, uint familyIndex)
{
	VkCommandPoolCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
		flags: VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
		queueFamilyIndex: familyIndex,
	};
	VkCommandPool commandPool;
	assert(vkCreateCommandPool(device, &createInfo, null, &commandPool) == VkResult.VK_SUCCESS);
	return commandPool;
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

	VkSemaphore acquireSemaphore = createSemaphore(device);
	assert(acquireSemaphore);
	scope(exit) vkDestroySemaphore(device, acquireSemaphore, null);

	VkSemaphore releaseSemaphore = createSemaphore(device);
	assert(releaseSemaphore);
	scope(exit) vkDestroySemaphore(device, releaseSemaphore, null);

	VkQueue queue;
	vkGetDeviceQueue(device, familyIndex, 0, &queue);

	Swapchain swapchain;
	createSwapchain(&swapchain, physicalDevice, device, surface, familyIndex, swapchainFormat);
	scope(exit) destroySwapchain(device, &swapchain);

	VkCommandPool commandPool = createCommandPool(device, familyIndex);
	assert(commandPool);

	VkCommandBufferAllocateInfo allocateInfo = {
		sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool: commandPool,
		level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
		commandBufferCount: 1,
	};
	VkCommandBuffer commandBuffer;
	assert(vkAllocateCommandBuffers(device, &allocateInfo, &commandBuffer) == VkResult.VK_SUCCESS);

	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();

		uint imageIndex = 0;
		assert(vkAcquireNextImageKHR(device, swapchain.swapchain, ~0UL, acquireSemaphore, VK_NULL_HANDLE, &imageIndex) == VkResult.VK_SUCCESS);

		assert(vkResetCommandPool(device, commandPool, 0) == VkResult.VK_SUCCESS);

		VkCommandBufferBeginInfo beginInfo = {
			sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
			flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
		};
		assert(vkBeginCommandBuffer(commandBuffer, &beginInfo) == VkResult.VK_SUCCESS);

		VkClearColorValue color;
		color.int32 = [1, 0, 1, 1];
		VkImageSubresourceRange range = {
			aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
			levelCount: 1,
			layerCount: 1,
		};
		vkCmdClearColorImage(commandBuffer, swapchain.images[imageIndex], VK_IMAGE_LAYOUT_GENERAL, &color, 1, &range);

		assert(vkEndCommandBuffer(commandBuffer) == VkResult.VK_SUCCESS);

		VkPipelineStageFlags submitStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		VkSubmitInfo submitInfo = {
			sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,
			waitSemaphoreCount: 1,
			pWaitSemaphores: &acquireSemaphore,
			pWaitDstStageMask: &submitStageMask,
			commandBufferCount: 1,
			pCommandBuffers: &commandBuffer,
			signalSemaphoreCount: 1,
			pSignalSemaphores: &releaseSemaphore,
		};
		assert(vkQueueSubmit(queue, 1, &submitInfo, VK_NULL_HANDLE) == VkResult.VK_SUCCESS);

		VkPresentInfoKHR presentInfo = {
			sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
			waitSemaphoreCount: 1,
			pWaitSemaphores: &releaseSemaphore,
			pSwapchains: &swapchain.swapchain,
			swapchainCount: 1,
			pImageIndices: &imageIndex,
		};
		assert(vkQueuePresentKHR(queue, &presentInfo) == VkResult.VK_SUCCESS);

		assert(vkDeviceWaitIdle(device) == VkResult.VK_SUCCESS);
	}
}