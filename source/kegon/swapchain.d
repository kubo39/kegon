module kegon.swapchain;

version(Windows) import core.sys.windows.windows;

import erupted;

public import kegon.common;

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