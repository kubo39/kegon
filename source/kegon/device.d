module kegon.device;

version(Windows) import core.sys.windows.windows;
import core.stdc.stdio : printf, snprintf;
import std.stdio;

import erupted;

import kegon.common;

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
		sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
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
	float queuePriorities = 1.0f;
	VkDeviceQueueCreateInfo queueInfo = {
		sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex: familyIndex,
		queueCount: 1,
		pQueuePriorities: &queuePriorities,
	};

	const(char)*[] extensions = [
		VK_KHR_SWAPCHAIN_EXTENSION_NAME,
		VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
	];

	VkPhysicalDeviceVulkan12Features features12 = {
		sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		storageBuffer8BitAccess: true,
		uniformAndStorageBuffer8BitAccess: true,
		shaderInt8: true,
	};

	VkPhysicalDeviceFeatures2 features = {
		sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
		pNext: &features12,
	};

	VkDeviceCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
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
