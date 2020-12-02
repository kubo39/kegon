module kegon.device;

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
