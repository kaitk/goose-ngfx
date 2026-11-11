// The ngfx layer's device and frames: opening NoGraphicsAPI, recording and
// submitting each frame, the upload queue and deferred releases, and the
// screen, which windowed is the window's image.

#include "ngfx_gpu.hpp"

#include <thread>


namespace ngfx {

State g;

namespace {

void report_error(const char* message, bool fatal) noexcept
{
    ngfx_fail("NoGraphicsAPI: %s", message);
    if (fatal) fprintf(stderr, "ngfx: NoGraphicsAPI: %s\n", message);
}

// The releases since the last submission, to run once `retire` has.
void run_pending(uint64 retire)
{
    for (Release& r : g.pending)
    {
        r.retire = retire;
        g.retiring.push_back(r);
    }
    g.pending.clear();
}

// Runs the releases whose submissions have finished; all of them when `all`.
void release_retired(bool all)
{
    const uint64 done = all ? UINT64_MAX : timeline_completed_value(g.timeline.semaphore);
    size_t n = 0;
    while (n < g.retiring.size() && g.retiring[n].retire <= done) ++n;
    if (!n) return;
    // A release may defer another, which lands in `pending`, not here.
    for (size_t i = 0; i < n; ++i) g.retiring[i].fn(g.retiring[i].arg);
    g.retiring.erase(g.retiring.begin(), g.retiring.begin() + ptrdiff_t(n));
}

void begin_frame_commands()
{
    g.commands = begin_commands(g.pools[g.slot]);
    // Command-buffer bindings are not inherited (NoGraphicsAPI.hpp), so every
    // buffer gets the heaps.
    set_texture_descriptor_heap(g.commands, g.texture_descriptors);
    set_sampler_descriptor_heap(g.commands, g.sampler_descriptors);
    g.bound_pso = nullptr;
}

// GOOSE_NGFX_BENCH=1: the frame's stamps in this slot, which its
// commands write and the timeline wait has seen finish.
void collect_stamps(uint32 slot)
{
    read_timestamps(g.pools[slot]);
    BenchStamps& s = g.bench_stamps[slot];
    if (s.begin && s.passes_end) g.bench_frames.push_back(s);
    s = {};
}

void begin_frame_stamps()
{
    if (g.bench) write_timestamp(g.commands, &g.bench_stamps[g.slot].begin);
}

// Per frame, on stderr: the GPU time of the frame's passes in microseconds,
// then 0 and the same time again (once the screen's copy and the whole
// frame, kept for bench/run_bench.py); then the time ngfx::slang took.
void print_stamps()
{
    const double us = get_device_caps(g.device).timestamp_period_ns / 1000.0;
    for (const BenchStamps& s : g.bench_frames)
    {
        const double passes = double(s.passes_end - s.begin) * us;
        fprintf(stderr, "ngfx_bench gpu %.2f 0.00 %.2f\n", passes, passes);
    }
    double seconds = 0;
    int modules = 0;
    ngfx_slang_time(&seconds, &modules);
    fprintf(stderr, "ngfx_bench slang %.1f %d\n", seconds * 1000.0, modules);
}

// Clears the headless screen to black, and its depth, if it has one, to
// far, as gfx's starts.
void clear_screen()
{
    TextureSlot* color = g.windowed ? nullptr : texture_slot(g.screen);
    TextureSlot* depth = g.screen_depth.id ? texture_slot(g.screen_depth) : nullptr;
    if (!color && !depth) return;
    CommandBuffer* commands = frame_commands();
    frame_boundary_barrier(commands);
    const ColorAttachment colors[] = {{.render_view = color ? render_view(color, 0, 0) : nullptr, .load = LoadOp::clear,
                                       .clear = {.x = 0.0f, .y = 0.0f, .z = 0.0f, .w = 1.0f}}};
    RenderingDesc pass{.colors = {colors, color ? 1u : 0u}};
    if (depth) pass.depth = {.render_view = render_view(depth, 0, 0), .load = LoadOp::clear, .clear = 1.0f};
    begin_render_pass(commands, pass);
    end_render_pass(commands);
}

// Puts a new texture of `desc` behind `handle`, the old one released once
// the frames using it finish.
bool replace_texture(ngfx_texture& handle, const ngfx_texture_desc& desc)
{
    uint32 id = 0;
    TextureSlot* fresh = nullptr;
    if (!create_texture(desc, &id, &fresh)) return false;
    TextureSlot* old = g.textures.find(handle.id);
    if (!old)
    {
        handle.id = id;
        return true;
    }
    if (old->placed.texture) release_texture_later(*old);
    *old = *fresh;
    g.textures.remove(id);
    return true;
}

void release_stand_in()
{
    if (g.stand_in.placed.texture) release_texture_later(g.stand_in);
    g.stand_in = {};
}

// The screen's depth at w x h.
bool create_screen_depth(int w, int h)
{
    return replace_texture(g.screen_depth, {.kind = NGFX_TEXTURE_2D, .format = NGFX_DEPTH, .usage = NGFX_DEPTH_TARGET,
                                            .width = w, .height = h, .depth = 1, .mips = 1});
}

// The screen at w x h, with its depth only once a program has asked for it
// (screen_depth()): most draw the screen without one. Windowed, the screen's
// slot only describes the window's image, which the window's size sets.
bool create_screen(int w, int h)
{
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (g.windowed)
    {
        TextureSlot* s = g.textures.find(g.screen.id);
        if (!s) s = g.textures.add(g.screen.id);
        if (!s) return false;
        s->desc = {.extent = {.x = uint32(w), .y = uint32(h), .z = 1}, .format = Format::bgra8_unorm,
                   .usage = TextureUsage::color_attachment};
        s->goose = {.kind = NGFX_TEXTURE_2D, .format = NGFX_BGRA8, .usage = NGFX_COLOR_TARGET, .width = w, .height = h,
                    .depth = 1, .mips = 1};
        release_stand_in();
    }
    else if (!replace_texture(g.screen, {.kind = NGFX_TEXTURE_2D, .format = NGFX_RGBA8,
                                         .usage = NGFX_SAMPLED | NGFX_COLOR_TARGET, .width = w, .height = h,
                                         .depth = 1, .mips = 1}))
    {
        return false;
    }
    if (g.screen_depth.id && !create_screen_depth(w, h)) return false;
    g.width = w;
    g.height = h;
    clear_screen();
    return true;
}

// Gives back the driver memory that recording keeps: a Metal 4 command
// allocator holds on to the most it was ever recorded into, and resetting it
// returns none, so the frames that set a program up (the textures'
// initialization, uploads in parts) leave their command memory with it for
// good: 11 MB of Draughts' 20 MB of driver memory at rest. The pools are made
// again, and the upload queue too once more than its staging has gone
// through it. Waits for the GPU first, which an idle program has little left
// for.
void trim()
{
    wait_timeline(g.timeline);
    release_retired(false);
    for (uint32 i = 0; i < frames_in_flight; ++i)
    {
        destroy_command_pool(g.pools[i]);
        g.pools[i] = create_command_pool(g.device);
        g.pool_values[i] = 0;
    }
    if (g.uploaded_since_trim > upload_capacity)
    {
        g.uploads->destroy();
        delete g.uploads;
        g.uploads = new UploadQueue(g.device, upload_capacity, 0, upload_batches);
    }
    g.worked_since_trim = false;
    g.uploaded_since_trim = 0;
}

} // namespace

CommandBuffer* frame_commands()
{
    g.worked = true;
    return g.commands;
}

namespace {
struct OldFrameMemory
{
    GpuHeap heap;
    BumpAllocator* data;
};
} // namespace

GpuCpuRange<byte> frame_allocate(uint64 size)
{
    const uint32 i = g.slot;
    GpuCpuRange<byte> r = g.frame_data[i]->allocate(size);
    if (r.size) return r;
    // Outgrown: twice the memory, or room for this, whichever is more. What
    // the frame already holds stays where it is, given back once the frame
    // has finished on the GPU, and the frames after start in the new memory.
    uint64 grown = g.frame_heaps[i].range.size * 2;
    while (grown < size + BumpAllocator::alignment) grown *= 2;
    const GpuHeap heap = create_gpu_heap(g.device, grown, MemoryType::cpu_visible);
    if (!heap.owner) return {};
    defer_release([](void* p) {
        OldFrameMemory* old = static_cast<OldFrameMemory*>(p);
        delete old->data;
        destroy_gpu_heap(old->heap);
        delete old;
    }, new OldFrameMemory{g.frame_heaps[i], g.frame_data[i]});
    g.frame_heaps[i] = heap;
    g.frame_data[i] = new BumpAllocator(heap.range);
    return g.frame_data[i]->allocate(size);
}

RenderView* screen_view()
{
    if (g.drawable) return g.drawable;
    if (!g.stand_in.placed.texture)
    {
        const uint32x2 extent = get_drawable_extent(g.device);
        if (extent.x == uint32(g.width) && extent.y == uint32(g.height))
        {
            // The frame's work so far goes first, so that only the submission
            // that presents waits for the image.
            submit_frame_commands();
            begin_frame_commands();
            const SwapchainFrame frame = acquire(g.commands);
            if (frame.render_view)
            {
                g.drawable = frame.render_view;
                return g.drawable;
            }
        }
        uint32 id = 0;
        TextureSlot* made = nullptr;
        if (!create_texture({.kind = NGFX_TEXTURE_2D, .format = NGFX_BGRA8, .usage = NGFX_COLOR_TARGET,
                             .width = g.width, .height = g.height, .depth = 1, .mips = 1}, &id, &made))
            return nullptr;
        g.stand_in = *made;
        g.textures.remove(id);
    }
    return render_view(&g.stand_in, 0, 0);
}

CommandBuffer* begin_setup()
{
    g.worked = true;
    return begin_commands(g.pools[g.slot]);
}

void end_setup(CommandBuffer* commands)
{
    end_commands(commands);
    ++g.timeline.value;
    submit(g.device, {.commands = {commands}, .completion = g.timeline});
    g.pool_values[g.slot] = g.timeline.value;
}

void defer_release(void (*fn)(void*), void* arg)
{
    g.pending.push_back({.retire = 0, .fn = fn, .arg = arg});
}

void flush_uploads()
{
    g.uploads->flush();
    g.uploaded.clear();
    g.uploaded_textures.clear();
}

void upload(GpuRange destination, const void* data, uint64 size)
{
    g.worked = true;
    g.uploaded_since_trim += size;
    const byte* begin = static_cast<const byte*>(destination.gpu);
    for (const GpuRange& r : g.uploaded)
    {
        const byte* other = static_cast<const byte*>(r.gpu);
        if (begin < other + r.size && other < begin + size)
        {
            flush_uploads();
            break;
        }
    }
    if (data)
    {
        g.uploads->upload_buffer({.gpu = destination.gpu, .size = size}, ByteSpan(data, size_t(size)));
    }
    else
    {
        // UploadQueue copies only from memory, so zeros come from a block of them.
        static const byte zeros[1 << 20] = {};
        for (uint64 at = 0; at < size; at += sizeof zeros)
        {
            const uint64 n = size - at < sizeof zeros ? size - at : sizeof zeros;
            g.uploads->upload_buffer({.gpu = static_cast<byte*>(destination.gpu) + at, .size = n}, ByteSpan(zeros, size_t(n)));
        }
    }
    g.uploaded.push_back({.gpu = destination.gpu, .size = size});
}

void upload_texture(TextureSlot* s, const TextureCopyDesc& region, const void* data, uint64 size)
{
    g.worked = true;
    g.uploaded_since_trim += size;
    auto overlap = [](uint32 a, uint32 a_size, uint32 b, uint32 b_size) { return a < b + b_size && b < a + a_size; };
    for (const TextureUpload& u : g.uploaded_textures)
    {
        const TextureCopyDesc& o = u.region;
        if (u.texture == s->placed.texture && o.mip_level == region.mip_level && o.base_slice == region.base_slice &&
            overlap(o.offset.x, o.extent.x, region.offset.x, region.extent.x) &&
            overlap(o.offset.y, o.extent.y, region.offset.y, region.extent.y) &&
            overlap(o.offset.z, o.extent.z, region.offset.z, region.extent.z))
        {
            flush_uploads();
            break;
        }
    }
    gpu::upload_texture(*g.uploads, s->placed.texture, s->desc, ByteSpan(data, size_t(size)), region);
    g.uploaded_textures.push_back({.texture = s->placed.texture, .region = region});
}

void submit_frame_commands()
{
    // The uploads made so far go first, on the same queue: UploadQueue's own
    // barriers order them against the work before and after them.
    flush_uploads();
    end_commands(g.commands);
    ++g.timeline.value;
    if (g.drawable)
    {
        submit_and_present(g.device, {.commands = {g.commands}, .completion = g.timeline});
        g.drawable = nullptr;
        g.presented = true;
        release_stand_in();
    }
    else
    {
        submit(g.device, {.commands = {g.commands}, .completion = g.timeline});
    }
    g.pool_values[g.slot] = g.timeline.value;
    g.commands = nullptr;
    run_pending(g.timeline.value);
}

void finish()
{
    submit_frame_commands();
    wait_timeline(g.timeline);
    release_retired(false);
    begin_frame_commands();
}

} // namespace ngfx

