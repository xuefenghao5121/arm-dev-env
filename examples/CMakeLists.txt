cmake_minimum_required(VERSION 3.16)
project(arm_test C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# Cross-compilation hints (auto-detected in Docker ARM container)
if(NOT CMAKE_CROSSCOMPILING)
    message(STATUS "Native build for ${CMAKE_SYSTEM_PROCESSOR}")
else()
    message(STATUS "Cross-compiling for ${CMAKE_SYSTEM_PROCESSOR}")
endif()

add_executable(hello_arm hello_arm.c)
