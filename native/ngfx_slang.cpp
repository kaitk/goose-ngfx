// ngfx::slang: compiling one Slang module, every entry point of it, into the
// blob ngfx_blob.h describes, while the program runs. It runs the tools
// NoGraphicsAPI's own build runs (examples/NoGraphicsAPI_slang.cmake), with
// the same options, as subprocesses: slangc makes SPIR-V and, on a Mac, the
// Metal source that Xcode's `metal` and `metallib` turn into a metallib.
// Each tool is found through an environment variable, else where CMake
// found it, else on PATH:
//
//   NGFX_SLANGC          slangc (2026.18.2 or later)
//   NGFX_SPIRV_VAL       spirv-val, optional: validates the SPIR-V
//   NGFX_NOGRAPHICSAPI   NoGraphicsAPI's source tree, for the includes
//                        <NoGraphicsAPI/shader.slang> and
//                        <NoGraphicsAPIUtility/shader_types.h>
//
// The blob always holds SPIR-V, and a metallib on a Mac, where that is the
// backend a program runs on. The last blob compiled is kept here until the
// Goose side copies it out (ngfx_slang_result), since C cannot append to a
// Goose builder: gs_bld_append is static to the program's runtime.

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

#include "ngfx_blob.h"
#include "ngfx_internal.h"

#ifdef _WIN32
    #include <process.h>
    #define NGFX_POPEN _popen
    #define NGFX_PCLOSE _pclose
#else
    #include <unistd.h>
    #define NGFX_POPEN popen
    #define NGFX_PCLOSE pclose
#endif

using std::string;
using std::string_view;
using std::vector;

namespace {

string blob_result;

double slang_seconds = 0;
int slang_modules = 0;

// Adds one compile's time to slang_seconds, for GOOSE_NGFX_BENCH.
struct CompileTimer {
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    ~CompileTimer() {
        slang_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        ++slang_modules;
    }
};

string tool(const char *env, const char *configured, const char *name) {
    if (auto e = getenv(env); e && *e) return e;
    if (configured && *configured) return configured;
    return name;
}

string slangc_path() {
    #ifdef NGFX_SLANGC_PATH
        return tool("NGFX_SLANGC", NGFX_SLANGC_PATH, "slangc");
    #else
        return tool("NGFX_SLANGC", nullptr, "slangc");
    #endif
}

string spirv_val_path() {
    #ifdef NGFX_SPIRV_VAL_PATH
        return tool("NGFX_SPIRV_VAL", NGFX_SPIRV_VAL_PATH, "");
    #else
        return tool("NGFX_SPIRV_VAL", nullptr, "");
    #endif
}

string nographicsapi_dir() {
    #ifdef NGFX_NOGRAPHICSAPI_DIR
        return tool("NGFX_NOGRAPHICSAPI", NGFX_NOGRAPHICSAPI_DIR, "");
    #else
        return tool("NGFX_NOGRAPHICSAPI", nullptr, "");
    #endif
}

bool load_file(const string &path, string &out) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) return false;
    out.clear();
    char buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
    fclose(f);
    return true;
}

// Runs a command, its output and errors together into `out`: whether it
// exited with 0.
bool run_tool(const vector<string> &argv, string &out) {
    string cmd;
    for (auto &a : argv) {
        if (!cmd.empty()) cmd += ' ';
        #ifdef _WIN32
            cmd += '"' + a + '"';
        #else
            cmd += '\'';
            for (char ch : a) {
                if (ch == '\'') cmd += "'\\''";
                else cmd += ch;
            }
            cmd += '\'';
        #endif
    }
    cmd += " 2>&1";
    #ifdef _WIN32
        cmd = '"' + cmd + '"';   // cmd /c strips one pair of quotes around the whole.
    #endif
    out.clear();
    FILE *p = NGFX_POPEN(cmd.c_str(), "r");
    if (!p) return false;
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, p)) > 0) out.append(buf, n);
    return NGFX_PCLOSE(p) == 0;
}

// Just enough JSON for slangc's reflection: its entry points' names, stages
// and thread group sizes.
struct Json {
    enum Kind { NUL, NUM, STR, ARR, OBJ, OTHER } kind = NUL;
    double num = 0;
    string str;
    vector<Json> items;
    vector<string> keys;   // OBJ: items[i] is keys[i]'s value.

    const Json *get(string_view key) const {
        for (size_t i = 0; i < keys.size(); i++) if (keys[i] == key) return &items[i];
        return nullptr;
    }

