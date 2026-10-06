// MIT licensed StageDisc adapter around the Apache-2.0 tsMuxer UDF 2.50 writer.
#include "iso_writer.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <vector>
#include <algorithm>
namespace fs = std::filesystem;
int main(int argc, char** argv) {
    if (argc != 4) { std::cerr << "Usage: stagedisc-udf disc-root output.iso label\n"; return 2; }
    try {
        const fs::path root = fs::canonical(argv[1]);
        const fs::path output = fs::absolute(argv[2]);
        if (fs::exists(output)) throw std::runtime_error("Output already exists");
        std::vector<fs::path> files, dirs;
        int64_t total = 0;
        for (const auto& entry : fs::recursive_directory_iterator(root)) {
            if (entry.is_symlink()) throw std::runtime_error("Symlinks are not permitted in the disc tree");
            if (entry.is_directory()) dirs.push_back(entry.path());
            else if (entry.is_regular_file()) { files.push_back(entry.path()); total += entry.file_size(); }
        }
        if (files.empty()) throw std::runtime_error("Empty disc tree");
        std::sort(dirs.begin(), dirs.end()); std::sort(files.begin(), files.end());
        IsoWriter writer(IsoHeaderData::normal()); writer.setVolumeLabel(argv[3]);
        if (!writer.open(output.string(), total, static_cast<int>(files.size() / 16 + 4))) throw std::runtime_error("Cannot create output");
        for (const auto& dir : dirs) writer.createDir(fs::relative(dir, root).generic_string());
        std::vector<char> buffer(1024 * 1024);
        for (const auto& path : files) {
            std::ifstream input(path, std::ios::binary);
            if (!input) throw std::runtime_error("Cannot read " + path.string());
            std::unique_ptr<ISOFile> file(writer.createFile());
            if (!file->open(fs::relative(path, root).generic_string().c_str(), AbstractOutputStream::ofWrite)) throw std::runtime_error("Cannot add file");
            while (input) {
                input.read(buffer.data(), buffer.size()); const auto size = input.gcount();
                if (size && file->write(buffer.data(), static_cast<uint32_t>(size)) != size) throw std::runtime_error("Short write");
            }
            if (!input.eof()) throw std::runtime_error("Read error");
            file->close();
            std::cout << "Packed " << fs::relative(path, root).string() << std::endl;
        }
        writer.close(); std::cout << "UDF 2.50 image ready" << std::endl;
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