using namespace ngfx;

// Set while the C runtime initializes the program, which it does on the
// thread that then runs main. The compiler already rejects a thread_fn that
// reaches ngfx (main_thread_only in ngfx.build); this checks again at run time
// on the calls not made per draw.
static const std::thread::id main_thread = std::this_thread::get_id();

extern "C" {

bool ngfx_gpu_on_main_thread(void) { return std::this_thread::get_id() == main_thread; }

bool ngfx_gpu_in_pass(void) { return g.in_pass; }

const char* ngfx_gpu_driver(void)
{
#if defined(__APPLE__)
    return "metal";
#else
    return "vulkan";
#endif
}

void ngfx_gpu_screen_size(int* w, int* h)
{
    *w = g.width;
    *h = g.height;
}

bool ngfx_gpu_open(void* layer, int w, int h)
{
    set_error_callback(report_error);
    g.windowed = layer != nullptr;
    const char* sync = getenv("GOOSE_NGFX_SYNC");
    g.full_sync = sync && !strcmp(sync, "full");
    const char* bench = getenv("GOOSE_NGFX_BENCH");
    g.bench = bench && !strcmp(bench, "1");
    // The window's image takes what a frame draws as it is, without sRGB
    // conversion, as gfx's swapchain does.
    const DeviceInit init = create_device({.window = layer, .swapchain_format = layer ? Format::bgra8_unorm : Format::undefined,
                                           .desired_swapchain_image_count = 3,
                                           // Timestamp storage only for GOOSE_NGFX_BENCH: every
                                           // command buffer reserves its queries in the driver's memory.
                                           .timestamp_query_count = g.bench ? 256u : 0u});
    if (!init.device)
    {
        char why[512];
        snprintf(why, sizeof why, "%s", ngfx_error_text());
        ngfx_fail("no NoGraphicsAPI device (error %d)%s%s", int(init.error), why[0] ? ": " : "", why);
        return false;
    }
    g.device = init.device;
    g.timeline.semaphore = create_timeline_semaphore(g.device);
    g.texture_descriptors = create_texture_descriptor_heap(g.device, texture_descriptors);
    g.sampler_descriptors = create_sampler_descriptor_heap(g.device, sampler_descriptors);
    if (!g.timeline.semaphore || !g.texture_descriptors || !g.sampler_descriptors)
    {
        if (!ngfx_error_text()[0]) ngfx_fail("creating the device's resources");
        return false;
    }
    for (uint32 i = 0; i < frames_in_flight; ++i)
    {
        g.pools[i] = create_command_pool(g.device);
        if (!g.pools[i]) return ngfx_fail("creating a command pool");
        g.frame_heaps[i] = create_gpu_heap(g.device, frame_memory_start, MemoryType::cpu_visible);
        if (!g.frame_heaps[i].owner) return ngfx_fail("creating frame memory");
        g.frame_data[i] = new BumpAllocator(g.frame_heaps[i].range);
    }
    g.uploads = new UploadQueue(g.device, upload_capacity, 0, upload_batches);
    if (!g.uploads->valid()) return ngfx_fail("creating the upload queue");
    g.texture_slots.capacity = texture_descriptors;
    g.sampler_slots.capacity = sampler_descriptors;
    begin_frame_commands();
    begin_frame_stamps();
    return create_screen(w, h);
}

void ngfx_gpu_close(void)
{
    if (!g.device)
    {
        g = State{};
        return;
    }
    if (g.commands)
    {
        if (g.in_pass) end_render_pass(g.commands);
        g.in_pass = false;
        submit_frame_commands();
    }
    wait_idle(g.device);
    if (g.bench)
    {
        for (uint32 i = 1; i <= frames_in_flight; ++i) collect_stamps((g.slot + i) % frames_in_flight);
        print_stamps();
    }
    run_pending(g.timeline.value);
    if (g.uploads) g.uploads->destroy();
    delete g.uploads;
    release_retired(true);
    release_pipelines();
    g.textures.each([](TextureSlot& s) {
        if (s.placed.texture) free_texture(s);
    });
    if (g.stand_in.placed.texture) free_texture(g.stand_in);
    g.buffers.each([](BufferSlot& s) {
        if (s.chunk < 0) destroy_gpu_heap(s.own);
    });
    for (HeapAllocator* a : g.buffer_allocators) delete a;
    for (const GpuHeap& h : g.buffer_heaps) destroy_gpu_heap(h);
    for (size_t i = 0; i < g.texture_allocators.size(); ++i)
    {
        if (!g.texture_allocators[i]) continue;
        delete g.texture_allocators[i];
        destroy_texture_heap(g.texture_heaps[i]);
    }
    g.texture_heaps.clear();
    g.texture_allocators.clear();
    g.texture_alone.clear();
    for (uint32 i = 0; i < frames_in_flight; ++i)
    {
        delete g.frame_data[i];
        destroy_command_pool(g.pools[i]);
    }
    for (const GpuHeap& h : g.frame_heaps)
        if (h.owner) destroy_gpu_heap(h);
    destroy_texture_descriptor_heap(g.texture_descriptors);
    destroy_sampler_descriptor_heap(g.sampler_descriptors);
    destroy_timeline_semaphore(g.timeline.semaphore);
    destroy_device(g.device);
    set_error_callback(nullptr);
    g = State{};
}

bool ngfx_gpu_next_frame(void)
{
    BenchStamps& stamps = g.bench_stamps[g.slot];
    if (g.bench) write_timestamp(g.commands, &stamps.passes_end);
    submit_frame_commands();
    const bool shown = g.presented;
    g.presented = false;
    // The first frame that records nothing after frames that did: the
    // program is idle, and the driver's memory for its work goes back.
    if (!g.worked && g.worked_since_trim && !g.bench) trim();
    g.worked_since_trim = g.worked_since_trim || g.worked;
    g.worked = false;
    // The next frame in flight's pool and memory, once the frame that last
    // used them has finished, as examples/cube waits.
    g.slot = (g.slot + 1) % frames_in_flight;
    if (g.pool_values[g.slot]) wait_timeline({.semaphore = g.timeline.semaphore, .value = g.pool_values[g.slot]});
    if (g.bench) collect_stamps(g.slot);
    reset_command_pool(g.pools[g.slot]);
    g.frame_data[g.slot]->reset();
    release_retired(false);
    g.uploads->reclaim();
    begin_frame_commands();
    begin_frame_stamps();
    g.frame_barrier = false;
    g.written_targets.clear();
    return shown;
}

bool ngfx_gpu_resize(int w, int h) { return create_screen(w, h); }

ngfx_texture ngfx_screen(void)
{
    ngfx_need_device("screen");
    return g.screen;
}

ngfx_texture ngfx_screen_depth(void)
{
    if (!ngfx_need_device("screen_depth")) return g.screen_depth;
    if (!g.screen_depth.id && create_screen_depth(g.width, g.height)) clear_screen();
    return g.screen_depth;
}

void ngfx_gpu_finish(void) { finish(); }

} // extern "C"
