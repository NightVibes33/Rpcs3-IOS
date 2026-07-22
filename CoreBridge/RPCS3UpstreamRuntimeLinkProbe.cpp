extern "C" int rpcs3_ios_upstream_runtime_link_probe(const char* data_root);

int main()
{
    // This executable is cross-linked for arm64 iOS but is not executed in CI.
    // Calling the bridge here forces the linker to resolve Emu.Init(),
    // System.cpp, interpreter code, callbacks, and every transitive dependency.
    return rpcs3_ios_upstream_runtime_link_probe(nullptr) ? 0 : 1;
}