    static void space(string_view &s) {
        while (!s.empty() && isspace((uint8_t)s[0])) s.remove_prefix(1);
    }

    static bool parse(string_view &s, Json &v) {
        space(s);
        if (s.empty()) return false;
        if (s[0] == '{' || s[0] == '[') {
            bool obj = s[0] == '{';
            v.kind = obj ? OBJ : ARR;
            s.remove_prefix(1);
            space(s);
            if (!s.empty() && s[0] == (obj ? '}' : ']')) { s.remove_prefix(1); return true; }
            for (;;) {
                if (obj) {
                    Json key;
                    if (!parse(s, key) || key.kind != STR) return false;
                    space(s);
                    if (s.empty() || s[0] != ':') return false;
                    s.remove_prefix(1);
                    v.keys.push_back(key.str);
                }
                v.items.emplace_back();
                if (!parse(s, v.items.back())) return false;
                space(s);
                if (s.empty()) return false;
                if (s[0] == ',') { s.remove_prefix(1); continue; }
                if (s[0] != (obj ? '}' : ']')) return false;
                s.remove_prefix(1);
                return true;
            }
        }
        if (s[0] == '"') {
            v.kind = STR;
            s.remove_prefix(1);
            while (!s.empty() && s[0] != '"') {
                if (s[0] == '\\' && s.size() > 1) {
                    char e = s[1];
                    v.str += e == 'n' ? '\n' : e == 't' ? '\t' : e;
                    s.remove_prefix(e == 'u' && s.size() >= 6 ? 6 : 2);
                } else {
                    v.str += s[0];
                    s.remove_prefix(1);
                }
            }
            if (s.empty()) return false;
            s.remove_prefix(1);
            return true;
        }
        if (s[0] == '-' || isdigit((uint8_t)s[0])) {
            v.kind = NUM;
            size_t n = 0;
            while (n < s.size() && (isdigit((uint8_t)s[n]) || strchr("+-.eE", s[n]))) n++;
            v.num = strtod(string(s.substr(0, n)).c_str(), nullptr);
            s.remove_prefix(n);
            return true;
        }
        v.kind = OTHER;   // true, false, null
        while (!s.empty() && isalpha((uint8_t)s[0])) s.remove_prefix(1);
        return true;
    }
};

// slangc's diagnostic, "error[E30015]: undefined identifier\n --> f.slang:3:36\n
// ... ^^^ undefined identifier 'foo'.", as "f.slang:3: error: undefined
// identifier 'foo'.". Output it cannot read comes back as it is.
string slang_message(const string &out) {
    vector<string_view> lines;
    for (size_t at = 0; at < out.size();) {
        auto nl = out.find('\n', at);
        if (nl == string::npos) nl = out.size();
        lines.push_back(string_view(out).substr(at, nl - at));
        at = nl + 1;
    }
    for (size_t i = 0; i < lines.size(); i++) {
        auto l = lines[i];
        if (l.substr(0, 5) != "error") continue;
        auto colon = l.find(": ");
        string headline(colon == string_view::npos ? l : l.substr(colon + 2));
        string where, detail;
        for (size_t j = i + 1; j < lines.size() && !lines[j].starts_with("error"); j++) {
            auto m = lines[j];
            if (auto arrow = m.find("--> "); arrow != string_view::npos && where.empty()) {
                // path:line:column, where the path may hold colons itself.
                auto loc = m.substr(arrow + 4);
                auto c2 = loc.rfind(':');
                auto c1 = c2 == string_view::npos ? c2 : loc.rfind(':', c2 - 1);
                where = c1 == string_view::npos ? string(loc) : string(loc.substr(0, c2));
            } else if (auto caret = m.find('^'); caret != string_view::npos && detail.empty()) {
                auto d = m.substr(caret);
                while (!d.empty() && (d[0] == '^' || d[0] == ' ')) d.remove_prefix(1);
                detail = string(d);
            }
        }
        auto msg = detail.empty() ? headline : detail;
        while (!msg.empty() && (msg.back() == '\r' || isspace((uint8_t)msg.back()))) msg.pop_back();
        return where.empty() ? msg : where + ": error: " + msg;
    }
    auto s = out;
    while (!s.empty() && isspace((uint8_t)s.back())) s.pop_back();
    return s;
}

