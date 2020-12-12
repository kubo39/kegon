module kegon.shaders;

import std.stdio;

import erupted;

import kegon.common;

VkShaderModule loadShader(VkDevice device, string path)
{
    auto f = File(path, "rb");
    scope(exit) f.close;
    size_t length = f.size;
    auto buffer = f.rawRead(new char[length]);

    assert(length % 4 == 0);

    VkShaderModuleCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        codeSize: length,
        pCode: cast(const(uint)*) buffer,
    };
    VkShaderModule shaderModule;
    enforceVK(vkCreateShaderModule(device, &createInfo, null, &shaderModule));
    return shaderModule;
}

VkPipelineLayout createPipelineLayout(VkDevice device)
{
    VkPipelineLayoutCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };
    VkPipelineLayout layout;
    enforceVK(vkCreatePipelineLayout(device, &createInfo, null, &layout));
    return layout;
}

VkPipeline createGraphicsPipeline(VkDevice device, VkRenderPass renderPass, VkShaderModule vs, VkShaderModule fs, VkPipelineLayout layout)
{
    VkPipelineShaderStageCreateInfo[2] stages;
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].Module = vs;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].Module = fs;
    stages[1].pName = "main";

    // legacy FFP IA
    VkVertexInputBindingDescription stream = { 0, 32, VK_VERTEX_INPUT_RATE_VERTEX };
    VkVertexInputAttributeDescription[3] attrs;

    attrs[0].location = 0;
    attrs[0].format = VK_FORMAT_R32G32B32_SFLOAT;
    attrs[0].offset = 0;
    attrs[1].location = 1;
    attrs[1].format = VK_FORMAT_R32G32B32_SFLOAT;
    attrs[1].offset = 12;
    attrs[2].location = 2;
    attrs[2].format = VK_FORMAT_R32G32_SFLOAT;
    attrs[2].offset = 24;

    VkPipelineVertexInputStateCreateInfo vertexInput = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount: 1,
        pVertexBindingDescriptions: &stream,
        vertexAttributeDescriptionCount: 3,
        pVertexAttributeDescriptions: attrs.ptr,
    };

    VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };

    VkPipelineViewportStateCreateInfo viewportState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount: 1,
        scissorCount: 1,
    };

    VkPipelineRasterizationStateCreateInfo rasterizationState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable: VK_FALSE,
        lineWidth: 1.0f,
        depthBiasEnable: VK_FALSE,
        depthBiasClamp: 0.0f,
    };

    VkPipelineMultisampleStateCreateInfo multisampeState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
    };

    VkPipelineDepthStencilStateCreateInfo depthStencilState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    };

    VkPipelineColorBlendAttachmentState colorAttachmentState;
    colorAttachmentState.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

    VkPipelineColorBlendStateCreateInfo colorBlendState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount: 1,
        pAttachments: &colorAttachmentState,
    };

    VkDynamicState[2] dynamicStates = [
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR
    ];
    VkPipelineDynamicStateCreateInfo dynamicState = {
        sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount: cast(uint) dynamicStates.length,
        pDynamicStates: dynamicStates.ptr,
    };

    VkGraphicsPipelineCreateInfo createInfo = {
        sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount: 2,
        pStages: stages.ptr,
        pVertexInputState: &vertexInput,
        pInputAssemblyState: &inputAssembly,
        pViewportState: &viewportState,
        pRasterizationState: &rasterizationState,
        pMultisampleState: &multisampeState,
        pDepthStencilState: &depthStencilState,
        pColorBlendState: &colorBlendState,
        pDynamicState: &dynamicState,
        layout: layout,
        renderPass: renderPass,
    };

    VkPipeline pipeline;
    enforceVK(vkCreateGraphicsPipelines(device, null, 1, &createInfo, null, &pipeline));
    return pipeline;
}