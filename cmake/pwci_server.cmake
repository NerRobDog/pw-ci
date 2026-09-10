# pw-ci: turn the monolithic client build into the SERVER build (UniServerApp).
#
# Included from Src/CMakeLists.txt right before `#print_list( ALL_SRCS )`, i.e. after the
# whole GLOB + list_remove_regexp block and *before* add_executable(). Same injection point
# and same technique as cmake/pwci_extra.cmake, but the two are mutually exclusive:
# build-server.yml injects ONLY this file, build.yml injects only pwci_extra.cmake.
#
# WHY NOT REUSE pwci_extra.cmake:
#   pwci_extra.cmake hand-picks a handful of server .cpp files back into the client link and
#   adds stubs/pwci_stubs.cpp, whose RegisterRemoteFactory<lobby::RIEntrance> /
#   <Monitoring::RIMonitor> explicit specializations are *replacements* for the real
#   R*.auto.cpp files. In a server build those real files are compiled, so the stubs would be
#   duplicate symbols. The vendor-lib / include_directories part of pwci_extra.cmake is
#   duplicated below on purpose — keeping the two snippets independent means a client-side
#   tweak cannot silently break the server build.
#
# STATUS: exploratory. This has never linked. Everything below is a best guess derived from
# Src/Game/PF/UniServer/UniServerApp.application (Nival's own build description) plus the
# include graph of Src/Game/PF/UniServer/main.cpp.

# ---------------------------------------------------------------------------------------
# 1. Target name.
#
# set_target_properties(OUTPUT_NAME) is unavailable here (no target yet). The trick used
# instead: CMakeLists.txt spells the target as ${PROJECT_NAME} everywhere below this point
# (add_executable, SET_TARGET_PROPERTIES, target_link_libraries, process_dyn_lib), and
# PROJECT_NAME is just a normal variable after project() has run. Overriding it renames the
# target — and therefore UniServerApp.exe — with no patch to CMakeLists at all.
# Everything that *reads* PROJECT_NAME earlier (${PrimeWorld_SOURCE_DIR} -> SRC_DIR/VENDOR,
# the version vars) has already been evaluated, so the rename is safe here and only here.
# ---------------------------------------------------------------------------------------
set( PROJECT_NAME UniServerApp )

# ---------------------------------------------------------------------------------------
# 2. Drop the client-only subsystems.
#
# The server runs the same simulation as the client but with /D VISUAL_CUTTED, so
# PF_GameLogic / PF_Core / Scene / Terrain / Types stay. Render, UI, Sound, input and the
# editors / Maya / tool subsystems go. OPEN QUESTION: PF_GameLogic under VISUAL_CUTTED may
# still pull DBRender/DBUI *types* (they live in Render/UI headers, which remain on the
# include path) — if that turns into a wall of LNK2019, the fix is to keep Render/UI .cpp in
# and let the linker drop them, not to fight the headers.
# ---------------------------------------------------------------------------------------
set( PWCI_CLIENT_DIRS
  PW_Client
  PW_Game
  PW_MiniLauncher
  Render
  UI
  Sound
  NivalInput
  ShaderCompiler
  EditorLib
  EditorNative
  EditorPlugins
  PF_Editor
  PF_EditorC
  PF_EditorNative
  MayaExtension
  MayaExeInteraction
  Samples
  MeshConverter
  FormulaBuilder
  DBCodeGen
  EaselLevelEditor
  Client            # Src/Client = screens/console/tooltips. NB: the UniServerApp component
                    # 'Client/LobbyPvx/...' is Game/PF/Client, a different tree, kept below.
)
foreach( _d ${PWCI_CLIENT_DIRS} )
  list_remove_regexp( ALL_SRCS "${SRC_DIR}/${_d}/.+" )
endforeach()

