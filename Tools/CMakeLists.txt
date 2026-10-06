cmake_minimum_required(VERSION 3.16)
project(StageDiscUDF LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(TS "${CMAKE_CURRENT_SOURCE_DIR}/../ThirdParty/tsMuxer")
add_subdirectory("${TS}/libmediation" mediation)
add_executable(stagedisc-udf udf_main.cpp
    "${TS}/tsMuxer/iso_writer.cpp"
    "${TS}/tsMuxer/convertUTF.cpp"
    "${TS}/tsMuxer/utf8Converter.cpp"
    "${TS}/tsMuxer/vod_common.cpp")
target_include_directories(stagedisc-udf PRIVATE "${TS}/tsMuxer" "${TS}/libmediation")
target_compile_definitions(stagedisc-udf PRIVATE TSMUXER_VERSION="2.7.0")
target_link_libraries(stagedisc-udf mediation)