// A directory of its own for one compilation's files, removed when done.
struct Temp {
    std::filesystem::path dir;
    Temp() {
        static std::atomic<int> counter { 0 };
        #ifdef _WIN32
            auto pid = (long)_getpid();
        #else
            auto pid = (long)getpid();
        #endif
        std::error_code ec;
        dir = std::filesystem::temp_directory_path(ec) /
              ("goose-ngfx-slang-" + std::to_string(pid) + "-" + std::to_string(counter++));
        std::filesystem::create_directories(dir, ec);
    }
    ~Temp() {
        std::error_code ec;
        std::filesystem::remove_all(dir, ec);
    }
    string operator()(const char *name) const { return (dir / name).string(); }
};

uint32_t stage_of(const string &name) {
    if (name == "vertex") return NGFX_BLOB_STAGE_VERTEX;
    if (name == "fragment" || name == "pixel") return NGFX_BLOB_STAGE_FRAGMENT;
    if (name == "compute") return NGFX_BLOB_STAGE_COMPUTE;
    return UINT32_MAX;
}

bool fail(const string &msg) { return ngfx_fail("%s", msg.c_str()); }

// The blob for the Slang module in the file at `path` into blob_result,
// with #include also looking in `includedir`; or false with ngfx_error set,
// to "path:line: error: message" when slangc says where.
bool compile_file(const string &path, const string &includedir) {
    Temp tmp;
    auto slangc = slangc_path();
    vector<string> common = { slangc, path, "-fvk-use-c-layout", "-matrix-layout-row-major" };
    if (!includedir.empty()) { common.push_back("-I"); common.push_back(includedir); }
    auto ng = nographicsapi_dir();
    if (!ng.empty()) {
        for (auto inc : { "/include", "/utility/include" }) {
            common.push_back("-I");
            common.push_back(ng + inc);
        }
    }
    string out;

    const char *no_entries = "the module has no entry points: mark each with [shader(\"vertex\")], "
                             "[shader(\"fragment\")] or [shader(\"compute\")]";
    // SPIR-V, and the reflection that lists the entry points.
    auto argv = common;
    for (auto a : { "-target", "spirv", "-profile", "spirv_1_5", "-emit-spirv-directly",
                    "-fvk-use-entrypoint-name", "-capability", "spvDescriptorHeapEXT" })
        argv.push_back(a);
    argv.push_back("-o");
    argv.push_back(tmp("module.spv"));
    argv.push_back("-reflection-json");
    argv.push_back(tmp("reflection.json"));
    if (!run_tool(argv, out)) {
        if (out.find("error") == string::npos)
            return fail("cannot run slangc (" + slangc + "; set NGFX_SLANGC): " + slang_message(out));
        if (out.find("contains no exported symbols") != string::npos) return fail(no_entries);
        return fail(slang_message(out));
    }
    string json;
    if (!load_file(tmp("reflection.json"), json)) return fail("slangc wrote no reflection");
    Json root;
    string_view js = json;
    if (!Json::parse(js, root) || root.kind != Json::OBJ)
        return fail("cannot read slangc's reflection");
    vector<ngfx_blob_entry> entries;
    if (auto eps = root.get("entryPoints"); eps && eps->kind == Json::ARR) {
        for (auto &ep : eps->items) {
            auto name = ep.get("name");
            auto stage = ep.get("stage");
            if (!name || !stage) continue;
            ngfx_blob_entry e {};
            if (name->str.size() >= NGFX_BLOB_NAME_SIZE)
                return fail("the entry point name " + name->str + " is longer than " +
                            std::to_string(NGFX_BLOB_NAME_SIZE - 1) + " characters");
            memcpy(e.name, name->str.data(), name->str.size());
            e.stage = stage_of(stage->str);
            if (e.stage == UINT32_MAX)
                return fail("the entry point " + name->str + " is a " + stage->str +
                            " shader; ngfx takes vertex, fragment and compute shaders");
            e.threadgroup[0] = e.threadgroup[1] = e.threadgroup[2] = 1;
            if (auto tg = ep.get("threadGroupSize"); tg && tg->kind == Json::ARR)
                for (size_t i = 0; i < 3 && i < tg->items.size(); i++)
                    e.threadgroup[i] = (uint32_t)tg->items[i].num;
            entries.push_back(e);
        }
    }
    if (entries.empty()) return fail(no_entries);
    string spv;
    if (!load_file(tmp("module.spv"), spv)) return fail("slangc wrote no SPIR-V");
    if (auto val = spirv_val_path(); !val.empty()) {
        if (!run_tool({ val, "--target-env", "vulkan1.4", "--scalar-block-layout",
                        tmp("module.spv") }, out))
            return fail("spirv-val rejects the SPIR-V slangc made: " + slang_message(out));
    }

    // The metallib, on a Mac.
    string metallib;
    #ifdef __APPLE__
        argv = common;
        for (auto a : { "-target", "metal", "-DNOGRAPHICSAPI_METAL" }) argv.push_back(a);
        argv.push_back("-o");
        argv.push_back(tmp("module.metal"));
        if (!run_tool(argv, out)) return fail(slang_message(out));
        if (!run_tool({ "xcrun", "-sdk", "macosx", "metal", "-std=metal4.0", "-c",
                        tmp("module.metal"), "-o", tmp("module.air") }, out))
            return fail("Xcode's Metal compiler failed on slangc's output (install it with "
                        "xcodebuild -downloadComponent MetalToolchain): " + slang_message(out));
        if (!run_tool({ "xcrun", "-sdk", "macosx", "metallib", tmp("module.air"), "-o",
                        tmp("module.metallib") }, out))
            return fail("metallib failed: " + slang_message(out));
        if (!load_file(tmp("module.metallib"), metallib)) return fail("metallib wrote nothing");
    #endif

    // header | entries | SPIR-V | metallib, each section 16-byte aligned.
    auto align = [](size_t n) { return (n + 15) & ~(size_t)15; };
    ngfx_blob_header h {};
    h.magic = NGFX_BLOB_MAGIC;
    h.version = NGFX_BLOB_VERSION;
    h.entry_count = (uint32_t)entries.size();
    h.spirv_offset = (uint32_t)align(sizeof h + entries.size() * sizeof(ngfx_blob_entry));
    h.spirv_size = (uint32_t)spv.size();
    h.metallib_offset = (uint32_t)align(h.spirv_offset + spv.size());
    h.metallib_size = (uint32_t)metallib.size();
    blob_result.assign(h.metallib_offset + metallib.size(), '\0');
    memcpy(blob_result.data(), &h, sizeof h);
    memcpy(blob_result.data() + sizeof h, entries.data(), entries.size() * sizeof(ngfx_blob_entry));
    memcpy(blob_result.data() + h.spirv_offset, spv.data(), spv.size());
    memcpy(blob_result.data() + h.metallib_offset, metallib.data(), metallib.size());
    return true;
}