# ---------------------------------------------------------------------------------------
# 3. Put the server sources back.
#
# Done with a private GLOB rather than by editing CMakeLists' exclusion list, because the
# exclusions live in two places (CMakeLists itself and the CI patch step) and several of them
# are load-bearing for the client. Globbing separately and appending sidesteps both.
# ---------------------------------------------------------------------------------------
file( GLOB_RECURSE PWCI_SRV_SRCS
  ${SRC_DIR}/Server/*.cpp             ${SRC_DIR}/Server/*.c
  ${SRC_DIR}/Game/PF/Server/*.cpp     ${SRC_DIR}/Game/PF/Server/*.c
  ${SRC_DIR}/Game/PF/HybridServer/*.cpp
  ${SRC_DIR}/Game/PF/UniServer/*.cpp
  ${SRC_DIR}/Net/*.cpp                # excluded wholesale by CMakeLists ".+/Net/.+"
  ${SRC_DIR}/System/Node/*.cpp        # excluded by the CI patch step; main.h needs CNodeManager
)

# Src/Server.Old is not matched by ${SRC_DIR}/Server/* — no exclusion needed for it.
set( PWCI_SRV_DROP
  "${SRC_DIR}/Server/AdminConsole/.+"              # MFC/WTL admin GUI
  "${SRC_DIR}/Server/ClusterAdminClientApp/.+"     # separate GUI app, has its own main()
  "${SRC_DIR}/Server/DebugConsole/.+"              # separate app
  "${SRC_DIR}/Server/TestEcho/.+"
  "${SRC_DIR}/Server/TransportTest/.+"
  "${SRC_DIR}/Server/TestClientBase/.+"
  "${SRC_DIR}/Server/ZZima/.+"                     # ZZima portal integration, dead
  "${SRC_DIR}/Server/UpdateService.4Delete/.+"     # name says it
  "${SRC_DIR}/Server/WebServer/.+"                 # mongoose-based, not a UniServer component
  "${SRC_DIR}/Server/Monitoring/MonitorConsole/.+" # GUI
  "${SRC_DIR}/Server/NetworkAIO/netlib/.+"         # alternative transport, unused on win32
  "${SRC_DIR}/Server/NetworkAIO/tests/.+"
  "${SRC_DIR}/Server/RPC/Tests.Complex/.+"
  ".+/tests/.+"
  ".+/Tests/.+"
  ".+\\.tests?\\.cpp$"
  ".+\\.test[0-9a-z]*\\.cpp$"
  ".+/main\\.test\\.cpp$"
)
foreach( _p ${PWCI_SRV_DROP} )
  list_remove_regexp( PWCI_SRV_SRCS ${_p} )
endforeach()

# Login service. Network/LoginServerAsync.cpp is dropped by CMakeLists (".+/LoginServerAsync\.cpp$")
# and LoginServerBase.cpp by the CI patch step, because the client only wants LoginClient.
# KNOWN GAP: CMakeLists also drops ".+/LLoginServerAsync\.auto\.cpp$" and that generated file is
# NOT in the published tree -> Login::LoginServerAsync will almost certainly fail to link.
# Registered in main.cpp at Login::serviceId, so it cannot simply be dropped; expect this in the
# first error list.
set( PWCI_SRV_SRCS ${PWCI_SRV_SRCS}
  ${SRC_DIR}/Network/LoginServerAsync.cpp
  ${SRC_DIR}/Network/LoginServerBase.cpp
  ${VENDOR}/MD4/md4c.c
  ${VENDOR}/MD4/md5c.c
)

list( REMOVE_DUPLICATES PWCI_SRV_SRCS )
set( ALL_SRCS ${ALL_SRCS} ${PWCI_SRV_SRCS} )
list( REMOVE_DUPLICATES ALL_SRCS )   # CMakeLists re-adds a few server files by hand; dedupe
                                     # or jom emits duplicate object rules.
list( LENGTH PWCI_SRV_SRCS _n_srv )
list( LENGTH ALL_SRCS _n_all )
message( STATUS "pwci-server: ${_n_srv} server sources added, ${_n_all} sources total" )

# ---------------------------------------------------------------------------------------
# 4. Include paths.
#
# main.cpp includes headers relative to a component's own directory ("RelaySvc/...",
# "ChatSvc/...", "UserManagerSvc/...", "GameBalancer/..."), which Nival's per-component build
# provided implicitly. The monolith needs them spelled out.
# ---------------------------------------------------------------------------------------
include_directories(
  ${SRC_DIR}/Server/Relay
  ${SRC_DIR}/Server/Chat
  ${SRC_DIR}/Server/UserManager
  ${SRC_DIR}/Server/Monitoring
  ${SRC_DIR}/Server/ClusterAdmin
  ${SRC_DIR}/Server/MatchMaking
  ${SRC_DIR}/Server/NetworkAIO/netlib
  ${SRC_DIR}/Game/PF/Server
  ${SRC_DIR}/Game/PF/Server/GameSession
  ${SRC_DIR}/Game/PF/UniServer
  ${SRC_DIR}/Server/Monitoring
  ${VENDOR}/JsonCpp/include
  ${VENDOR}/boost
  ${VENDOR}/libcurl/include
  ${VENDOR}/tinyxml
  ${VENDOR}/tinyxml/src
  ${VENDOR}/pthreads/Pre-built.2/include
)

# ---------------------------------------------------------------------------------------
# 5. Defines.
#
# The four globalCompilerKeys come verbatim from UniServerApp.application. VISUAL_CUTTED is
# the one that matters: ~250 files in PF_GameLogic/Render/UI branch on it to compile out the
# rendering side of the simulation.
# NOT enabled although the .application sets settings.enableProfiler = True:
# NI_ENABLE_INLINE_PROFILER, which drags in System/InlineProfiler3/Profiler3UI (a GUI).
# Revisit once the thing links.
# ---------------------------------------------------------------------------------------
add_definitions( -DVISUAL_CUTTED -DSERVER_DB -DCHECK_TOWN_CONSISTENCY -DLOG_THREAD_EXIT )
add_definitions( -DCURL_STATICLIB )   # Vendor/libcurl is a static build, same as Nival's vcproj

# ---------------------------------------------------------------------------------------
# 6. Libraries.
#
# rpcrt4 / shlwapi come from UniServerApp.application libDependencies (rpcrt4 is already in
# CMakeLists). The rest mirror pwci_extra.cmake — the server uses curl (billing/http),
# tinyxml + JsonCpp (configs), CensorDll (Game/PF/Server/Censorship), wbemuuid (WMI perf
# counters in Server/Monitoring).
# ACE / IOTerabit / TProactor / OpenSSL are already listed by CMakeLists itself.
# ---------------------------------------------------------------------------------------
simple_add_library( shlwapi )
simple_add_library( wbemuuid )
simple_add_library( ws2_32 )
simple_add_library( wldap32 )
simple_add_library( ${VENDOR}/tinyxml/Release/tinyxml )
simple_add_library( ${VENDOR}/JsonCpp/lib/Release/JsonCpp )
simple_add_library( ${VENDOR}/libcurl/lib/Release/libcurl )
simple_add_library( ${SRC_DIR}/../Tools/Censor/lib/Release/CensorDll )

# ---------------------------------------------------------------------------------------
# 7. Static-init order.
#
# Same problem as the client (see pwci_extra.cmake): MSVC runs global constructors in link
# order, the DLL build had a dependency order, the monolithic GLOB is alphabetical. Order
# below follows PF.sln bottom-up, with the server layers appended after the shared ones.
# UNVERIFIED for the server — it only starts to matter once the exe actually runs.
# ---------------------------------------------------------------------------------------
set( PWCI_INIT_ORDER
  MemoryLib System libdb Terrain Scripts Scene
  Server/RPC Server/NetworkAIO Network Net Core
  PF_Core PF_GameLogic PF_Minigames
  Server/ServerAppBase Server/AppFramework Server/Coordinator Server/Chat
  Server/Relay Server/UserManager Server/MatchMaking Server/ClusterAdmin
  Server/Monitoring Server/NewLogin Server/ClientControl Server
  Game/PF/Client Game/PF/Server Game/PF/HybridServer Game/PF/UniServer )
set( _pwci_rest ${ALL_SRCS} )
set( _pwci_sorted )
foreach( _d ${PWCI_INIT_ORDER} )
  set( _m ${_pwci_rest} )
  list( FILTER _m INCLUDE REGEX "/Src/${_d}/" )
  list( APPEND _pwci_sorted ${_m} )
  list( FILTER _pwci_rest EXCLUDE REGEX "/Src/${_d}/" )
endforeach()
set( ALL_SRCS ${_pwci_sorted} ${_pwci_rest} )
list( LENGTH _pwci_sorted _n1 )
list( LENGTH _pwci_rest _n2 )
message( STATUS "pwci-server: init-order sorted ${_n1} sources, ${_n2} unmatched appended last" )

# --- optional extra definitions from workflow_dispatch (space separated) ---
if( PWCI_EXTRA_DEFS )
  separate_arguments( _pwci_defs WINDOWS_COMMAND "${PWCI_EXTRA_DEFS}" )
  add_definitions( ${_pwci_defs} )
  message( STATUS "pwci-server: extra defs: ${_pwci_defs}" )
endif()
