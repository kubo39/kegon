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
        sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
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