string bytes(ngfx_bytes s) { return string((const char *)s.data, (size_t)s.len); }

}  // namespace

// The module in the file at `path`, relative to the working directory, its
// #include also looking in the file's own directory. The blob's size, or -1.
int64_t ngfx_compile_slang_file(ngfx_bytes path) {
    CompileTimer timer;
    blob_result.clear();
    auto p = bytes(path);
    std::error_code ec;
    if (!std::filesystem::is_regular_file(p, ec)) {
        ngfx_fail("cannot open Slang file: %s", p.c_str());
        return -1;
    }
    auto dir = std::filesystem::absolute(p, ec).parent_path().string();
    return compile_file(p, dir) ? (int64_t)blob_result.size() : -1;
}

// The module `source`, compiled from a file of its own, its errors given at
// "<slang source>:line", with #include also looking in the working
// directory. The blob's size, or -1.
int64_t ngfx_compile_slang(ngfx_bytes source) {
    CompileTimer timer;
    blob_result.clear();
    Temp tmp;
    auto file = tmp("source.slang");
    FILE *f = fopen(file.c_str(), "wb");
    if (!f) {
        ngfx_fail("cannot write %s", file.c_str());
        return -1;
    }
    fwrite(source.data, 1, (size_t)source.len, f);
    fclose(f);
    std::error_code ec;
    auto cwd = std::filesystem::current_path(ec).string();
    if (compile_file(file, cwd)) return (int64_t)blob_result.size();
    string msg = ngfx_error_text();
    if (msg.compare(0, file.size(), file) == 0) {
        msg = "<slang source>" + msg.substr(file.size());
        fail(msg);
    }
    return -1;
}

// Copies the blob the last compile made into `out`, which holds its size.
int64_t ngfx_slang_result(ngfx_bytes out) {
    auto n = std::min((int64_t)blob_result.size(), out.len);
    if (n > 0) memcpy(out.data, blob_result.data(), (size_t)n);
    return (int64_t)blob_result.size();
}

void ngfx_slang_time(double *seconds, int *modules) {
    *seconds = slang_seconds;
    *modules = slang_modules;
}
