# pw-ci: turn the monolithic client build into the SERVER build (UniServerApp).
#
# Included from Src/CMakeLists.txt right before `#print_list( ALL_SRCS )`, i.e. after the
# whole GLOB + list_remove_regexp block and *before* add_executable(). Same injection point
# and same technique as cmake/pwci_extra.cmake, but the two are mutually exclusive:
# build-server.yml injects ONLY this file, build.yml injects only pwci_extra.cmake.
#
# WHERE THE SOURCE LIST COMES FROM
#   Not from the client GLOB. Nival described UniServerApp with its own build language:
#   Src/Game/PF/UniServer/UniServerApp.application lists `components`, each `.component`
#   lists `sources` and further `components`. tools/resolve_components.py walks that graph
#   (the resolution rules are Nival's own, lifted from Tools/CMakeGenerator/main.py and
#   Tools/TestFramework/componentAnalyzer.py) and writes pwci_server_srcs.cmake, which the
#   workflow regenerates on every run right before configure.
#
#   The first exploratory run took the opposite route - "the whole client monolith minus the
#   client directories, plus /D VISUAL_CUTTED" - and lost 120 TUs to it. That approach is
#   wrong at the root: the VISUAL_CUTTED branches in the client-side game code were never
#   compiled by Nival either (Src/Terrain/Terrain.h:73 declares `NatureMap natureMap;` under
#   VISUAL_CUTTED, and Terrain::NatureMap is abstract - only the render-side NatureMapVisual
#   implements it). UniServerApp simply does not contain Terrain / Scene / PF_GameLogic:
#   the component graph resolves to ~640 sources, of which exactly one is in PF_GameLogic.
#
# STATUS: exploratory. This has never linked.

# ---------------------------------------------------------------------------------------
# 1. Target name.
#
# set_target_properties(OUTPUT_NAME) is unavailable here (no target yet). The trick used
# instead: CMakeLists.txt spells the target as ${PROJECT_NAME} everywhere below this point
# (add_executable, SET_TARGET_PROPERTIES, target_link_libraries, process_dyn_lib), and
# PROJECT_NAME is just a normal variable after project() has run. Overriding it renames the
# target - and therefore UniServerApp.exe - with no patch to CMakeLists at all.
# Everything that *reads* PROJECT_NAME earlier (${PrimeWorld_SOURCE_DIR} -> SRC_DIR/VENDOR,
# the version vars) has already been evaluated, so the rename is safe here and only here.
# ---------------------------------------------------------------------------------------
set( PROJECT_NAME UniServerApp )

# ---------------------------------------------------------------------------------------
# 2. The resolved component graph replaces ALL_SRCS wholesale.
#
# Everything the client GLOB collected is dropped, including the handful of files
# CMakeLists.txt appends by hand below the exclusion block - those are client link fixups
# and have no business in the server. Sources arrive in post-order of the component graph
# (dependencies first), which is the closest thing we have to the link order of Nival's
# per-DLL build; MSVC runs global constructors in link order.
# ---------------------------------------------------------------------------------------
include( "${CMAKE_CURRENT_LIST_DIR}/pwci_server_srcs.cmake" )

list( REMOVE_DUPLICATES PWCI_SRV_SRCS )
set( ALL_SRCS ${PWCI_SRV_SRCS} )

list( LENGTH ALL_SRCS _n_all )
message( STATUS "pwci-server: ${_n_all} sources from the UniServerApp component graph" )

# ---------------------------------------------------------------------------------------
# 3. Include paths.
#
# PWCI_SRV_INCDIRS is every component's own directory plus its declared includePaths, which
# is what Nival's per-component build provided implicitly (main.cpp includes "RelaySvc/...",
# "ChatSvc/...", "UserManagerSvc/...", "GameBalancer/..." and so on). The extra entries
# below are the ones CMakeLists.txt already provides for the client and that the server also
# needs; harmless duplicates.
# ---------------------------------------------------------------------------------------
# 80+ component directories on top of CMakeLists' own ~30 blows past cmd.exe's 8191-char
# command line, so make the include list go through a response file explicitly instead of
# relying on the generator's default.
set( CMAKE_C_USE_RESPONSE_FILE_FOR_INCLUDES 1 )
set( CMAKE_CXX_USE_RESPONSE_FILE_FOR_INCLUDES 1 )

