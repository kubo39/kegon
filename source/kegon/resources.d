module kegon.resources;

import erupted;

import kegon.common;

VkImageMemoryBarrier imageBarrier(VkImage image, VkAccessFlags srcAccessMask, VkAccessFlags dstAccessMask, VkImageLayout oldLayout, VkImageLayout newLayout)
{
    VkImageSubresourceRange subresourceRange = {
        aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
        levelCount: VK_REMAINING_MIP_LEVELS,
        layerCount: VK_REMAINING_ARRAY_LAYERS,
    };
    VkImageMemoryBarrier result = {
        srcAccessMask: srcAccessMask,
        dstAccessMask: dstAccessMask,
        oldLayout: oldLayout,
        newLayout: newLayout,
        srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
        image: image,
        subresourceRange: subresourceRange,
    };
    return result;
}

struct Buffer
{
	VkBuffer buffer;
	VkDeviceMemory memory;
	void* data;
	size_t size;
}

private uint selectMemoryType(const ref VkPhysicalDeviceMemoryProperties memoryProperties, uint memoryTypeBits, VkMemoryPropertyFlags flags)
{
	foreach (i; 0 .. memoryProperties.memoryTypeCount)
	{
		if ((memoryTypeBits & (1 << i)) != 0 && (memoryProperties.memoryTypes[i].propertyFlags & flags) == flags)
		{
			return i;
		}
	}
	assert(false, "No compatible memory type found");
}

void createBuffer(ref Buffer result, VkDevice device, const ref VkPhysicalDeviceMemoryProperties memoryProperties, size_t size, VkBufferUsageFlags usage)
{
	VkBufferCreateInfo createInfo = {
		size: size,
		usage: usage,
	};

	VkBuffer buffer;
	enforceVK(vkCreateBuffer(device, &createInfo, null, &buffer));

	VkMemoryRequirements memoryRequirements;
	vkGetBufferMemoryRequirements(device, buffer, &memoryRequirements);

	uint memoryTypeIndex = selectMemoryType(memoryProperties, memoryRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

	VkMemoryAllocateInfo allocateInfo = {
		allocationSize: memoryRequirements.size,
		memoryTypeIndex: memoryTypeIndex,
	};

	VkDeviceMemory memory;
	enforceVK(vkAllocateMemory(device, &allocateInfo, null, &memory));

	enforceVK(vkBindBufferMemory(device, buffer, memory, 0));

	void* data;
	enforceVK(vkMapMemory(device, memory, 0, size, 0, &data));

	result.buffer = buffer;
	result.memory = memory;
	result.data = data;
	result.size = size;
}

void destroyBuffer(ref Buffer buffer, VkDevice device)
{
	vkFreeMemory(device, buffer.memory, null);
	vkDestroyBuffer(device, buffer.buffer, null);
}
