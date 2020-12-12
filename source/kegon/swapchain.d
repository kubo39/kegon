module kegon.swapchain;

version(Windows) import core.sys.windows.windows;
import std.algorithm : max;

import erupted;

public import kegon.common;

struct Swapchain
{
	VkSwapchainKHR swapchain;
	VkImage[] images;
	VkImageView[] imageViews;
	VkFramebuffer[] framebuffers;
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
		enforceVK(vkCreateWin32SurfaceKHR(instance, &createInfo, null, &surface));
		return surface;
	}
	else static assert(false, "Unsupported platform.");
}

VkFormat getSwapchainFormat(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
{
	uint formatCount = 0;
	enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, null));
	assert(formatCount > 0);

	auto formats = new VkSurfaceFormatKHR[](formatCount);
	enforceVK(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &formatCount, formats.ptr));

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

VkFramebuffer createFramebuffer(VkDevice device, VkRenderPass renderPass, VkImageView colorView, uint width, uint height)
{
	VkFramebufferCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
		renderPass: renderPass,
		attachmentCount: 1,
		pAttachments: &colorView,
		width: width,
		height: height,
		layers: 1,
	};
	VkFramebuffer framebuffer;
	enforceVK(vkCreateFramebuffer(device, &createInfo, null, &framebuffer));
	return framebuffer;
}

VkImageView createImageView(VkDevice device, VkImage image, VkFormat format)
{
	VkImageSubresourceRange subresourceRange = {
		aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
		levelCount: 1,
		layerCount: 1,
	};
	VkImageViewCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
		image: image,
		viewType: VK_IMAGE_VIEW_TYPE_2D,
		format: format,
		subresourceRange: subresourceRange,
	};
	VkImageView view;
	enforceVK(vkCreateImageView(device, &createInfo, null, &view));
	return view;
}

VkSwapchainKHR createSwapchain(VkDevice device, VkSurfaceKHR surface, VkSurfaceCapabilitiesKHR surfaceCaps, uint familyIndex, VkFormat format, VkSwapchainKHR oldSwapchain)
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
		minImageCount: max(2, surfaceCaps.minImageCount),
		imageFormat: format,
		imageColorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
		imageArrayLayers: 1,
		imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
		queueFamilyIndexCount: 1,
		pQueueFamilyIndices: &familyIndex,
		preTransform: VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
		presentMode: VK_PRESENT_MODE_FIFO_KHR,
		compositeAlpha: surfaceComposite,
		oldSwapchain: oldSwapchain,
	};
	createInfo.imageExtent.width = surfaceCaps.currentExtent.width;
	createInfo.imageExtent.height = surfaceCaps.currentExtent.height;

	VkSwapchainKHR swapchain;
	enforceVK(vkCreateSwapchainKHR(device, &createInfo, null, &swapchain));
	return swapchain;
}

void createSwapchain(Swapchain* result, VkPhysicalDevice physicalDevice, VkDevice device, VkSurfaceKHR surface, uint familyIndex, VkFormat format, VkRenderPass renderPass, VkSwapchainKHR oldSwapchain)
{
	VkSurfaceCapabilitiesKHR surfaceCaps;
	enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &surfaceCaps));

	auto width = surfaceCaps.currentExtent.width;
	auto height = surfaceCaps.currentExtent.height;

	VkSwapchainKHR swapchain = createSwapchain(device, surface, surfaceCaps, familyIndex, format, oldSwapchain);

	uint imageCount = 0;
	enforceVK(vkGetSwapchainImagesKHR(device, swapchain, &imageCount, null));

	auto images = new VkImage[](imageCount);
	enforceVK(vkGetSwapchainImagesKHR(device, swapchain, &imageCount, images.ptr));

	auto imageViews = new VkImageView[](imageCount);
	foreach (uint i; 0 .. imageCount)
	{
		imageViews[i] = createImageView(device, images[i], format);
		assert(imageViews[i]);
	}

	auto framebuffers = new VkFramebuffer[](imageCount);
	foreach (uint i; 0 .. imageCount)
	{
		framebuffers[i] = createFramebuffer(device, renderPass, imageViews[i], width, height);
		assert(framebuffers[i]);
	}

	result.swapchain = swapchain;
	result.images = images;
	result.imageViews = imageViews;
	result.framebuffers = framebuffers;
	result.width = width;
	result.height = height;
	result.imageCount = imageCount;
}

void destroySwapchain(VkDevice device, Swapchain* swapchain)
{
	vkDestroySwapchainKHR(device, swapchain.swapchain, null);
	foreach (uint i; 0 .. swapchain.imageCount)
	{
		vkDestroyImageView(device, swapchain.imageViews[i], null);
	}
	foreach (uint i; 0 .. swapchain.imageCount)
	{
		vkDestroyFramebuffer(device, swapchain.framebuffers[i], null);
	}
}

enum SwapchainStatus
{
	NotReady,
	Ready,
	Resized,
};

SwapchainStatus updateSwapchain(Swapchain* result, VkPhysicalDevice physicalDevice, VkDevice device, VkSurfaceKHR surface, uint familyIndex, VkFormat format, VkRenderPass renderPass)
{
	VkSurfaceCapabilitiesKHR surfaceCaps;
	enforceVK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &surfaceCaps));

	uint newWidth = surfaceCaps.currentExtent.width;
	uint newHeight = surfaceCaps.currentExtent.height;

	if (newWidth == 0 || newHeight == 0)
	{
		return SwapchainStatus.NotReady;
	}

	if (result.width == newWidth && result.height == newHeight)
	{
		return SwapchainStatus.Ready;
	}

	Swapchain old = *result;

	createSwapchain(result, physicalDevice, device, surface, familyIndex, format, renderPass, old.swapchain);

	enforceVK(vkDeviceWaitIdle(device));

	destroySwapchain(device, &old);

	return SwapchainStatus.Resized;
}