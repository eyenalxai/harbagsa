use std::ffi::CStr;
use std::os::raw::c_char;

use ash::vk;
use rune::{Cx, Color, El, Env, Runtime};
use rune::render::Renderer;

const SIZE: u32 = 256;

fn view(_: &(), _: &mut Cx<()>) -> El {
    rune::el()
        .w_full()
        .h_full()
        .fill(Color { r: 1.0, g: 0.0, b: 0.0, a: 1.0 })
}

fn graphics_family(instance: &ash::Instance, device: vk::PhysicalDevice) -> u32 {
    let families = unsafe { instance.get_physical_device_queue_family_properties(device) };
    families
        .iter()
        .position(|f| f.queue_flags.contains(vk::QueueFlags::GRAPHICS))
        .expect("no graphics queue family") as u32
}

fn memory_type(
    instance: &ash::Instance,
    device: vk::PhysicalDevice,
    bits: u32,
    flags: vk::MemoryPropertyFlags,
) -> u32 {
    let props = unsafe { instance.get_physical_device_memory_properties(device) };
    for (i, ty) in props.memory_types_as_slice().iter().enumerate() {
        if bits & (1 << i) != 0 && ty.property_flags.contains(flags) {
            return i as u32;
        }
    }
    panic!("no memory type for {bits:#x}");
}