include_directories( ${PWCI_SRV_INCDIRS} )
include_directories(
  ${SRC_DIR}
  ${SRC_DIR}/System
  ${SRC_DIR}/Server
  ${SRC_DIR}/Server/NetworkAIO
  ${SRC_DIR}/Game/PF
  ${VENDOR}
  ${VENDOR}/boost
  ${VENDOR}/CrashRpt/include
)

# ---------------------------------------------------------------------------------------
# 4. Defines.
#
# PWCI_SRV_DEFS is the union of globalCompilerKeys / compilerKeys / defines over the graph,
# filtered down to -D and /wd (codegen switches like /MD /Zi /EHa belong to CMAKE_CXX_FLAGS
# and would fight it). It already contains the four keys UniServerApp.application declares:
# VISUAL_CUTTED, SERVER_DB, CHECK_TOWN_CONSISTENCY, LOG_THREAD_EXIT.
# ---------------------------------------------------------------------------------------
add_definitions( ${PWCI_SRV_DEFS} )
add_definitions( -DCURL_STATICLIB )   # Vendor/libcurl is a static build, same as Nival's vcproj

# ---------------------------------------------------------------------------------------
# 5. Forced includes (Nival's per-component PCH).
#
# Tools/TestFramework/platforms.py compiled every source of a component with
# /FI"<generated pch>", where the generated header #includes whatever
# platformFeatures = { 'win32': Win32Features('stdafx.h') } declared - for that component
# AND for every inlined component below it, since componentAnalyzer merges the children's
# features up before applying (RemoveDummyDependencies -> InlinePlatformFeatures ->
# ApplyPlatformFeatures). Nothing in this codebase includes <windows.h> on its own; the pch
# is where it comes from. Skipping it cost 290 of 619 TUs in run 34425524256, 132 of them
# on Src/Server/RPC/Types.h alone - it guards `#include <Rpc.h>` on NV_WIN_PLATFORM, and
# Src/System/config.h only defines that once something has pulled it in.
# The resolver emits one generated header per distinct union and this macro attaches them
# as per-source COMPILE_FLAGS. .c sources are left alone - they cannot swallow a C++ pch.
# ---------------------------------------------------------------------------------------
PWCI_SRV_apply_pch()

# ---------------------------------------------------------------------------------------
# 6. Libraries.
#
# rpcrt4 / shlwapi come from UniServerApp.application libDependencies (rpcrt4 is already in
# CMakeLists). ACE / IOTerabit / TProactor / OpenSSL / zlib are already listed by CMakeLists
# itself. Thrift, wsdlpull, mongoose, tinyxml-as-source and JsonCpp come in as *sources* via
# the component graph, so no .lib is needed for them - except tinyxml/JsonCpp, whose
# components only contribute a couple of files, so keep the prebuilt libs too.
# ---------------------------------------------------------------------------------------
simple_add_library( shlwapi )
simple_add_library( wbemuuid )
simple_add_library( ws2_32 )
simple_add_library( wldap32 )
simple_add_library( ${VENDOR}/pthreads/Pre-built.2/lib/pthreadVCE2 )
simple_add_library( ${VENDOR}/libcurl/lib/Release/libcurl )
simple_add_library( ${SRC_DIR}/../Tools/Censor/lib/Release/CensorDll )

# --- optional extra definitions from workflow_dispatch (space separated) ---
if( PWCI_EXTRA_DEFS )
  separate_arguments( _pwci_defs WINDOWS_COMMAND "${PWCI_EXTRA_DEFS}" )
  add_definitions( ${_pwci_defs} )
  message( STATUS "pwci-server: extra defs: ${_pwci_defs}" )
endif()
