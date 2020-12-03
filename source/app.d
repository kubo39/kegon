version(Windows) import core.sys.windows.windows;
import std.stdio;
import std.string;

import bindbc.glfw;
import bindbc.loader;
import erupted;

import kegon.common;
import kegon.device;
import kegon.swapchain;

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

VkRenderPass createRenderPass(VkDevice device, VkFormat colorFormat)
{
	VkAttachmentDescription[1] attachments;
	with (attachments[0])
	{
		format = colorFormat;
		samples = VK_SAMPLE_COUNT_1_BIT;
		loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
		finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
	}

	VkAttachmentReference colorAttachment = { 0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
	VkSubpassDescription subpass = {
		pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
		colorAttachmentCount: 1,
		pColorAttachments: &colorAttachment,
	};
	VkRenderPassCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
		attachmentCount: 1,
		pAttachments: attachments.ptr,
		subpassCount: 1,
		pSubpasses: &subpass,
	};
	VkRenderPass renderPass;
	assert(vkCreateRenderPass(device, &createInfo, null, &renderPass) == VkResult.VK_SUCCESS);
	return renderPass;
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
	assert(vkCreateFramebuffer(device, &createInfo, null, &framebuffer) == VkResult.VK_SUCCESS);
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
	assert(vkCreateImageView(device, &createInfo, null, &view) == VkResult.VK_SUCCESS);
	return view;
}

void main()
{
	VkInstance instance = createInstance();
	scope(exit) vkDestroyInstance(instance, null);
	kegon.common.loadInstanceLevelFunctions(instance);

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
	kegon.common.loadDeviceLevelFunctions(instance);

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

	VkRenderPass renderPass = createRenderPass(device, swapchainFormat);
	assert(renderPass);
	scope(exit) vkDestroyRenderPass(device, renderPass, null);

	Swapchain swapchain;
	createSwapchain(&swapchain, physicalDevice, device, surface, familyIndex, swapchainFormat);
	scope(exit) destroySwapchain(device, &swapchain);

	VkImageView[16] swapchainImageViews;
	foreach (uint i; 0 .. swapchain.imageCount)
	{
		swapchainImageViews[i] = createImageView(device, swapchain.images[i], VK_FORMAT_R32_SFLOAT);
		assert(swapchainImageViews[i]);
	}
	scope(exit)
	{
		foreach (uint i; 0 .. swapchain.imageCount)
		{
			vkDestroyImageView(device, swapchainImageViews[i], null);
		}
	}

	VkFramebuffer[16] swapchainFramebuffers;
	foreach (uint i; 0 .. swapchain.imageCount)
	{
		swapchainFramebuffers[i] = createFramebuffer(device, renderPass, swapchainImageViews[i], swapchain.width, swapchain.height);
		assert(swapchainFramebuffers[i]);
	}
	scope(exit)
	{
		foreach (uint i; 0 .. swapchain.imageCount)
		{
			vkDestroyFramebuffer(device, swapchainFramebuffers[i], null);
		}
	}

	VkCommandPool commandPool = createCommandPool(device, familyIndex);
	assert(commandPool);
	scope(exit) vkDestroyCommandPool(device, commandPool, null);

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

		// TODO: not sure but could not fill the image.
		VkClearColorValue color;
		color.int32 = [1, 0, 1, 1];
		VkClearValue clearColor = { color: color };

		VkRenderPassBeginInfo passBeginInfo = {
			sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
			renderPass: renderPass,
			framebuffer: swapchainFramebuffers[imageIndex],
			clearValueCount: 1,
			pClearValues: &clearColor,
		};
		passBeginInfo.renderArea.extent.width = swapchain.width;
		passBeginInfo.renderArea.extent.height = swapchain.height;
		vkCmdBeginRenderPass(commandBuffer, &passBeginInfo, VK_SUBPASS_CONTENTS_INLINE);

		// draw calls

		vkCmdEndRenderPass(commandBuffer);

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