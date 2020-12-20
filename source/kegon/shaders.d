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
        codeSize: length,
        pCode: cast(const(uint)*) buffer,
    };
    VkShaderModule shaderModule;
    enforceVK(vkCreateShaderModule(device, &createInfo, null, &shaderModule));
    return shaderModule;
}

VkDescriptorSetLayout createSetLayout(VkDevice device)
{
	VkDescriptorSetLayoutBinding setBinding = {
		binding: 0,
		descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
		descriptorCount: 1,
		stageFlags: VK_SHADER_STAGE_VERTEX_BIT,
	};
	VkDescriptorSetLayoutCreateInfo createInfo = {
		flags: VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR,
		bindingCount: 1,
		pBindings: &setBinding,
	};
	VkDescriptorSetLayout setLayout;
	enforceVK(vkCreateDescriptorSetLayout(device, &createInfo, null, &setLayout));
	return setLayout;	
}

VkPipelineLayout createPipelineLayout(VkDevice device, VkDescriptorSetLayout setLayout)
{
    VkPipelineLayoutCreateInfo createInfo = {
		setLayoutCount: 1,
		pSetLayouts: &setLayout,
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

    VkPipelineVertexInputStateCreateInfo vertexInput;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
        topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };

    VkPipelineViewportStateCreateInfo viewportState = {
        viewportCount: 1,
        scissorCount: 1,
    };

    VkPipelineRasterizationStateCreateInfo rasterizationState = {
        depthClampEnable: VK_FALSE,
        lineWidth: 1.0f,
        depthBiasEnable: VK_FALSE,
        depthBiasClamp: 0.0f,
    };

    VkPipelineMultisampleStateCreateInfo multisampeState = {
        rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
    };

    VkPipelineDepthStencilStateCreateInfo depthStencilState;

    VkPipelineColorBlendAttachmentState colorAttachmentState;
    colorAttachmentState.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;

    VkPipelineColorBlendStateCreateInfo colorBlendState = {
        attachmentCount: 1,
        pAttachments: &colorAttachmentState,
    };

    VkDynamicState[2] dynamicStates = [
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR
    ];
    VkPipelineDynamicStateCreateInfo dynamicState = {
        dynamicStateCount: cast(uint) dynamicStates.length,
        pDynamicStates: dynamicStates.ptr,
    };

    VkGraphicsPipelineCreateInfo createInfo = {
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