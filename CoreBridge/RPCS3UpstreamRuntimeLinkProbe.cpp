extern "C" int rpcs3_ios_upstream_runtime_link_probe(const char* data_root);

int main()
{
    // Cross-linked for arm64 iOS and intentionally not executed in CI. The call
    // forces the linker to resolve Emu.Init(), System.cpp, PPU/SPU interpreter
    // code, renderer callbacks, MoltenVK, Metal, and every transitive library.
    return rpcs3_ios_upstream_runtime_link_probe(nullptr) ? 0 : 1;
}