fn main() {
    let entry = unsafe { ash::Entry::load() }.expect("load Vulkan");
    let flags = wgpu::InstanceFlags::default();
    let instance_extensions = wgpu::hal::vulkan::Instance::desired_extensions(
        &entry,
        vk::API_VERSION_1_3,
        flags,
    )
    .expect("wgpu instance extensions");

    let app_name = CStr::from_bytes_with_nul(b"harbagsa-ui-spike\0").unwrap();
    let extension_ptrs: Vec<*const c_char> =
        instance_extensions.iter().map(|e| e.as_ptr()).collect();
    let application = vk::ApplicationInfo::default()
        .application_name(app_name)
        .api_version(vk::API_VERSION_1_3);
    let create_info = vk::InstanceCreateInfo::default()
        .application_info(&application)
        .enabled_extension_names(&extension_ptrs);
    let raw_instance = unsafe { entry.create_instance(&create_info, None) }
        .expect("vkCreateInstance");

    let hal_instance = unsafe {
        wgpu::hal::vulkan::Instance::from_raw(
            entry.clone(),
            raw_instance.clone(),
            vk::API_VERSION_1_3,
            0,
            None,
            instance_extensions.clone(),
            flags,
            wgpu::MemoryBudgetThresholds::default(),
            false,
            None,
        )
    }
    .expect("adopt the instance");
    let instance =
        unsafe { wgpu::Instance::from_hal::<wgpu::hal::api::Vulkan>(hal_instance) };

    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    let adapter = adapters.into_iter().next().expect("no Vulkan adapter");
    let info = adapter.get_info();
    println!("adapter: {} ({:?})", info.name, info.backend);

    let hal_adapter = unsafe { adapter.as_hal::<wgpu::hal::api::Vulkan>() }
        .expect("adapter hal");
    let raw_physical = unsafe { hal_adapter.raw_physical_device() };
    let features = wgpu::Features::empty();
    let device_extensions = unsafe { hal_adapter.required_device_extensions(features) };
    let mut device_features =
        unsafe { hal_adapter.physical_device_features(&device_extensions, features) };
    let limits = adapter.limits();
    let memory_hints = wgpu::MemoryHints::default();

    let family = graphics_family(&raw_instance, raw_physical);
    let priority = [1.0f32];
    let queue_info = vk::DeviceQueueCreateInfo::default()
        .queue_family_index(family)
        .queue_priorities(&priority);
    let device_extension_ptrs: Vec<*const c_char> =
        device_extensions.iter().map(|e| e.as_ptr()).collect();
    let device_info = vk::DeviceCreateInfo::default()
        .queue_create_infos(std::slice::from_ref(&queue_info))
        .enabled_extension_names(&device_extension_ptrs);
    let device_info = device_features.add_to_device_create(device_info);
    let raw_device =
        unsafe { raw_instance.create_device(raw_physical, &device_info, None) }
            .expect("vkCreateDevice");

    let open_device = unsafe {
        hal_adapter.device_from_raw(
            raw_device.clone(),
            None,
            &device_extensions,
            features,
            &limits,
            &memory_hints,
            family,
            0,
        )
    }
    .expect("adopt the device");
    let (device, queue) = unsafe {
        adapter.create_device_from_hal::<wgpu::hal::api::Vulkan>(
            open_device,
            &wgpu::DeviceDescriptor {
                label: Some("harbagsa-ui"),
                required_features: features,
                required_limits: limits.clone(),
                experimental_features: wgpu::ExperimentalFeatures::disabled(),
                memory_hints: memory_hints.clone(),
                trace: wgpu::Trace::Off,
            },
        )
    }
    .expect("create the wgpu device");

    let image_info = vk::ImageCreateInfo::default()
        .image_type(vk::ImageType::TYPE_2D)
        .format(vk::Format::R8G8B8A8_UNORM)
        .extent(vk::Extent3D {
            width: SIZE,
            height: SIZE,
            depth: 1,
        })
        .mip_levels(1)
        .array_layers(1)
        .samples(vk::SampleCountFlags::TYPE_1)
        .tiling(vk::ImageTiling::OPTIMAL)
        .usage(vk::ImageUsageFlags::COLOR_ATTACHMENT | vk::ImageUsageFlags::TRANSFER_SRC)
        .sharing_mode(vk::SharingMode::EXCLUSIVE)
        .initial_layout(vk::ImageLayout::UNDEFINED);
    let image = unsafe { raw_device.create_image(&image_info, None) }.expect("vkCreateImage");
    let requirements = unsafe { raw_device.get_image_memory_requirements(image) };
    let type_index = memory_type(
        &raw_instance,
        raw_physical,
        requirements.memory_type_bits,
        vk::MemoryPropertyFlags::DEVICE_LOCAL,
    );
    let allocation = vk::MemoryAllocateInfo::default()
        .allocation_size(requirements.size)
        .memory_type_index(type_index);
    let memory = unsafe { raw_device.allocate_memory(&allocation, None) }
        .expect("vkAllocateMemory");
    unsafe { raw_device.bind_image_memory(image, memory, 0) }.expect("vkBindImageMemory");

    let hal_desc = wgpu::hal::TextureDescriptor {
        label: Some("ui-target"),
        size: wgpu::Extent3d {
            width: SIZE,
            height: SIZE,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUses::COLOR_TARGET | wgpu::TextureUses::COPY_SRC,
        memory_flags: wgpu::hal::MemoryFlags::empty(),
        view_formats: vec![],
    };
    let hal_device = unsafe { device.as_hal::<wgpu::hal::api::Vulkan>() }
        .expect("device hal");
    let hal_texture = unsafe {
        hal_device.texture_from_raw(
            image,
            &hal_desc,
            None,
            wgpu::hal::vulkan::TextureMemory::External,
        )
    };
    let descriptor = wgpu::TextureDescriptor {
        label: Some("ui-target"),
        size: hal_desc.size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    };
    let texture = unsafe {
        device.create_texture_from_hal::<wgpu::hal::api::Vulkan>(
            hal_texture,
            &descriptor,
            wgpu::TextureUses::COLOR_TARGET,
        )
    };
    let target = texture.create_view(&wgpu::TextureViewDescriptor::default());

    let mut runtime = Runtime::new(
        (),
        view,
        (SIZE as f32, SIZE as f32),
        Env::new(false, 1.0),
    );
    runtime.frame(0.0);
    println!("instances: {}", runtime.instances.len());

    let mut renderer = Renderer::new(&device, wgpu::TextureFormat::Rgba8Unorm);
    renderer.prepare(
        &device,
        &queue,
        &mut runtime.text.atlas,
        &runtime.instances,
        (SIZE, SIZE),
    );

    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("readback"),
        size: u64::from(SIZE * SIZE * 4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("spike"),
    });
    renderer.encode_layers(&mut encoder);
    renderer.draw_target_range_with(
        &mut encoder,
        &target,
        wgpu::TextureFormat::Rgba8Unorm,
        wgpu::LoadOp::Clear(wgpu::Color::BLACK),
        0..runtime.instances.len() as u32,
        &mut |_, _| {},
    );
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &buffer,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(SIZE * 4),
                rows_per_image: Some(SIZE),
            },
        },
        wgpu::Extent3d {
            width: SIZE,
            height: SIZE,
            depth_or_array_layers: 1,
        },
    );
    renderer.submit(&queue, encoder);

    let slice = buffer.slice(..);
    let (sender, receiver) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        sender.send(result).unwrap();
    });
    device.poll(wgpu::PollType::wait_indefinitely()).expect("poll");
    receiver.recv().expect("map callback").expect("map");
    let data = slice.get_mapped_range().expect("map range");
    let pixel = &data[0..4];
    println!("pixel: {pixel:?}");
    assert!(pixel[0] > 100, "expected red, got {pixel:?}");
    println!("ok");
}
