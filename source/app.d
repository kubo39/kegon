version(Windows) import core.sys.windows.windows;
import core.stdc.string : memcpy;
import std.path;
import std.stdio;
import std.string;

import bindbc.glfw;
import bindbc.loader;
import erupted;

import kegon.common;
import kegon.device;
import kegon.objparser;
import kegon.resources;
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
	VkSemaphoreCreateInfo createInfo;
	VkSemaphore semaphore;
	enforceVK(vkCreateSemaphore(device, &createInfo, null, &semaphore));
	return semaphore;
}

VkCommandPool createCommandPool(VkDevice device, uint familyIndex)
{
	VkCommandPoolCreateInfo createInfo = {
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

struct Vertex
{
	float vx, vy, vz;
	ubyte nx, ny, nz, nw;
	float tu, tv;
}

struct Mesh
{
	Vertex[] vertices;
	uint[] indices;
}

bool loadMesh(ref Mesh result, string path)
{
	import std.string : toStringz;

	ObjFile file;
	if (!objParseFile(file, path.toStringz))
	{
		return false;
	}
	assert(objValidate(file));

	size_t indexCount = file.f_size / 3;

	auto vertices = new Vertex[](indexCount);

	foreach (i; 0 .. indexCount)
	{
		auto v = &vertices[i];

		int vi = file.f[i * 3 + 0];
		int vti = file.f[i * 3 + 1];
		int vni = file.f[i * 3 + 2];

		float nx = vni < 0 ? 0.0f : file.vn[vni * 3 + 0];
		float ny = vni < 0 ? 0.0f : file.vn[vni * 3 + 1];
		float nz = vni < 0 ? 1.0f : file.vn[vni * 3 + 2];

		v.vx = file.v[vi * 3 + 0];
		v.vy = file.v[vi * 3 + 1];
		v.vz = file.v[vi * 3 + 2];
		v.nx = cast(ubyte) (nx * 127.0f + 127.5f);
		v.ny = cast(ubyte) (ny * 127.0f + 127.5f);
		v.nz = cast(ubyte) (nz * 127.0f + 127.5f);
		v.tu = vti < 0 ? 0.0f : file.vt[vti * 3 + 0];
		v.tv = vti < 0 ? 0.0f : file.vt[vti * 3 + 1];
	}

	result.vertices = vertices;
	result.indices = new uint[](indexCount);
	foreach (i; 0 .. indexCount)
	{
		result.indices[i] = cast(uint) i;
	}

	return true;
}

void main(string[] args)
{
	if (args.length < 2)
	{
		writefln("Usage: %s [mesh]", args[0]);
		assert(false);
	}

	VkInstance instance = createInstance();
	scope(exit) vkDestroyInstance(instance, null);
	kegon.common.loadInstanceLevelFunctions(instance);

	VkDebugReportCallbackEXT debugCallback = registerDebugCallback(instance);
	assert(debugCallback);
	scope(exit) vkDestroyDebugReportCallbackEXT(instance, debugCallback, null);

	VkPhysicalDevice[16] physicalDevices;
	uint physicalDeviceCount = cast(uint) physicalDevices.length;
	enforceVK(vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, physicalDevices.ptr));
	VkPhysicalDevice physicalDevice = pickPhysicalDevice(physicalDevices.ptr, physicalDeviceCount);
	assert(physicalDevice);

	uint extensionCount = 0;
	enforceVK(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, null));
	auto extensions = new VkExtensionProperties[](extensionCount);
	enforceVK(vkEnumerateDeviceExtensionProperties(physicalDevice, null, &extensionCount, extensions.ptr));

	bool pushDescriptorsSupported = false;
	bool meshShadingSupported = false;

	foreach (extension; extensions)
	{
		pushDescriptorsSupported = pushDescriptorsSupported || (extension.extensionName.ptr.fromStringz == VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME);
		meshShadingSupported = meshShadingSupported || (extension.extensionName.ptr.fromStringz == VK_NV_MESH_SHADER_EXTENSION_NAME);
	}

	VkPhysicalDeviceProperties props;
	vkGetPhysicalDeviceProperties(physicalDevice, &props);
	assert(props.limits.timestampComputeAndGraphics);

	const uint familyIndex = getGraphicsFamilyIndex(physicalDevice);
	assert(familyIndex != VK_QUEUE_FAMILY_IGNORED);

	VkDevice device = createDevice(instance, physicalDevice, familyIndex, pushDescriptorsSupported, meshShadingSupported);
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

	VkDescriptorSetLayout setLayout = createSetLayout(device);
	assert(setLayout);
	scope(exit) vkDestroyDescriptorSetLayout(device, setLayout, null);

	VkPipelineLayout triangleLayout = createPipelineLayout(device, setLayout);
	assert(triangleLayout);
	scope(exit) vkDestroyPipelineLayout(device, triangleLayout, null);

	VkPipeline trianglePipeline = createGraphicsPipeline(device, renderPass, triangleVS, triangleFS, triangleLayout);
	assert(trianglePipeline);
	scope(exit) vkDestroyPipeline(device, trianglePipeline, null);

	Swapchain swapchain;
	createSwapchain(&swapchain, physicalDevice, device, surface, familyIndex, swapchainFormat, renderPass, VK_NULL_HANDLE);
	scope(exit) destroySwapchain(device, &swapchain);

	VkCommandPool commandPool = createCommandPool(device, familyIndex);
	assert(commandPool);
	scope(exit) vkDestroyCommandPool(device, commandPool, null);

	VkCommandBufferAllocateInfo allocateInfo = {
		commandPool: commandPool,
		level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
		commandBufferCount: 1,
	};
	VkCommandBuffer commandBuffer;
	enforceVK(vkAllocateCommandBuffers(device, &allocateInfo, &commandBuffer));

	VkPhysicalDeviceMemoryProperties memoryProperties;
	vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);

	Mesh mesh;
	bool rcm = loadMesh(mesh, args[1]);
	assert(rcm);

	Buffer vb;
	createBuffer(vb, device, memoryProperties, 128 * 1024 * 1024, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
	assert(vb.buffer);
	assert(vb.memory);
	scope(exit) destroyBuffer(vb, device);

	Buffer ib;
	createBuffer(ib, device, memoryProperties, 128 * 1024 * 1024, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT);
	assert(ib.buffer);
	assert(ib.memory);
	scope(exit) destroyBuffer(ib, device);

	assert(vb.size >= mesh.vertices.length * Vertex.sizeof);
	memcpy(vb.data, mesh.vertices.ptr, mesh.vertices.length * Vertex.sizeof);

	assert(ib.size >= mesh.indices.length * uint.sizeof);
	memcpy(ib.data, mesh.indices.ptr, mesh.indices.length * uint.sizeof);

	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();

		SwapchainStatus swapchainStatus = updateSwapchain(&swapchain, physicalDevice, device, surface, familyIndex, swapchainFormat, renderPass);

		if (swapchainStatus == SwapchainStatus.NotReady)
		{
			continue;
		}

		uint imageIndex = 0;
		enforceVK(vkAcquireNextImageKHR(device, swapchain.swapchain, ~0UL, acquireSemaphore, VK_NULL_HANDLE, &imageIndex));

		enforceVK(vkResetCommandPool(device, commandPool, 0));

		VkCommandBufferBeginInfo beginInfo = {
			flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
		};
		enforceVK(vkBeginCommandBuffer(commandBuffer, &beginInfo));

		VkImageMemoryBarrier renderBeginBarrier = imageBarrier(swapchain.images[imageIndex], 0, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
		vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_DEPENDENCY_BY_REGION_BIT, 0, null, 0, null, 1, &renderBeginBarrier);

		VkClearColorValue color;
		color.float32 = [48.0f / 255.0f, 10.0f / 255.0f, 36.0f / 255.0f, 1.0f];
		VkClearValue clearColor = { color: color };

		VkRenderPassBeginInfo passBeginInfo = {
			renderPass: renderPass,
			framebuffer: swapchain.framebuffers[imageIndex],
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

		VkDescriptorBufferInfo bufferInfo = {
			buffer: vb.buffer,
			offset: 0,
			range: vb.size,
		};

		VkWriteDescriptorSet descriptor = {
			dstBinding: 0,
			descriptorCount: 1,
			descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
			pBufferInfo: &bufferInfo,
		};
		vkCmdPushDescriptorSetKHR(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, triangleLayout, 0, 1, &descriptor);

		vkCmdBindIndexBuffer(commandBuffer, ib.buffer, 0, VK_INDEX_TYPE_UINT32);
		vkCmdDrawIndexed(commandBuffer, cast(uint) mesh.indices.length, 1, 0, 0, 0);

		vkCmdEndRenderPass(commandBuffer);

		VkImageMemoryBarrier renderEndBarrier = imageBarrier(swapchain.images[imageIndex], VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, 0, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
		vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_DEPENDENCY_BY_REGION_BIT, 0, null, 0, null, 1, &renderEndBarrier);

		enforceVK(vkEndCommandBuffer(commandBuffer));

		VkPipelineStageFlags submitStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		VkSubmitInfo submitInfo = {
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