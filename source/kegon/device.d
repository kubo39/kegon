module kegon.device;

version(Windows) import core.sys.windows.windows;
import core.stdc.stdio : printf, snprintf;
import std.stdio;

import erupted;

import kegon.common;

VkInstance createInstance()
{
	VkApplicationInfo appInfo = {
		pNext: null,
		apiVersion: VK_MAKE_API_VERSION(0, 1, 2, 0),
	};

	VkInstanceCreateInfo createInfo = {
		pNext: null,
		pApplicationInfo: &appInfo,
	};

	//debug
	{
		const(char)*[] debugLayers = [
			"VK_LAYER_KHRONOS_validation"
		];
		createInfo.ppEnabledLayerNames = debugLayers.ptr;
		createInfo.enabledLayerCount = cast(uint) debugLayers.length;
	}

	const(char)*[] extensions = [
		VK_KHR_SURFACE_EXTENSION_NAME,
		VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
		VK_EXT_DEBUG_REPORT_EXTENSION_NAME,
	];

	createInfo.ppEnabledExtensionNames = extensions.ptr;
	createInfo.enabledExtensionCount = cast(uint) extensions.length;

	VkInstance instance;
	enforceVK(vkCreateInstance(&createInfo, null, &instance));
	return instance;
}

extern (Windows) VkBool32 debugReportCallback(VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objectType, ulong object, size_t location, int messageCode, const(char)* pLayerPrefix, const(char)* pMessage, void* pUserData)
	nothrow @nogc
{
	const(char)* type =
		(flags & VK_DEBUG_REPORT_ERROR_BIT_EXT)
		? "ERROR"
		: (flags & VK_DEBUG_REPORT_WARNING_BIT_EXT)
			? "WARNING"
			: "INFO";
	char[4096] message;
	snprintf(message.ptr, message.length, "%s: %s\n", type, pMessage);
	printf("%s", message.ptr);

	version(Windows)
	{
		OutputDebugStringA(message.ptr);
	}

	if (flags & VK_DEBUG_REPORT_ERROR_BIT_EXT)
	{
		assert(false, "Validation error encounted");
	}

	return VK_FALSE;
}

VkDebugReportCallbackEXT registerDebugCallback(VkInstance instance)
{
	VkDebugReportCallbackCreateInfoEXT createInfo = {
		flags: VK_DEBUG_REPORT_WARNING_BIT_EXT | VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT | VK_DEBUG_REPORT_ERROR_BIT_EXT,
		pfnCallback: &debugReportCallback,
	};
	VkDebugReportCallbackEXT callback;
	enforceVK(vkCreateDebugReportCallbackEXT(instance, &createInfo, null, &callback));
	return callback;
}

uint getGraphicsFamilyIndex(VkPhysicalDevice physicalDevice)
{
	uint queueCount;
	vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, null);
	assert(queueCount > 0);
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
		if (props.apiVersion < VK_MAKE_API_VERSION(0, 1, 2, 0))
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

VkDevice createDevice(VkInstance instance, VkPhysicalDevice physicalDevice, uint familyIndex, bool pushDescriptorsSupported, bool meshShadingSupported)
{
	float queuePriorities = 1.0f;
	VkDeviceQueueCreateInfo queueInfo = {
		queueFamilyIndex: familyIndex,
		queueCount: 1,
		pQueuePriorities: &queuePriorities,
	};

	const(char)*[] extensions = [
		VK_KHR_SWAPCHAIN_EXTENSION_NAME
	];

	if (pushDescriptorsSupported)
	{
		extensions = extensions ~ VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME;
	}

	if (meshShadingSupported)
	{
		extensions = extensions ~ VK_NV_MESH_SHADER_EXTENSION_NAME;
	}

	VkPhysicalDeviceMeshShaderFeaturesNV featuresMesh = {
		sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_NV,
		taskShader: true,
		meshShader: true,
	};

	VkPhysicalDeviceVulkan12Features features12 = {
		storageBuffer8BitAccess: true,
		uniformAndStorageBuffer8BitAccess: true,
		shaderInt8: true,
	};

	if (meshShadingSupported)
	{
		features12.pNext = &featuresMesh;
	}

	VkPhysicalDeviceFeatures2 features = {
		pNext: &features12,
	};

	VkDeviceCreateInfo createInfo = {
		pQueueCreateInfos: &queueInfo,
		queueCreateInfoCount: 1,
		ppEnabledExtensionNames: extensions.ptr,
		enabledExtensionCount: cast(uint) extensions.length,
		pNext: &features,
	};

	VkDevice device;
	enforceVK(vkCreateDevice(physicalDevice, &createInfo, null, &device));
	return device;
}
