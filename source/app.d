version(Windows) import core.sys.windows.windows;
import std.path;
import std.stdio;
import std.string;

import bindbc.glfw;
import bindbc.loader;
import erupted;

import kegon.common;
import kegon.device;
import kegon.shaders;
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
	enforceVK(vkCreateSemaphore(device, &createInfo, null, &semaphore));
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
	enforceVK(vkCreateCommandPool(device, &createInfo, null, &commandPool));
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
		initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
	}

	VkAttachmentReference colorAttachment = {
		attachment: 0,
		layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
	};
	VkSubpassDescription subpass = {
		pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
		colorAttachmentCount: 1,
		pColorAttachments: &colorAttachment,
	};

	VkSubpassDependency dependency = {
		srcSubpass: VK_SUBPASS_EXTERNAL,
		dstSubpass: 0,
		srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
		srcAccessMask: 0,
		dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
		dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
	};

	VkRenderPassCreateInfo createInfo = {
		sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
		attachmentCount: 1,
		pAttachments: attachments.ptr,
		subpassCount: 1,
		pSubpasses: &subpass,
		dependencyCount: 1,
		pDependencies: &dependency,
	};
	VkRenderPass renderPass;
	enforceVK(vkCreateRenderPass(device, &createInfo, null, &renderPass));
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

void main()
{
	VkInstance instance = createInstance();
	scope(exit) vkDestroyInstance(instance, null);
	kegon.common.loadInstanceLevelFunctions(instance);

	VkPhysicalDevice[16] physicalDevices;
	uint physicalDeviceCount = cast(uint) physicalDevices.length;
	enforceVK(vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, physicalDevices.ptr));
	VkPhysicalDevice physicalDevice = pickPhysicalDevice(physicalDevices.ptr, physicalDeviceCount);
	assert(physicalDevice);

	uint extensionCount = 0;
	enforceVK(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, null));
	auto extensions = new VkExtensionProperties[](extensionCount);
	enforceVK(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, extensions.ptr));

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
	enforceVK(vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, familyIndex, surface, &presentSupported));
	assert(presentSupported);

	VkFormat swapchainFormat = getSwapchainFormat(physicalDevice, surface);
	assert(swapchainFormat);

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

	VkShaderModule triangleVS = loadShader(device, buildPath("source", "kegon", "shaders", "triangle.vert.spv"));
	assert(triangleVS);
	scope(exit) vkDestroyShaderModule(device, triangleVS, null);
	VkShaderModule triangleFS = loadShader(device, buildPath("source", "kegon", "shaders", "triangle.frag.spv"));
	assert(triangleFS);
	scope(exit) vkDestroyShaderModule(device, triangleFS, null);

	VkPipelineLayout triangleLayout = createPipelineLayout(device);
	assert(triangleLayout);
	scope(exit) vkDestroyPipelineLayout(device, triangleLayout, null);

	VkPipeline trianglePipeline = createGraphicsPipeline(device, renderPass, triangleVS, triangleFS, triangleLayout);
	assert(trianglePipeline);
	scope(exit) vkDestroyPipeline(device, trianglePipeline, null);

	Swapchain swapchain;
	createSwapchain(&swapchain, physicalDevice, device, surface, familyIndex, swapchainFormat);
	scope(exit) destroySwapchain(device, &swapchain);

	VkImageView[16] swapchainImageViews;
	foreach (uint i; 0 .. swapchain.imageCount)
	{
		swapchainImageViews[i] = createImageView(device, swapchain.images[i], swapchainFormat);
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
	enforceVK(vkAllocateCommandBuffers(device, &allocateInfo, &commandBuffer));

	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();

		uint imageIndex = 0;
		enforceVK(vkAcquireNextImageKHR(device, swapchain.swapchain, ~0UL, acquireSemaphore, VK_NULL_HANDLE, &imageIndex));

		enforceVK(vkResetCommandPool(device, commandPool, 0));

		VkCommandBufferBeginInfo beginInfo = {
			sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
			flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
		};
		enforceVK(vkBeginCommandBuffer(commandBuffer, &beginInfo));

		VkClearColorValue color;
		color.float32 = [48.0f / 255.0f, 10.0f / 255.0f, 36.0f / 255.0f, 1.0f];
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

		VkViewport viewport = { 0.0f, cast(float) swapchain.height, cast(float) swapchain.width, -1 * cast(float) swapchain.height, 0.0f, 1.0f };
		VkRect2D scissor = { { 0, 0 }, { swapchain.width, swapchain.height } };

		vkCmdSetViewport(commandBuffer, 0, 1, &viewport);
		vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

		vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, trianglePipeline);
		vkCmdDraw(commandBuffer, 3, 1, 0, 0);

		vkCmdEndRenderPass(commandBuffer);

		enforceVK(vkEndCommandBuffer(commandBuffer));

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
		enforceVK(vkQueueSubmit(queue, 1, &submitInfo, VK_NULL_HANDLE));

		VkPresentInfoKHR presentInfo = {
			sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
			waitSemaphoreCount: 1,
			pWaitSemaphores: &releaseSemaphore,
			pSwapchains: &swapchain.swapchain,
			swapchainCount: 1,
			pImageIndices: &imageIndex,
		};
		enforceVK(vkQueuePresentKHR(queue, &presentInfo));

		enforceVK(vkDeviceWaitIdle(device));
	}
}